import Foundation
import Observation

enum LUIListItemInteractionStyle: Equatable {
    case button
    case composite
}

enum LUIListItemInteractionPolicy {
    static let longPressMinimumDuration = 0.35

    static func style(hasInteractiveChildren: Bool) -> LUIListItemInteractionStyle {
        hasInteractiveChildren ? .composite : .button
    }
}

enum LUIListItemLayoutPolicy {
    static let navigationHeadingSpacing = 8.0

    static func horizontalPadding(isNavigationRow: Bool) -> Double {
        isNavigationRow ? 12.0 : 16.0
    }

    static func stretchesChild(kind: LUINodeKind?, grow: Double?) -> Bool {
        kind == .row || (grow ?? 0.0) > 0.0
    }

    static func showsTrailingSpacer(childGrows: Bool) -> Bool {
        !childGrows
    }

    static func usesInlineTrailingIcon(isNavigationHeading: Bool) -> Bool {
        isNavigationHeading
    }

    static func minimumHeight(
        isNativeListRow: Bool,
        isNavigationRow: Bool,
        isNavigationHeading: Bool,
        explicitMinimumHeight: Int?
    ) -> Double? {
        _ = isNativeListRow
        _ = isNavigationRow
        let semanticMinimumHeight: Double? = isNavigationHeading ? 44.0 : nil
        guard let explicitMinimumHeight else { return semanticMinimumHeight }
        let explicit = Double(explicitMinimumHeight)
        if let semanticMinimumHeight, semanticMinimumHeight > explicit {
            return semanticMinimumHeight
        }
        return explicit
    }
}

enum LUIBinaryControlLayoutPolicy {
    static func minimumTouchHeight(
        isIOS: Bool,
        isNativeFormRow: Bool
    ) -> Double? {
        _ = isIOS
        _ = isNativeFormRow
        return nil
    }

    static func usesAccentTint(isNativeFormRow: Bool) -> Bool {
        !isNativeFormRow
    }

    static func wrapsIdentifiedControlInButton(kind: LUINodeKind) -> Bool {
        switch kind {
        case .checkbox, .switchControl, .toggle:
            true
        default:
            false
        }
    }
}
import SwiftUI
import CoreGraphics

public enum LUIAppleIconSource: Equatable, Sendable {
    case systemName(String)
    case assetName(String)
}

public struct LUIRootSection: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

@Observable
@MainActor
final class LUINodeModel: Identifiable {
    let id: Int
    let kind: LUINodeKind

    private(set) var properties: [LUIProperty: LUIWireValue]
    private(set) var children: [Int]
    private(set) var parent: Int?
    private(set) var revision = 0

    init(id: Int, state: LUINodeState) {
        self.id = id
        kind = state.kind
        properties = state.properties
        children = state.children
        parent = state.parent
    }

    func property(_ property: LUIProperty) -> LUIWireValue? {
        properties[property]
    }

    func apply(state: LUINodeState) {
        guard properties != state.properties || children != state.children ||
            parent != state.parent else {
            return
        }
        properties = state.properties
        children = state.children
        parent = state.parent
        revision += 1
    }

    func invalidateResource() {
        revision += 1
    }

    var text: String {
        properties[.text]?.stringValue ?? ""
    }

    var isEnabled: Bool {
        properties[.enabled]?.boolValue ?? true
    }

    var isChecked: Bool {
        properties[.checked]?.boolValue ?? false
    }

