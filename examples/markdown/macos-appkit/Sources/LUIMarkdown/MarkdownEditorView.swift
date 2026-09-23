#if canImport(AppKit)
import AppKit
import LUIAppleBackend
import SwiftUI

// The extension element: an AppKit NSTextView hosted inside the SwiftUI
// tree LUI mounts for the `markdown-editor` schema. The OCaml model owns the
// canonical text; the view emits text-changed/cursor events and applies the
// model's text back only when it diverges (external loads etc.).

struct MarkdownEditorView: NSViewRepresentable {
    let context: LUIAppleExtensionViewContext

    final class Coordinator {
        weak var textView: MarkdownTextView?
        var didFocus = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context ctx: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let storage = NSTextStorage()
        let layout = MarkdownLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        let highlighter = MarkdownHighlighter(textView: textView)
        layout.theme = highlighter.theme
        storage.delegate = highlighter
        textView.highlighter = highlighter
        textView.minSize = NSSize(width: 0, height: 320)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        ctx.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context ctx: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView
        else { return }
        ctx.coordinator.textView = textView
        MarkdownTextView.active = textView

        if let value = context.property("placeholder"),
           case let .string(placeholder) = value {
            textView.placeholder = placeholder
        }
        if let value = context.property("readonly"),
           case let .bool(readonly) = value {
            textView.isEditable = !readonly
        }
        textView.emitEvent = { name, values in
            try? context.emit(name: name, values: values)
        }

        // model → view sync: only when the model diverged from what the view
        // already shows (never during an echo of our own emit).
        if let value = context.property("text"),
           case let .string(modelText) = value,
           textView.string != modelText {
            syncText(textView, to: modelText)
        }

        if !ctx.coordinator.didFocus, textView.window != nil {
            ctx.coordinator.didFocus = true
            textView.window?.makeFirstResponder(textView)
        }
    }

    /// Programmatic replacement — not a user edit, so set the string wholesale
    /// and restyle instead of routing through `applyEdit`.
    private func syncText(_ textView: MarkdownTextView, to text: String) {
        let selection = textView.selectedRange()
        textView.string = text
        let clamped = NSRange(
            location: min(selection.location, (text as NSString).length),
            length: 0)
        textView.highlighter?.activeCharacterRange = clamped
        textView.highlighter?.restyle()
        textView.setSelectedRange(clamped)
    }
}
#endif
