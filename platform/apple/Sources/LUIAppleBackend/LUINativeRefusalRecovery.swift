import Foundation

/// A call the OCaml runtime refused, as reported by `lui_ocaml_last_error`.
public struct LUIRuntimeFailure: Error, Decodable, Equatable, Sendable, CustomStringConvertible {
    public let bridge: String
    public let phase: String
    public let node: Int?
    public let message: String

    public init(bridge: String, phase: String, node: Int?, message: String) {
        self.bridge = bridge
        self.phase = phase
        self.node = node
        self.message = message
    }

    public static func decode(_ json: String) -> LUIRuntimeFailure? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LUIRuntimeFailure.self, from: data)
    }

    public var description: String {
        "\(bridge) \(phase) failed\(node.map { " at node \($0)" } ?? ""): \(message)"
    }
}

nonisolated(unsafe) private var capturedRuntimeFailure: String?

nonisolated(unsafe) private let captureRuntimeFailure: @convention(c) (UnsafePointer<CChar>?) -> Void = { source in
    capturedRuntimeFailure = source.map { String(cString: $0) }
}

/// Recovery for hosts that load the `lui_ocaml_*` C ABI themselves. Pass
/// every call's result to `check`: when OCaml threw, it reads the
/// diagnostic, logs it and asks `lui_ocaml_resync` for the authoritative
/// tree. Route batches delivered while `isReceivingSnapshot` is true to
/// `LUIAppleBackend.applySnapshot(json:)`.
@MainActor
public final class LUINativeRefusalRecovery {
    public typealias Receiver = @convention(c) (UnsafePointer<CChar>?) -> Void
    private typealias LastErrorSymbol = @convention(c) (Receiver?) -> Int32
    private typealias ResyncSymbol = @convention(c) () -> Int32

    private let lastError: ((Receiver) -> Int32)?
    private let resync: (() -> Int32)?
    public private(set) var isReceivingSnapshot = false
    public var onFailure: ((LUIRuntimeFailure) -> Void)?

    /// Libraries built before the diagnostic ABI lack `lastError`; their
    /// refusals are then ignored as before.
    public init(lastError: ((Receiver) -> Int32)?, resync: (() -> Int32)?) {
        self.lastError = lastError
        self.resync = resync
    }

    /// Resolves `lui_ocaml_last_error` and `lui_ocaml_resync` from a
    /// `dlopen` handle.
    public convenience init(library handle: UnsafeMutableRawPointer) {
        let lastError = dlsym(handle, "lui_ocaml_last_error").map {
            unsafeBitCast($0, to: LastErrorSymbol.self)
        }
        let resync = dlsym(handle, "lui_ocaml_resync").map {
            unsafeBitCast($0, to: ResyncSymbol.self)
        }
        self.init(
            lastError: lastError.map { function in { function($0) } },
            resync: resync.map { function in { function() } }
        )
    }

    /// Reads and clears the pending diagnostic.
    public func takeFailure() -> LUIRuntimeFailure? {
        guard let lastError else { return nil }
        capturedRuntimeFailure = nil
        guard lastError(captureRuntimeFailure) == 1, let json = capturedRuntimeFailure else {
            return nil
        }
        capturedRuntimeFailure = nil
        return LUIRuntimeFailure.decode(json)
            ?? LUIRuntimeFailure(bridge: "", phase: "unknown", node: nil, message: json)
    }

    /// `accepted` is a bridge call's result, or nil when the call was not
    /// exported. A refusal without a diagnostic (argument validation)
    /// leaves no partial patches, so only a reported exception resyncs.
    public func check(_ accepted: Int32?) {
        guard let accepted, accepted != 1, let failure = takeFailure() else { return }
        FileHandle.standardError.write(Data("LUI: \(failure)\n".utf8))
        isReceivingSnapshot = true
        let resynced = resync?() == 1
        isReceivingSnapshot = false
        if !resynced {
            FileHandle.standardError.write(Data("LUI: resync after refusal failed\n".utf8))
        }
        onFailure?(failure)
    }
}
