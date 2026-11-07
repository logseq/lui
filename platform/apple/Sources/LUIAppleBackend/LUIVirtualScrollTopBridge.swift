#if os(iOS)
import SwiftUI
import UIKit

/// A distant status-bar return needs its destination window before UIKit moves.
struct LUIVirtualScrollTopBridge: UIViewRepresentable {
    let prepared: Bool
    let requestTop: () -> Void

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ view: Probe, context: Context) {
        view.prepared = prepared
        view.requestTop = requestTop
        view.install()
        view.completeReturn()
    }

    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.uninstall() }

    final class Probe: UIView {
        var prepared = false
        var requestTop: (() -> Void)?
        private weak var scroll: UIScrollView?
        private let proxy = DelegateProxy()
        private var returning = false

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            proxy.shouldReturn = { [weak self] scroll in
                guard let self, scroll.contentOffset.y + scroll.adjustedContentInset.top > scroll.bounds.height else { return true }
                returning = true
                // Stop momentum without replacing the visible window while the destination is prepared.
                scroll.setContentOffset(scroll.contentOffset, animated: false)
                if prepared { completeReturn() } else { requestTop?() }
                return false
            }
            proxy.cancelReturn = { [weak self] in self?.returning = false }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { install() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            install()
        }

        func install() {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    if self.scroll !== scroll { uninstall(); self.scroll = scroll }
                    if scroll.delegate !== proxy {
                        proxy.original = scroll.delegate
                        scroll.delegate = proxy
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        func uninstall() {
            if let scroll, scroll.delegate === proxy { scroll.delegate = proxy.original }
            scroll = nil
        }

        func completeReturn() {
            guard returning, prepared, let scroll else { return }
            returning = false
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: false)
        }
    }

    private final class DelegateProxy: NSObject, UIScrollViewDelegate {
        weak var original: UIScrollViewDelegate?
        var shouldReturn: (@MainActor (UIScrollView) -> Bool)?
        var cancelReturn: (@MainActor () -> Void)?

        override func responds(to selector: Selector!) -> Bool {
            if super.responds(to: selector) { return true }
            return MainActor.assumeIsolated { original?.responds(to: selector) == true }
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            let target = MainActor.assumeIsolated { original }
            return target?.responds(to: selector) == true ? target : super.forwardingTarget(for: selector)
        }

        func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
            guard original?.scrollViewShouldScrollToTop?(scrollView) != false else { return false }
            return shouldReturn?(scrollView) ?? true
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            cancelReturn?()
            original?.scrollViewWillBeginDragging?(scrollView)
        }
    }
}
#endif
