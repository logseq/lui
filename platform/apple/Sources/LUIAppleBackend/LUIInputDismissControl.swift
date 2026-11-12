import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// A probe may climb only through the input's small native wrapper hierarchy.
// An ambiguous or oversized container is never searched as if it owned a field.
enum LUIInputEditorSearch<NativeView> {
    case empty
    case one(NativeView)
    case ambiguous
    case exhausted

    static func find(in root: NativeView, remaining: inout Int,
                     isEditor: (NativeView) -> Bool,
                     children: (NativeView) -> [NativeView]) -> Self {
        var pending = [root]
        var found: NativeView?
        while let view = pending.popLast() {
            guard remaining > 0 else { return .exhausted }
            remaining -= 1
            if isEditor(view) {
                if case .some = found { return .ambiguous }
                found = view
            } else {
                let descendants = children(view)
                guard descendants.count <= remaining - pending.count else { return .exhausted }
                pending.append(contentsOf: descendants)
            }
        }
        return found.map(Self.one) ?? .empty
    }
}

// State belongs to the retained input, not the surrounding dialog. Cancellation
// can synchronously remove that dialog and cause a blur before the event returns.
@MainActor
final class LUIInputDismissSession {
    private weak var backend: LUIAppleBackend?
    private var model: LUINodeModel?
    private var suppressBlurSubmit = false
    private var cancellationSent = false
    private var editing = false
    var requestCancel: (() -> Bool)?

    func configure(model: LUINodeModel, backend: LUIAppleBackend) {
        if self.model !== model || self.backend !== backend {
            suppressBlurSubmit = false
            cancellationSent = false
            editing = false
        }
        self.model = model
        self.backend = backend
    }

    private var currentModel: LUINodeModel? {
        guard let model, let backend, backend.model(id: model.id) === model,
              model.isEnabled else { return nil }
        return model
    }

    var dismissEnabled: Bool { currentModel?.property(.dismissEnabled)?.boolValue == true }
    var observesEditing: Bool {
        dismissEnabled || currentModel?.property(.submitOnBlur)?.boolValue == true
    }

    func focusBegan() { editing = true; textEdited() }
    func textEdited() { suppressBlurSubmit = false; cancellationSent = false }

    func submit() {
        guard !cancellationSent, let model = currentModel, let backend else { return }
        suppressBlurSubmit = true
        try? backend.performSubmit(node: model.id)
    }

    @discardableResult
    func cancel(composing: Bool) -> Bool {
        guard !composing, !cancellationSent, dismissEnabled,
              let model = currentModel, let backend else { return false }
        suppressBlurSubmit = true
        cancellationSent = true
        do {
            try backend.performDismiss(node: model.id)
            return true
        } catch {
            suppressBlurSubmit = false
            cancellationSent = false
            return false
        }
    }

    func focusEnded(composing: Bool = false) {
        guard editing else { return }
        editing = false
        let suppressed = suppressBlurSubmit
        suppressBlurSubmit = false
        guard !composing, !suppressed, let model = currentModel,
              model.property(.submitOnBlur)?.boolValue == true else { return }
        try? backend?.performSubmit(node: model.id)
    }
}

struct LUIInputDismissControl: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let session: LUIInputDismissSession
    var nativeSearch = false

    func body(content: Content) -> some View {
        content.background(
            LUIInputDismissProbe(model: model, backend: backend, session: session,
                                 nativeSearch: nativeSearch).frame(width: 0, height: 0)
        )
        #if os(iOS)
        .onKeyPress(.escape, phases: .down) { press in
            guard press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else {
                return .ignored
            }
            return session.requestCancel?() == true ? .handled : .ignored
        }
        #endif
    }
}

#if os(macOS)
private struct LUIInputDismissProbe: NSViewRepresentable {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let session: LUIInputDismissSession
    let nativeSearch: Bool
    func makeNSView(context: Context) -> LUIInputDismissProbeView { LUIInputDismissProbeView() }
    func updateNSView(_ view: LUIInputDismissProbeView, context: Context) {
        session.configure(model: model, backend: backend)
        view.session = session
        view.refresh()
    }
    static func dismantleNSView(_ view: LUIInputDismissProbeView, coordinator: ()) { view.disconnect() }
}

