import SwiftUI

#if os(macOS)
  import AppKit

  struct LUISparseScrollProbe: NSViewRepresentable {
    let state: LUISparseVirtualState
    func makeNSView(context: Context) -> Probe { Probe(state: state) }
    func updateNSView(_ view: Probe, context: Context) { view.connect() }
    static func dismantleNSView(_ view: Probe, coordinator: ()) { view.disconnect() }

    final class Probe: NSView {
      private weak var state: LUISparseVirtualState?
      private weak var scrollView: NSScrollView?
      private var observers: [NSObjectProtocol] = []
      private var pointerMonitor: Any?
      private weak var composition: NSTextView?
      private var compositionRow: Int?
      private weak var focusedView: NSView?
      private var focusedRow: Int?
      private var menus: [ObjectIdentifier: (row: Int, token: UUID)] = [:]

      init(state: LUISparseVirtualState) {
        self.state = state
        super.init(frame: .zero)
      }
      required init?(coder: NSCoder) { nil }
      override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        connect()
      }
      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        connect()
      }
      override func layout() {
        super.layout()
        connect()
      }

      func connect() {
        var ancestor = superview
        while let view = ancestor, !(view is NSScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? NSScrollView else { return }
        if scrollView !== scroll {
          disconnect()
          scrollView = scroll
          scroll.contentView.postsBoundsChangedNotifications = true
          let center = NotificationCenter.default
          for (name, object) in [
            (NSView.boundsDidChangeNotification, scroll.contentView as AnyObject),
            (NSControl.textDidBeginEditingNotification, nil),
            (NSControl.textDidEndEditingNotification, nil),
            (NSText.didChangeNotification, nil),
            (NSWindow.didUpdateNotification, scroll.window as AnyObject?),
          ] {
            observers.append(
              center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
              })
          }
          for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            center.addObserver(self, selector: #selector(menuTracking(_:)), name: name, object: nil)
          }
          pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseUp, .rightMouseUp, .otherMouseUp,
          ]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointer(event) }
            return event
          }
          state?.scroll = { [weak self] offset, animated in
            self?.scroll(to: offset, animated: animated)
          }
          state?.refreshOwners = { [weak self] in self?.owners() }
        }
        changed()
      }

      func disconnect() {
        NotificationCenter.default.removeObserver(
          self, name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.removeObserver(
          self, name: NSMenu.didEndTrackingNotification, object: nil)
        for owner in menus.values {
          state?.popup(row: owner.row, token: owner.token, presented: false)
        }
        menus.removeAll()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        scrollView = nil
        state?.scroll = nil
        state?.refreshOwners = nil
      }

      private func changed() {
        guard let scroll = scrollView else { return }
        state?.viewport(
          offset: scroll.contentView.bounds.minY, height: scroll.contentView.bounds.height)
      }

      private func owners() {
        guard let scroll = scrollView, let document = scroll.documentView else { return }
        var responder = scroll.window?.firstResponder as? NSView
        if let fieldEditor = responder as? NSTextView, fieldEditor.isFieldEditor,
          let field = fieldEditor.delegate as? NSView
        {
          responder = field
        }
        if let responder, responder.isDescendant(of: document) {
          let id: Int?
          if responder === focusedView {
            id = focusedRow.flatMap { state?.contains($0) == true ? $0 : nil }
          } else {
            let frame = responder.convert(responder.bounds, to: document)
            id = state?.row(at: frame.midY)
            focusedView = responder
            focusedRow = id
          }
          if let text = scroll.window?.firstResponder as? NSTextView, text.hasMarkedText() {
            composition = text
            compositionRow = id
          }
          state?.focus(id)
        } else if composition?.hasMarkedText() == true {
          state?.focus(compositionRow)
        } else {
          composition = nil
          compositionRow = nil
          focusedView = nil
          focusedRow = nil
          state?.focus(nil)
        }
      }

      private func pointer(_ event: NSEvent) {
        guard let scroll = scrollView, event.window === scroll.window,
          let document = scroll.documentView
        else { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
          let point = scroll.contentView.convert(event.locationInWindow, from: nil)
          guard scroll.contentView.bounds.contains(point) else { return }
          let position = document.convert(event.locationInWindow, from: nil).y
          state?.pointer(state?.row(at: position))
        default:
          // Release after native mouse-up dispatch has finished its action.
          Task { @MainActor [weak self] in
            await Task.yield()
            self?.state?.pointer(nil)
          }
        }
      }

      @objc private func menuTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        let identity = ObjectIdentifier(menu)
        if notification.name == NSMenu.didEndTrackingNotification {
          if let owner = menus.removeValue(forKey: identity) {
            state?.popup(row: owner.row, token: owner.token, presented: false)
          }
          return
        }
        guard menus[identity] == nil, let document = scrollView?.documentView else { return }
        func owns(_ candidate: NSMenu?) -> Bool {
          guard let candidate else { return false }
          var current: NSMenu? = menu
          while let value = current {
            if value === candidate { return true }
            current = value.supermenu
          }
          return false
        }
        func ownerView(_ view: NSView) -> NSView? {
          if owns(view.menu) { return view }
          for child in view.subviews { if let found = ownerView(child) { return found } }
          return nil
        }
        guard let view = ownerView(document),
          let row = state?.row(at: view.convert(view.bounds, to: document).midY)
        else { return }
        let token = UUID()
        menus[identity] = (row, token)
        state?.popup(row: row, token: token, presented: true)
        // A native menu enters its own event-tracking loop. Transfer row
        // ownership before a source update can arrive in that loop.
        state?.flushOwnership()
      }

      private func scroll(to offset: CGFloat, animated: Bool) {
        guard let scroll = scrollView else { return }
        let point = NSPoint(x: scroll.contentView.bounds.minX, y: offset)
        if animated {
          NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            scroll.contentView.animator().setBoundsOrigin(point)
          }
        } else {
          scroll.contentView.scroll(to: point)
        }
        scroll.reflectScrolledClipView(scroll.contentView)
        changed()
      }
    }
  }
