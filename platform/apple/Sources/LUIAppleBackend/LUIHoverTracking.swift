#if os(macOS)
import AppKit
import SwiftUI

/// Track hover without adding an interaction surface above sibling views.
struct LUIHoverTracking: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> LUIHoverTrackingView {
        let view = LUIHoverTrackingView()
        view.configure(changed)
        return view
    }
    func updateNSView(_ view: LUIHoverTrackingView, context: Context) { view.configure(changed) }
    static func dismantleNSView(_ view: LUIHoverTrackingView, coordinator: ()) { view.invalidate() }
}

final class LUIHoverTrackingView: NSView {
    private var changed: ((Bool) -> Void)?
    private var area: NSTrackingArea?
    private var sampled: Bool?
    private var scheduled = false

    func configure(_ changed: @escaping (Bool) -> Void) {
        self.changed = changed
        sampled = nil
        scheduleSample()
    }
    func invalidate() {
        changed = nil
        if let area { removeTrackingArea(area) }
        area = nil
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleSample() }
    override func layout() { super.layout(); scheduleSample() }
    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        area = next
        addTrackingArea(next)
        super.updateTrackingAreas()
        scheduleSample()
    }
    override func mouseEntered(with event: NSEvent) { deliver(true) }
    override func mouseExited(with event: NSEvent) { deliver(false) }

    private func deliver(_ inside: Bool) {
        guard changed != nil, sampled != inside else { return }
        sampled = inside
        changed?(inside)
    }
    private func scheduleSample() {
        guard !scheduled else { return }
        scheduled = true
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scheduled = false
                guard self.changed != nil else { return }
                guard let window = self.window, window.isVisible, !self.isHiddenOrHasHiddenAncestor else {
                    self.deliver(false)
                    return
                }
                let point = self.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                self.deliver(self.bounds.contains(point) && self.visibleRect.contains(point))
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
#endif
