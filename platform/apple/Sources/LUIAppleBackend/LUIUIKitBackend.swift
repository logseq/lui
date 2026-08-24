#if canImport(UIKit)
import Foundation
import UIKit

@MainActor
public final class LUIUIKitBackend {
    public private(set) var generation = 0
    public var onEvent: ((LUIEvent) -> Void)?

    private var tree = LUIRetainedTree()
    private var views: [Int: UIView] = [:]
    private let decoder = JSONDecoder()

    public init() {}

    public func view(id: Int) -> UIView? {
        views[id]
    }

    public func id(of view: UIView) -> Int? {
        views.first(where: { $0.value === view })?.key
    }

    public var rootViews: [UIView] {
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

    private func makeView(kind: LUINodeKind, id: Int) -> UIView {
        let view: UIView
        switch kind {
        case .row, .column:
            let stack = UIStackView()
            stack.axis = kind == .row ? .horizontal : .vertical
            stack.alignment = .fill
            stack.distribution = .fill
            view = stack
        case .text:
            let label = UILabel()
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
            view = label
        case .button:
            let button = UIButton(type: .system)
            button.addAction(
                UIAction { [weak self] _ in self?.onEvent?(.press(node: id)) },
                for: .touchUpInside
            )
            view = button
        case .textInput:
            let field = LUITextField()
            field.borderStyle = .roundedRect
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.addAction(
                UIAction { [weak self, weak field] _ in
                    guard let text = field?.text else { return }
                    self?.onEvent?(.textChanged(node: id, text: text))
                },
                for: .editingChanged
            )
            view = field
        case .textArea:
            let area = LUIUIKitTextArea()
            area.font = .preferredFont(forTextStyle: .body)
            area.adjustsFontForContentSizeCategory = true
            area.onChange = { [weak self] text in
                self?.onEvent?(.textChanged(node: id, text: text))
            }
            view = area
        case .scroll:
            let scroll = UIScrollView()
            scroll.alwaysBounceVertical = true
            view = scroll
        case .spacer:
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
            view = spacer
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func apply(_ property: LUIProperty, value: LUIWireValue, to view: UIView) {
        switch (property, value) {
        case let (.text, .string(text)):
            if let label = view as? UILabel, label.text != text { label.text = text }
            if let button = view as? UIButton { button.configuration = .plain(); button.setTitle(text, for: .normal) }
            if let field = view as? UITextField, field.text != text { field.text = text }
            (view as? LUIUIKitTextArea)?.setText(text)
        case let (.enabled, .bool(enabled)):
            (view as? UIControl)?.isEnabled = enabled
            (view as? LUIUIKitTextArea)?.isEditorEnabled = enabled
        case let (.gap, .int(gap)):
            (view as? UIStackView)?.spacing = CGFloat(gap)
        case let (.padding, .int(padding)):
            if let stack = view as? UIStackView {
                let inset = CGFloat(padding)
                stack.isLayoutMarginsRelativeArrangement = true
                stack.directionalLayoutMargins = NSDirectionalEdgeInsets(
                    top: inset,
                    leading: inset,
                    bottom: inset,
                    trailing: inset
                )
            }
        case let (.background, .string(color)):
            view.backgroundColor = Self.color(named: color)
        case let (.placeholder, .string(placeholder)):
            (view as? UITextField)?.placeholder = placeholder
            (view as? LUIUIKitTextArea)?.placeholder = placeholder
        case let (.readOnly, .bool(readOnly)):
            (view as? LUITextField)?.isReadOnly = readOnly
            (view as? LUIUIKitTextArea)?.isReadOnly = readOnly
        case let (.accessibilityLabel, .string(label)):
            view.accessibilityLabel = label
        case let (.minLines, .int(lines)):
            (view as? LUIUIKitTextArea)?.minLines = lines
        case let (.maxLines, .int(lines)):
            (view as? LUIUIKitTextArea)?.maxLines = lines
        default:
            break
        }
    }

    private func insert(viewID childID: Int, into parentID: Int, at index: Int) throws {
        guard let parent = views[parentID], let child = views[childID] else {
            throw invalid("missing native parent or child")
        }
        if let stack = parent as? UIStackView {
            stack.insertArrangedSubview(child, at: index)
        } else if let scroll = parent as? UIScrollView {
            scroll.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                child.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                child.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                child.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            ])
        } else {
            parent.insertSubview(child, at: index)
        }
    }

    private func remove(viewID childID: Int, from parentID: Int) throws {
        guard let parent = views[parentID], let child = views[childID] else {
            throw invalid("missing native parent or child")
        }
        if let stack = parent as? UIStackView {
            stack.removeArrangedSubview(child)
        }
        child.removeFromSuperview()
    }

    private func invalid(_ message: String) -> LUIBackendError {
        .invalidBatch(message)
    }

    private static func color(named name: String) -> UIColor {
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
final class LUIUIKitTextArea: UITextView, UITextViewDelegate {
    var onChange: ((String) -> Void)?

    var minLines = 2 {
        didSet { updateIntrinsicHeight() }
    }

    var maxLines: Int? {
        didSet { updateIntrinsicHeight() }
    }

    var placeholder = "" {
        didSet {
            placeholderLabel.text = placeholder
            accessibilityHint = placeholder
            updatePlaceholder()
        }
    }

    var isReadOnly = false {
        didSet { updateEditability() }
    }

    var isEditorEnabled = true {
        didSet { updateEditability() }
    }

    private let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: CGSize {
        let lineHeight = font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let verticalInsets = textContainerInset.top + textContainerInset.bottom
        let minimumHeight = lineHeight * CGFloat(minLines) + verticalInsets
        guard bounds.width > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: minimumHeight)
        }

        let fittingSize = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        let naturalHeight = max(minimumHeight, super.sizeThatFits(fittingSize).height)
        let maximumHeight = maxLines.map { lineHeight * CGFloat($0) + verticalInsets }
        let height = maximumHeight.map { min(naturalHeight, $0) } ?? naturalHeight
        isScrollEnabled = maximumHeight.map { naturalHeight > $0 } ?? false
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    func setText(_ value: String) {
        guard text != value else { return }
        let selection = selectedRange
        text = value
        selectedRange = NSRange(location: min(selection.location, value.utf16.count), length: 0)
        updateAfterTextChange()
    }

    func textViewDidChange(_ textView: UITextView) {
        updateAfterTextChange()
        onChange?(textView.text)
    }

    private func configure() {
        delegate = self
        backgroundColor = .secondarySystemBackground
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 8

        placeholderLabel.font = font ?? .preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: textContainerInset.left + textContainer.lineFragmentPadding
            ),
            placeholderLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: textContainerInset.top
            ),
            placeholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -(textContainerInset.right + textContainer.lineFragmentPadding)
            ),
        ])
        updatePlaceholder()
    }

    private func updateEditability() {
        isEditable = isEditorEnabled && !isReadOnly
        isSelectable = isEditorEnabled
    }

    private func updateAfterTextChange() {
        updatePlaceholder()
        updateIntrinsicHeight()
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty || placeholder.isEmpty
    }

    private func updateIntrinsicHeight() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

private final class LUITextField: UITextField, UITextFieldDelegate {
    var isReadOnly = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        !isReadOnly
    }
}
#endif
