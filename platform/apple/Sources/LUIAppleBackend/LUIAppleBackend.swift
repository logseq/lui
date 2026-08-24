import Foundation

#if canImport(AppKit)
import AppKit

@MainActor
public final class LUIAppleBackend {
    public private(set) var generation = 0
    public var onEvent: ((LUIEvent) -> Void)?

    private var tree = LUIRetainedTree()
    private var views: [Int: NSView] = [:]
    private var controls: [Int: ControlTarget] = [:]
    private let decoder = JSONDecoder()

    public init() {}

    public func view(id: Int) -> NSView? {
        views[id]
    }

    public func id(of view: NSView) -> Int? {
        views.first(where: { $0.value === view })?.key
    }

    public var rootViews: [NSView] {
        tree.rootIDs.compactMap { views[$0] }
    }

    public func apply(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw LUIBackendError.invalidBatch("patch batch is not UTF-8")
        }
        let batch: LUIPatchBatch
        do {
            batch = try decoder.decode(LUIPatchBatch.self, from: data)
        } catch let error as LUIBackendError {
            throw error
        } catch {
            throw LUIBackendError.invalidBatch(error.localizedDescription)
        }

        let expectedGeneration = generation + 1
        guard batch.generation == expectedGeneration else {
            throw invalid(
                "expected patch generation \(expectedGeneration), received \(batch.generation)"
            )
        }

        let nextTree = try tree.applying(batch.ops)
        for operation in batch.ops {
            try commit(operation)
        }
        tree = nextTree
        generation = batch.generation
    }

    private func commit(_ operation: LUIPatchOperation) throws {
        switch operation {
        case let .createNode(id, kind):
            views[id] = makeView(kind: kind, id: id)
        case let .dropNode(id):
            views[id]?.removeFromSuperview()
            views[id] = nil
            controls[id] = nil
        case let .setProp(id, property, value):
            guard let view = views[id] else { throw invalid("missing native view") }
            apply(property, value: value, to: view)
        case let .insertChild(parent, child, index):
            try insert(viewID: child, into: parent, at: index)
        case let .removeChild(parent, child):
            try remove(viewID: child, from: parent)
        case let .moveChild(parent, child, index):
            try remove(viewID: child, from: parent)
            try insert(viewID: child, into: parent, at: index)
        }
    }

    private func makeView(kind: LUINodeKind, id: Int) -> NSView {
        switch kind {
        case .row, .column:
            let view = NSStackView()
            view.orientation = kind == .row ? .horizontal : .vertical
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        case .text:
            let view = NSTextField(labelWithString: "")
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        case .button:
            let target = ControlTarget { [weak self] in self?.onEvent?(.press(node: id)) }
            let view = NSButton(title: "", target: target, action: #selector(ControlTarget.performAction))
            controls[id] = target
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        case .textInput:
            let target = ControlTarget { [weak self] in
                guard let field = self?.views[id] as? NSTextField else { return }
                self?.onEvent?(.textChanged(node: id, text: field.stringValue))
            }
            let view = NSTextField(string: "")
            view.delegate = target
            controls[id] = target
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        case .textArea:
            let view = LUIAppKitTextArea()
            view.onChange = { [weak self] text in
                self?.onEvent?(.textChanged(node: id, text: text))
            }
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        case .scroll:
            let view = NSScrollView()
            view.hasVerticalScroller = true
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        case .spacer:
            let view = NSView()
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }
    }

    private func apply(_ property: LUIProperty, value: LUIWireValue, to view: NSView) {
        switch (property, value) {
        case let (.text, .string(text)):
            if let label = view as? NSTextField { label.stringValue = text }
            if let button = view as? NSButton { button.title = text }
            if let area = view as? LUIAppKitTextArea { area.setText(text) }
        case let (.enabled, .bool(enabled)):
            (view as? NSControl)?.isEnabled = enabled
            (view as? LUIAppKitTextArea)?.isEditorEnabled = enabled
        case let (.gap, .int(gap)):
            (view as? NSStackView)?.spacing = CGFloat(gap)
        case let (.padding, .int(padding)):
            if let stack = view as? NSStackView {
                let inset = CGFloat(padding)
                stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
            }
        case let (.background, .string(color)):
            view.wantsLayer = true
            view.layer?.backgroundColor = Self.color(named: color).cgColor
        case let (.placeholder, .string(placeholder)):
            (view as? NSTextField)?.placeholderString = placeholder
            (view as? LUIAppKitTextArea)?.placeholder = placeholder
        case let (.readOnly, .bool(readOnly)):
            (view as? NSTextField)?.isEditable = !readOnly
            (view as? LUIAppKitTextArea)?.isReadOnly = readOnly
        case let (.accessibilityLabel, .string(label)):
            view.setAccessibilityLabel(label)
        case let (.minLines, .int(lines)):
            (view as? LUIAppKitTextArea)?.minLines = lines
        case let (.maxLines, .int(lines)):
            (view as? LUIAppKitTextArea)?.maxLines = lines
        default:
            break
        }
    }

    private func insert(viewID childID: Int, into parentID: Int, at index: Int) throws {
        guard let parent = views[parentID], let child = views[childID] else {
            throw invalid("missing native parent or child")
        }
        if let stack = parent as? NSStackView {
            stack.insertArrangedSubview(child, at: index)
        } else if let scroll = parent as? NSScrollView {
            scroll.documentView = child
        } else {
            parent.addSubview(child, positioned: .above, relativeTo: index == 0 ? nil : parent.subviews[index - 1])
        }
    }

    private func remove(viewID childID: Int, from parentID: Int) throws {
        guard let parent = views[parentID], let child = views[childID] else {
            throw invalid("missing native parent or child")
        }
        if let stack = parent as? NSStackView {
            stack.removeArrangedSubview(child)
        } else if let scroll = parent as? NSScrollView, scroll.documentView === child {
            scroll.documentView = nil
        }
        child.removeFromSuperview()
    }

    private func invalid(_ message: String) -> LUIBackendError {
        .invalidBatch(message)
    }

    private static func color(named name: String) -> NSColor {
        switch name.lowercased() {
        case "black": .black
        case "white": .white
        case "red": .systemRed
        case "blue": .systemBlue
        case "green": .systemGreen
        default: .clear
        }
    }
}

