import LUIAppleBackend
import SwiftUI
import Observation
import Foundation

typealias PatchCallback = @convention(c) (UnsafePointer<CChar>?) -> Void
@_silgen_name("lui_ocaml_start") func startOCaml(_ callback: PatchCallback?, _ platform: Int32, _ host: Int32) -> Int32
@_silgen_name("lui_ocaml_press") func pressOCaml(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_virtual_rows_version") func virtualRowsVersionOCaml() -> Int32
@_silgen_name("lui_ocaml_virtual_window") func virtualWindowOCaml(_ node: Int64, _ generation: Int64,
    _ first: Int64, _ last: Int64, _ pins: UnsafePointer<Int64>?, _ count: Int32) -> Int32
@_silgen_name("lui_ocaml_visible_range") func visibleRangeOCaml(_ node: Int64, _ first: Int64, _ last: Int64) -> Int32
@_silgen_name("lui_ocaml_scroll_completed") func scrollCompletedOCaml(_ node: Int64, _ token: Int64, _ outcome: UnsafePointer<CChar>?) -> Int32
@_silgen_name("lui_ocaml_extension_event") func extensionOCaml(_ node: Int64, _ identifier: UnsafePointer<CChar>, _ name: UnsafePointer<CChar>, _ values: UnsafePointer<CChar>) -> Int32
@_silgen_name("lui_ocaml_last_error") func lastErrorOCaml(_ receiver: PatchCallback?) -> Int32
@_silgen_name("lui_ocaml_resync") func resyncOCaml() -> Int32
@_silgen_name("lui_ocaml_agent_utf8") func agentOCaml(_ request: UnsafePointer<CChar>?, _ length: Int32, _ reply: PatchCallback?) -> Int32

nonisolated(unsafe) var activeHost: NavigationHost?
let receivePatch: PatchCallback = { source in
    guard let source else { return }
    let json = String(cString: source)
    MainActor.assumeIsolated { activeHost?.apply(json) }
}

@MainActor @Observable final class NavigationHost {
    let backend: LUIAppleBackend
    let recovery = LUINativeRefusalRecovery(lastError: { lastErrorOCaml($0) }, resync: { resyncOCaml() })
    var rootID: Int?
    #if DEBUG
    @ObservationIgnored private var agentServer: LUIAgentServer?
    #endif
    init() {
        let registry = LUIAppleExtensionRegistry()
        do {
            try LUINavigation.register(in: registry)
            backend = try LUIAppleBackend(extensionRegistry: registry)
        } catch { fatalError("Navigation registry: \(error)") }
        backend.onEvent = { [recovery] event in
            switch event {
            case let .press(node): recovery.check(pressOCaml(Int64(node)))
            case let .virtualWindow(node, generation, first, last, pins):
                let ids = pins.map(Int64.init)
                ids.withUnsafeBufferPointer {
                    recovery.check(virtualWindowOCaml(Int64(node), Int64(generation), Int64(first), Int64(last), $0.baseAddress, Int32($0.count)))
                }
            case let .visibleRange(node, first, last): recovery.check(visibleRangeOCaml(Int64(node), Int64(first), Int64(last)))
            case let .scrollCompleted(node, token, outcome):
                outcome.withCString { recovery.check(scrollCompletedOCaml(Int64(node), Int64(token), $0)) }
            case let .extension(node, identifier, name, values):
                let scalars: [String: Any] = values.mapValues { value in
                    switch value {
                    case let .string(v): return v
                    case let .int(v): return v
                    case let .bool(v): return v
                    case let .double(v): return v
                    }
                }
                let json = String(decoding: try! JSONSerialization.data(withJSONObject: scalars, options: [.sortedKeys]), as: UTF8.self)
                identifier.withCString { identifier in name.withCString { name in json.withCString { values in
                    recovery.check(extensionOCaml(Int64(node), identifier, name, values))
                }}}
            default: break
            }
        }
    }
    func start() {
        guard rootID == nil else { return }
        activeHost = self
        guard startOCaml(receivePatch, 2, virtualRowsVersionOCaml() == 1 ? 258 : 2) == 1 else {
            fatalError("Navigation start: \(recovery.takeFailure().map(String.init(describing:)) ?? "rejected")")
        }
        #if DEBUG
        let agent = LUINativeAgent(agent: { agentOCaml($0, $1, $2) }, recovery: recovery)
        do {
            agentServer = try LUIAgentServer.startFromEnvironment { agent.answer($0) }
        } catch { fatalError("Navigation lui-agent: \(error)") }
        #endif
    }
    func apply(_ json: String) {
        do {
            if recovery.isReceivingSnapshot {
                try backend.applySnapshot(json: json)
            } else {
                try backend.apply(json: json)
            }
            rootID = backend.rootIDs.first
        } catch { fatalError("Navigation patch: \(error)") }
    }
}

@main struct NavigationDemo: App {
    @State private var host = NavigationHost()
    var body: some Scene {
        WindowGroup {
            Group {
                if let root = host.rootID { LUISwiftUIRoot(backend: host.backend, rootID: root) }
                else { Text("Starting navigation demo") }
            }.task { host.start() }
        }
    }
}
