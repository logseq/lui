import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Owner and source markers occupy their real layout bounds. They do not
/// replace a scroll delegate or infer row ownership from a hit coordinate.
struct LUISharedOwnerProbe {
    let model: LUINodeModel
    let backend: LUIAppleBackend
}

struct LUISharedSourceProbe {
    let state: LUISparseVirtualState
    let backend: LUIAppleBackend
}

struct LUISharedRowProbe {
    let state: LUISparseVirtualState
    let row: LUISparseVirtualState.Row
    let generation: Int
    let backend: LUIAppleBackend
}

@MainActor
final class LUIWeakSharedRowAnchor {
    weak var value: LUISharedRowMarker?
    init(_ value: LUISharedRowMarker) { self.value = value }
}

#if os(macOS)
extension LUISharedOwnerProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> LUISharedOwnerMarker { LUISharedOwnerMarker() }
    func updateNSView(_ view: LUISharedOwnerMarker, context: Context) { view.configure(model, backend: backend) }
    static func dismantleNSView(_ view: LUISharedOwnerMarker, coordinator: ()) { view.disconnect() }
}
extension LUISharedSourceProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> LUISharedSourceMarker { LUISharedSourceMarker() }
    func updateNSView(_ view: LUISharedSourceMarker, context: Context) { view.configure(state, backend: backend) }
    static func dismantleNSView(_ view: LUISharedSourceMarker, coordinator: ()) { view.disconnect() }
}
extension LUISharedRowProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> LUISharedRowMarker { LUISharedRowMarker() }
    func updateNSView(_ view: LUISharedRowMarker, context: Context) {
        view.configure(state, row: row, generation: generation, backend: backend)
    }
    static func dismantleNSView(_ view: LUISharedRowMarker, coordinator: ()) { view.disconnect() }
}
#else
extension LUISharedOwnerProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> LUISharedOwnerMarker { LUISharedOwnerMarker() }
    func updateUIView(_ view: LUISharedOwnerMarker, context: Context) { view.configure(model, backend: backend) }
    static func dismantleUIView(_ view: LUISharedOwnerMarker, coordinator: ()) { view.disconnect() }
}
extension LUISharedSourceProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> LUISharedSourceMarker { LUISharedSourceMarker() }
    func updateUIView(_ view: LUISharedSourceMarker, context: Context) { view.configure(state, backend: backend) }
    static func dismantleUIView(_ view: LUISharedSourceMarker, coordinator: ()) { view.disconnect() }
}
extension LUISharedRowProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> LUISharedRowMarker { LUISharedRowMarker() }
    func updateUIView(_ view: LUISharedRowMarker, context: Context) {
        view.configure(state, row: row, generation: generation, backend: backend)
    }
    static func dismantleUIView(_ view: LUISharedRowMarker, coordinator: ()) { view.disconnect() }
}
#endif

@MainActor
final class LUISharedRowMarker: LUIHostNativeView {
    private weak var state: LUISparseVirtualState?
    private weak var backend: LUIAppleBackend?
    private(set) var row = LUISparseVirtualState.Row(id: 0, index: 0)
    private(set) var generation = 0
    func configure(_ state: LUISparseVirtualState, row: LUISparseVirtualState.Row,
        generation: Int, backend: LUIAppleBackend) {
        if self.state !== state || self.row.id != row.id { disconnect() }
        self.state = state
        self.row = row
        self.generation = generation
        self.backend = backend
        changed()
    }
    private func changed() {
        if let state { backend?.sharedVirtualViewport.rowAnchor(state: state, row: row.id, view: self, attached: window != nil) }
    }
    func disconnect() {
        if let state { backend?.sharedVirtualViewport.rowAnchor(state: state, row: row.id, view: self, attached: false) }
        state = nil
        backend = nil
    }
    #if os(macOS)
    override var isFlipped: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); changed() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); changed() }
    override func layout() { super.layout(); changed() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func didMoveToWindow() { super.didMoveToWindow(); changed() }
    override func didMoveToSuperview() { super.didMoveToSuperview(); changed() }
    override func layoutSubviews() { super.layoutSubviews(); changed() }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    #endif
}