    var isSelected: Bool { properties[.selected]?.boolValue ?? false }
    var role: String? { properties[.role]?.stringValue }
    var treeLevel: Int? { properties[.treeLevel]?.intValue }
    var isExpanded: Bool? { properties[.expanded]?.boolValue }
    var isTreeItem: Bool { role == "treeitem" }
    var requestsAutofocus: Bool { properties[.autofocus]?.boolValue ?? false }
    var supportsLongPress: Bool { properties[.longPressEnabled]?.boolValue ?? false }
    var supportsChange: Bool { properties[.changeEnabled]?.boolValue ?? false }
    var supportsToggle: Bool { properties[.toggleEnabled]?.boolValue ?? false }
    var supportsPress: Bool { properties[.pressEnabled]?.boolValue ?? false }
    var supportsSubmit: Bool { properties[.submitEnabled]?.boolValue ?? false }
    var supportsDoublePress: Bool {
        properties[.doublePressEnabled]?.boolValue ?? false
    }
    var supportsAppear: Bool { properties[.appearEnabled]?.boolValue ?? false }
    var containerRelativeFrame: String? {
        properties[.containerRelativeFrame]?.stringValue
    }
    var containerRelativeFrameInset: Int {
        properties[.containerRelativeFrameInset]?.intValue ?? 0
    }
    var sliderValue: Double { properties[.progressValue]?.doubleValue ?? 0.0 }
    var splitFraction: Double { properties[.progressValue]?.doubleValue ?? 0.0 }
    var splitGap: Int { properties[.gap]?.intValue ?? 9 }
    var splitResizeDuration: Int { properties[.resizeDuration]?.intValue ?? 0 }
    var splitResizeEasing: String { properties[.resizeEasing]?.stringValue ?? "standard" }
    var splitResizeOrigin: Double? { properties[.resizeOrigin]?.doubleValue }
    var buttonVariant: String { properties[.variant]?.stringValue ?? "default" }
    var buttonSize: String { properties[.size]?.stringValue ?? "default" }
    var buttonIconName: String { properties[.icon]?.stringValue ?? "" }
    var buttonIconPlacement: String {
        properties[.iconPlacement]?.stringValue ?? "leading"
    }

    var surfaceWidth: Int? { properties[.width]?.intValue }
    var surfaceHeight: Int? { properties[.height]?.intValue }
    var surfaceMinWidth: Int? { properties[.minWidth]?.intValue }
    var surfaceMaxWidth: Int? { properties[.maxWidth]?.intValue }
    var surfaceMinHeight: Int? { properties[.minHeight]?.intValue }
    var surfaceMaxHeight: Int? { properties[.maxHeight]?.intValue }

    var spinnerExtent: Int {
        switch properties[.size]?.stringValue ?? "default" {
        case "sm": 16
        case "lg": 24
        default: 20
        }
    }

    var spinnerWidth: Int { surfaceWidth ?? spinnerExtent }
    var spinnerHeight: Int { surfaceHeight ?? spinnerExtent }

    var spinnerControlSize: ControlSize {
        switch properties[.size]?.stringValue ?? "default" {
        case "sm": .small
        case "lg": .large
        default: .regular
        }
    }

    var spinnerStyle: LUISpinnerStyle {
        switch properties[.size]?.stringValue ?? "default" {
        case "sm": .small
        case "lg": .large
        default: .regular
        }
    }

    var iconExtent: Int {
        switch properties[.size]?.stringValue ?? "default" {
        case "sm": 16
        case "lg", "icon": 24
        default: 18
        }
    }

    var iconWidth: Int { surfaceWidth ?? iconExtent }
    var iconHeight: Int { surfaceHeight ?? iconExtent }

    var iconName: String { properties[.name]?.stringValue ?? "" }