@MainActor
final class LUIAppKitTextArea: NSScrollView, NSTextViewDelegate {
    let textView = NSTextView(frame: .zero)
    var onChange: ((String) -> Void)?

    var minLines = 2 {
        didSet { updateIntrinsicHeight() }
    }

    var maxLines: Int? {
        didSet { updateIntrinsicHeight() }
    }

    var placeholder = "" {
        didSet {
            placeholderLabel.stringValue = placeholder
            textView.setAccessibilityPlaceholderValue(placeholder)
            updatePlaceholder()
        }
    }

    var isReadOnly = false {
        didSet { updateEditability() }
    }

    var isEditorEnabled = true {
        didSet { updateEditability() }
    }

    private let placeholderLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: NSSize {
        let lineHeight = nativeLineHeight
        let verticalInsets = textView.textContainerInset.height * 2
        let minimumHeight = lineHeight * CGFloat(minLines) + verticalInsets

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minimumHeight)
        }
        layoutManager.ensureLayout(for: textContainer)
        let contentHeight = ceil(layoutManager.usedRect(for: textContainer).height + verticalInsets)
        let desiredHeight = max(minimumHeight, contentHeight)
        let maximumHeight = maxLines.map { lineHeight * CGFloat($0) + verticalInsets }
        let height = maximumHeight.map { min(desiredHeight, $0) } ?? desiredHeight
        hasVerticalScroller = maximumHeight.map { desiredHeight > $0 } ?? false
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    func setText(_ text: String) {
        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(selection.location, text.utf16.count), length: 0))
        updateAfterTextChange()
    }

    func textDidChange(_ notification: Notification) {
        updateAfterTextChange()
        onChange?(textView.string)
    }

    private var nativeLineHeight: CGFloat {
        let font = textView.font ?? NSFont.preferredFont(forTextStyle: .body)
        return textView.layoutManager?.defaultLineHeight(for: font) ?? font.boundingRectForFont.height
    }

    private func configure() {
        borderType = .bezelBorder
        drawsBackground = true
        autohidesScrollers = true

        textView.delegate = self
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isRichText = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        documentView = textView

        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel, positioned: .above, relativeTo: contentView)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: textView.textContainerInset.width + 5
            ),
            placeholderLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: textView.textContainerInset.height
            ),
        ])
        updatePlaceholder()
    }

    private func updateEditability() {
        textView.isEditable = isEditorEnabled && !isReadOnly
        textView.isSelectable = isEditorEnabled
    }

    private func updateAfterTextChange() {
        updatePlaceholder()
        updateIntrinsicHeight()
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.string.isEmpty || placeholder.isEmpty
    }

    private func updateIntrinsicHeight() {
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
}

@MainActor
private final class ControlTarget: NSObject, NSTextFieldDelegate {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction() {
        action()
    }

    func controlTextDidChange(_ notification: Notification) {
        action()
    }
}
#endif