@MainActor
final class LUISharedSourceMarker: LUIHostNativeView {
    private weak var state: LUISparseVirtualState?
    private weak var backend: LUIAppleBackend?
    func configure(_ state: LUISparseVirtualState, backend: LUIAppleBackend) {
        if self.state !== state { disconnect() }
        self.state = state
        self.backend = backend
        changed()
    }
    private func changed() {
        if let state { backend?.sharedVirtualViewport.sourceAnchor(state: state, view: window == nil ? nil : self) }
    }
    func disconnect() {
        if let state { backend?.sharedVirtualViewport.sourceAnchor(state: state, view: nil) }
        state = nil
        backend = nil
    }
    #if os(macOS)
    override var isFlipped: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); changed() }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); changed() }
    override func layout() { super.layout(); changed() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func didMoveToWindow() { super.didMoveToWindow(); changed() }
    override func didMoveToSuperview() { super.didMoveToSuperview(); changed() }
    override func layoutSubviews() { super.layoutSubviews(); changed() }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    #endif
}

@MainActor
final class LUISharedOwnerMarker: LUIHostNativeView {
    private weak var model: LUINodeModel?
    private weak var backend: LUIAppleBackend?
    private weak var scroll: LUIHostNativeScroll?
    private var notifications: [NSObjectProtocol] = []
    #if os(macOS)
    private var pointerMonitor: Any?
    #else
    private var observation: NSKeyValueObservation?
    private var touch: LUISharedTouchObserver?
    #endif

    func configure(_ model: LUINodeModel, backend: LUIAppleBackend) {
        if self.model !== model { disconnect() }
        self.model = model
        self.backend = backend
        connect()
    }
    private func connect() {
        guard window != nil, let model, let backend else { return }
        var ancestor = superview
        while let view = ancestor, !(view is LUIHostNativeScroll) { ancestor = view.superview }
        guard let native = ancestor as? LUIHostNativeScroll else { return }
        if scroll !== native {
            disconnectObservers()
            scroll = native
            #if os(macOS)
            native.contentView.postsBoundsChangedNotifications = true
            for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
                observe(name, object: native.contentView)
            }
            observe(NSWindow.didUpdateNotification, object: window)
            for name in [NSText.didBeginEditingNotification, NSText.didEndEditingNotification, NSText.didChangeNotification] {
                observe(name, object: nil)
            }
            for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(menuTracking(_:)), name: name, object: nil)
            }
            pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, event.window === self.window else { return }
                    let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
                    let content = self.window?.contentView
                    let target = content?.hitTest(content?.convert(event.locationInWindow, from: nil) ?? .zero)
                    self.backend?.sharedVirtualViewport.pointer(view: target, down: down)
                }
                return event
            }
            #else
            observation = native.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.backend?.sharedVirtualViewport.schedule() }
            }
            for name in [UITextField.textDidBeginEditingNotification, UITextField.textDidEndEditingNotification,
                UITextField.textDidChangeNotification, UITextView.textDidBeginEditingNotification,
                UITextView.textDidEndEditingNotification, UITextView.textDidChangeNotification,
                UIResponder.keyboardDidChangeFrameNotification] { observe(name, object: nil) }
            let touch = LUISharedTouchObserver()
            touch.manager = backend.sharedVirtualViewport
            native.addGestureRecognizer(touch)
            self.touch = touch
            #endif
        }
        backend.sharedVirtualViewport.owner(model: model, scroll: native)
    }
    private func observe(_ name: Notification.Name, object: AnyObject?) {
        notifications.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.backend?.sharedVirtualViewport.schedule() }
        })
    }
    private func disconnectObservers() {
        for token in notifications { NotificationCenter.default.removeObserver(token) }
        notifications.removeAll()
        #if os(macOS)
        NotificationCenter.default.removeObserver(self)
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        #else
        observation = nil
        if let touch { scroll?.removeGestureRecognizer(touch) }
        touch = nil
        #endif
    }
    func disconnect() {
        detachWindow()
        model = nil
        backend = nil
    }
    private func detachWindow() {
        disconnectObservers()
        if let model { backend?.sharedVirtualViewport.removeOwner(model: model, scroll: scroll) }
        scroll = nil
    }
    #if os(macOS)
    @objc private func menuTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        backend?.sharedVirtualViewport.menu(menu, opened: notification.name == NSMenu.didBeginTrackingNotification)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { detachWindow() } else { connect() } }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); connect() }
    override func layout() { super.layout(); connect() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { detachWindow() } else { connect() } }
    override func didMoveToSuperview() { super.didMoveToSuperview(); connect() }
    override func layoutSubviews() { super.layoutSubviews(); connect() }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    #endif
}

#if os(iOS)
@MainActor
final class LUISharedTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var manager: LUISharedVirtualViewport?
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        manager?.pointer(view: touches.first?.view, down: true)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        manager?.pointer(view: nil, down: false)
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        manager?.pointer(view: nil, down: false)
        state = .failed
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
#endif