    var imageSourceRect: CGRect? {
        guard let x = properties[.sourceX]?.doubleValue,
              let y = properties[.sourceY]?.doubleValue,
              let width = properties[.sourceWidth]?.doubleValue,
              let height = properties[.sourceHeight]?.doubleValue else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var avatarSourceRect: CGRect? { imageSourceRect }

    func registeredImage(in backend: LUIAppleBackend) -> CGImage? {
        guard let imageID = properties[.image]?.intValue, imageID > 0 else {
            return nil
        }
        return backend.registeredImage(id: imageID)
    }

    func avatarDisplayImage(in backend: LUIAppleBackend) -> CGImage? {
        guard let image = registeredImage(in: backend) else { return nil }
        return croppedImage(image, source: avatarSourceRect)
    }

    func imageDisplayImage(in backend: LUIAppleBackend) -> CGImage? {
        guard let image = registeredImage(in: backend) else { return nil }
        return croppedImage(image, source: imageSourceRect)
    }

    private func croppedImage(_ image: CGImage, source: CGRect?) -> CGImage? {
        guard let source else { return image }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = source.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return image.cropping(to: clipped)
    }

    func mediaSurfaceFrame(in backend: LUIAppleBackend) -> CGImage? {
        guard mediaSurfaceID > 0 else {
            return nil
        }
        return backend.mediaSurfaceFrame(id: mediaSurfaceID)
    }

    var mediaSurfaceID: Int { properties[.surface]?.intValue ?? 0 }
    var activeStepIndex: Int { properties[.active]?.intValue ?? 0 }
    var timelineTitle: String { properties[.title]?.stringValue ?? "" }
    var timelineDescription: String { properties[.description]?.stringValue ?? "" }
    var timelineMeta: String { properties[.meta]?.stringValue ?? "" }
    var timelineIndicator: String { properties[.indicator]?.stringValue ?? "" }
    var timelineConnector: Bool { properties[.connector]?.boolValue ?? true }
    var bottomTabTitle: String { properties[.title]?.stringValue ?? "" }
    var bottomTabIconName: String { properties[.icon]?.stringValue ?? "" }
    var bottomTabSystemIconName: String { Self.systemIconName(for: bottomTabIconName) }

    var mediaSurfacePlaceholderComponents: [Int] {
        let surfaceID = mediaSurfaceID
        return [
            64 + (surfaceID * 37) % 64,
            64 + (surfaceID * 57) % 64,
            64 + (surfaceID * 83) % 64,
        ]
    }

    var iconSystemName: String {
        Self.systemIconName(for: iconName)
    }

    static func systemIconName(for name: String) -> String {
        switch name {
        case "alert": "exclamationmark.triangle"
        case "archive": "archivebox"
        case "arrow-down": "arrow.down"
        case "arrow-right": "arrow.right"
        case "arrow-up": "arrow.up"
        case "check": "checkmark"
        case "check-circle": "checkmark.circle"
        case "chevron-down": "chevron.down"
        case "chevron-left": "chevron.left"
        case "chevron-right": "chevron.right"
        case "chevron-up": "chevron.up"
        case "circle-dot": "circle.circle"
        case "clock": "clock"
        case "copy": "doc.on.doc"
        case "download": "arrow.down.to.line"
        case "edit": "pencil"
        case "ellipsis": "ellipsis"
        case "external-link": "arrow.up.right.square"
        case "eye": "eye"
        case "file-text": "doc.text"
        case "folder": "folder"
        case "folder-open": "folder.fill"
        case "git-branch": "arrow.triangle.branch"
        case "git-merge": "arrow.triangle.merge"
        case "git-pull-request": "arrow.triangle.pull"
        case "info": "info.circle"
        case "menu": "line.3.horizontal"
        case "mic": "mic"
        case "moon": "moon"
        case "music": "music.note"
        case "panel-left": "sidebar.left"
        case "panel-right": "sidebar.right"
        case "pause": "pause"
        case "play": "play"
        case "plus": "plus"
        case "refresh-cw": "arrow.clockwise"
        case "repeat": "repeat"
        case "save": "square.and.arrow.down"
        case "search": "magnifyingglass"
        case "send": "paperplane"
        case "settings": "gearshape"
        case "shuffle": "shuffle"
        case "skip-back": "backward.end"
        case "skip-forward": "forward.end"
        case "sun": "sun.max"
        case "terminal": "terminal"
        case "trash": "trash"
        case "volume": "speaker.wave.2"
        case "wrench": "wrench"
        case "x": "xmark"
        case "x-circle": "xmark.circle"
        default: "questionmark.square.dashed"
        }
    }

    var progressFraction: Double {
        min(max(properties[.progressValue]?.doubleValue ?? 0.0, 0.0), 1.0)
    }

    func accessibilityLabel(in backend: LUIAppleBackend) -> String? {
        properties[.accessibilityLabel]?.stringValue
    }

    func accessibilityIdentifier(in backend: LUIAppleBackend) -> String? {
        properties[.accessibilityIdentifier]?.stringValue
    }

    func accessibilityHint(in backend: LUIAppleBackend) -> String? { nil }
}

@MainActor
public final class LUIAppleBackend {
    public private(set) var generation = 0
    public var onEvent: ((LUIEvent) -> Void)?

