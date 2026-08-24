import Foundation

public enum LUIBackendError: Error, Equatable {
    case invalidBatch(String)
}

public enum LUIEvent: Equatable, Sendable {
    case press(node: Int)
    case textChanged(node: Int, text: String)
    case toggleChanged(node: Int, checked: Bool)
}

enum LUINodeKind: String, Decodable, Equatable {
    case row, column, grid, stack, panel, card, box, text, heading, paragraph, label, button
    case textInput = "text-input", textArea = "text-area"
    case checkbox
    case switchControl = "switch"
    case progress
    case divider
    case scroll, list, spacer, spinner
}

enum LUIProperty: String, Decodable, Hashable {
    case text, enabled, gap, main, cross, grow, columns, padding, background, placeholder
    case paddingHorizontal = "padding-horizontal"
    case paddingVertical = "padding-vertical"
    case foreground
    case borderColor = "border-color"
    case borderWidth = "border-width"
    case cornerRadius = "corner-radius"
    case width, height
    case minWidth = "min-width"
    case maxWidth = "max-width"
    case minHeight = "min-height"
    case maxHeight = "max-height"
    case readOnly = "read-only"
    case accessibilityLabel = "accessibility-label"
    case minLines = "min-lines"
    case maxLines = "max-lines"
    case styleClass = "style-class"
    case headingLevel = "heading-level"
    case labelledBy = "labelled-by"
    case describedBy = "described-by"
    case errorMessageBy = "error-message-by"
    case inputType = "input-type"
    case invalid
    case checked, indeterminate
    case progressValue = "value"
    case minValue = "min-value"
    case maxValue = "max-value"
    case orientation
    case size
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

enum LUIWireValue: Decodable, Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let decoded = try? value.decode(Bool.self) {
            self = .bool(decoded)
        } else if let decoded = try? value.decode(Int.self) {
            self = .int(decoded)
        } else if let decoded = try? value.decode(Double.self) {
            self = .double(decoded)
        } else {
            self = .string(try value.decode(String.self))
        }
    }

    func matches(_ property: LUIProperty) -> Bool {
        switch (property, self) {
        case let (.headingLevel, .int(level)): (1...6).contains(level)
        case (.labelledBy, .int), (.describedBy, .int),
             (.errorMessageBy, .int): true
        case let (.inputType, .string(type)): Self.inputTypes.contains(type)
        case (.invalid, .bool): true
        case (.checked, .bool), (.indeterminate, .bool): true
        case (.progressValue, .int), (.minValue, .int), (.maxValue, .int): true
        case let (.orientation, .string(value)):
            value == "horizontal" || value == "vertical"
        case let (.size, .string(value)):
            Self.controlSizes.contains(value)
        case let (.main, .string(value)):
            Self.mainAlignments.contains(value)
        case let (.cross, .string(value)):
            Self.crossAlignments.contains(value)
        case let (.grow, .double(value)): value.isFinite && value >= 0
        case let (.columns, .int(value)): value >= 0
        case (.foreground, .string), (.borderColor, .string): true
        case let (.paddingHorizontal, .int(value)),
             let (.paddingVertical, .int(value)),
             let (.borderWidth, .int(value)),
             let (.cornerRadius, .int(value)),
             let (.width, .int(value)),
             let (.height, .int(value)),
             let (.minWidth, .int(value)),
             let (.maxWidth, .int(value)),
             let (.minHeight, .int(value)),
             let (.maxHeight, .int(value)): value >= 0
        case (.text, .string), (.enabled, .bool), (.gap, .int),
             (.padding, .int), (.background, .string),
             (.placeholder, .string), (.readOnly, .bool),
             (.accessibilityLabel, .string), (.minLines, .int),
             (.maxLines, .int), (.styleClass, .string): true
        default: false
        }
    }

    private static let inputTypes: Set<String> = [
        "button", "checkbox", "color", "date", "datetime-local", "email",
        "file", "hidden", "image", "month", "number", "password", "radio",
        "range", "reset", "search", "submit", "tel", "text", "time", "url", "week",
    ]

    private static let mainAlignments: Set<String> = [
        "start", "center", "end", "space_between",
    ]

    private static let crossAlignments: Set<String> = [
        "stretch", "start", "center", "end",
    ]

    private static let controlSizes: Set<String> = [
        "default", "sm", "lg", "icon",
    ]
}

