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
        case let (.enabled, .bool(enabled)):
            (view as? NSControl)?.isEnabled = enabled
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
        case let (.readOnly, .bool(readOnly)):
            (view as? NSTextField)?.isEditable = !readOnly
        case let (.accessibilityLabel, .string(label)):
            view.setAccessibilityLabel(label)
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
