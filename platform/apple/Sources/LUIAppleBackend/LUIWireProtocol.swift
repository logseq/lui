import Foundation

public enum LUIBackendError: Error, Equatable {
    case invalidBatch(String)
}

public enum LUIEvent: Equatable, Sendable {
    case press(node: Int)
    case textChanged(node: Int, text: String)
}

enum LUINodeKind: String, Decodable {
    case row, column, text, button, textInput = "text-input", scroll, spacer
}

enum LUIProperty: String, Decodable {
    case text, enabled, gap, padding, background, placeholder
    case readOnly = "read-only"
    case accessibilityLabel = "accessibility-label"
}

struct LUIPatchBatch: Decodable {
    let generation: Int
    let ops: [LUIPatchOperation]
}

enum LUIPatchOperation: Decodable {
    case createNode(id: Int, kind: LUINodeKind)
    case dropNode(id: Int)
    case setProp(id: Int, property: LUIProperty, value: LUIWireValue)
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
                kind: try values.decode(LUINodeKind.self, forKey: .kind)
            )
        case "drop-node":
            self = .dropNode(id: try values.decode(Int.self, forKey: .id))
        case "set-prop":
            self = .setProp(
                id: try values.decode(Int.self, forKey: .id),
                property: try values.decode(LUIProperty.self, forKey: .property),
                value: try values.decode(LUIWireValue.self, forKey: .value)
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

enum LUIWireValue: Decodable {
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

    func matches(_ property: LUIProperty) -> Bool {
        switch (property, self) {
        case (.text, .string), (.enabled, .bool), (.gap, .int),
             (.padding, .int), (.background, .string),
             (.placeholder, .string), (.readOnly, .bool),
             (.accessibilityLabel, .string): true
        default: false
        }
    }
}

struct LUINodeState {
    let kind: LUINodeKind
    var parent: Int?
    var children: [Int]
}

struct LUIRetainedTree {
    private(set) var nodes: [Int: LUINodeState] = [:]

    var rootIDs: [Int] {
        nodes.compactMap { id, node in node.parent == nil ? id : nil }
    }

    func applying(_ operations: [LUIPatchOperation]) throws -> Self {
        var next = self
        for operation in operations {
            try next.apply(operation)
        }
        return next
    }

    private mutating func apply(_ operation: LUIPatchOperation) throws {
        switch operation {
        case let .createNode(id, kind):
            guard nodes[id] == nil else { throw invalid("node already exists") }
            nodes[id] = LUINodeState(kind: kind, parent: nil, children: [])
        case let .dropNode(id):
            guard let node = nodes[id] else { throw invalid("unknown node") }
            guard node.parent == nil && node.children.isEmpty else {
                throw invalid("cannot drop an attached node")
            }
            nodes[id] = nil
        case let .setProp(id, property, value):
            guard let node = nodes[id] else { throw invalid("unknown node") }
            guard Self.supports(property, on: node.kind), value.matches(property) else {
                throw invalid("unsupported property value")
            }
        case let .insertChild(parent, child, index):
            guard var parentNode = nodes[parent], var childNode = nodes[child] else {
                throw invalid("unknown parent or child")
            }
            guard Self.canContainChildren(parentNode.kind) else {
                throw invalid("parent cannot contain children")
            }
            guard !Self.isSingleChildContainer(parentNode.kind) || parentNode.children.isEmpty else {
                throw invalid("parent can contain only one child")
            }
            guard childNode.parent == nil else { throw invalid("child is already attached") }
            guard index >= 0 && index <= parentNode.children.count else {
                throw invalid("child index is out of bounds")
            }
            guard !isDescendant(parent, of: child) else {
                throw invalid("child insertion would create a cycle")
            }
            parentNode.children.insert(child, at: index)
            childNode.parent = parent
            nodes[parent] = parentNode
            nodes[child] = childNode
        case let .removeChild(parent, child):
            guard var parentNode = nodes[parent], var childNode = nodes[child],
                  let index = parentNode.children.firstIndex(of: child) else {
                throw invalid("child is not attached to parent")
            }
            parentNode.children.remove(at: index)
            childNode.parent = nil
            nodes[parent] = parentNode
            nodes[child] = childNode
        case let .moveChild(parent, child, index):
            guard var parentNode = nodes[parent],
                  let oldIndex = parentNode.children.firstIndex(of: child) else {
                throw invalid("child is not attached to parent")
            }
            parentNode.children.remove(at: oldIndex)
            guard index >= 0 && index <= parentNode.children.count else {
                throw invalid("child index is out of bounds")
            }
            parentNode.children.insert(child, at: index)
            nodes[parent] = parentNode
        }
    }

    private func isDescendant(_ target: Int, of root: Int) -> Bool {
        guard let node = nodes[root] else { return false }
        return root == target || node.children.contains { isDescendant(target, of: $0) }
    }

    private static func supports(_ property: LUIProperty, on kind: LUINodeKind) -> Bool {
        switch property {
        case .padding, .background: true
        case .text: kind == .text || kind == .button || kind == .textInput
        case .enabled: kind == .button || kind == .textInput
        case .gap: kind == .row || kind == .column
        case .placeholder, .readOnly: kind == .textInput
        case .accessibilityLabel: kind == .textInput
        }
    }

    private static func canContainChildren(_ kind: LUINodeKind) -> Bool {
        kind == .row || kind == .column || kind == .scroll
    }

    private static func isSingleChildContainer(_ kind: LUINodeKind) -> Bool {
        kind == .scroll
    }

    private func invalid(_ message: String) -> LUIBackendError {
        .invalidBatch(message)
    }
}