struct LUINodeState {
    let kind: LUINodeKind
    var parent: Int?
    var children: [Int]
    var properties: [LUIProperty: LUIWireValue]
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
        try next.validateNodeProperties()
        return next
    }

    private mutating func apply(_ operation: LUIPatchOperation) throws {
        switch operation {
        case let .createNode(id, kind):
            guard nodes[id] == nil else { throw invalid("node already exists") }
            nodes[id] = LUINodeState(
                kind: kind,
                parent: nil,
                children: [],
                properties: [:]
            )
        case let .dropNode(id):
            guard let node = nodes[id] else { throw invalid("unknown node") }
            guard node.parent == nil && node.children.isEmpty else {
                throw invalid("cannot drop an attached node")
            }
            nodes[id] = nil
            removeRelationships(to: id)
        case let .setProp(id, property, value):
            guard var node = nodes[id] else { throw invalid("unknown node") }
            let normalizedValue = value.normalized(for: property)
            guard Self.supports(property, on: node.kind), normalizedValue.matches(property) else {
                throw invalid("unsupported property value")
            }
            try validateRelationship(property, value: normalizedValue)
            node.properties[property] = normalizedValue
            nodes[id] = node
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
        case .main, .cross:
            kind == .row || kind == .column || kind == .list
        case .grow: true
        case .columns: kind == .grid
        case .padding, .background, .borderColor, .borderWidth,
             .cornerRadius, .styleClass, .width, .height,
             .minWidth, .maxWidth, .minHeight, .maxHeight: true
        case .paddingHorizontal, .paddingVertical:
            kind == .row || kind == .column || kind == .grid || kind == .box
        case .foreground:
            kind == .text || kind == .heading || kind == .paragraph ||
                kind == .label || kind == .button || kind == .textInput ||
                kind == .textArea || kind == .checkbox || kind == .spinner
        case .text:
            kind == .text || kind == .heading || kind == .paragraph || kind == .label ||
                kind == .button || kind == .textInput || kind == .textArea
        case .enabled:
            kind == .button || kind == .textInput || kind == .textArea ||
                kind == .checkbox || kind == .switchControl
        case .gap: kind == .row || kind == .column || kind == .grid || kind == .list
        case .placeholder, .readOnly:
            kind == .textInput || kind == .textArea
        case .accessibilityLabel:
            kind == .textInput || kind == .textArea || kind == .checkbox ||
                kind == .switchControl || kind == .progress
        case .minLines, .maxLines: kind == .textArea
        case .headingLevel: kind == .heading
        case .labelledBy:
            kind == .textInput || kind == .textArea || kind == .switchControl ||
                kind == .progress
        case .describedBy, .errorMessageBy:
            kind == .textInput || kind == .textArea || kind == .switchControl
        case .invalid:
            kind == .textInput || kind == .textArea || kind == .checkbox ||
                kind == .switchControl
        case .inputType: kind == .textInput
        case .checked: kind == .checkbox || kind == .switchControl
        case .indeterminate: kind == .checkbox
        case .progressValue, .minValue, .maxValue: kind == .progress
        case .orientation: kind == .divider
        case .size: kind == .spinner
        }
    }

    private static func canContainChildren(_ kind: LUINodeKind) -> Bool {
        kind == .row || kind == .column || kind == .grid || kind == .stack ||
            kind == .panel || kind == .card || kind == .box || kind == .scroll ||
            kind == .list || kind == .switchControl
    }

    private static func isSingleChildContainer(_ kind: LUINodeKind) -> Bool {
        kind == .switchControl
    }

    private func validateNodeProperties() throws {
        for node in nodes.values {
            try validateSizeAxis(
                node,
                fixed: .width,
                minimum: .minWidth,
                maximum: .maxWidth
            )
            try validateSizeAxis(
                node,
                fixed: .height,
                minimum: .minHeight,
                maximum: .maxHeight
            )
            if node.kind == .progress {
                let minimum = node.properties[.minValue]?.intValue ?? 0
                let maximum = node.properties[.maxValue]?.intValue ?? 100
                guard maximum > minimum else {
                    throw invalid("progress max-value must be greater than min-value")
                }
            }
        }
    }

    private func validateSizeAxis(
        _ node: LUINodeState,
        fixed: LUIProperty,
        minimum: LUIProperty,
        maximum: LUIProperty
    ) throws {
        let lower = node.properties[minimum]?.intValue ?? 0
        let upper = node.properties[maximum]?.intValue ?? .max
        let exact = node.properties[fixed]?.intValue ?? lower
        guard lower <= upper, exact >= lower, exact <= upper else {
            throw invalid("surface size constraints conflict")
        }
    }

    private mutating func removeRelationships(to removed: Int) {
        let relationships: [LUIProperty] = [
            .labelledBy,
            .describedBy,
            .errorMessageBy,
        ]
        for id in Array(nodes.keys) {
            guard var node = nodes[id] else { continue }
            for property in relationships
            where node.properties[property]?.intValue == removed {
                node.properties[property] = nil
            }
            nodes[id] = node
        }
    }

    private func validateRelationship(
        _ property: LUIProperty,
        value: LUIWireValue
    ) throws {
        guard case let .int(target) = value else { return }
        switch property {
        case .labelledBy:
            guard nodes[target]?.kind == .label else {
                throw invalid("labelled-by must reference a label")
            }
        case .describedBy, .errorMessageBy:
            guard let kind = nodes[target]?.kind,
                  kind == .text || kind == .paragraph else {
                throw invalid("description must reference text content")
            }
        default:
            break
        }
    }

    private func invalid(_ message: String) -> LUIBackendError {
        .invalidBatch(message)
    }
}

extension LUIWireValue {
    func normalized(for property: LUIProperty) -> LUIWireValue {
        if property == .grow, case let .int(value) = self {
            return .double(Double(value))
        }
        return self
    }

    var intValue: Int? {
        guard case let .int(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case let .double(value) = self else { return nil }
        return value
    }
}