final class LUIInputDismissProbeView: NSView {
    var session: LUIInputDismissSession?
    private weak var control: NSView?
    private var monitor: Any?
    var monitorsEscape: Bool { monitor != nil }

    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); refresh() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refresh() }
    override func layout() { super.layout(); connect() }

    func refresh() {
        connect()
        DispatchQueue.main.async { [weak self] in self?.connect() }
    }

    private func connect() {
        guard window != nil, session?.observesEditing == true else { disconnect(); return }
        var remaining = 128
        var ancestor = superview
        for _ in 0..<6 {
            guard let current = ancestor else { break }
            let result = LUIInputEditorSearch.find(in: current, remaining: &remaining,
                isEditor: { $0 is NSTextField || $0 is NSTextView }, children: { $0.subviews })
            switch result {
            case .ambiguous, .exhausted:
                disconnect()
                return
            case let .one(target):
                if control !== target {
                    disconnect()
                    control = target
                    for name in [NSControl.textDidBeginEditingNotification,
                                 NSText.didBeginEditingNotification] {
                        NotificationCenter.default.addObserver(self, selector: #selector(began),
                                                               name: name, object: target)
                    }
                    for name in [NSControl.textDidEndEditingNotification,
                                 NSText.didEndEditingNotification] {
                        NotificationCenter.default.addObserver(self, selector: #selector(ended),
                                                               name: name, object: target)
                    }
                    if focusedEditor != nil { session?.focusBegan() }
                }
                updateMonitor()
                return
            case .empty: break
            }
            if current === window?.contentView { break }
            ancestor = current.superview
        }
        disconnect()
    }

    private var focusedEditor: NSTextView? {
        let editor = (control as? NSTextField)?.currentEditor() as? NSTextView ?? control as? NSTextView
        guard let editor, window?.firstResponder === editor else { return nil }
        return editor
    }

    @objc private func began(_ notification: Notification) {
        session?.focusBegan()
        updateMonitor()
    }
    @objc private func ended(_ notification: Notification) {
        removeMonitor()
        let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView
            ?? (control as? NSTextField)?.currentEditor() as? NSTextView
            ?? control as? NSTextView
        session?.focusEnded(composing: editor?.hasMarkedText() == true)
    }

    private func updateMonitor() {
        guard session?.dismissEnabled == true, focusedEditor != nil else { removeMonitor(); return }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event) == true ? nil : event
            }
        }
    }

    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !event.isARepeat, event.keyCode == 53, event.window === window,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              let editor = focusedEditor else { return false }
        return session?.cancel(composing: editor.hasMarkedText()) == true
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
    func disconnect() {
        removeMonitor()
        NotificationCenter.default.removeObserver(self)
        control = nil
    }
}
#else
private struct LUIInputDismissProbe: UIViewRepresentable {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let session: LUIInputDismissSession
    let nativeSearch: Bool
    func makeUIView(context: Context) -> LUIInputDismissProbeView { LUIInputDismissProbeView() }
    func updateUIView(_ view: LUIInputDismissProbeView, context: Context) {
        session.configure(model: model, backend: backend)
        view.session = session
        view.nativeSearch = nativeSearch
        view.refresh()
    }
    static func dismantleUIView(_ view: LUIInputDismissProbeView, coordinator: ()) { view.disconnect() }
}

final class LUIInputDismissProbeView: UIView {
    var session: LUIInputDismissSession?
    var nativeSearch = false
    private weak var control: UIView?
    override func didMoveToSuperview() { super.didMoveToSuperview(); refresh() }
    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
    override func layoutSubviews() { super.layoutSubviews(); connect() }

    func refresh() {
        connect()
        DispatchQueue.main.async { [weak self] in self?.connect() }
    }
    private func connect() {
        guard window != nil, session?.observesEditing == true else { disconnect(); return }
        if nativeSearch {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let search = controller.navigationItem.searchController
                    ?? controller.navigationController?.topViewController?.navigationItem.searchController {
                    attach(search.searchBar.searchTextField)
                    return
                }
                responder = current.next
            }
        } else {
            var remaining = 128
            var ancestor = superview
            for _ in 0..<6 {
                guard let current = ancestor else { break }
                let result = LUIInputEditorSearch.find(in: current, remaining: &remaining,
                    isEditor: { $0 is UITextField || $0 is UITextView }, children: { $0.subviews })
                switch result {
                case .ambiguous, .exhausted:
                    disconnect()
                    return
                case let .one(target): attach(target); return
                case .empty: break
                }
                if current.next is UIViewController { break }
                ancestor = current.superview
            }
        }
        disconnect()
    }
    private func attach(_ target: UIView) {
        if control !== target {
            disconnect()
            control = target
            for name in [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(began), name: name, object: target)
            }
            for name in [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(ended), name: name, object: target)
            }
            if target.isFirstResponder { session?.focusBegan() }
        }
        session?.requestCancel = { [weak self] in self?.cancelFocusedInput() == true }
    }
    @discardableResult
    func cancelFocusedInput() -> Bool {
        guard let control, control.isFirstResponder, let input = control as? any UITextInput else { return false }
        return session?.cancel(composing: input.markedTextRange != nil) == true
    }
    @objc private func began(_ notification: Notification) { session?.focusBegan() }
    @objc private func ended(_ notification: Notification) {
        session?.focusEnded(composing: (control as? any UITextInput)?.markedTextRange != nil)
    }
    func disconnect() {
        NotificationCenter.default.removeObserver(self)
        session?.requestCancel = nil
        control = nil
    }
}
#endif