#elseif os(iOS)
  import UIKit

  struct LUISparseScrollProbe: UIViewRepresentable {
    let state: LUISparseVirtualState
    func makeUIView(context: Context) -> Probe { Probe(state: state) }
    func updateUIView(_ view: Probe, context: Context) { view.connect() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.disconnect() }

    final class Probe: UIView {
      private weak var state: LUISparseVirtualState?
      private weak var scrollView: UIScrollView?
      private var observation: NSKeyValueObservation?
      private var notifications: [NSObjectProtocol] = []
      private var touch: TouchObserver?
      private weak var focusedView: UIView?
      private var focusedRow: Int?
      private weak var composition: UIView?
      private var compositionRow: Int?
      init(state: LUISparseVirtualState) {
        self.state = state
        super.init(frame: .zero)
      }
      required init?(coder: NSCoder) { nil }
      override func didMoveToSuperview() {
        super.didMoveToSuperview()
        connect()
      }
      override func didMoveToWindow() {
        super.didMoveToWindow()
        connect()
      }
      override func layoutSubviews() {
        super.layoutSubviews()
        connect()
      }
      func connect() {
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? UIScrollView else { return }
        if scrollView !== scroll {
          disconnect()
          scrollView = scroll
          observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.changed() }
          }
          for name in [
            UITextField.textDidBeginEditingNotification, UITextField.textDidEndEditingNotification,
            UITextField.textDidChangeNotification, UITextView.textDidChangeNotification,
            UITextView.textDidBeginEditingNotification, UITextView.textDidEndEditingNotification,
          ] {
            notifications.append(
              NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
              })
          }
          let touch = TouchObserver()
          touch.changed = { [weak self] point in
            guard let self else { return }
            state?.pointer(point.flatMap { state?.row(at: $0.y) })
          }
          scroll.addGestureRecognizer(touch)
          self.touch = touch
          state?.scroll = { [weak self] offset, animated in
            guard let self, let scrollView else { return }
              scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: offset - scrollView.adjustedContentInset.top), animated: animated)
            changed()
          }
          state?.refreshOwners = { [weak self] in self?.owners() }
        }
        changed()
      }
      func disconnect() {
        observation = nil
        for token in notifications { NotificationCenter.default.removeObserver(token) }
        notifications.removeAll()
        if let touch { scrollView?.removeGestureRecognizer(touch) }
        touch = nil
        scrollView = nil
        state?.scroll = nil
        state?.refreshOwners = nil
      }
      private func changed() {
        guard let scrollView else { return }
        let inset = scrollView.adjustedContentInset
        state?.viewport(offset: scrollView.contentOffset.y + inset.top,
                        height: max(0, scrollView.bounds.height - inset.top - inset.bottom))
      }
      private func owners() {
        guard let scrollView else { return }
        func firstResponder(_ view: UIView) -> UIView? {
          if view.isFirstResponder { return view }
          for child in view.subviews { if let found = firstResponder(child) { return found } }
          return nil
        }
        guard let responder = firstResponder(scrollView) else {
          if (composition as? any UITextInput)?.markedTextRange != nil {
            state?.focus(compositionRow)
          } else {
            composition = nil
            compositionRow = nil
            focusedView = nil
            focusedRow = nil
            state?.focus(nil)
          }
          return
        }
        if responder === focusedView {
          state?.focus(focusedRow.flatMap { state?.contains($0) == true ? $0 : nil })
        } else {
          let frame = responder.convert(responder.bounds, to: scrollView)
          focusedView = responder
          focusedRow = state?.row(at: frame.midY)
          state?.focus(focusedRow)
        }
        if (responder as? any UITextInput)?.markedTextRange != nil {
          composition = responder
          compositionRow = focusedRow
        }
      }
    }

    final class TouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
      var changed: ((CGPoint?) -> Void)?
      override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
      }
      convenience init() { self.init(target: nil, action: nil) }
      override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        changed?(touches.first?.location(in: view))
      }
      override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        changed?(nil)
        state = .failed
      }
      override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        changed?(nil)
        state = .failed
      }
      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
      ) -> Bool { true }
    }
  }
#endif