    private var tree = LUIRetainedTree()
    private var models: [Int: LUINodeModel] = [:]
    private var extensionModels: [Int: LUIExtensionNodeModel] = [:]
    private var eventDeferralDepth = 0
    private var deferredEvents: [LUIEvent] = []
    private var interactionLockedDrawers: Set<Int> = []
    private var images: [Int: CGImage] = [:]
    private var mediaSurfaces: [Int: CGImage] = [:]
    private let decoder = JSONDecoder()
    private let appIcons: [String: LUIAppleIconSource]
    let appIconBundle: Bundle?
    private let extensionRegistry: LUIAppleExtensionRegistry
    let tooltipSession = LUITooltipSession()
    let modalPresentation = LUIModalPresentationStore()

    public init(
        appIcons: [String: LUIAppleIconSource] = [:],
        appIconBundle: Bundle? = nil
    ) {
        self.appIcons = appIcons
        self.appIconBundle = appIconBundle
        extensionRegistry = .frozenEmpty()
    }

    public init(
        appIcons: [String: LUIAppleIconSource] = [:],
        appIconBundle: Bundle? = nil,
        extensionRegistry: LUIAppleExtensionRegistry
    ) throws {
        try extensionRegistry.freeze()
        self.appIcons = appIcons
        self.appIconBundle = appIconBundle
        self.extensionRegistry = extensionRegistry
    }

    func iconSource(for name: String) -> LUIAppleIconSource {
        if name.hasPrefix("app:") {
            return appIcons[String(name.dropFirst(4))]
                ?? .systemName("questionmark.square.dashed")
        }
        return .systemName(LUINodeModel.systemIconName(for: name))
    }

    public var rootIDs: [Int] {
        tree.rootIDs.sorted()
    }

    public func rootSections(rootID: Int) -> [LUIRootSection] {
        guard let root = models[rootID] else { return [] }
        return root.children.map { pageID in
            LUIRootSection(
                id: pageID,
                title: firstSectionTitle(nodeID: pageID) ?? "Component \(pageID)"
            )
        }
    }

    func model(id: Int) -> LUINodeModel? {
        models[id]
    }

    func setDrawerInteractionLocked(_ locked: Bool, node: Int) {
        if locked {
            interactionLockedDrawers.insert(node)
        } else {
            interactionLockedDrawers.remove(node)
        }
    }

    func allowsControlInteraction(node: Int) -> Bool {
        guard models[node] != nil || extensionModels[node] != nil else { return false }
        guard !interactionLockedDrawers.isEmpty else { return true }
        // Hit testing cannot cancel a Button press that began before a drawer drag.
        // Check ancestors at delivery time; the drawer's own toggle remains usable.
        var parent = models[node]?.parent ?? extensionModels[node]?.parent
        while let ancestor = parent {
            if interactionLockedDrawers.contains(ancestor) { return false }
            parent = models[ancestor]?.parent ?? extensionModels[ancestor]?.parent
        }
        return true
    }

    func extensionModel(id: Int) -> LUIExtensionNodeModel? {
        extensionModels[id]
    }

    func extensionView(nodeID: Int) -> AnyView {
        guard let model = extensionModels[nodeID],
              let registration = extensionRegistry.registration(model.identifier) else {
            return AnyView(EmptyView())
        }
        return registration.viewFactory(
            LUIAppleExtensionViewContext(nodeID: nodeID, backend: self)
        )
    }

    func anyNodeView(nodeID: Int) -> AnyView {
        AnyView(LUIAnyNodeView(nodeID: nodeID, backend: self))
    }

    private func firstSectionTitle(nodeID: Int) -> String? {
        if let node = models[nodeID] {
            if (node.kind == .heading || node.kind == .text), !node.text.isEmpty {
                return node.text
            }
            for child in node.children {
                if let title = firstSectionTitle(nodeID: child) { return title }
            }
            return nil
        }
        guard let node = extensionModels[nodeID] else { return nil }
        for child in node.children {
            if let title = firstSectionTitle(nodeID: child) { return title }
        }
        return nil
    }

