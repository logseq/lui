import SwiftUI
#if os(macOS)
import AppKit
typealias LUIHostNativeView = NSView
typealias LUIHostNativeScroll = NSScrollView
#else
import UIKit
typealias LUIHostNativeView = UIView
typealias LUIHostNativeScroll = UIScrollView
#endif

extension LUIAppleBackend {
    /// Scrolls a retained `scroll` node in top-origin logical points, clamped
    /// to its content. False flags a missing/non-scroll node, nonfinite top,
    /// or a native viewport that has not mounted yet. Retry via onFramesReport.
    @discardableResult
    public func setScrollTop(nodeID: Int, top: CGFloat) -> Bool {
        guard top.isFinite, let marker = scrollMarker(nodeID: nodeID, container: true),
              let scroll = marker.scroll, let metrics = marker.metrics else { return false }
        sharedVirtualViewport.explicitScroll(scroll)
        return setNativeScrollTop(scroll, top: top, documentHeight: metrics.contentSize.height,
            viewportHeight: metrics.viewportSize.height)
    }

    // Shared owners already hold their exact native scroller. They use this
    // same write path without enabling the optional node-query marker.
    @discardableResult
    func setNativeScrollTop(_ scroll: LUIHostNativeScroll, top: CGFloat,
        documentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        guard top.isFinite, documentHeight.isFinite, viewportHeight.isFinite else { return false }
        let offset = min(max(top, 0), max(0, documentHeight - viewportHeight))
        #if os(macOS)
        guard let document = scroll.documentView else { return false }
        let clip = scroll.contentView
        let visible = document.convert(clip.bounds, from: clip)
        let y = document.isFlipped ? document.bounds.minY + offset
            : document.bounds.maxY - offset - visible.height
        let destination = document.convert(CGRect(x: visible.minX, y: y,
            width: visible.width, height: visible.height), to: clip)
        clip.scroll(to: destination.origin)
        scroll.reflectScrolledClipView(clip)
        #else
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
            y: offset - scroll.adjustedContentInset.top), animated: false)
        #endif
        scheduleFramesReport()
        return true
    }

    /// Reveals a mounted retained node in its nearest enclosing native scroll
    /// viewport. True also means already visible. False flags an unavailable
    /// node/viewport; no deferred command is retained by the backend.
    @discardableResult
    public func scrollIntoView(nodeID: Int) -> Bool {
        guard let marker = scrollMarker(nodeID: nodeID, container: false),
              let target = marker.target,
              let scroll = LUIHostScrollMarker.enclosingScroll(of: target) else { return false }
        #if os(macOS)
        guard scroll.documentView != nil else { return false }
        #endif
        sharedVirtualViewport.explicitScroll(scroll)
        #if os(macOS)
        _ = target.scrollToVisible(target.bounds)
        #else
        scroll.scrollRectToVisible(target.convert(target.bounds, to: scroll), animated: false)
        #endif
        scheduleFramesReport()
        return true
    }

    /// Sizes and offset use logical points. UIKit's adjusted content insets are
    /// excluded from the viewport and normalized out of the top-origin offset.
    /// Missing, non-scroll and unmounted nodes return nil.
    public func scrollMetrics(nodeID: Int) -> (offset: CGFloat, contentSize: CGSize, viewportSize: CGSize)? {
        scrollMarker(nodeID: nodeID, container: true)?.metrics
    }

    private func scrollMarker(nodeID: Int, container: Bool) -> LUIHostScrollMarker? {
        guard let model = model(id: nodeID), !container || model.kind == .scroll else { return nil }
        if !hostQueries.scrollQueries.contains(nodeID) {
            hostQueries.scrollQueries.insert(nodeID)
            scheduleFramesReport()
        }
        guard let marker = hostQueries.scrollViews[nodeID]?.value,
              marker.model === model, marker.window != nil else { return nil }
        #if os(macOS)
        guard !marker.isHiddenOrHasHiddenAncestor else { return nil }
        #else
        var ancestor: UIView? = marker
        while let view = ancestor {
            if view.isHidden { return nil }
            ancestor = view.superview
        }
        #endif
        return marker
    }
}

/// An inert background probe, installed only for nodes queried by a host.
/// It never replaces native delegates or changes gesture/keyboard behavior.
struct LUIHostScrollProbe {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    var ownsScroll = false
}

#if os(macOS)
extension LUIHostScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> LUIHostScrollMarker { LUIHostScrollMarker() }
    func updateNSView(_ view: LUIHostScrollMarker, context: Context) {
        view.configure(model: model, backend: backend, ownsScroll: ownsScroll)
    }
    static func dismantleNSView(_ view: LUIHostScrollMarker, coordinator: ()) { view.disconnect() }
}
#else
extension LUIHostScrollProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> LUIHostScrollMarker { LUIHostScrollMarker() }
    func updateUIView(_ view: LUIHostScrollMarker, context: Context) {
        view.isUserInteractionEnabled = false
        view.configure(model: model, backend: backend, ownsScroll: ownsScroll)
    }
    static func dismantleUIView(_ view: LUIHostScrollMarker, coordinator: ()) { view.disconnect() }
}
#endif

