import Foundation

#if canImport(AppKit)
import AppKit
import SwiftUI

public typealias LUIAppleEventCallback =
    @convention(c) (Int32, Int32, UnsafePointer<CChar>?) -> Void

nonisolated(unsafe) private var eventCallback: LUIAppleEventCallback?

@MainActor
private final class LUIAppleBridge {
    static let shared = LUIAppleBridge()

    private(set) var backend = LUIAppleBackend()
    private var window: NSWindow?
    private var hostedRootID: Int?

    private init() {
        connectEvents()
    }

    func apply(_ json: String) throws {
        try backend.apply(json: json)
        refreshWindow()
    }

    func show() {
        _ = NSApplication.shared
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = "LUI"
            window = created
        }
        refreshWindow()
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func reset() {
        window?.close()
        window = nil
        hostedRootID = nil
        backend = LUIAppleBackend()
        connectEvents()
    }

    private func connectEvents() {
        backend.onEvent = { event in
            guard let callback = eventCallback else { return }
            switch event {
            case let .press(node):
                "".withCString { callback(0, Int32(node), $0) }
            case let .hold(node):
                "".withCString { callback(3, Int32(node), $0) }
            case let .textChanged(node, text):
                text.withCString { callback(1, Int32(node), $0) }
            case let .submit(node):
                "".withCString { callback(6, Int32(node), $0) }
            case let .toggleChanged(node, checked):
                (checked ? "true" : "false").withCString {
                    callback(2, Int32(node), $0)
                }
            case let .change(node):
                "".withCString { callback(4, Int32(node), $0) }
            case let .valueChanged(node, value):
                String(value).withCString { callback(5, Int32(node), $0) }
            case let .dismiss(node):
                "".withCString { callback(7, Int32(node), $0) }
            case let .doublePress(node):
                "".withCString { callback(8, Int32(node), $0) }
            case let .extension(node, identifier, name, values):
                let payload: [String: Any] = [
                    "identifier": identifier,
                    "name": name,
                    "values": values.mapValues(\.foundationValue),
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: payload),
                      let json = String(data: data, encoding: .utf8) else { return }
                json.withCString { callback(9, Int32(node), $0) }
            }
        }
    }

    private func refreshWindow() {
        guard let window else { return }
        guard let rootID = backend.rootIDs.first else {
            window.contentView = nil
            hostedRootID = nil
            return
        }
        guard hostedRootID != rootID else { return }
        window.contentView = NSHostingView(
            rootView: LUISwiftUIRoot(backend: backend, rootID: rootID)
                .padding(16)
        )
        hostedRootID = rootID
    }
}

private extension LUIExtensionValue {
    var foundationValue: Any {
        switch self {
        case let .string(value): value
        case let .bool(value): value
        case let .int(value): value
        case let .double(value): value
        }
    }
}

@_cdecl("lui_apple_apply")
public func luiAppleApply(_ source: UnsafePointer<CChar>?) -> Int32 {
    guard let source else { return 0 }
    let json = String(cString: source)
    return MainActor.assumeIsolated {
        do {
            try LUIAppleBridge.shared.apply(json)
            return 1
        } catch {
            return 0
        }
    }
}

@_cdecl("lui_apple_set_event_callback")
public func luiAppleSetEventCallback(_ callback: LUIAppleEventCallback?) {
    eventCallback = callback
}

@_cdecl("lui_apple_show")
public func luiAppleShow() {
    MainActor.assumeIsolated {
        LUIAppleBridge.shared.show()
    }
}

@_cdecl("lui_apple_reset")
public func luiAppleReset() {
    MainActor.assumeIsolated {
        LUIAppleBridge.shared.reset()
    }
}

@_cdecl("lui_apple_perform_action")
public func luiApplePerformAction(_ node: Int32) -> Int32 {
    MainActor.assumeIsolated {
        do {
            try LUIAppleBridge.shared.backend.performAction(node: Int(node))
            return 1
        } catch {
            return 0
        }
    }
}
#endif
