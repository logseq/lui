import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// SwiftUI has no read-only TextField modifier. Configure the existing native
// editor so focus, selection, copy, styling and retained identity stay native.
struct LUIReadOnlyTextControl: ViewModifier {
    let readOnly: Bool
    var nativeSearch = false
    func body(content: Content) -> some View {
        content.background(LUIReadOnlyProbe(readOnly: readOnly, nativeSearch: nativeSearch).frame(width: 0, height: 0))
    }
}

#if os(macOS)
private struct LUIReadOnlyProbe: NSViewRepresentable {
    let readOnly: Bool
    let nativeSearch: Bool
    func makeNSView(context: Context) -> LUIReadOnlyProbeView { LUIReadOnlyProbeView() }
    func updateNSView(_ view: LUIReadOnlyProbeView, context: Context) {
        view.readOnly = readOnly
        view.refresh()
    }
}

private final class LUIReadOnlyProbeView: NSView {
    var readOnly = false
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); refresh() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refresh() }
    override func layout() { super.layout(); apply() }
    func refresh() {
        apply()
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }
    private func apply() {
        func fields(in view: NSView) -> [NSTextField] {
            if let field = view as? NSTextField { return [field] }
            return view.subviews.flatMap { fields(in: $0) }
        }
        var ancestor = superview
        for _ in 0..<6 {
            guard let current = ancestor else { return }
            let controls = fields(in: current)
            if controls.count == 1, let field = controls.first {
                if field.isEditable == readOnly { field.isEditable = !readOnly }
                if !field.isSelectable { field.isSelectable = true }
                // The shared field editor may already be the first responder
                // when a retained patch toggles read-only during selection.
                if let editor = field.currentEditor() as? NSTextView,
                   editor.isEditable == readOnly { editor.isEditable = !readOnly }
                return
            }
            ancestor = current.superview
        }
    }
}
#else
private struct LUIReadOnlyProbe: UIViewRepresentable {
    let readOnly: Bool
    let nativeSearch: Bool
    func makeUIView(context: Context) -> LUIReadOnlyProbeView { LUIReadOnlyProbeView() }
    func updateUIView(_ view: LUIReadOnlyProbeView, context: Context) {
        view.readOnly = readOnly
        view.nativeSearch = nativeSearch
        view.refresh()
    }
}

private final class LUIReadOnlyFieldDelegate: NSObject, UITextFieldDelegate {
    var readOnly = false
    nonisolated(unsafe) weak var original: (any UITextFieldDelegate)?
    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }
    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? { original }
    func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        !readOnly && (original?.textField?(field, shouldChangeCharactersIn: range,
                                          replacementString: string) ?? true)
    }
    func textFieldShouldClear(_ field: UITextField) -> Bool {
        !readOnly && (original?.textFieldShouldClear?(field) ?? true)
    }
}

private final class LUIReadOnlyProbeView: UIView {
    var readOnly = false
    var nativeSearch = false
    private let fieldDelegate = LUIReadOnlyFieldDelegate()
    override func didMoveToSuperview() { super.didMoveToSuperview(); refresh() }
    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }
    override func layoutSubviews() { super.layoutSubviews(); apply() }
    func refresh() {
        apply()
        DispatchQueue.main.async { [weak self] in self?.apply() }
    }
    private func configure(_ field: UITextField) {
        fieldDelegate.readOnly = readOnly
        if field.delegate !== fieldDelegate {
            fieldDelegate.original = field.delegate
            field.delegate = fieldDelegate
        }
    }
    private func apply() {
        if nativeSearch {
            var responder: UIResponder? = self
            while let current = responder {
                if let controller = current as? UIViewController,
                   let search = controller.navigationItem.searchController
                    ?? controller.navigationController?.topViewController?.navigationItem.searchController {
                    configure(search.searchBar.searchTextField)
                    return
                }
                responder = current.next
            }
            return
        }
        func controls(in view: UIView) -> [UIView] {
            if view is UITextField || view is UITextView { return [view] }
            return view.subviews.flatMap { controls(in: $0) }
        }
        var ancestor = superview
        for _ in 0..<6 {
            guard let current = ancestor else { return }
            let editors = controls(in: current)
            if editors.count == 1, let editor = editors.first {
                if let field = editor as? UITextField {
                    configure(field)
                } else if let textView = editor as? UITextView {
                    textView.isEditable = !readOnly
                    textView.isSelectable = true
                }
                return
            }
            ancestor = current.superview
        }
    }
}
#endif