    func registeredImage(id: Int) -> CGImage? {
        images[id]
    }

    func mediaSurfaceFrame(id: Int) -> CGImage? {
        mediaSurfaces[id]
    }

    public func registerImage(id: Int, image: CGImage) throws {
        guard id > 0 else {
            throw invalid("registered image id must be positive")
        }
        images[id] = image
        invalidateAvatars(imageID: id)
    }

    public func unregisterImage(id: Int) {
        guard images.removeValue(forKey: id) != nil else { return }
        invalidateAvatars(imageID: id)
    }

    public func presentMediaSurfaceFrame(id: Int, image: CGImage) throws {
        guard id > 0 else {
            throw invalid("media surface id must be positive")
        }
        mediaSurfaces[id] = image
        invalidateMediaSurfaces(surfaceID: id)
    }

    public func unregisterMediaSurface(id: Int) {
        guard mediaSurfaces.removeValue(forKey: id) != nil else { return }
        invalidateMediaSurfaces(surfaceID: id)
    }

    public func apply(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw invalid("patch batch is not UTF-8")
        }
        let batch: LUIPatchBatch
        do {
            batch = try decoder.decode(LUIPatchBatch.self, from: data)
        } catch let error as LUIBackendError {
            throw error
        } catch {
            throw invalid(error.localizedDescription)
        }

        let expectedGeneration = generation + 1
        guard batch.generation == expectedGeneration else {
            throw invalid(
                "expected patch generation \(expectedGeneration), received \(batch.generation)"
            )
        }

        let nextTree = try tree.applying(
            batch.ops,
            extensionRegistry: extensionRegistry
        )
        withDeferredEventDelivery {
            withTransaction(Transaction(animation: nil)) {
                commit(nextTree)
            }
            tree = nextTree
            syncModalPresentation()
            generation = batch.generation
        }
    }

    func performPress(node: Int) throws {
        guard allowsControlInteraction(node: node) else { return }
        guard let model = models[node],
              model.kind == .button || model.kind == .toggleButton ||
                (model.kind == .text && model.supportsPress) ||
                (model.kind == .bottomTab && model.supportsPress) ||
                (model.kind == .tableCell && model.supportsPress) ||
                model.kind == .select ||
                model.kind == .combobox || model.kind == .menuItem ||
                model.kind == .listItem ||
                (model.kind == .timelineItem && model.supportsPress) ||
                (model.isTreeItem && model.supportsPress),
              model.isEnabled else {
            throw invalid("node \(node) is not an enabled pressable control")
        }
        emit(.press(node: node))
    }

    func performLongPress(node: Int) throws {
        guard allowsControlInteraction(node: node) else { return }
        guard let model = models[node],
              model.kind == .button || model.kind == .toggleButton ||
                model.kind == .listItem,
              model.isEnabled, model.supportsLongPress else {
            throw invalid("node \(node) is not enabled for long press")
        }
        emit(.longPress(node: node))
    }

    func performTextChange(node: Int, text: String) throws {
        guard let model = models[node],
              Self.isTextEntry(model.kind), model.isEnabled else {
            throw invalid("node \(node) is not an editable text control")
        }
        emit(.textChanged(node: node, text: text))
    }

    func performSubmit(node: Int) throws {
        guard let model = models[node],
              Self.isTextEntry(model.kind) ||
                (model.kind == .listItem && model.supportsSubmit),
              model.isEnabled else {
            throw invalid("node \(node) is not an enabled text control")
        }
        emit(.submit(node: node))
    }

    func performDoublePress(node: Int) throws {
        guard let model = models[node], model.kind == .listItem,
              model.isEnabled, model.supportsDoublePress else {
            throw invalid("node \(node) is not an enabled double-press control")
        }
        emit(.doublePress(node: node))
    }

    func performAppear(node: Int) throws {
        guard let model = models[node], model.isEnabled, model.supportsAppear else {
            throw invalid("node \(node) is not enabled for appearance events")
        }
        emit(.appear(node: node))
    }

