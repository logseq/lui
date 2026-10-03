import LUIAppleBackend
import SwiftUI
import Observation
import Foundation

typealias PatchCallback = @convention(c) (UnsafePointer<CChar>?) -> Void
@_silgen_name("lui_ocaml_start") func startOCaml(_ callback: PatchCallback?, _ platform: Int32, _ host: Int32) -> Int32
@_silgen_name("lui_ocaml_press") func pressOCaml(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_extension_event") func extensionOCaml(_ node: Int64, _ identifier: UnsafePointer<CChar>, _ name: UnsafePointer<CChar>, _ values: UnsafePointer<CChar>) -> Int32

nonisolated(unsafe) var activeHost: NavigationHost?
let receivePatch: PatchCallback = { source in
    guard let source else { return }
    let json = String(cString: source)
    MainActor.assumeIsolated { activeHost?.apply(json) }
}

@MainActor @Observable final class NavigationHost {
    let backend: LUIAppleBackend
    var rootID: Int?
    init() {
        let registry = LUIAppleExtensionRegistry()
        do {
            try LUINavigation.register(in: registry)
            backend = try LUIAppleBackend(extensionRegistry: registry)
        } catch { fatalError("Navigation registry: \(error)") }
        backend.onEvent = { event in
            switch event {
            case let .press(node): _ = pressOCaml(Int64(node))
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
                    _ = extensionOCaml(Int64(node), identifier, name, values)
                }}}
            default: break
            }
        }
    }
    func start() {
        guard rootID == nil else { return }
        activeHost = self
        precondition(startOCaml(receivePatch, 2, 2) == 1)
    }
    func apply(_ json: String) {
        do {
            try backend.apply(json: json)
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
