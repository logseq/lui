#if os(macOS)
import AppKit
import Testing
@testable import LUIAppleBackend

private final class HoverPointerWindow: NSWindow {
    var pointer = NSPoint(x: 30, y: 35)
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

@MainActor
@Suite("Nonintercepting native hover", .serialized)
struct LUIHoverTrackingTests {
    private func pump() { CFRunLoopRunInMode(.defaultMode, 0.005, false) }

    @Test("Late activation samples a stationary pointer and preserves the native control hit")
    func lateActivationAndRebinding() throws {
        _ = NSApplication.shared
        let window = HoverPointerWindow(contentRect: CGRect(x: -10000, y: 0, width: 100, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let button = NSButton(frame: CGRect(x: 10, y: 20, width: 80, height: 30))
        root.addSubview(button)
        window.contentView = root
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        let tracking = LUIHoverTrackingView(frame: button.frame)
        var first: [Bool] = []
        tracking.configure { first.append($0) }
        root.addSubview(tracking)
        root.layoutSubtreeIfNeeded()
        pump()
        #expect(first == [true])
        let point = root.convert(window.pointer, from: nil)
        #expect(root.hitTest(root.convert(point, to: root.superview)) === button)
        var rebound: [Bool] = []
        tracking.configure { rebound.append($0) }
        pump()
        #expect(rebound == [true], "A new owner must receive the stationary pointer state")
        tracking.invalidate()
        tracking.removeFromSuperview()
    }

    @Test("Retirement cancels a queued hover sample")
    func retiredSample() {
        var events: [Bool] = []
        let tracking = LUIHoverTrackingView()
        tracking.configure { events.append($0) }
        tracking.invalidate()
        pump()
        #expect(events.isEmpty)
    }
}
#endif