    public func performExtensionEvent(
        node: Int,
        name: String,
        values: [String: LUIExtensionValue]
    ) throws {
        guard let model = extensionModels[node],
              let registration = extensionRegistry.registration(model.identifier),
              let event = registration.events.first(where: { $0.name == name }) else {
            throw invalid("unknown extension event")
        }
        let fields = Dictionary(uniqueKeysWithValues: event.fields.map { ($0.name, $0) })
        guard values.allSatisfy({ name, value in
            fields[name]?.kind.accepts(value.wireValue) == true
        }), event.fields.allSatisfy({ !$0.isRequired || values[$0.name] != nil }) else {
            throw invalid("invalid extension event payload")
        }
        emit(.extension(
            node: node,
            identifier: model.identifier,
            name: name,
            values: values
        ))
    }

    func performToggle(node: Int, checked: Bool) throws {
        guard allowsControlInteraction(node: node) else { return }
        guard let model = models[node],
              model.kind == .toggleButton || model.kind == .checkbox ||
                model.kind == .switchControl || model.kind == .toggle ||
                model.kind == .accordion || model.kind == .drawer || model.isTreeItem,
              model.isEnabled,
              (model.kind != .accordion && model.kind != .drawer && !model.isTreeItem) ||
                model.supportsToggle else {
            throw invalid("node \(node) is not an enabled toggle")
        }
        emit(.toggleChanged(node: node, checked: checked))
    }

    func performChange(node: Int) throws {
        guard let model = models[node],
              model.kind == .radio || model.isTreeItem, model.isEnabled else {
            throw invalid("node \(node) is not an enabled change control")
        }
        if model.supportsChange {
            if !model.isChecked { emit(.change(node: node)) }
        } else if model.supportsToggle {
            emit(.toggleChanged(node: node, checked: true))
        } else if model.supportsPress {
            emit(.press(node: node))
        }
    }

    func performValueChange(node: Int, value: Double) throws {
        guard let model = models[node],
              model.kind == .slider || model.kind == .split,
              model.isEnabled,
              value.isFinite else {
            throw invalid("node \(node) is not an enabled value control")
        }
        emit(.valueChanged(node: node, value: min(max(value, 0.0), 1.0)))
    }

    func performDismiss(node: Int) throws {
        guard let model = models[node],
              model.kind == .select || model.kind == .combobox ||
                model.kind == .dropdownMenu || model.kind == .dialog ||
                model.kind == .sheet || model.kind == .toast else {
            throw invalid("node \(node) is not dismissible")
        }
        emit(.dismiss(node: node))
    }

    func performAction(node: Int) throws {
        guard let model = models[node] else { throw invalid("unknown node") }
        if model.isTreeItem {
            if model.supportsPress { try performPress(node: node) }
            return
        }
        switch model.kind {
        case .button, .select, .combobox, .menuItem, .listItem, .timelineItem:
            try performPress(node: node)
        case .toggleButton:
            try performToggle(node: node, checked: !model.isSelected)
        case .checkbox, .switchControl, .toggle:
            try performToggle(node: node, checked: !model.isChecked)
        case .accordion:
            try performToggle(node: node, checked: !model.isSelected)
        case .radio:
            try performChange(node: node)
        default:
            throw invalid("node \(node) has no action")
        }
    }

    func performTreeTap(node: Int) throws {
        guard let model = models[node], model.isTreeItem, model.isEnabled else {
            throw invalid("node \(node) is not an enabled tree item")
        }
        let nextExpanded = !(model.isExpanded ?? false)
        if model.supportsPress {
            try performPress(node: node)
        } else if model.supportsChange {
            try performChange(node: node)
        }
        if model.supportsToggle {
            try performToggle(node: node, checked: nextExpanded)
        }
    }

    func treeItemIDs(tree treeID: Int) throws -> [Int] {
        guard models[treeID]?.kind == .tree else {
            throw invalid("node \(treeID) is not a tree")
        }
        var result: [Int] = []
        func visit(_ id: Int) {
            guard let model = models[id] else { return }
            if model.isTreeItem { result.append(id) }
            for child in model.children { visit(child) }
        }
        for child in models[treeID]?.children ?? [] { visit(child) }
        return result
    }

