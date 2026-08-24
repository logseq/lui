import AppKit
import Foundation

public enum LUIBackendError: Error, Equatable {
    case invalidBatch(String)
}

public enum LUIEvent: Equatable, Sendable {
    case press(node: Int)
    case textChanged(node: Int, text: String)
}

private enum NodeKind: String, Decodable {
    case row, column, text, button, textInput = "text-input", scroll, spacer
}

private enum Property: String, Decodable {
    case text, enabled, gap, padding, background
}

private struct PatchBatch: Decodable {
    let generation: Int
    let ops: [PatchOperation]
}

private enum PatchOperation: Decodable {
    case createNode(id: Int, kind: NodeKind)
    case dropNode(id: Int)
    case setProp(id: Int, property: Property, value: WireValue)
    case insertChild(parent: Int, child: Int, index: Int)
    case removeChild(parent: Int, child: Int)
    case moveChild(parent: Int, child: Int, index: Int)

    private enum CodingKeys: String, CodingKey {
        case op, id, kind, property, value, parent, child, index
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .op) {
        case "create-node":
            self = .createNode(
                id: try values.decode(Int.self, forKey: .id),
                kind: try values.decode(NodeKind.self, forKey: .kind)
            )
        case "drop-node":
            self = .dropNode(id: try values.decode(Int.self, forKey: .id))
        case "set-prop":
            self = .setProp(
                id: try values.decode(Int.self, forKey: .id),
                property: try values.decode(Property.self, forKey: .property),
                value: try values.decode(WireValue.self, forKey: .value)
            )
        case "insert-child":
            self = .insertChild(
                parent: try values.decode(Int.self, forKey: .parent),
                child: try values.decode(Int.self, forKey: .child),
                index: try values.decode(Int.self, forKey: .index)
            )
        case "remove-child":
            self = .removeChild(
                parent: try values.decode(Int.self, forKey: .parent),
                child: try values.decode(Int.self, forKey: .child)
            )
        case "move-child":
            self = .moveChild(
                parent: try values.decode(Int.self, forKey: .parent),
                child: try values.decode(Int.self, forKey: .child),
                index: try values.decode(Int.self, forKey: .index)
            )
        default:
            throw LUIBackendError.invalidBatch("unknown patch operation")
        }
    }
}

private enum WireValue: Decodable {
    case string(String)
    case bool(Bool)
    case int(Int)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let decoded = try? value.decode(Bool.self) {
            self = .bool(decoded)
        } else if let decoded = try? value.decode(Int.self) {
            self = .int(decoded)
        } else {
            self = .string(try value.decode(String.self))
        }
    }
}

private struct NodeState {
    let kind: NodeKind
    var parent: Int?
    var children: [Int]
}

@MainActor
public final class LUIAppleBackend {
    public private(set) var generation = 0
    public var onEvent: ((LUIEvent) -> Void)?

    private var states: [Int: NodeState] = [:]
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
        states.compactMap { id, state in state.parent == nil ? views[id] : nil }
    }

    public func apply(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw LUIBackendError.invalidBatch("patch batch is not UTF-8")
        }
        let batch: PatchBatch
        do {
            batch = try decoder.decode(PatchBatch.self, from: data)
        } catch let error as LUIBackendError {
            throw error
        } catch {
            throw LUIBackendError.invalidBatch(error.localizedDescription)
        }

        let nextState = try validatedState(after: batch.ops)
        for operation in batch.ops {
            try commit(operation)
        }
        states = nextState
        generation = batch.generation
    }

    private func validatedState(after operations: [PatchOperation]) throws -> [Int: NodeState] {
        var next = states
        for operation in operations {
            switch operation {
            case let .createNode(id, kind):
                guard next[id] == nil else { throw invalid("node already exists") }
                next[id] = NodeState(kind: kind, parent: nil, children: [])
            case let .dropNode(id):
                guard let node = next[id] else { throw invalid("unknown node") }
                guard node.parent == nil && node.children.isEmpty else {
                    throw invalid("cannot drop an attached node")
                }
                next[id] = nil
            case let .setProp(id, property, value):
                guard let node = next[id] else { throw invalid("unknown node") }
                guard supports(property, on: node.kind), value.matches(property) else {
                    throw invalid("unsupported property value")
                }
            case let .insertChild(parent, child, index):
                guard var parentNode = next[parent], var childNode = next[child] else {
                    throw invalid("unknown parent or child")
                }
                guard childNode.parent == nil else { throw invalid("child is already attached") }
                guard index >= 0 && index <= parentNode.children.count else {
                    throw invalid("child index is out of bounds")
                }
                guard !isDescendant(parent, of: child, in: next) else {
                    throw invalid("child insertion would create a cycle")
                }
                parentNode.children.insert(child, at: index)
                childNode.parent = parent
                next[parent] = parentNode
                next[child] = childNode
            case let .removeChild(parent, child):
                guard var parentNode = next[parent], var childNode = next[child],
                      let index = parentNode.children.firstIndex(of: child) else {
                    throw invalid("child is not attached to parent")
                }
                parentNode.children.remove(at: index)
                childNode.parent = nil
                next[parent] = parentNode
                next[child] = childNode
            case let .moveChild(parent, child, index):
                guard var parentNode = next[parent],
                      let oldIndex = parentNode.children.firstIndex(of: child) else {
                    throw invalid("child is not attached to parent")
                }
                parentNode.children.remove(at: oldIndex)
                guard index >= 0 && index <= parentNode.children.count else {
                    throw invalid("child index is out of bounds")
                }
                parentNode.children.insert(child, at: index)
                next[parent] = parentNode
            }
        }
        return next
    }

    private func commit(_ operation: PatchOperation) throws {
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

    private func makeView(kind: NodeKind, id: Int) -> NSView {
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

    private func apply(_ property: Property, value: WireValue, to view: NSView) {
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

    private func isDescendant(_ target: Int, of root: Int, in state: [Int: NodeState]) -> Bool {
        guard let node = state[root] else { return false }
        return root == target || node.children.contains { isDescendant(target, of: $0, in: state) }
    }

    private func supports(_ property: Property, on kind: NodeKind) -> Bool {
        switch property {
        case .padding, .background: true
        case .text: kind == .text || kind == .button || kind == .textInput
        case .enabled: kind == .button || kind == .textInput
        case .gap: kind == .row || kind == .column
        }
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

private extension WireValue {
    func matches(_ property: Property) -> Bool {
        switch (property, self) {
        case (.text, .string), (.enabled, .bool), (.gap, .int),
             (.padding, .int), (.background, .string): true
        default: false
        }
    }
}
