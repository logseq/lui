#if DEBUG && os(iOS)
import Foundation
import CoreFoundation
import Network
import UIKit

extension LUIWireValue {
    var debugDriveJSONValue: Any {
        switch self {
        case let .string(value): value
        case let .bool(value): value
        case let .int(value): value
        case let .double(value): value
        }
    }
}

/// Read-only, single-client loopback probe. Retain it in a DEBUG app host only.
@MainActor
public final class LUIDriveSnapshotProbe {
    public private(set) var failure: String?
    private let backend: LUIAppleBackend
    private weak var window: UIWindow?
    private let savedReporting: Bool
    private let savedSuspension: Bool
    private var listener: NWListener?
    private var connection: NWConnection?
    private var buffer = Data()
    private var request = 0
    private var timeout: Task<Void, Never>?
    private var stopped = false

    isolated deinit { stop() }

    /// No listener is created unless LUI_DRIVE_PROBE=1 is explicitly supplied.
    public static func startIfEnabled(
        backend: LUIAppleBackend, window: UIWindow,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LUIDriveSnapshotProbe? {
        guard environment["LUI_DRIVE_PROBE"] == "1" else { return nil }
        let rawPort = environment["LUI_DRIVE_PROBE_PORT"] ?? "49378"
        guard let port = UInt16(rawPort), port >= 1024,
              !backend.debugDriveProbeActive else {
            throw LUIBackendError.invalidBatch("invalid Drive probe port or probe already active")
        }
        return try LUIDriveSnapshotProbe(backend: backend, window: window, port: port)
    }

    private init(backend: LUIAppleBackend, window: UIWindow, port: UInt16) throws {
        self.backend = backend
        self.window = window
        savedReporting = backend.frameReportingEnabled
        savedSuspension = backend.frameCollectionSuspended
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        backend.debugDriveProbeActive = true
        backend.frameCollectionSuspended = false
        backend.frameReportingEnabled = true
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case let .failed(error) = state {
                    self?.failure = String(describing: error)
                    self?.stop()
                }
            }
        }
        listener.start(queue: .main)
    }

    /// Call on host teardown. The pre-existing frame callback is never replaced.
    public func stop() {
        guard !stopped else { return }
        stopped = true
        closeClient()
        listener?.cancel()
        listener = nil
        backend.frameReportingEnabled = savedReporting
        backend.frameCollectionSuspended = savedSuspension
        backend.debugDriveProbeActive = false
    }

    private func accept(_ client: NWConnection) {
        guard !stopped, connection == nil,
              case let .hostPort(host, _) = client.endpoint,
              host == .ipv4(.loopback) else { client.cancel(); return }
        connection = client
        buffer.removeAll(keepingCapacity: true)
        request = 0
        client.stateUpdateHandler = { [weak self, weak client] state in
            Task { @MainActor in
                guard let self, let client, self.connection === client else { return }
                switch state {
                case .failed, .cancelled: self.closeClient()
                default: break
                }
            }
        }
        client.start(queue: .main)
        receive(client)
    }

    private func closeClient() {
        timeout?.cancel()
        timeout = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: true)
    }

    private struct Request: Decodable {
        let probe: String
        let version: Int
        let request: Int
    }

    private func receive(_ client: NWConnection) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self, self.connection === client else { return }
                if let data { self.buffer.append(data) }
                if self.timeout == nil, !self.buffer.isEmpty {
                    self.timeout = Task { [weak self, weak client] in
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled, let self, let client,
                              self.connection === client else { return }
                        self.closeClient()
                    }
                }
                guard error == nil, !done, self.buffer.count <= 4096 else {
                    self.closeClient(); return
                }
                guard let newline = self.buffer.firstIndex(of: 10) else {
                    self.receive(client); return
                }
                let line = self.buffer.prefix(upTo: newline)
                self.buffer.removeSubrange(...newline)
                do {
                    let command = try JSONDecoder().decode(Request.self, from: line)
                    guard let raw = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                          Set(raw.keys) == Set(["probe", "version", "request"]),
                          ["version", "request"].allSatisfy({ key in
                              guard let number = raw[key] as? NSNumber else { return false }
                              return CFGetTypeID(number) != CFBooleanGetTypeID() &&
                                  !["f", "d"].contains(String(cString: number.objCType))
                          }) else { self.closeClient(); return }
                    guard command.probe == "snapshot", command.version == 1,
                          self.request < Int.max, command.request == self.request + 1,
                          self.buffer.isEmpty, let window = self.window,
                          window.isKeyWindow, window.windowScene?.activationState == .foregroundActive,
                          window.windowScene?.windows.filter({ !$0.isHidden && $0.windowLevel == .normal }).count == 1
                    else { self.closeClient(); return }
                    self.request = command.request
                    guard var snapshot = try JSONSerialization.jsonObject(
                        with: self.backend.debugDriveSnapshot()
                    ) as? [String: Any] else { self.closeClient(); return }
                    snapshot["viewport"] = [0, 0, window.bounds.width, window.bounds.height]
                    snapshot["coordinateSpace"] = "window-top-left-points"
                    var bytes = try JSONSerialization.data(withJSONObject: [
                        "probe": "snapshot", "version": 1, "request": command.request,
                        "snapshot": snapshot,
                    ], options: [.sortedKeys])
                    bytes.append(10)
                    client.send(content: bytes, completion: .contentProcessed { [weak self] error in
                        Task { @MainActor in
                            guard let self, self.connection === client else { return }
                            if error != nil { self.closeClient() }
                            else {
                                self.timeout?.cancel()
                                self.timeout = nil
                                self.receive(client)
                            }
                        }
                    })
                } catch { self.closeClient() }
            }
        }
    }

}
#endif
