import Foundation

public enum LUIBackendError: Error, Equatable {
    case invalidBatch(String)
}

public enum LUIEvent: Equatable, Sendable {
    case press(node: Int)
    case longPress(node: Int)
    case textChanged(node: Int, text: String)
    case submit(node: Int)
    case toggleChanged(node: Int, checked: Bool)
    case change(node: Int)
    case valueChanged(node: Int, value: Double)
    case dismiss(node: Int)
    case doublePress(node: Int)
    case appear(node: Int)
    case `extension`(
        node: Int,
        identifier: String,
        name: String,
        values: [String: LUIExtensionValue]
    )
}

struct LUIPatchBatch: Decodable, Sendable {
    let generation: Int
    let ops: [LUIPatchOperation]
}

enum LUIPatchOperation: Decodable, Sendable {
    case createNode(id: Int, kind: LUINodeKind)
    case createExtension(id: Int, identifier: String, fingerprint: String)
    case dropNode(id: Int)
    case setProp(id: Int, property: LUIProperty, value: LUIWireValue)
    case removeProp(id: Int, property: LUIProperty)
    case setExtensionProp(id: Int, property: String, value: LUIWireValue)
    case removeExtensionProp(id: Int, property: String)
    case insertChild(parent: Int, child: Int, index: Int)
    case removeChild(parent: Int, child: Int)
    case moveChild(parent: Int, child: Int, index: Int)

