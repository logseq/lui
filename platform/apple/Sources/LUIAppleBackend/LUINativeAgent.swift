import Foundation
#if canImport(Network)
import Network
#endif

nonisolated(unsafe) private var capturedAgentReply: String?

nonisolated(unsafe) private let captureAgentReply: @convention(c) (UnsafePointer<CChar>?) -> Void = { source in
    capturedAgentReply = source.map { String(cString: $0) }
}

/// Answers lui-agent requests (see tooling/lui_agent.mjs) through
/// `lui_ocaml_agent_utf8` on the thread that owns the OCaml runtime. An
/// action's patches reach the host's patch callback before `answer`
/// returns; a refused request is recovered through `recovery` like any
/// refused call and answered with `{"ok":false,"refused":true,...}`.
@MainActor
public final class LUINativeAgent {
    public typealias Receiver = LUINativeRefusalRecovery.Receiver
    public typealias Function = (UnsafePointer<CChar>, Int32, Receiver) -> Int32
    private typealias AgentSymbol = @convention(c) (UnsafePointer<CChar>?, Int32, Receiver?) -> Int32

    private let agent: Function?
    private let recovery: LUINativeRefusalRecovery

    /// Libraries built before the agent ABI pass nil; every request is then
    /// answered with an error.
    public init(agent: Function?, recovery: LUINativeRefusalRecovery) {
        self.agent = agent
        self.recovery = recovery
    }

    /// Resolves `lui_ocaml_agent_utf8` from a `dlopen` handle.
    public convenience init(library handle: UnsafeMutableRawPointer, recovery: LUINativeRefusalRecovery) {
        let agent = dlsym(handle, "lui_ocaml_agent_utf8").map {
            unsafeBitCast($0, to: AgentSymbol.self)
        }
        self.init(agent: agent.map { function in { function($0, $1, $2) } }, recovery: recovery)
    }

    public func answer(_ request: String) -> String {
        guard let agent else {
            return Self.failure(["error": "this LUI library predates lui_ocaml_agent_utf8"])
        }
        capturedAgentReply = nil
        let accepted = request.withCString { agent($0, Int32(request.utf8.count), captureAgentReply) }
        let reply = capturedAgentReply
        capturedAgentReply = nil
        if accepted == 1, let reply { return reply }
        guard let failure = recovery.recover(accepted) else {
            return Self.failure(["error": "the OCaml runtime rejected the agent request"])
        }
        var diagnostic: [String: Any] = [
            "bridge": failure.bridge, "phase": failure.phase,
            "message": failure.message, "recovery": "resync",
        ]
        if let node = failure.node { diagnostic["node"] = node }
        return Self.failure(["refused": true, "error": failure.message, "diagnostic": diagnostic])
    }

    static func failure(_ fields: [String: Any]) -> String {
        var fields = fields
        fields["ok"] = false
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return #"{"error":"lui: unencodable agent failure","ok":false}"# }
        return text
    }
}

#if canImport(Network)
public struct LUIAgentServerError: Error, CustomStringConvertible {
    public let description: String
}

/// Serves lui-agent requests from one loopback TCP client at a time on the
/// main queue: each request line goes to `answer` and each reply is one
/// line. Start it only when a developer opts in, as `startFromEnvironment`
/// does, and `stop()` it during host teardown.
@MainActor
public final class LUIAgentServer {
    public static let listenEnvironmentKey = "LUI_AGENT_LISTEN"
    static let maxLine = 1 << 20

    private let listener: NWListener
    private let answer: (String) -> String
    private var connection: NWConnection?
    private var generation = 0
    private var buffer = Data()
    private var discarding = false
    public private(set) var port: UInt16?
    public private(set) var failure: String?
    public var onReady: ((UInt16) -> Void)?

    /// Listens on 127.0.0.1 only; port 0 picks a free port, published in
    /// `port` once the listener is ready.
    public init(port: UInt16 = 0, answer: @escaping (String) -> String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        listener = try NWListener(using: parameters)
        self.answer = answer
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerChanged(state) }
        }
        listener.newConnectionHandler = { [weak self] incoming in
            MainActor.assumeIsolated { self?.accept(incoming) }
        }
        listener.start(queue: .main)
    }

    /// Starts a server when `LUI_AGENT_LISTEN=127.0.0.1:PORT` is set.
    public static func startFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        answer: @escaping (String) -> String
    ) throws -> LUIAgentServer? {
        guard let address = environment[listenEnvironmentKey], !address.isEmpty else { return nil }
        guard let port = loopbackPort(address) else {
            throw LUIAgentServerError(description: "\(listenEnvironmentKey)=\(address) is not a loopback host:port")
        }
        let server = try LUIAgentServer(port: port, answer: answer)
        server.onReady = { port in
            FileHandle.standardError.write(Data("lui-agent listening on 127.0.0.1:\(port)\n".utf8))
        }
        return server
    }

    static func loopbackPort(_ address: String) -> UInt16? {
        guard let colon = address.lastIndex(of: ":") else { return nil }
        let host = address[..<colon]
        guard host == "127.0.0.1" || host == "localhost" else { return nil }
        return UInt16(address[address.index(after: colon)...])
    }

    public func stop() {
        drop()
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let ready = listener.port?.rawValue else { return }
            port = ready
            onReady?(ready)
        case .failed(let error):
            failure = "\(error)"
            FileHandle.standardError.write(Data("lui-agent listener failed: \(error)\n".utf8))
            listener.cancel()
        default:
            break
        }
    }

    private func accept(_ incoming: NWConnection) {
        guard connection == nil else {
            incoming.cancel()
            return
        }
        generation += 1
        let current = generation
        connection = incoming
        buffer = Data()
        discarding = false
        incoming.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.drop(current)
                default: break
                }
            }
        }
        incoming.start(queue: .main)
        receive(current)
    }

    private func receive(_ current: Int) {
        guard current == generation, let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, current == self.generation else { return }
                if let data { self.consume(data) }
                if isComplete || error != nil {
                    self.drop(current)
                } else {
                    self.receive(current)
                }
            }
        }
    }

    // A line longer than maxLine is consumed to its end and then refused, so
    // the client keeps its connection.
    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            let overflowed = discarding || line.count > Self.maxLine
            buffer.removeSubrange(buffer.startIndex...newline)
            discarding = false
            if overflowed {
                send(LUINativeAgent.failure(["error": "lui: agent request exceeds 1 MiB"]))
            } else if let text = String(data: line, encoding: .utf8) {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send(answer(text)) }
            } else {
                send(LUINativeAgent.failure(["error": "lui: agent request is not UTF-8"]))
            }
        }
        if buffer.count > Self.maxLine {
            buffer = Data()
            discarding = true
        }
    }

    private func send(_ reply: String) {
        connection?.send(content: Data((reply + "\n").utf8), completion: .contentProcessed { _ in })
    }

    private func drop(_ current: Int? = nil) {
        if let current, current != generation { return }
        generation += 1
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer = Data()
        discarding = false
    }
}
#endif
