import Foundation

#if canImport(AppKit)
import AppKit

public typealias LUIAppleEventCallback =
    @convention(c) (Int32, Int32, UnsafePointer<CChar>?) -> Void

nonisolated(unsafe) private var eventCallback: LUIAppleEventCallback?

@MainActor
private final class LUIAppleBridge {
    static let shared = LUIAppleBridge()

    private(set) var backend = LUIAppleBackend()
    private var window: NSWindow?

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
            let root = NSStackView()
            root.orientation = .vertical
            root.translatesAutoresizingMaskIntoConstraints = false
            let content = NSView()
            content.addSubview(root)
            NSLayoutConstraint.activate([
                root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            ])
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = "LUI"
            created.contentView = content
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
        backend = LUIAppleBackend()
        connectEvents()
    }

    private func connectEvents() {
        backend.onEvent = { event in
            guard let callback = eventCallback else { return }
            switch event {
            case let .press(node):
                "".withCString { callback(0, Int32(node), $0) }
            case let .textChanged(node, text):
                text.withCString { callback(1, Int32(node), $0) }
            }
        }
    }

    private func refreshWindow() {
        guard let root = window?.contentView?.subviews.first as? NSStackView else { return }
        let nextViews = backend.rootViews
        guard root.arrangedSubviews.count != nextViews.count
                || !zip(root.arrangedSubviews, nextViews).allSatisfy({ $0 === $1 }) else {
            return
        }
        for child in root.arrangedSubviews {
            root.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        for view in nextViews {
            root.addArrangedSubview(view)
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
        guard let button = LUIAppleBridge.shared.backend.view(id: Int(node)) as? NSButton else {
            return 0
        }
        button.performClick(nil)
        return 1
    }
}
#endif
