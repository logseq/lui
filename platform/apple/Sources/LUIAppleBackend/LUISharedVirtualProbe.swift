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

/// A point-in-time native acquisition, never a requested scroll position.
/// Weak identities cannot keep a retired owner, window or row alive.
@MainActor
struct LUISparseNativeObservation {
    weak var scroll: LUIHostNativeScroll?
    weak var source: LUIVirtualNativeView?
    weak var marker: LUISharedRowMarker?
    weak var window: AnyObject?
    let geometry: LUISharedViewportGeometry
    let anchorRect: CGRect
    let sourceBounds: CGRect
    let viewportBounds: CGRect
    let insets: [CGFloat]
    let intersectsViewport: Bool

    func matches(_ other: Self) -> Bool {
        guard let scroll, let source, let marker, let window,
              scroll === other.scroll, source === other.source,
              marker === other.marker, window === other.window,
              intersectsViewport == other.intersectsViewport else { return false }
        let left = [geometry.offset, geometry.height, geometry.documentHeight, geometry.origin]
            + components(anchorRect) + components(sourceBounds) + components(viewportBounds) + insets
        let right = [other.geometry.offset, other.geometry.height, other.geometry.documentHeight, other.geometry.origin]
            + components(other.anchorRect) + components(other.sourceBounds) + components(other.viewportBounds) + other.insets
        return zip(left, right).allSatisfy { abs($0 - $1) <= 1 }
    }

    private func components(_ rect: CGRect) -> [CGFloat] {
        [rect.minX, rect.minY, rect.width, rect.height]
    }

    static func geometry(scroll: LUIHostNativeScroll, source: LUIVirtualNativeView) -> LUISharedViewportGeometry? {
        guard let window = scroll.window, source.window === window else { return nil }
        #if os(macOS)
        guard let document = scroll.documentView, source.isDescendant(of: document) else { return nil }
        let clip = document.convert(scroll.contentView.bounds, from: scroll.contentView)
        let frame = source.convert(source.bounds, to: document)
        let offset = document.isFlipped ? clip.minY - document.bounds.minY : document.bounds.maxY - clip.maxY
        let origin = document.isFlipped ? frame.minY - document.bounds.minY : document.bounds.maxY - frame.maxY
        let height = clip.height
        let total = document.bounds.height
        let basis = source.convert(CGPoint.zero, to: document)
        let xAxis = source.convert(CGPoint(x: 1, y: 0), to: document)
        let yAxis = source.convert(CGPoint(x: 0, y: 1), to: document)
        let expectedY: CGFloat = source.isFlipped == document.isFlipped ? 1 : -1
        #else
        guard source.isDescendant(of: scroll) else { return nil }
        let inset = scroll.adjustedContentInset
        let offset = scroll.contentOffset.y + inset.top
        let height = scroll.bounds.height - inset.top - inset.bottom
        let total = scroll.contentSize.height
        let origin = source.convert(source.bounds, to: scroll).minY + inset.top
        let basis = source.convert(CGPoint.zero, to: scroll)
        let xAxis = source.convert(CGPoint(x: 1, y: 0), to: scroll)
        let yAxis = source.convert(CGPoint(x: 0, y: 1), to: scroll)
        let expectedY: CGFloat = 1
        #endif
        var ancestor = source.superview
        while let current = ancestor {
            if let candidate = current as? LUIHostNativeScroll {
                guard candidate === scroll else { return nil }
                break
            }
            ancestor = current.superview
        }
        let epsilon: CGFloat = 0.000001
        guard [offset, height, total, origin].allSatisfy(\.isFinite), height > 0, total >= 0,
              abs(xAxis.y - basis.y) < epsilon, abs(yAxis.x - basis.x) < epsilon,
              abs(xAxis.x - basis.x - 1) < epsilon,
              abs(yAxis.y - basis.y - expectedY) < epsilon else { return nil }
        return .init(offset: offset, height: height, documentHeight: total, origin: origin)
    }

    static func anchorFrame(_ marker: LUISharedRowMarker, source: LUIVirtualNativeView,
        geometry: LUISharedViewportGeometry) -> CGRect? {
        guard marker.window != nil, marker.window === source.window,
              let owner = nearestScroller(source), nearestScroller(marker) === owner else { return nil }
        let frame = marker.convert(marker.bounds, to: source)
        #if os(macOS)
        let top = source.isFlipped ? frame.minY - source.bounds.minY : source.bounds.maxY - frame.maxY
        #else
        let top = frame.minY - source.bounds.minY
        #endif
        let rect = CGRect(x: frame.minX - source.bounds.minX, y: geometry.origin + top,
            width: frame.width, height: frame.height)
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    // SwiftUI backgrounds are sibling native leaves. Source membership comes
    // from the state/row registry; both leaves must occupy the exact same native
    // scroller, rather than pretending the source marker contains the row view.
    private static func nearestScroller(_ view: LUIVirtualNativeView) -> LUIHostNativeScroll? {
        var ancestor = view.superview
        while let current = ancestor {
            if let scroll = current as? LUIHostNativeScroll { return scroll }
            ancestor = current.superview
        }
        return nil
    }

    static func read(scroll: LUIHostNativeScroll, source: LUIVirtualNativeView,
        marker: LUISharedRowMarker, geometry: LUISharedViewportGeometry? = nil,
        anchorRect: CGRect? = nil) -> Self? {
        guard let geometry = geometry ?? Self.geometry(scroll: scroll, source: source),
              let rect = anchorRect ?? anchorFrame(marker, source: source, geometry: geometry),
              let window = scroll.window, marker.window === window else { return nil }
        #if os(macOS)
        let viewport = scroll.contentView.bounds
        let visible = marker.convert(marker.bounds, to: scroll.contentView).intersection(viewport)
        let nativeInsets = scroll.contentInsets
        #else
        let viewport = scroll.bounds.inset(by: scroll.adjustedContentInset)
        let visible = marker.convert(marker.bounds, to: scroll).intersection(viewport)
        let nativeInsets = scroll.adjustedContentInset
        #endif
        let values = [source.bounds.minX, source.bounds.minY, source.bounds.width, source.bounds.height,
            viewport.minX, viewport.minY, viewport.width, viewport.height,
            nativeInsets.top, nativeInsets.left, nativeInsets.bottom, nativeInsets.right]
        guard values.allSatisfy(\.isFinite), source.bounds.width > 0, viewport.width > 0 else { return nil }
        return Self(scroll: scroll, source: source, marker: marker, window: window,
            geometry: geometry, anchorRect: rect, sourceBounds: source.bounds, viewportBounds: viewport,
            insets: [nativeInsets.top, nativeInsets.left, nativeInsets.bottom, nativeInsets.right],
            intersectsViewport: !visible.isNull && visible.width > 0 && visible.height > 0)
    }
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
    private(set) weak var retainedModel: AnyObject?
    func configure(_ state: LUISparseVirtualState, row: LUISparseVirtualState.Row,
        generation: Int, backend: LUIAppleBackend) {
        if self.state !== state || self.row.id != row.id { disconnect() }
        self.state = state
        self.row = row
        self.generation = generation
        self.backend = backend
        retainedModel = backend.model(id: row.id) as AnyObject? ?? backend.extensionModel(id: row.id)
        changed()
    }
    private func changed() {
        state?.nativeRowAnchor(self, attached: window != nil)
    }
    func disconnect() {
        state?.nativeRowAnchor(self, attached: false)
        state = nil
        backend = nil
        retainedModel = nil
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
        state?.nativeSourceAnchor(self, attached: window != nil)
    }
    func disconnect() {
        state?.nativeSourceAnchor(self, attached: false)
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