    private func treeLevel(tree: Int, node: Int) -> Int {
        if let level = models[node]?.treeLevel { return level }
        var level = 1
        var parent = models[node]?.parent
        while let parentID = parent, parentID != tree {
            if models[parentID]?.isTreeItem == true { level += 1 }
            parent = models[parentID]?.parent
        }
        return level
    }

    @discardableResult
    func performTreeKey(tree treeID: Int, node nodeID: Int, key: LUITreeKey) throws -> Int {
        let items = try treeItemIDs(tree: treeID).filter {
            models[$0]?.isEnabled == true
        }
        guard let index = items.firstIndex(of: nodeID),
              let node = models[nodeID], node.isEnabled else {
            throw invalid("node \(nodeID) is not an enabled item in tree \(treeID)")
        }

        func select(_ target: Int) throws -> Int {
            let model = models[target]
            if model?.supportsChange == true {
                try performChange(node: target)
            } else if model?.supportsPress == true {
                try performPress(node: target)
            }
            return target
        }

        switch key {
        case .up:
            return try index > 0 ? select(items[index - 1]) : nodeID
        case .down:
            return try index + 1 < items.count ? select(items[index + 1]) : nodeID
        case .home:
            return try select(items[0])
        case .end:
            return try select(items[items.count - 1])
        case .left:
            if node.isExpanded == true, node.supportsToggle {
                try performToggle(node: nodeID, checked: false)
                return nodeID
            }
            let level = treeLevel(tree: treeID, node: nodeID)
            guard level > 1 else { return nodeID }
            for candidate in items[..<index].reversed()
            where treeLevel(tree: treeID, node: candidate) == level - 1 {
                return try select(candidate)
            }
            return nodeID
        case .right:
            if node.isExpanded == false, node.supportsToggle {
                try performToggle(node: nodeID, checked: true)
                return nodeID
            }
            let next = index + 1
            if next < items.count,
               treeLevel(tree: treeID, node: items[next]) ==
                treeLevel(tree: treeID, node: nodeID) + 1 {
                return try select(items[next])
            }
            return nodeID
        case .activate:
            if node.supportsPress { try performPress(node: nodeID) }
            return nodeID
        }
    }

    private func commit(_ nextTree: LUIRetainedTree) {
        for id in Array(models.keys) where nextTree.nodes[id] == nil {
            models[id] = nil
        }
        for (id, state) in nextTree.nodes {
            if let model = models[id] {
                model.apply(state: state)
            } else {
                models[id] = LUINodeModel(id: id, state: state)
            }
        }
        for id in Array(extensionModels.keys) where nextTree.extensionNodes[id] == nil {
            extensionModels[id] = nil
        }
        for (id, state) in nextTree.extensionNodes {
            if let model = extensionModels[id] {
                model.apply(state: state)
            } else {
                extensionModels[id] = LUIExtensionNodeModel(id: id, state: state)
            }
        }
    }

    func withDeferredEventDelivery(_ operation: () -> Void) {
        eventDeferralDepth += 1
        operation()
        eventDeferralDepth -= 1
        guard eventDeferralDepth == 0, !deferredEvents.isEmpty else { return }
        let events = deferredEvents
        deferredEvents.removeAll(keepingCapacity: true)
        for event in events {
            onEvent?(event)
        }
    }

    private func emit(_ event: LUIEvent) {
        if eventDeferralDepth > 0 {
            deferredEvents.append(event)
        } else {
            onEvent?(event)
        }
    }

