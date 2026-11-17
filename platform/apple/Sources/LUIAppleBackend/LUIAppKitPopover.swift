#if os(macOS)
import AppKit
import SwiftUI

enum LUIAppKitPopoverAnchor {
    case point(UnitPoint)
    case rect(CGRect)
}

/// AppKit presents across independent hosting graphs; retained LUI declarations
/// still own admission and dismissal authority.
struct LUIAppKitPopover<Content: View>: NSViewRepresentable {
    let presentationID: AnyHashable?
    let isPresented: Binding<Bool>
    let attachment: LUIAppKitPopoverAnchor
    let arrowEdge: Edge
    let content: Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.changed = { [weak coordinator = context.coordinator] in coordinator?.schedule() }
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.connect()
        context.coordinator.update(
            id: presentationID, binding: isPresented, attachment: attachment, edge: arrowEdge, direction: context.environment.layoutDirection,
            content: AnyView(content.environment(\.self, context.environment)))
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        view.disconnect()
        coordinator.retire()
    }

    final class AnchorView: NSView {
        var changed: (() -> Void)?
        private weak var observedWindow: NSWindow?
        private weak var observedClip: NSClipView?
        private var observers: [NSObjectProtocol] = []

        func connect() {
            let clip = enclosingScrollView?.contentView
            guard observedWindow !== window || observedClip !== clip else { return }
            clearObservers()
            observedWindow = window
            observedClip = clip
            if let window { observe(NSWindow.didUpdateNotification, object: window) }
            if let clip {
                clip.postsBoundsChangedNotifications = true
                observe(NSView.boundsDidChangeNotification, object: clip)
            }
        }
        private func observe(_ name: Notification.Name, object: AnyObject) {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: object, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed?() }
            })
        }
        private func clearObservers() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
        }
        func disconnect() { changed = nil; clearObservers() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); connect(); changed?() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); connect(); changed?() }
        override func layout() { super.layout(); connect(); changed?() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        weak var anchor: AnchorView?
        private var requestedID: AnyHashable?
        private var presentedID: AnyHashable?
        private var binding: Binding<Bool>?
        private var attachment = LUIAppKitPopoverAnchor.point(.zero)
        private var edge = NSRectEdge.maxY
        private var content = AnyView(EmptyView())
        private var popover: NSPopover?
        private var controller: NSHostingController<AnyView>?
        private var sizeObservation: NSKeyValueObservation?
        private var scheduled = false
        private var retired = false

        func update(id: AnyHashable?, binding: Binding<Bool>, attachment: LUIAppKitPopoverAnchor, edge: Edge, direction: LayoutDirection, content: AnyView) {
            requestedID = id
            self.binding = binding
            self.attachment = attachment
            self.edge = switch edge {
            case .top: .maxY
            case .bottom: .minY
            case .leading: direction == .leftToRight ? .minX : .maxX
            case .trailing: direction == .leftToRight ? .maxX : .minX
            }
            self.content = content
            if presentedID == id { controller?.rootView = content }
            schedule()
        }

        func schedule() {
            guard !scheduled, !retired else { return }
            scheduled = true
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.scheduled = false
                    self.synchronize()
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }

        private func close() {
            let previous = popover
            sizeObservation = nil
            popover = nil
            controller = nil
            presentedID = nil
            previous?.delegate = nil
            previous?.close()
        }

        func retire() {
            retired = true
            binding = nil
            close()
        }

        private func synchronize() {
            guard !retired else { return }
            guard let id = requestedID, binding?.wrappedValue == true else { close(); return }
            guard let anchor, let window = anchor.window, let positioningView = window.contentView,
                  anchor.bounds.width > 0, anchor.bounds.height > 0 else { return }
            let preferred: NSRectEdge
            if positioningView.isFlipped {
                preferred = edge == .minY ? .maxY : edge == .maxY ? .minY : edge
            } else { preferred = edge }
            var rect: CGRect
            switch attachment {
            case .point(let point):
                rect = CGRect(x: anchor.bounds.width * point.x,
                              y: anchor.bounds.height * (1 - point.y), width: 0, height: 0)
            case .rect(let value):
                rect = CGRect(x: value.minX, y: anchor.bounds.height - value.maxY,
                              width: value.width, height: value.height)
            }
            rect = anchor.convert(rect, to: positioningView)
            if rect.isEmpty {
                // Empty rectangles mean the whole view in AppKit. A one-point
                // box preserves the placement of SwiftUI's point attachments.
                if !positioningView.isFlipped { rect.origin.y -= 1 }
                rect.size = CGSize(width: 1, height: 1)
            }
            if presentedID == id, let popover, popover.isShown {
                if popover.positioningRect != rect { popover.positioningRect = rect }
                return
            }
            close()
            let controller = NSHostingController(rootView: content)
            controller.sizingOptions = [.preferredContentSize]
            controller.safeAreaRegions = []
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = controller
            popover.delegate = self
            self.controller = controller
            self.popover = popover
            presentedID = id
            sizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak self] owner, change in
                MainActor.assumeIsolated {
                    guard let self, self.controller === owner, let size = change.newValue,
                          size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return }
                    if self.popover?.contentSize != size { self.popover?.contentSize = size }
                }
            }
            controller.view.layoutSubtreeIfNeeded()
            let size = controller.preferredContentSize
            if size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite {
                popover.contentSize = size
            }
            popover.show(relativeTo: rect, of: positioningView, preferredEdge: preferred)
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closed = notification.object as? NSPopover, closed === popover else { return }
            let current = presentedID == requestedID
            close()
            if current { binding?.wrappedValue = false }
        }
    }
}
#endif