    private enum CodingKeys: String, CodingKey {
        case op, id, kind, identifier, fingerprint, property, value, parent, child, index
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .op) {
        case "create-node":
            self = .createNode(
                id: try values.decode(Int.self, forKey: .id),
                kind: try values.decode(LUINodeKind.self, forKey: .kind)
            )
        case "create-extension":
            self = .createExtension(
                id: try values.decode(Int.self, forKey: .id),
                identifier: try values.decode(String.self, forKey: .identifier),
                fingerprint: try values.decode(String.self, forKey: .fingerprint)
            )
        case "drop-node":
            self = .dropNode(id: try values.decode(Int.self, forKey: .id))
        case "set-prop":
            self = .setProp(
                id: try values.decode(Int.self, forKey: .id),
                property: try values.decode(LUIProperty.self, forKey: .property),
                value: try values.decode(LUIWireValue.self, forKey: .value)
            )
        case "remove-prop":
            self = .removeProp(
                id: try values.decode(Int.self, forKey: .id),
                property: try values.decode(LUIProperty.self, forKey: .property)
            )
        case "set-extension-prop":
            self = .setExtensionProp(
                id: try values.decode(Int.self, forKey: .id),
                property: try values.decode(String.self, forKey: .property),
                value: try values.decode(LUIWireValue.self, forKey: .value)
            )
        case "remove-extension-prop":
            self = .removeExtensionProp(
                id: try values.decode(Int.self, forKey: .id),
                property: try values.decode(String.self, forKey: .property)
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
        if let decoded = try? value.decode(String.self) {
            self = .string(decoded)
        } else if let decoded = try? value.decode(Bool.self) {
            self = .bool(decoded)
        } else if let decoded = try? value.decode(Int.self) {
            self = .int(decoded)
        } else {
            self = .double(try value.decode(Double.self))
        }
    }

    func matches(_ property: LUIProperty, on kind: LUINodeKind) -> Bool {
        switch property {
        case .headingLevel:
            guard let value = intValue else { return false }
            return (1...6).contains(value)
        case .checked, .selected, .autofocus, .submitOnEnter, .longPressEnabled,
             .changeEnabled, .toggleEnabled, .pressEnabled, .submitEnabled,
             .doublePressEnabled, .appearEnabled, .connector, .expanded, .enabled:
            return boolValue != nil
        case .progressValue:
            return doubleValue != nil
        case .resizeDuration, .image, .surface, .active, .columns,
             .paddingHorizontal, .paddingVertical, .borderWidth, .cornerRadius,
             .width, .height, .minWidth, .maxWidth, .minHeight, .maxHeight,
             .containerRelativeFrameInset:
            guard let value = intValue else { return false }
            return value >= 0
        case .resizeEasing:
            guard let value = stringValue else { return false }
            return ["linear", "standard", "emphasized", "spring"].contains(value)
        case .resizeOrigin, .sourceX, .sourceY, .sourceWidth, .sourceHeight,
             .anchorOffset:
            guard let value = doubleValue else { return false }
            return value.isFinite
        case .orientation:
            guard let value = stringValue else { return false }
            return value == "horizontal" || value == "vertical"
        case .placement:
            guard let value = stringValue else { return false }
            return Self.toolbarPlacements.contains(value)
        case .size:
            guard let value = stringValue else { return false }
            return Self.controlSizes.contains(value) ||
                (kind == .tableCell && Self.textSizes.contains(value))
        case .name, .icon:
            guard let value = stringValue else { return false }
            return Self.iconNames.contains(value) || Self.isApplicationIconName(value)
        case .variant:
            guard let value = stringValue else { return false }
            return Self.buttonVariants.contains(value)
        case .iconPlacement:
            guard let value = stringValue else { return false }
            return value == "leading" || value == "trailing" || value == "top"
        case .title, .description, .meta, .indicator, .foreground, .borderColor,
             .text, .background, .placeholder, .accessibilityLabel,
             .accessibilityIdentifier, .styleClass:
            return stringValue != nil
        case .containerRelativeFrame:
            guard let value = stringValue else { return false }
            return [
                "horizontal", "vertical", "both",
                "min-horizontal", "min-vertical", "min-both",
            ].contains(value)
        case .anchor:
            guard let value = stringValue else { return false }
            return ["above", "below", "left", "right"].contains(value)
        case .anchorAlignment:
            guard let value = stringValue else { return false }
            return ["start", "end", "stretch"].contains(value)
        case .tooltipDelay, .duration:
            guard let value = intValue else { return false }
            return (0...Int(Int32.max)).contains(value)
        case .textAlignment:
            guard let value = stringValue else { return false }
            return Self.textAlignments.contains(value)
        case .role:
            guard let value = stringValue else { return false }
            return value == "treeitem" || value == "navigation" ||
                value == "navigation-heading"
        case .treeLevel:
            guard let value = intValue else { return false }
            return value > 0
        case .main:
            guard let value = stringValue else { return false }
            return Self.mainAlignments.contains(value)
        case .cross:
            guard let value = stringValue else { return false }
            return Self.crossAlignments.contains(value)
        case .grow:
            guard let value = doubleValue else { return false }
            return value.isFinite && value >= 0
        case .gap, .padding:
            return intValue != nil
        }
    }


    private static let mainAlignments: Set<String> = [
        "start", "center", "end", "space_between",
    ]

    private static let crossAlignments: Set<String> = [
        "stretch", "start", "center", "end",
    ]

    private static let controlSizes: Set<String> = [
        "default", "sm", "lg", "icon",
    ]

    private static let textSizes: Set<String> = ["heading", "display"]

    private static let textAlignments: Set<String> = ["start", "center", "end"]

    private static let toolbarPlacements: Set<String> = [
        "automatic", "bottom", "navigation", "principal", "primary-action",
        "secondary-action", "status", "confirmation-action", "cancellation-action",
        "destructive-action", "top-bar-leading", "top-bar-trailing",
    ]

    private static let buttonVariants: Set<String> = [
        "default", "primary", "secondary", "outline", "ghost", "destructive",
    ]

    private static let iconNames: Set<String> = [
        "alert", "archive", "arrow-down", "arrow-right", "arrow-up",
        "check", "check-circle", "chevron-down", "chevron-left", "chevron-right",
        "chevron-up", "circle-dot", "clock", "copy", "download", "edit",
        "ellipsis", "external-link", "eye", "file-text", "folder", "folder-open",
        "git-branch", "git-merge", "git-pull-request", "info", "menu", "mic",
        "moon", "music", "panel-left", "panel-right", "pause", "play", "plus",
        "refresh-cw", "repeat", "save", "search", "send", "settings", "shuffle",
        "skip-back", "skip-forward", "sun", "terminal", "trash", "volume",
        "wrench", "x", "x-circle",
    ]

    private static func isApplicationIconName(_ value: String) -> Bool {
        guard value.hasPrefix("app:") else { return false }
        let name = value.dropFirst(4)
        let segments = name.split(separator: "-", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { segment in
            !segment.isEmpty && segment.utf8.allSatisfy { byte in
                let value = Int(byte)
                return (value >= 97 && value <= 122) ||
                    (value >= 48 && value <= 57)
            }
        }
    }
}

struct LUINodeState {
    let kind: LUINodeKind
    var parent: Int?
    var children: [Int]
    var properties: [LUIProperty: LUIWireValue]
}

@MainActor
struct LUIRetainedTree {
    private(set) var nodes: [Int: LUINodeState] = [:]
    private(set) var extensionNodes: [Int: LUIExtensionNodeState] = [:]

    var rootIDs: [Int] {
        nodes.compactMap { id, node in node.parent == nil ? id : nil } +
            extensionNodes.compactMap { id, node in node.parent == nil ? id : nil }
    }

    struct PatchEffects {
        /// Nodes created or mutated by an op. Ops only mutate the nodes they
        /// name, so this set covers every state difference between `self` and
        /// the result.
        var touched: Set<Int> = []
        /// Nodes removed from the tree (only `dropNode` deletes).
        var dropped: Set<Int> = []
        /// Structural ops (insert/remove/move child) that can change ancestry.
        var structural = false
        /// Nodes whose own kind can affect modal presentation (`dialog`/`sheet`
        /// membership or `list` dialog anchoring).
        var modalRelevant: Set<Int> = []
        /// Nodes whose invariants must be revalidated: touched nodes, their
        /// parents and children (checks read one level up/down), and the whole
        /// subtree of children moved by structural ops (ancestry-dependent
        /// checks like "treeitem inside tree" change for every descendant).
        var validationScope: Set<Int> = []
    }

    /// Applies a batch in place and reports which nodes changed. Ops only
    /// mutate the nodes they name, so `effects.touched` covers every state
    /// difference the batch makes; the caller uses it to reconcile, validate,
    /// and resync modals in O(touched) instead of O(tree).
    ///
    /// Pre-op states are snapshotted per touched node so a rejected batch
    /// rolls the tree back completely — failure keeps the pre-batch state.
    @discardableResult
    mutating func applying(
        _ operations: [LUIPatchOperation],
        extensionRegistry: LUIAppleExtensionRegistry
    ) throws -> PatchEffects {
        var effects = PatchEffects()
        var structuralChildren = Set<Int>()
        var snapshotted = Set<Int>()
        var oldNodes: [Int: LUINodeState] = [:]
        var oldExtensions: [Int: LUIExtensionNodeState] = [:]
        do {
            for operation in operations {
                for id in Self.affectedIDs(of: operation) where !snapshotted.contains(id) {
                    snapshotted.insert(id)
                    oldNodes[id] = nodes[id]
                    oldExtensions[id] = extensionNodes[id]
                }
                // `dropNode` erases the state, so its kind must be read first.
                if case let .dropNode(id) = operation,
                   let kind = nodes[id]?.kind,
                   kind == .dialog || kind == .sheet || kind == .list {
                    effects.modalRelevant.insert(id)
                }
                try apply(operation, extensionRegistry: extensionRegistry)
                switch operation {
                case let .createNode(id, _), let .setProp(id, _, _),
                     let .removeProp(id, _):
                    effects.touched.insert(id)
                case let .createExtension(id, _, _),
                     let .setExtensionProp(id, _, _),
                     let .removeExtensionProp(id, _):
                    effects.touched.insert(id)
                case let .dropNode(id):
                    effects.touched.insert(id)
                    effects.dropped.insert(id)
                case let .insertChild(parent, child, _):
                    effects.structural = true
                    effects.touched.formUnion([parent, child])
                    structuralChildren.insert(child)
                case let .removeChild(parent, child):
                    effects.structural = true
                    effects.touched.formUnion([parent, child])
                    structuralChildren.insert(child)
                case let .moveChild(parent, child, _):
                    effects.structural = true
                    effects.touched.formUnion([parent, child])
                    structuralChildren.insert(child)
                }
            }
            effects.modalRelevant.formUnion(effects.touched.filter {
                let kind = nodes[$0]?.kind
                return kind == .dialog || kind == .sheet || kind == .list
            })
            // Revalidate every check whose inputs could have changed: the
            // touched node itself, its parent (a changed child list or parent
            // property is an input to sibling/child checks), its children
            // (they read the parent's kind/properties), and the whole subtree
            // of children moved by structural ops (ancestor-dependent checks
            // change per descendant).
            var scope = effects.touched
            for id in effects.touched {
                if let node = nodes[id] {
                    scope.formUnion(node.children)
                    if let parent = node.parent { scope.insert(parent) }
                } else if let node = extensionNodes[id] {
                    scope.formUnion(node.children)
                    if let parent = node.parent { scope.insert(parent) }
                }
            }
            for child in structuralChildren {
                var pending = [child]
                while let id = pending.popLast() {
                    guard scope.insert(id).inserted else { continue }
                    if let node = nodes[id] {
                        pending.append(contentsOf: node.children)
                    } else if let node = extensionNodes[id] {
                        pending.append(contentsOf: node.children)
                    }
                }
            }
            effects.validationScope = scope
            try validateNodeProperties(
                extensionRegistry: extensionRegistry,
                scope: scope
            )
        } catch {
            for id in snapshotted {
                nodes[id] = oldNodes[id]
                extensionNodes[id] = oldExtensions[id]
            }
            throw error
        }
        return effects
    }

    /// The node ids an op can mutate: the named node, plus parent and child
    /// for structural ops (child-list membership and parent pointer).
    private static func affectedIDs(of operation: LUIPatchOperation) -> [Int] {
        switch operation {
        case let .createNode(id, _), let .setProp(id, _, _),
             let .removeProp(id, _), let .createExtension(id, _, _),
             let .setExtensionProp(id, _, _), let .removeExtensionProp(id, _),
             let .dropNode(id):
            return [id]
        case let .insertChild(parent, child, _),
             let .removeChild(parent, child),
             let .moveChild(parent, child, _):
            return [parent, child]
        }
    }

    private mutating func apply(
        _ operation: LUIPatchOperation,
        extensionRegistry: LUIAppleExtensionRegistry
    ) throws {
        switch operation {
        case let .createNode(id, kind):
            guard !contains(id) else { throw invalid("node already exists") }
            nodes[id] = LUINodeState(
                kind: kind,
                parent: nil,
                children: [],
                properties: [:]
            )
        case let .createExtension(id, identifier, fingerprint):
            guard !contains(id) else { throw invalid("node already exists") }
            guard let registration = extensionRegistry.registration(identifier) else {
                throw invalid("unknown extension identifier")
            }
            guard registration.fingerprint == fingerprint else {
                throw invalid("extension fingerprint mismatch")
            }
            extensionNodes[id] = LUIExtensionNodeState(
                identifier: identifier,
                fingerprint: fingerprint,
                parent: nil,
                children: [],
                properties: Dictionary(
                    uniqueKeysWithValues: registration.properties.compactMap { property in
                        property.defaultValue.map { (property.name, $0.wireValue) }
                    }
                )
            )
        case let .dropNode(id):
            guard contains(id) else { throw invalid("unknown node") }
            guard parent(of: id) == nil, children(of: id)?.isEmpty == true else {
                throw invalid("cannot drop an attached node")
            }
            nodes[id] = nil
            extensionNodes[id] = nil
        case let .setProp(id, property, value):
            guard var node = nodes[id] else { throw invalid("unknown node") }
            let normalizedValue = value.normalized(for: property)
            guard Self.supports(property, on: node.kind),
                  normalizedValue.matches(property, on: node.kind) else {
                throw invalid("unsupported property value")
            }
            node.properties[property] = normalizedValue
            nodes[id] = node
        case let .removeProp(id, property):
            guard var node = nodes[id] else { throw invalid("unknown node") }
            guard Self.supports(property, on: node.kind) else {
                throw invalid("unsupported property")
            }
            node.properties[property] = nil
            nodes[id] = node
        case let .setExtensionProp(id, property, value):
            guard var node = extensionNodes[id] else { throw invalid("unknown extension node") }
            guard let registration = extensionRegistry.registration(node.identifier),
                  let schema = registration.properties.first(where: { $0.name == property }),
                  schema.kind.accepts(value) else {
                throw invalid("unsupported extension property value")
            }
            node.properties[property] = schema.kind.normalize(value)
            extensionNodes[id] = node
        case let .removeExtensionProp(id, property):
            guard var node = extensionNodes[id] else { throw invalid("unknown extension node") }
            guard extensionRegistry.registration(node.identifier)?.properties.contains(
                where: { $0.name == property }
            ) == true else {
                throw invalid("unknown extension property")
            }
            node.properties[property] = nil
            extensionNodes[id] = node
        case let .insertChild(parent, child, index):
            guard contains(parent), contains(child) else {
                throw invalid("unknown parent or child")
            }
            try validateChild(parent: parent, child: child, registry: extensionRegistry)
            guard self.parent(of: child) == nil else {
                throw invalid("child is already attached")
            }
            var parentChildren = children(of: parent) ?? []
            guard index >= 0 && index <= parentChildren.count else {
                throw invalid("child index is out of bounds")
            }
            guard !isDescendant(parent, of: child) else {
                throw invalid("child insertion would create a cycle")
            }
            parentChildren.insert(child, at: index)
            setChildren(parentChildren, for: parent)
            setParent(parent, for: child)
        case let .removeChild(parent, child):
            guard var parentChildren = children(of: parent),
                  let index = parentChildren.firstIndex(of: child), contains(child) else {
                throw invalid("child is not attached to parent")
            }
            parentChildren.remove(at: index)
            setChildren(parentChildren, for: parent)
            setParent(nil, for: child)
        case let .moveChild(parent, child, index):
            guard var parentChildren = children(of: parent),
                  let oldIndex = parentChildren.firstIndex(of: child) else {
                throw invalid("child is not attached to parent")
            }
            parentChildren.remove(at: oldIndex)
            guard index >= 0 && index <= parentChildren.count else {
                throw invalid("child index is out of bounds")
            }
            parentChildren.insert(child, at: index)
            setChildren(parentChildren, for: parent)
        }
    }

    private func contains(_ id: Int) -> Bool {
        nodes[id] != nil || extensionNodes[id] != nil
    }

    private func parent(of id: Int) -> Int? {
        nodes[id]?.parent ?? extensionNodes[id]?.parent
    }

    private func children(of id: Int) -> [Int]? {
        nodes[id]?.children ?? extensionNodes[id]?.children
    }

    private mutating func setParent(_ parent: Int?, for id: Int) {
        if var node = nodes[id] {
            node.parent = parent
            nodes[id] = node
        } else if var node = extensionNodes[id] {
            node.parent = parent
            extensionNodes[id] = node
        }
    }

    private mutating func setChildren(_ children: [Int], for id: Int) {
        if var node = nodes[id] {
            node.children = children
            nodes[id] = node
        } else if var node = extensionNodes[id] {
            node.children = children
            extensionNodes[id] = node
        }
    }

    private func validateChild(
        parent: Int,
        child: Int,
        registry: LUIAppleExtensionRegistry
    ) throws {
        if nodes[child]?.kind == .root {
            throw invalid("runtime root cannot be nested")
        }
        if let childNode = extensionNodes[child],
           let registration = registry.registration(childNode.identifier),
           registration.isTweak {
            guard childNode.children.count == 1, let innerChild = childNode.children.first else {
                throw invalid("platform tweak requires exactly one child")
            }
            try validateChild(parent: parent, child: innerChild, registry: registry)
            return
        }
        if let parentNode = nodes[parent], let childNode = nodes[child] {
            guard Self.canContainChildren(parentNode.kind) else {
                throw invalid("parent cannot contain children")
            }
            if parentNode.kind == .table, childNode.kind != .tableRow {
                throw invalid("table can contain only table-row")
            }
            if parentNode.kind == .tableRow, childNode.kind != .tableCell {
                throw invalid("table-row can contain only table-cell")
            }
            if parentNode.kind == .tree,
               !Self.isTreeRow(childNode.kind), childNode.kind != .virtualList {
                throw invalid("tree accepts only row containers")
            }
            if parentNode.kind == .stepper, childNode.kind != .step {
                throw invalid("stepper accepts only step children")
            }
            if parentNode.kind == .timeline, childNode.kind != .timelineItem {
                throw invalid("timeline accepts only timeline-item children")
            }
            if parentNode.kind == .bottomTabs, childNode.kind != .bottomTab {
                throw invalid("bottom-tabs accepts only bottom-tab children")
            }
            if parentNode.kind == .bottomTab, childNode.kind == .bottomTab {
                throw invalid("bottom-tab cannot directly contain bottom-tab")
            }
            if parentNode.kind == .inputGroup,
               childNode.kind != .textarea, childNode.kind != .inputGroupActions {
                throw invalid("input-group accepts textarea and input-group-actions")
            }
            if parentNode.kind == .dropdownMenu,
               childNode.kind != .menuItem, childNode.kind != .divider {
                throw invalid("dropdown-menu accepts only menu-item or separator children")
            }
            if parentNode.kind == .contextMenu,
               childNode.kind != .menuItem, childNode.kind != .divider {
                throw invalid("context-menu accepts only menu-item or separator children")
            }
            if parentNode.kind == .toolbar, !Self.isToolbarChild(childNode.kind) {
                throw invalid("toolbar accepts only interactive controls and dividers")
            }
            if parentNode.kind == .menuItem,
               childNode.kind != .contextMenu, childNode.kind != .dropdownMenu {
                throw invalid("menu-item accepts only nested menu metadata")
            }
            if parentNode.kind != .menuItem,
               Self.isContextMenuLeafHost(parentNode.kind),
               childNode.kind != .contextMenu {
                throw invalid("interactive leaf accepts only context-menu metadata")
            }
            return
        }
        if let parentNode = nodes[parent], extensionNodes[child] != nil {
            guard Self.acceptsExtensionChildren(parentNode.kind) else {
                throw invalid("standard node cannot contain extension")
            }
            return
        }
        guard let parentNode = extensionNodes[parent],
              let registration = registry.registration(parentNode.identifier) else {
            throw invalid("unknown extension parent")
        }
        if registration.isTweak {
            guard parentNode.children.isEmpty else {
                throw invalid("platform tweak requires exactly one child")
            }
            return
        }
        if nodes[child] != nil {
            guard registration.acceptsStandardChildren else {
                throw invalid("extension does not accept standard children")
            }
            return
        }
        guard let childNode = extensionNodes[child],
              registration.childIdentifiers.contains(childNode.identifier) else {
            throw invalid("unsupported extension child")
        }
    }

    // target is a descendant-or-self of root iff walking the parent
    // chain from target reaches root.
    private func isDescendant(_ target: Int, of root: Int) -> Bool {
        var current: Int? = target
        while let id = current {
            if id == root { return true }
            current = parent(of: id)
        }
        return false
    }

    private static func supports(_ property: LUIProperty, on kind: LUINodeKind) -> Bool {
        if property == .accessibilityIdentifier { return true }
        // Restrictive per-kind allow-lists and additive extras come from
        // schema/components.json via LUISchemaMatrix; kinds absent from the
        // restrictive table fall back to the shared structural rules below.
        if let matrix = LUISchemaMatrix.restrictive[kind] {
            return matrix.contains(property)
        }
        if LUISchemaMatrix.extra[kind]?.contains(property) == true { return true }
        if kind == .root { return false }
        if kind == .contextMenu { return false }
        return switch property {
        case .main, .cross:
            kind == .row || kind == .column || kind == .list || kind == .virtualList ||
                kind == .card || kind == .panel || kind == .box ||
                isHorizontalGroup(kind)
        case .grow: kind != .avatar && kind != .tooltip && !isModalSurface(kind)
        case .columns: kind == .grid
        case .padding, .width, .height: kind != .tooltip
        case .styleClass:
            kind != .tooltip
        case .background, .borderColor, .borderWidth,
             .cornerRadius,
             .minWidth, .maxWidth, .minHeight, .maxHeight:
            kind != .tooltip && !isModalSurface(kind)
        case .containerRelativeFrame, .containerRelativeFrameInset:
            kind != .root && !isModalSurface(kind)
        case .paddingHorizontal, .paddingVertical:
            kind == .row || kind == .column || kind == .grid || kind == .box ||
                kind == .card || kind == .panel || kind == .scroll ||
                (property == .paddingHorizontal && kind == .button)
        case .foreground:
            kind == .row || kind == .column || kind == .grid || kind == .box ||
                kind == .panel || kind == .card || kind == .stack ||
                kind == .scroll || kind == .avatar ||
                kind == .text || kind == .heading || kind == .paragraph ||
                kind == .label || kind == .button || kind == .toggleButton ||
                isTextEntry(kind) || kind == .checkbox || kind == .toggle ||
                kind == .radio || kind == .slider || kind == .spinner || kind == .icon
                || kind == .select || kind == .combobox || kind == .dropdownMenu
                || kind == .menuItem || kind == .listItem
                || kind == .tableCell || kind == .resizable || kind == .split ||
                kind == .alert || kind == .bubble || kind == .statusBar
        case .text:
            kind == .text || kind == .heading || kind == .paragraph || kind == .label ||
                kind == .button || kind == .toggleButton || isTextEntry(kind) ||
                kind == .checkbox || kind == .switchControl || kind == .toggle || kind == .radio ||
                kind == .select || kind == .menuItem || kind == .listItem || kind == .avatar ||
                kind == .tooltip ||
                kind == .tableCell ||
                kind == .alert || kind == .bubble || kind == .statusBar ||
                isModalSurface(kind) || kind == .drawer
        case .enabled:
            kind == .button || kind == .toggleButton || isTextEntry(kind) ||
                kind == .checkbox || kind == .switchControl || kind == .toggle ||
                kind == .radio || kind == .slider || kind == .select ||
                kind == .combobox || kind == .menuItem || kind == .listItem ||
                kind == .drawer
        case .gap:
            kind == .row || kind == .column || kind == .grid || kind == .list ||
                kind == .virtualList || kind == .scroll || kind == .card ||
                kind == .panel || kind == .box ||
                kind == .dropdownMenu || isHorizontalGroup(kind) || kind == .split
                || kind == .tableRow || kind == .tree
        case .placeholder:
            isTextEntry(kind) || kind == .select
        case .accessibilityIdentifier:
            true
        case .accessibilityLabel:
            kind == .button || kind == .toggleButton || isTextEntry(kind) || kind == .checkbox ||
                kind == .switchControl || kind == .toggle ||
                kind == .radioGroup || kind == .tabs ||
                kind == .buttonGroup || kind == .toggleGroup ||
                kind == .breadcrumb || kind == .pagination ||
                kind == .radio || kind == .slider || kind == .select ||
                kind == .avatar || kind == .image ||
                kind == .mediaSurface || kind == .tree ||
                kind == .resizable || kind == .split || kind == .drawer ||
                kind == .alert || kind == .bubble ||
                kind == .listItem ||
                isTreeRow(kind)
        case .headingLevel: kind == .heading
        case .checked:
            kind == .checkbox || kind == .switchControl || kind == .toggle || kind == .radio
        case .progressValue: kind == .progress || kind == .slider || kind == .split
        case .resizeDuration, .resizeEasing, .resizeOrigin: kind == .split
        case .orientation: kind == .divider || kind == .tabs || kind == .scroll
        case .placement: kind == .toolbar
        case .size:
            kind == .button || kind == .toggleButton || kind == .spinner ||
                kind == .icon || kind == .text || kind == .tableCell ||
                kind == .menuItem
        case .name: kind == .icon
        case .variant:
            kind == .button || kind == .toggleButton || kind == .menuItem ||
                kind == .alert || kind == .bubble
        case .iconPlacement:
            kind == .button || kind == .toggleButton || kind == .listItem
        case .longPressEnabled:
            kind == .button || kind == .toggleButton || kind == .listItem
        case .icon:
            kind == .button || kind == .toggleButton || kind == .menuItem ||
                kind == .listItem
        case .selected:
            kind == .button || kind == .toggleButton || kind == .menuItem ||
                kind == .listItem || kind == .tableRow || kind == .drawer ||
                kind == .virtualList || isTreeRow(kind)
        case .autofocus:
            kind == .button || kind == .toggleButton || isTextEntry(kind)
        case .submitOnEnter: kind == .textarea
        case .changeEnabled: kind == .radio || isTreeRow(kind)
        case .toggleEnabled: kind == .radio || kind == .drawer || isTreeRow(kind)
        case .pressEnabled:
            kind == .text || kind == .radio || kind == .select || kind == .combobox ||
                kind == .menuItem || kind == .listItem
                || kind == .tableCell || isTreeRow(kind)
        case .submitEnabled: kind == .combobox || kind == .listItem
        case .doublePressEnabled: kind == .listItem
        case .appearEnabled: kind != .root
        case .image:
            kind == .avatar || kind == .image
        case .surface:
            kind == .mediaSurface
        case .sourceX, .sourceY, .sourceWidth, .sourceHeight:
            kind == .avatar || kind == .image
        case .anchor, .anchorAlignment, .anchorOffset:
            kind == .dropdownMenu || kind == .tooltip
        case .tooltipDelay: kind == .tooltip
        case .duration: false
        case .textAlignment:
            kind == .text || kind == .button || kind == .toggleButton ||
                kind == .tableCell || kind == .bubble || kind == .statusBar
        case .role: isTreeRow(kind) || kind == .listItem
        case .treeLevel, .expanded: isTreeRow(kind)
        case .active, .title, .description, .meta, .indicator, .connector: false
        }
    }

    private static func isTextEntry(_ kind: LUINodeKind) -> Bool {
        kind == .textField || kind == .secureField || kind == .input || kind == .searchField || kind == .textarea ||
            kind == .combobox
    }

    private static func canContainChildren(_ kind: LUINodeKind) -> Bool {
        kind == .root || kind == .row || kind == .column || kind == .grid || kind == .stack ||
            kind == .panel || kind == .card || kind == .box || kind == .scroll ||
            kind == .list || kind == .virtualList || isHorizontalGroup(kind) || kind == .radioGroup
            || kind == .dropdownMenu || kind == .contextMenu || kind == .listItem || isModalSurface(kind)
            || kind == .accordion
            || kind == .table || kind == .tableRow || kind == .tree || kind == .resizable
            || kind == .split || kind == .drawer || kind == .alert || kind == .bubble ||
            kind == .stepper || kind == .timeline ||
            kind == .inputGroup || kind == .inputGroupActions ||
            kind == .toast || kind == .toolbar || kind == .bottomTabs || kind == .bottomTab ||
            isContextMenuLeafHost(kind)
    }

    private static func acceptsExtensionChildren(_ kind: LUINodeKind) -> Bool {
        kind == .root || kind == .row || kind == .column || kind == .grid || kind == .stack ||
            kind == .panel || kind == .card || kind == .box || kind == .scroll ||
            kind == .list || kind == .virtualList || kind == .listItem || kind == .dialog ||
            kind == .sheet || kind == .accordion || kind == .resizable || kind == .split ||
            kind == .drawer ||
            kind == .alert || kind == .bubble || kind == .toast || kind == .toolbar ||
            kind == .bottomTab
    }

    private static func isModalSurface(_ kind: LUINodeKind) -> Bool {
        kind == .dialog || kind == .sheet
    }

    private static func isHorizontalGroup(_ kind: LUINodeKind) -> Bool {
        kind == .tabs || kind == .buttonGroup || kind == .toggleGroup ||
            kind == .breadcrumb || kind == .pagination
    }

    private static func isToolbarChild(_ kind: LUINodeKind) -> Bool {
        kind == .button || kind == .toggleButton || kind == .buttonGroup ||
            kind == .toggleGroup || kind == .checkbox || kind == .switchControl ||
            kind == .toggle || kind == .radioGroup || kind == .select ||
            kind == .combobox || kind == .textField || kind == .secureField || kind == .input ||
            kind == .searchField || kind == .menuItem || kind == .spacer ||
            kind == .divider || kind == .text
    }

    private static func isTreeRow(_ kind: LUINodeKind) -> Bool {
        kind == .row || kind == .column || kind == .panel || kind == .card ||
            kind == .box || kind == .listItem
    }

    private func validateNodeProperties(
        extensionRegistry: LUIAppleExtensionRegistry,
        scope: Set<Int>? = nil
    ) throws {
        for (id, node) in nodes where scope?.contains(id) ?? true {
            if node.kind == .root {
                guard node.parent == nil else {
                    throw invalid("runtime root cannot have a parent")
                }
                guard node.children.count == 1 else {
                    throw invalid("runtime root requires exactly one child")
                }
            }
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
            if node.kind == .icon, node.properties[.name] == nil {
                throw invalid("icon requires name")
            }
            if node.kind == .button || node.kind == .toggleButton ||
                node.kind == .toggle || node.kind == .radio {
                let text = node.properties[.text]?.stringValue ?? ""
                let label = node.properties[.accessibilityLabel]?.stringValue ?? ""
                let icon = node.properties[.icon]?.stringValue ?? ""
                guard !text.isEmpty || !label.isEmpty else {
                    throw invalid("button requires an accessible name")
                }
                if text.isEmpty && !icon.isEmpty && label.isEmpty {
                    throw invalid("icon-only button requires label")
                }
            }
            if node.kind == .radioGroup || node.kind == .slider {
                guard !(node.properties[.accessibilityLabel]?.stringValue ?? "").isEmpty else {
                    throw invalid("value control requires an accessibility label")
                }
            }
            if node.kind == .slider || node.kind == .progress {
                guard case let .double(value)? = node.properties[.progressValue], value.isFinite else {
                    throw invalid("value control requires a finite fractional value")
                }
            }
            if node.kind == .split {
                guard node.children.count == 2 else {
                    throw invalid("split requires exactly two children")
                }
                guard case let .double(value)? = node.properties[.progressValue],
                      value.isFinite else {
                    throw invalid("split requires a finite fractional value")
                }
                let duration = node.properties[.resizeDuration]?.intValue ?? 0
                if node.properties[.resizeEasing] != nil || node.properties[.resizeOrigin] != nil {
                    guard duration > 0 else {
                        throw invalid("split animation options require a positive duration")
                    }
                }
            }
            if node.kind == .drawer, node.children.count != 2 {
                throw invalid("drawer requires exactly two children")
            }
            if node.kind == .radio, !hasAncestor(node.parent, kind: .radioGroup) {
                throw invalid("radio must be contained by a radio-group")
            }
            if node.kind == .select || node.kind == .combobox {
                let text = node.properties[.text]?.stringValue ?? ""
                let placeholder = node.properties[.placeholder]?.stringValue ?? ""
                guard !text.isEmpty || !placeholder.isEmpty else {
                    throw invalid("picker trigger requires text or placeholder")
                }
            }
            if node.kind == .menuItem {
                guard !(node.properties[.text]?.stringValue ?? "").isEmpty else {
                    throw invalid("menu-item requires text")
                }
            }
            if node.kind == .contextMenu {
                guard let parentID = node.parent, let parent = nodes[parentID],
                      Self.isContextMenuHost(parent.kind, properties: parent.properties) else {
                    throw invalid("context-menu requires an interactive direct host")
                }
                let menuCount = parent.children.filter { nodes[$0]?.kind == .contextMenu }.count
                guard menuCount == 1 else {
                    throw invalid("host accepts at most one context-menu")
                }
                for childID in node.children {
                    guard let child = nodes[childID] else { continue }
                    if child.kind == .menuItem {
                        guard child.properties[.pressEnabled]?.boolValue == true else {
                            throw invalid("context-menu menu-item requires press support")
                        }
                        guard child.children.isEmpty else {
                            throw invalid("context-menu does not support nested menus")
                        }
                        let allowed: Set<LUIProperty> = [
                            .text,
                            .enabled,
                            .pressEnabled,
                            .icon,
                            .foreground,
                            .variant,
                            .accessibilityIdentifier,
                        ]
                        guard child.properties.keys.allSatisfy({ allowed.contains($0) }) else {
                            throw invalid("context-menu menu-item has unsupported metadata")
                        }
                    } else if !child.properties.isEmpty && child.properties != [
                        .orientation: .string("horizontal"),
                        .styleClass: .string("lui-separator"),
                    ] {
                        throw invalid("context-menu separator accepts no attributes")
                    }
                }
            }
            if Self.isModalSurface(node.kind) {
                guard !(node.properties[.text]?.stringValue ?? "").isEmpty else {
                    throw invalid("modal surface requires text")
                }
            }
            if node.kind == .tooltip {
                guard !(node.properties[.text]?.stringValue ?? "").isEmpty else {
                    throw invalid("tooltip requires text")
                }
                if node.properties[.tooltipDelay] != nil, node.properties[.anchor] == nil {
                    throw invalid("tooltip-delay requires anchor")
                }
            }
            if node.kind == .accordion,
               (node.properties[.text]?.stringValue ?? "").isEmpty {
                throw invalid("accordion requires text")
            }
            if node.kind == .tree,
               (node.properties[.accessibilityLabel]?.stringValue ?? "").isEmpty {
                throw invalid("tree requires an accessibility label")
            }
            if node.kind == .toolbar,
               (node.properties[.accessibilityLabel]?.stringValue ?? "").isEmpty {
                throw invalid("toolbar requires an accessibility label")
            }
            if node.kind == .bottomTabs {
                guard !(node.properties[.accessibilityLabel]?.stringValue ?? "").isEmpty else {
                    throw invalid("bottom-tabs requires an accessibility label")
                }
                guard (2...5).contains(node.children.count) else {
                    throw invalid("bottom-tabs requires two to five destinations")
                }
            }
            if node.kind == .bottomTab {
                guard !(node.properties[.title]?.stringValue ?? "").isEmpty,
                      node.properties[.pressEnabled]?.boolValue == true,
                      !node.children.isEmpty,
                      let parent = node.parent, nodes[parent]?.kind == .bottomTabs else {
                    throw invalid("bottom-tab requires title, press support, content, and a direct bottom-tabs parent")
                }
            }
            let hasTreeMetadata = node.properties[.role]?.stringValue == "treeitem" ||
                node.properties[.treeLevel] != nil || node.properties[.expanded] != nil
            if hasTreeMetadata {
                guard node.properties[.role]?.stringValue == "treeitem",
                      hasAncestor(node.parent, kind: .tree) else {
                    throw invalid("tree row metadata requires a treeitem inside tree")
                }
                if node.properties[.expanded] != nil,
                   node.properties[.toggleEnabled]?.boolValue != true {
                    throw invalid("expanded treeitem requires toggle support")
                }
            }
            if node.kind == .dropdownMenu || node.kind == .tooltip {
                if node.properties[.anchorAlignment] != nil, node.properties[.anchor] == nil {
                    throw invalid("anchor-alignment requires anchor")
                }
                if node.properties[.anchorOffset] != nil, node.properties[.anchor] == nil {
                    throw invalid("anchor-offset requires anchor")
                }
            }
            if node.kind == .listItem {
                let hasText = !(node.properties[.text]?.stringValue ?? "").isEmpty
                let hasChildren = node.children.contains { nodes[$0]?.kind != .contextMenu }
                guard hasText || hasChildren else {
                    throw invalid("list-item requires text or children")
                }
                guard !(hasText && hasChildren) else {
                    throw invalid("list-item accepts text or children, not both")
                }
            }
            if node.kind == .avatar || node.kind == .image {
                if node.kind == .avatar,
                   (node.properties[.text]?.stringValue ?? "").isEmpty {
                    throw invalid("avatar requires initials")
                }
                if node.kind == .image, node.properties[.image]?.intValue == nil {
                    throw invalid("image requires image")
                }
                let sourceProperties: [LUIProperty] = [
                    .sourceX, .sourceY, .sourceWidth, .sourceHeight,
                ]
                let sourceCount = sourceProperties.filter {
                    node.properties[$0] != nil
                }.count
                guard sourceCount == 0 || sourceCount == sourceProperties.count else {
                    throw invalid("\(node.kind == .avatar ? "avatar" : "image") source crop requires all four coordinates")
                }
                if sourceCount == sourceProperties.count {
                    guard node.properties[.image]?.intValue != nil else {
                        throw invalid("avatar source crop requires an image")
                    }
                    let x = node.properties[.sourceX]?.doubleValue ?? -1.0
                    let y = node.properties[.sourceY]?.doubleValue ?? -1.0
                    let width = node.properties[.sourceWidth]?.doubleValue ?? 0.0
                    let height = node.properties[.sourceHeight]?.doubleValue ?? 0.0
                    guard x >= 0.0, y >= 0.0 else {
                        throw invalid("\(node.kind == .avatar ? "avatar" : "image") source crop coordinates must be non-negative")
                    }
                    guard width > 0.0, height > 0.0 else {
                        throw invalid("\(node.kind == .avatar ? "avatar" : "image") source crop dimensions must be positive")
                    }
                }
            }
            if node.kind == .mediaSurface, node.properties[.surface]?.intValue == nil {
                throw invalid("media-surface requires surface")
            }
            if node.kind == .stepper, node.properties[.active]?.intValue == nil {
                throw invalid("stepper requires active")
            }
            if node.kind == .step {
                guard !(node.properties[.text]?.stringValue ?? "").isEmpty,
                      let parent = node.parent, nodes[parent]?.kind == .stepper else {
                    throw invalid("step requires text and a direct stepper parent")
                }
            }
            if node.kind == .timelineItem {
                guard !(node.properties[.title]?.stringValue ?? "").isEmpty else {
                    throw invalid("timeline-item requires title")
                }
                guard let parent = node.parent, nodes[parent]?.kind == .timeline else {
                    throw invalid("timeline-item requires a direct timeline parent")
                }
            }
            if node.kind == .inputGroup {
                guard node.children.count == 1 || node.children.count == 2,
                      nodes[node.children[0]]?.kind == .textarea else {
                    throw invalid("input-group requires textarea first")
                }
                if node.children.count == 2,
                   nodes[node.children[1]]?.kind != .inputGroupActions {
                    throw invalid("input-group actions must follow textarea")
                }
            }
            if node.kind == .inputGroupActions {
                guard let parent = node.parent, nodes[parent]?.kind == .inputGroup else {
                    throw invalid("input-group-actions requires a direct input-group parent")
                }
            }
        }
        for (id, node) in extensionNodes where scope?.contains(id) ?? true {
            guard let registration = extensionRegistry.registration(node.identifier) else {
                throw invalid("unknown extension identifier")
            }
            if registration.isTweak, node.children.count != 1 {
                throw invalid("platform tweak requires exactly one child")
            }
            for property in registration.properties where property.isRequired {
                guard node.properties[property.name] != nil else {
                    throw invalid("extension properties are incomplete")
                }
            }
        }
    }

    private static func isContextMenuHost(
        _ kind: LUINodeKind,
        properties: [LUIProperty: LUIWireValue]
    ) -> Bool {
        let inherent: Set<LUINodeKind> = [
            .button, .toggleButton, .toggle, .radio, .slider, .textField, .secureField,
            .input, .searchField, .textarea, .checkbox, .switchControl,
            .select, .combobox, .menuItem, .listItem, .accordion, .text,
            .tableCell,
        ]
        return inherent.contains(kind) ||
            properties[.pressEnabled]?.boolValue == true ||
            properties[.doublePressEnabled]?.boolValue == true ||
            properties[.toggleEnabled]?.boolValue == true ||
            properties[.longPressEnabled]?.boolValue == true
    }

    private static func isContextMenuLeafHost(_ kind: LUINodeKind) -> Bool {
        let kinds: Set<LUINodeKind> = [
            .button, .toggleButton, .toggle, .radio, .slider, .textField, .secureField,
            .input, .searchField, .textarea, .checkbox, .switchControl,
            .select, .combobox, .menuItem, .text, .tableCell,
        ]
        return kinds.contains(kind)
    }

    private func hasAncestor(_ parent: Int?, kind: LUINodeKind) -> Bool {
        guard let parent, let node = nodes[parent] else { return false }
        return node.kind == kind || hasAncestor(node.parent, kind: kind)
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

    private func invalid(_ message: String) -> LUIBackendError {
        .invalidBatch(message)
    }
}

extension LUIWireValue {
    func normalized(for property: LUIProperty) -> LUIWireValue {
        if property == .grow || property == .anchorOffset ||
            property == .sourceX || property == .sourceY ||
            property == .sourceWidth || property == .sourceHeight,
           case let .int(value) = self {
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