    private func syncModalPresentation() {
        var presentation: LUIModalPresentation?
        var nestedSheets: [Int: LUIModalPresentation] = [:]
        var visited = Set<Int>()

        func visit(_ nodeID: Int, rootID: Int, dialogAnchorID: Int?, parentSheetID: Int?) {
            guard visited.insert(nodeID).inserted else { return }
            if let model = models[nodeID] {
                if model.kind == .dialog || model.kind == .sheet {
                    let item = LUIModalPresentation(
                        model: model,
                        rootID: rootID,
                        anchorID: model.kind == .dialog
                            ? (dialogAnchorID ?? rootID)
                            : rootID
                    )
                    if model.kind == .sheet, let parentSheetID {
                        nestedSheets[parentSheetID] = item
                    } else {
                        presentation = item
                    }
                }
                let childSheetID = model.kind == .sheet ? model.id : parentSheetID
                let childDialogAnchorID = model.kind == .list
                    ? model.id
                    : dialogAnchorID
                for childID in model.children {
                    visit(
                        childID,
                        rootID: rootID,
                        dialogAnchorID: childDialogAnchorID, parentSheetID: childSheetID
                    )
                }
            } else if let model = extensionModels[nodeID] {
                for childID in model.children {
                    visit(childID, rootID: rootID, dialogAnchorID: dialogAnchorID, parentSheetID: parentSheetID)
                }
            }
        }

        for rootID in rootIDs {
            visit(rootID, rootID: rootID, dialogAnchorID: nil, parentSheetID: nil)
        }
        modalPresentation.nestedSheets = nestedSheets
        modalPresentation.synchronize(with: presentation)
    }

    private func invalidateAvatars(imageID: Int) {
        withTransaction(Transaction(animation: nil)) {
            for model in models.values
            where (model.kind == .avatar || model.kind == .image) &&
                model.property(.image)?.intValue == imageID {
                model.invalidateResource()
            }
        }
    }

    private func invalidateMediaSurfaces(surfaceID: Int) {
        withTransaction(Transaction(animation: nil)) {
            for model in models.values
            where model.kind == .mediaSurface &&
                model.property(.surface)?.intValue == surfaceID {
                model.invalidateResource()
            }
        }
    }

    private func invalid(_ message: String) -> LUIBackendError {
        .invalidBatch(message)
    }

    private static func isTextEntry(_ kind: LUINodeKind) -> Bool {
        kind == .textField || kind == .secureField || kind == .input || kind == .searchField || kind == .textarea ||
            kind == .combobox
    }
}

enum LUITreeKey {
    case up
    case down
    case left
    case right
    case home
    case end
    case activate
}

@MainActor
final class LUITooltipSession {
    private var warmUntil = -Double.infinity

    func isWarm(at time: Double) -> Bool {
        time < warmUntil
    }

    func warm(at time: Double) {
        warmUntil = time + 0.4
    }

    func clear() {
        warmUntil = -Double.infinity
    }
}

@MainActor
final class LUITooltipIntent {
    private enum Origin {
        case pointer
        case focus
        case touch
    }

    private let session: LUITooltipSession
    private var revealAt: Double?
    private var origin: Origin?
    private(set) var isPresented = false

    init(session: LUITooltipSession) {
        self.session = session
    }

    func pointerEntered(at time: Double, delay: Double) {
        if session.isWarm(at: time) || delay == 0.0 {
            reveal(origin: .pointer)
        } else {
            revealAt = time + max(delay, 0)
        }
    }

    func advance(to time: Double) {
        guard let revealAt, time >= revealAt else { return }
        reveal(origin: .pointer)
    }

    func pointerLeft(at time: Double) {
        if isPresented, origin == .pointer {
            session.warm(at: time)
        }
        dismiss()
    }

    func focusEntered() {
        reveal(origin: .focus)
    }

    func focusLeft() {
        dismiss()
    }

    func longPress() {
        session.clear()
        reveal(origin: .touch)
    }

    func press() {
        session.clear()
        dismiss()
    }

    func escape() {
        dismiss()
    }

    func viewBlurred() {
        session.clear()
        dismiss()
    }

    private func reveal(origin: Origin) {
        revealAt = nil
        self.origin = origin
        isPresented = true
    }

    private func dismiss() {
        revealAt = nil
        origin = nil
        isPresented = false
    }
}

/// Spinner sizing tier shared by the platform spinner views.
public enum LUISpinnerStyle: Sendable {
    case small
    case regular
    case large

    /// Intrinsic drawing extent of the platform activity indicator for this
    /// style; the representables do not shrink below it, so callers scale when
    /// the declared frame is smaller.
    var intrinsicExtent: CGFloat {
        #if os(iOS)
        switch self {
        case .small, .regular: 20
        case .large: 37
        }
        #else
        switch self {
        case .small: 16
        case .regular, .large: 32
        }
        #endif
    }
}