final class LUIHostScrollMarker: LUIHostNativeView {
    weak var model: LUINodeModel?
    private weak var backend: LUIAppleBackend?
    private(set) weak var scroll: LUIHostNativeScroll?
    private var ownsScroll = false

    func configure(model: LUINodeModel, backend: LUIAppleBackend, ownsScroll: Bool) {
        if self.model !== model { disconnect() }
        self.model = model
        self.backend = backend
        self.ownsScroll = ownsScroll
        connect()
    }

    fileprivate static func enclosingScroll(of target: LUIHostNativeView) -> LUIHostNativeScroll? {
        var ancestor = target.superview
        while let view = ancestor {
            if let scroll = view as? LUIHostNativeScroll { return scroll }
            ancestor = view.superview
        }
        return nil
    }

    fileprivate var target: LUIHostNativeView? { ownsScroll ? scroll : self }

    fileprivate var metrics: (offset: CGFloat, contentSize: CGSize, viewportSize: CGSize)? {
        guard ownsScroll, let scroll, scroll.window != nil else { return nil }
        #if os(macOS)
        guard let document = scroll.documentView else { return nil }
        let visible = document.convert(scroll.contentView.bounds, from: scroll.contentView)
        let offset = document.isFlipped ? visible.minY - document.bounds.minY
            : document.bounds.maxY - visible.maxY
        return (max(0, offset), document.bounds.size, visible.size)
        #else
        let inset = scroll.adjustedContentInset
        return (max(0, scroll.contentOffset.y + inset.top), scroll.contentSize,
            CGSize(width: max(0, scroll.bounds.width - inset.left - inset.right),
                   height: max(0, scroll.bounds.height - inset.top - inset.bottom)))
        #endif
    }

    private func connect() {
        guard window != nil, let model, let backend,
              backend.model(id: model.id) === model else { disconnect(); return }
        let native = Self.enclosingScroll(of: self)
        let wasRegistered = backend.hostQueries.scrollViews[model.id]?.value === self
        let changed = scroll !== native
        scroll = native
        backend.hostQueries.scrollViews[model.id] = .init(value: self)
        if !wasRegistered || changed { backend.scheduleFramesReport() }
    }

    func disconnect() {
        if let model, let backend, backend.hostQueries.scrollViews[model.id]?.value === self {
            backend.hostQueries.scrollViews[model.id] = nil
            backend.scheduleFramesReport()
        }
        scroll = nil
    }

    #if os(macOS)
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); connect() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); connect() }
    override func layout() { super.layout(); connect() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func didMoveToSuperview() { super.didMoveToSuperview(); connect() }
    override func didMoveToWindow() { super.didMoveToWindow(); connect() }
    override func layoutSubviews() { super.layoutSubviews(); connect() }
    #endif
}

struct LUIHostScrollTargetModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    func body(content: Content) -> some View {
        if model.kind != .scroll, backend.hostQueries.scrollQueries.contains(model.id) {
            content.background {
                LUIHostScrollProbe(model: model, backend: backend)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}

struct LUIHostedScrollView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let children: [Int]
    @State private var viewportSize = CGSize.zero

    var body: some View {
        let horizontal = model.property(.orientation)?.stringValue == "horizontal"
        ScrollView(horizontal ? .horizontal : .vertical) {
            ZStack(alignment: .topLeading) {
                ForEach(children, id: \.self) { childID in
                    LUIAnyNodeView(nodeID: childID, backend: backend).equatable()
                }
            }
            .frame(minWidth: horizontal ? nil : viewportSize.width,
                   minHeight: horizontal ? viewportSize.height : nil, alignment: .topLeading)
            .environment(\.luiInsideScroll, true)
            .background {
                if model.property(.virtualViewportEpoch) != nil {
                    LUISharedOwnerProbe(model: model, backend: backend)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                if backend.hostQueries.scrollQueries.contains(model.id) {
                    LUIHostScrollProbe(model: model, backend: backend, ownsScroll: true)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
        // Accept smaller cross-axis proposals even while the content still
        // carries the previous viewport minimum. Keep scroll-axis ideal sizing.
        .frame(minWidth: horizontal ? nil : 0, maxWidth: horizontal ? nil : .infinity,
               minHeight: horizontal ? 0 : nil, maxHeight: horizontal ? .infinity : nil)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewportSize = $0 }
    }
}
