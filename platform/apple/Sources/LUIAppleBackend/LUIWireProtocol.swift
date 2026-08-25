import Foundation

public enum LUIBackendError: Error, Equatable {
    case invalidBatch(String)
}

public enum LUIEvent: Equatable, Sendable {
    case press(node: Int)
    case hold(node: Int)
    case textChanged(node: Int, text: String)
    case submit(node: Int)
    case toggleChanged(node: Int, checked: Bool)
    case change(node: Int)
    case valueChanged(node: Int, value: Double)
    case dismiss(node: Int)
    case doublePress(node: Int)
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

    func matches(_ property: LUIProperty, on kind: LUINodeKind) -> Bool {
        switch (property, self) {
        case let (.headingLevel, .int(level)): (1...6).contains(level)
        case (.checked, .bool): true
        case (.progressValue, .double): true
        case let (.resizeDuration, .int(value)): value >= 0
        case let (.resizeEasing, .string(value)):
            ["linear", "standard", "emphasized", "spring"].contains(value)
        case let (.resizeOrigin, .double(value)): value.isFinite
        case let (.orientation, .string(value)):
            value == "horizontal" || value == "vertical"
        case let (.size, .string(value)):
            Self.controlSizes.contains(value) ||
                (kind == .tableCell && Self.textSizes.contains(value))
        case let (.name, .string(value)):
            Self.iconNames.contains(value) || Self.isApplicationIconName(value)
        case let (.variant, .string(value)): Self.buttonVariants.contains(value)
        case let (.icon, .string(value)):
            Self.iconNames.contains(value) || Self.isApplicationIconName(value)
        case let (.iconPlacement, .string(value)):
            value == "leading" || value == "trailing"
        case (.selected, .bool), (.autofocus, .bool), (.submitOnEnter, .bool),
             (.holdEnabled, .bool),
             (.changeEnabled, .bool), (.toggleEnabled, .bool), (.pressEnabled, .bool),
             (.submitEnabled, .bool), (.doublePressEnabled, .bool): true
        case let (.image, .int(value)), let (.surface, .int(value)): value >= 0
        case let (.active, .int(value)): value >= 0
        case (.title, .string), (.description, .string), (.meta, .string),
             (.indicator, .string), (.connector, .bool): true
        case let (.sourceX, .double(value)),
             let (.sourceY, .double(value)),
             let (.sourceWidth, .double(value)),
             let (.sourceHeight, .double(value)): value.isFinite
        case let (.anchor, .string(value)):
            value == "above" || value == "below"
        case let (.anchorAlignment, .string(value)):
            ["start", "end", "stretch"].contains(value)
        case let (.anchorOffset, .double(value)): value.isFinite
        case let (.tooltipDelay, .int(value)): (0...Int(Int32.max)).contains(value)
        case let (.textAlignment, .string(value)):
            Self.textAlignments.contains(value)
        case let (.role, .string(value)): value == "treeitem"
        case let (.treeLevel, .int(value)): value > 0
        case (.expanded, .bool): true
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
             (.placeholder, .string), (.accessibilityLabel, .string),
             (.styleClass, .string): true
        default: false
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
            !segment.isEmpty && segment.unicodeScalars.allSatisfy { scalar in
                (scalar.value >= 97 && scalar.value <= 122) ||
                    (scalar.value >= 48 && scalar.value <= 57)
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
        case let .setProp(id, property, value):
            guard var node = nodes[id] else { throw invalid("unknown node") }
            let normalizedValue = value.normalized(for: property)
            guard Self.supports(property, on: node.kind),
                  normalizedValue.matches(property, on: node.kind) else {
                throw invalid("unsupported property value")
            }
            node.properties[property] = normalizedValue
            nodes[id] = node
        case let .insertChild(parent, child, index):
            guard var parentNode = nodes[parent], var childNode = nodes[child] else {
                throw invalid("unknown parent or child")
            }
            guard Self.canContainChildren(parentNode.kind) else {
                throw invalid("parent cannot contain children")
            }
            if parentNode.kind == .table, childNode.kind != .tableRow {
                throw invalid("table can contain only table-row")
            }
            if parentNode.kind == .tableRow, childNode.kind != .tableCell {
                throw invalid("table-row can contain only table-cell")
            }
            if parentNode.kind == .tree, !Self.isTreeRow(childNode.kind) {
                throw invalid("tree accepts only row containers")
            }
            if parentNode.kind == .stepper, childNode.kind != .step {
                throw invalid("stepper accepts only step children")
            }
            if parentNode.kind == .timeline, childNode.kind != .timelineItem {
                throw invalid("timeline accepts only timeline-item children")
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
            if Self.isContextMenuLeafHost(parentNode.kind),
               childNode.kind != .contextMenu {
                throw invalid("interactive leaf accepts only context-menu metadata")
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
        if kind == .contextMenu { return false }
        if kind == .accordion {
            return property == .text || property == .selected ||
                property == .toggleEnabled || property == .height
        }
        if kind == .stepper {
            return property == .active || property == .accessibilityLabel
        }
        if kind == .step { return property == .text }
        if kind == .timeline {
            return property == .gap || property == .grow ||
                property == .accessibilityLabel
        }
        if kind == .timelineItem {
            return property == .title || property == .description ||
                property == .meta || property == .indicator ||
                property == .icon || property == .variant ||
                property == .connector || property == .selected ||
                property == .pressEnabled
        }
        if kind == .inputGroup {
            return property == .accessibilityLabel || property == .width ||
                property == .height || property == .minWidth || property == .grow
        }
        if kind == .inputGroupActions { return property == .gap }
        return switch property {
        case .main, .cross:
            kind == .row || kind == .column || kind == .list ||
                isHorizontalGroup(kind)
        case .grow: kind != .avatar && kind != .tooltip && !isModalSurface(kind)
        case .columns: kind == .grid
        case .padding, .width, .height: kind != .avatar && kind != .tooltip
        case .background, .borderColor, .borderWidth,
             .cornerRadius, .styleClass,
             .minWidth, .maxWidth, .minHeight, .maxHeight:
            kind != .avatar && kind != .tooltip && !isModalSurface(kind)
        case .paddingHorizontal, .paddingVertical:
            kind == .row || kind == .column || kind == .grid || kind == .box
        case .foreground:
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
                isModalSurface(kind)
        case .enabled:
            kind == .button || kind == .toggleButton || isTextEntry(kind) ||
                kind == .checkbox || kind == .switchControl || kind == .toggle ||
                kind == .radio || kind == .slider || kind == .select ||
                kind == .combobox || kind == .menuItem || kind == .listItem
        case .gap:
            kind == .row || kind == .column || kind == .grid || kind == .list ||
                kind == .dropdownMenu || isHorizontalGroup(kind) || kind == .split
                || kind == .tableRow || kind == .tree
        case .placeholder:
            isTextEntry(kind) || kind == .select
        case .accessibilityLabel:
            kind == .button || kind == .toggleButton || isTextEntry(kind) || kind == .checkbox ||
                kind == .switchControl || kind == .toggle ||
                kind == .radioGroup || kind == .buttonGroup || kind == .toggleGroup ||
                kind == .breadcrumb || kind == .pagination ||
                kind == .radio || kind == .slider || kind == .avatar || kind == .image ||
                kind == .mediaSurface || kind == .tree ||
                kind == .resizable || kind == .split || kind == .alert || kind == .bubble ||
                isTreeRow(kind)
        case .headingLevel: kind == .heading
        case .checked:
            kind == .checkbox || kind == .switchControl || kind == .toggle || kind == .radio
        case .progressValue: kind == .progress || kind == .slider || kind == .split
        case .resizeDuration, .resizeEasing, .resizeOrigin: kind == .split
        case .orientation: kind == .divider
        case .size:
            kind == .button || kind == .toggleButton || kind == .spinner ||
                kind == .icon || kind == .text || kind == .tableCell
        case .name: kind == .icon
        case .variant:
            kind == .button || kind == .toggleButton || kind == .alert || kind == .bubble
        case .iconPlacement, .holdEnabled:
            kind == .button || kind == .toggleButton
        case .icon:
            kind == .button || kind == .toggleButton || kind == .menuItem ||
                kind == .listItem
        case .selected:
            kind == .button || kind == .toggleButton || kind == .menuItem ||
                kind == .listItem || kind == .tableRow || isTreeRow(kind)
        case .autofocus:
            kind == .button || kind == .toggleButton || isTextEntry(kind)
        case .submitOnEnter: kind == .textarea
        case .changeEnabled, .toggleEnabled: kind == .radio || isTreeRow(kind)
        case .pressEnabled:
            kind == .text || kind == .radio || kind == .select || kind == .combobox ||
                kind == .menuItem || kind == .listItem
                || kind == .tableCell || isTreeRow(kind)
        case .submitEnabled: kind == .combobox || kind == .listItem
        case .doublePressEnabled: kind == .listItem
        case .image:
            kind == .avatar || kind == .image
        case .surface:
            kind == .mediaSurface
        case .sourceX, .sourceY, .sourceWidth, .sourceHeight:
            kind == .avatar || kind == .image
        case .anchor, .anchorAlignment, .anchorOffset:
            kind == .dropdownMenu || kind == .tooltip
        case .tooltipDelay: kind == .tooltip
        case .textAlignment: kind == .tableCell || kind == .bubble || kind == .statusBar
        case .role, .treeLevel, .expanded: isTreeRow(kind)
        case .active, .title, .description, .meta, .indicator, .connector: false
        }
    }

    private static func isTextEntry(_ kind: LUINodeKind) -> Bool {
        kind == .textField || kind == .input || kind == .searchField || kind == .textarea ||
            kind == .combobox
    }

    private static func canContainChildren(_ kind: LUINodeKind) -> Bool {
        kind == .row || kind == .column || kind == .grid || kind == .stack ||
            kind == .panel || kind == .card || kind == .box || kind == .scroll ||
            kind == .list || isHorizontalGroup(kind) || kind == .radioGroup
            || kind == .dropdownMenu || kind == .contextMenu || kind == .listItem || isModalSurface(kind)
            || kind == .accordion
            || kind == .table || kind == .tableRow || kind == .tree || kind == .resizable
            || kind == .split || kind == .alert || kind == .bubble ||
            kind == .stepper || kind == .timeline ||
            kind == .inputGroup || kind == .inputGroupActions ||
            isContextMenuLeafHost(kind)
    }

    private static func isModalSurface(_ kind: LUINodeKind) -> Bool {
        kind == .dialog || kind == .drawer || kind == .sheet
    }

    private static func isHorizontalGroup(_ kind: LUINodeKind) -> Bool {
        kind == .tabs || kind == .buttonGroup || kind == .toggleGroup ||
            kind == .breadcrumb || kind == .pagination
    }

    private static func isTreeRow(_ kind: LUINodeKind) -> Bool {
        kind == .row || kind == .column || kind == .panel || kind == .card ||
            kind == .box || kind == .listItem
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
                        let allowed: Set<LUIProperty> = [.text, .enabled, .pressEnabled]
                        guard child.properties.keys.allSatisfy(allowed.contains) else {
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
            let hasTreeMetadata = node.properties[.role] != nil ||
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
                    let x = node.properties[.sourceX]?.doubleValue ?? -1
                    let y = node.properties[.sourceY]?.doubleValue ?? -1
                    let width = node.properties[.sourceWidth]?.doubleValue ?? 0
                    let height = node.properties[.sourceHeight]?.doubleValue ?? 0
                    guard x >= 0, y >= 0 else {
                        throw invalid("\(node.kind == .avatar ? "avatar" : "image") source crop coordinates must be non-negative")
                    }
                    guard width > 0, height > 0 else {
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
    }

    private static func isContextMenuHost(
        _ kind: LUINodeKind,
        properties: [LUIProperty: LUIWireValue]
    ) -> Bool {
        let inherent: Set<LUINodeKind> = [
            .button, .toggleButton, .toggle, .radio, .slider, .textField,
            .input, .searchField, .textarea, .checkbox, .switchControl,
            .select, .combobox, .menuItem, .listItem, .accordion, .text,
            .tableCell,
        ]
        return inherent.contains(kind) ||
            properties[.pressEnabled]?.boolValue == true ||
            properties[.doublePressEnabled]?.boolValue == true ||
            properties[.toggleEnabled]?.boolValue == true ||
            properties[.holdEnabled]?.boolValue == true
    }

    private static func isContextMenuLeafHost(_ kind: LUINodeKind) -> Bool {
        let kinds: Set<LUINodeKind> = [
            .button, .toggleButton, .toggle, .radio, .slider, .textField,
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
