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
    /// A single glyph from a font the app registered (e.g. an icon font
    /// bundled with the host). `family` is the font's family name, `scalar`
    /// the Unicode scalar of the glyph.
    case fontGlyph(family: String, scalar: UInt32)
}

public struct LUIRootSection: Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String

    public init(id: Int, title: String) {
        self.id = id
        self.title = title
    }
}

/// Display data decoded from wire props once per commit — the raw
/// `style-class` string plus its split token set, layout fields parents
/// read while laying children out, and the theme-scope contribution — so
/// view bodies read plain fields instead of re-parsing strings every
/// evaluation.
struct LUINodeDerived: Equatable {
    var styleClass: String?
    var styleClassTokens: Set<String>
    /// `grow` layout factor (absent = 0).
    var grow: Double
    /// `alignment` override consulted by overlay/stack parents.
    var alignment: String?
    /// `anchor` prop present — marks anchored menus/tooltips.
    var hasAnchor: Bool
    /// `enabled` prop (absent = true).
    var isEnabled: Bool
    var themeScope: LUIThemeScopeContribution

    init() {
        styleClass = nil
        styleClassTokens = []
        grow = 0
        alignment = nil
        hasAnchor = false
        isEnabled = true
        themeScope = LUIThemeScopeContribution()
    }

    init(properties: [LUIProperty: LUIWireValue]) {
        styleClass = properties[.styleClass]?.stringValue
        styleClassTokens = styleClass.map {
            Set($0.split(separator: " ").map(String.init))
        } ?? []
        grow = properties[.grow]?.doubleValue ?? 0
        alignment = properties[.alignment]?.stringValue
        hasAnchor = properties[.anchor] != nil
        isEnabled = properties[.enabled]?.boolValue ?? true
        themeScope = LUIThemeScopeContribution(
            tokens: LUIThemeTokenDecoder.tokens(properties[.theme]?.stringValue),
            scheme: LUIThemeTokenDecoder.colorScheme(
                properties[.themeMode]?.stringValue
            ),
            typography: LUITypographySpec(properties: properties)
        )
    }
}

/// Child fields a parent body reads while laying out — a view onto the
/// child's own commit-decoded `LUINodeDerived`, so the parent never
/// re-parses child props per evaluation.
struct LUIChildLayout: Equatable {
    var kind: LUINodeKind
    var derived: LUINodeDerived

    var grow: Double { derived.grow }
    var alignment: String? { derived.alignment }
    var isEnabled: Bool { derived.isEnabled }
    var styleClass: String? { derived.styleClass }
    var styleClassTokens: Set<String> { derived.styleClassTokens }
}

/// Everything a view body needs to know about a node's children — the
/// visible-child list, per-child layout fields, auxiliary-slot
/// capabilities and scroll-section titles — computed once per commit so
/// parents consume plain data instead of re-resolving child models and
/// re-parsing child props on every evaluation. Maintained by
/// `LUIAppleBackend` during `apply`, including for parents that were not
/// themselves touched but whose children were.
struct LUIChildData: Equatable {
    /// `children` minus auxiliary slots (context-menu, swipe-actions,
    /// list-section header/footer).
    var visible: [Int] = []
    /// Per-child layout fields keyed by child id; extension and unmounted
    /// children have no entry.
    var layout: [Int: LUIChildLayout] = [:]
    /// First `context-menu` child, retained even while its actions are empty.
    var contextMenuID: Int?
    /// First `dropdown-menu` / `tooltip` child carrying an `anchor` prop.
    var anchoredMenuID: Int?
    var anchoredTooltipID: Int?
    /// Anchored-menu trigger children the stack host handles specially.
    var hasComboboxChild = false
    var hasSelectChild = false
    /// Segmented-control fast path: non-empty, every child an enabled button.
    var segmentedTabsSupported = false
    /// Visible-child → active `scroll-section-title` for tracking lists.
    var sectionTitles: [Int: String]?
}

@Observable
@MainActor
final class LUINodeModel: Identifiable {
    let id: Int
    let kind: LUINodeKind

    @ObservationIgnored private var storedProperties: [LUIProperty: LUIWireValue]
    var properties: [LUIProperty: LUIWireValue] {
        access(keyPath: \.properties)
        return storedProperties
    }
    /// Prop-derived display data (style-class tokens, theme scope),
    /// refreshed whenever `properties` restages — subscribers only see a
    /// mutation when the derived data itself changes.
    @ObservationIgnored private var storedDerived: LUINodeDerived
    var derived: LUINodeDerived {
        access(keyPath: \.derived)
        return storedDerived
    }
    @ObservationIgnored private var storedChildren: [Int]
    var children: [Int] {
        access(keyPath: \.children)
        return storedChildren
    }
    /// Commit-computed data about this node's children: the visible-child
    /// list, per-child layout fields, auxiliary-slot capabilities and
    /// scroll-section titles. Maintained by the backend so view bodies
    /// don't re-resolve child models or re-parse child props per
    /// evaluation.
    @ObservationIgnored private var storedChildData = LUIChildData()
    var childData: LUIChildData {
        access(keyPath: \.childData)
        return storedChildData
    }
    /// `children` minus auxiliary slots — kept as an alias over
    /// `childData` so existing readers subscribe to the same commit data.
    var visibleChildren: [Int] {
        access(keyPath: \.childData)
        return storedChildData.visible
    }
    @ObservationIgnored private var storedParent: Int?
    var parent: Int? {
        access(keyPath: \.parent)
        return storedParent
    }
    @ObservationIgnored private var storedRevision = 0
    var revision: Int {
        access(keyPath: \.revision)
        return storedRevision
    }
    /// Fold of this node's revision and all descendants' stamps,
    /// maintained at commit time — reads are O(1) and subscribe to one
    /// key path instead of the whole subtree.
    @ObservationIgnored private var storedSubtreeStamp = 0
    var subtreeStamp: Int {
        access(keyPath: \.subtreeStamp)
        return storedSubtreeStamp
    }

    init(id: Int, state: LUINodeState) {
        self.id = id
        kind = state.kind
        storedProperties = state.properties
        storedDerived = LUINodeDerived(properties: state.properties)
        storedChildren = state.children
        storedParent = state.parent
    }

    func property(_ property: LUIProperty) -> LUIWireValue? {
        properties[property]
    }

    // Stage without observation callbacks: a synchronous render must never
    // see a partially updated model or an incomplete graph.
    func stage(state: LUINodeState) -> LUIModelChanges {
        var changes: LUIModelChanges = []
        if storedProperties != state.properties {
            storedProperties = state.properties
            changes.insert(.properties)
            let derived = LUINodeDerived(properties: state.properties)
            if storedDerived != derived {
                storedDerived = derived
                changes.insert(.derived)
            }
        }
        if storedChildren != state.children {
            storedChildren = state.children
            changes.insert(.children)
        }
        if storedParent != state.parent {
            storedParent = state.parent
            changes.insert(.parent)
        }
        if !changes.isEmpty {
            storedRevision += 1
            changes.insert(.revision)
        }
        return changes
    }

    /// Restaged in a second commit pass once every child model holds its
    /// new state — parents refresh even when only a child's props changed.
    /// Deliberately does not bump `revision`: `.childData` readers
    /// subscribe to that key path directly, and folding it into the
    /// revision gate would re-evaluate every ancestor view on each
    /// descendant commit.
    func stageChildData(_ data: LUIChildData) -> LUIModelChanges {
        guard storedChildData != data else { return [] }
        storedChildData = data
        return [.childData]
    }

    /// Restaged after `stageChildData` so children already carry their
    /// fresh stamps when parents fold them. Same no-revision rule as
    /// `stageChildData` — a descendant commit must not walk view
    /// re-evaluation up the ancestor chain.
    func stageSubtreeStamp(_ stamp: Int) -> LUIModelChanges {
        guard storedSubtreeStamp != stamp else { return [] }
        storedSubtreeStamp = stamp
        return [.subtreeStamp]
    }

    /// Off-commit stamp invalidation for `invalidateResource` callers:
    /// bumps the stamp directly (and the backend propagates it to
    /// ancestors) since no restage pass runs.
    func invalidateSubtreeStamp() {
        storedSubtreeStamp &+= 1
        withMutation(keyPath: \.subtreeStamp) {}
    }

    func publish(_ changes: LUIModelChanges) {
        if changes.contains(.properties) { withMutation(keyPath: \.properties) {} }
        if changes.contains(.derived) { withMutation(keyPath: \.derived) {} }
        if changes.contains(.children) { withMutation(keyPath: \.children) {} }
        if changes.contains(.childData) { withMutation(keyPath: \.childData) {} }
        if changes.contains(.parent) { withMutation(keyPath: \.parent) {} }
        if changes.contains(.subtreeStamp) { withMutation(keyPath: \.subtreeStamp) {} }
        if changes.contains(.revision) { withMutation(keyPath: \.revision) {} }
    }

    func invalidateResource() {
        storedRevision += 1
        withMutation(keyPath: \.revision) {}
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
    var supportsPointer: Bool { properties[.pointerEnabled]?.boolValue ?? false }
    var rowKey: String? { properties[.key]?.stringValue }
    var separatorVisibility: String? { properties[.separator]?.stringValue }
    var listStyle: String? { properties[.style]?.stringValue }
    var scrollTarget: String? { properties[.scrollTarget]?.stringValue }
    var scrollAnchor: String? { properties[.scrollAnchor]?.stringValue }
    var scrollToken: Int? { properties[.scrollToken]?.intValue }
    var scrollAnimated: Bool { properties[.scrollAnimated]?.boolValue ?? true }
    var tracksVisibleRange: Bool {
        properties[.trackVisibleRange]?.boolValue ?? false
    }
    var containerRelativeFrame: String? {
        properties[.containerRelativeFrame]?.stringValue
    }
    var containerRelativeFrameInset: Int {
        properties[.containerRelativeFrameInset]?.intValue ?? 0
    }
    var sliderValue: Double { properties[.progressValue]?.doubleValue ?? 0.0 }
    var stepperValue: Double { properties[.progressValue]?.doubleValue ?? 0.0 }
    var stepperRange: ClosedRange<Double> {
        let lower = properties[.minValue]?.doubleValue ?? 0.0
        let upper = properties[.maxValue]?.doubleValue ?? .greatestFiniteMagnitude
        return lower...max(lower, upper)
    }
    var stepperStep: Double {
        let step = properties[.stepValue]?.doubleValue ?? 1.0
        return step > 0 ? step : 1.0
    }
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

    /// Last `croppedImage` result; a node's image and source rect only
    /// change via props, so one entry covers every body evaluation between
    /// commits and avoids a `CGImage.cropping(to:)` copy per eval.
    @ObservationIgnored private var cachedCrop:
        (source: CGImage, rect: CGRect, result: CGImage?)?

    private func croppedImage(_ image: CGImage, source: CGRect?) -> CGImage? {
        guard let source else { return image }
        if let cached = cachedCrop,
           cached.source === image, cached.rect == source {
            return cached.result
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = source.intersection(bounds)
        let result = clipped.isNull || clipped.isEmpty
            ? nil
            : image.cropping(to: clipped)
        cachedCrop = (image, source, result)
        return result
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

/// Observable flags backing `LUIAppleBackend`'s frame reporting: the
/// per-node geometry probe reads `isEnabled`/`isSuspended` in its body so
/// probes mount and unmount with the flags instead of staying installed
/// and no-op'ing.
@Observable
@MainActor
final class LUIFrameReporting {
    var isEnabled = false
    var isSuspended = false
}

@MainActor
public final class LUIAppleBackend {
    public private(set) var generation = 0
    /// Number of observable model commits, for diagnostics.
    public private(set) var commitSequence = 0
    public var onEvent: ((LUIEvent) -> Void)?

    // MARK: - Node frame reporting

    /// Observable side of `frameReportingEnabled`: views read this so the
    /// per-node geometry probes mount/unmount when reporting toggles.
    let frameReporting = LUIFrameReporting()

    /// Gates emission of `onFramesReport` and the per-node
    /// `onGeometryChange` probes. Toggling it on mounts the probes, whose
    /// first layout pass feeds `nodeFrames`, so a driver attaching
    /// mid-session still sees every node's latest geometry.
    public var frameReportingEnabled: Bool {
        get { frameReporting.isEnabled }
        set {
            let wasEnabled = frameReporting.isEnabled
            frameReporting.isEnabled = newValue
            if newValue && !wasEnabled {
                scheduleFramesReport()
            }
        }
    }

    /// Called once per coalesced layout flush with the full node-id →
    /// frame map in the scene's global coordinate space. Feeds drive's
    /// live-attach `tap x y` hit-testing; set `frameReportingEnabled` to
    /// start receiving reports.
    public var onFramesReport: (([Int: CGRect]) -> Void)?

    /// When true, per-node frame collection is skipped entirely — hosts
    /// running the LOGSEQ_NO_FRAME_PROBE mount-cost experiment set this so
    /// `onGeometryChange` recorders never mount.
    public var frameCollectionSuspended: Bool {
        get { frameReporting.isSuspended }
        set { frameReporting.isSuspended = newValue }
    }

    private var nodeFrames: [Int: CGRect] = [:]
    private var framesReportScheduled = false

    // MARK: - file-picker operations

    /// In-flight and completed file-picker requests keyed by node id. Held
    /// here rather than in `LUIFilePickerView`'s @State so a view teardown
    /// (tab switch, re-layout) does not release security-scoped files or
    /// lose the pending completion handshake for a still-mounted node.
    private var filePickerOperations: [Int: LUIFilePickerOperation] = [:]

    func filePickerOperation(node: Int) -> LUIFilePickerOperation? {
        filePickerOperations[node]
    }

    func setFilePickerOperation(node: Int, _ operation: LUIFilePickerOperation) {
        filePickerOperations[node] = operation
    }

    func acceptFilePickerSelection(node: Int, token: LUIWireValue, files: [LUIRetainedFile]) -> Bool {
        guard var operation = filePickerOperations[node],
              operation.token == token, operation.phase == .presenting else {
            releaseFilePickerFiles(files)
            return false
        }
        operation.phase = .awaitingCompletion
        operation.files = files
        filePickerOperations[node] = operation
        return true
    }

    /// Drops the operation and releases every file it retained.
    func clearFilePickerOperation(node: Int) {
        guard let operation = filePickerOperations.removeValue(forKey: node)
        else { return }
        releaseFilePickerFiles(operation.files)
    }

    func releaseFilePickerFiles(_ files: [LUIRetainedFile]) {
        for file in files {
            if file.securityScoped {
                file.url.stopAccessingSecurityScopedResource()
            }
            if file.temporary {
                try? FileManager.default.removeItem(at: file.url)
            }
        }
    }

    func reportNodeFrame(_ nodeID: Int, _ rect: CGRect) {
        if frameCollectionSuspended { return }
        if nodeFrames[nodeID] == rect { return }
        nodeFrames[nodeID] = rect
        scheduleFramesReport()
    }

    func removeNodeFrame(_ nodeID: Int) {
        if nodeFrames.removeValue(forKey: nodeID) != nil {
            scheduleFramesReport()
        }
    }

    /// Push the current frame table to `onFramesReport` immediately —
    /// for a driver/handler that attached after the last layout flush.
    public func emitFramesSnapshot() {
        guard frameReportingEnabled else { return }
        onFramesReport?(nodeFrames)
    }

    private func scheduleFramesReport() {
        guard !framesReportScheduled else { return }
        framesReportScheduled = true
        // CFRunLoop delivery, not DispatchQueue.main.async — GCD main-queue
        // wakeups go unserviced while the runloop waits for events.
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.framesReportScheduled = false
                guard self.frameReportingEnabled else { return }
                self.onFramesReport?(self.nodeFrames)
            }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private var tree = LUIRetainedTree()
    private let lookupObservation = LUIModelLookupObservation()
    private var models: [Int: LUINodeModel] = [:]
    private var extensionModels: [Int: LUIExtensionNodeModel] = [:]
    // Count of mounted dialog/sheet/filePreview nodes; maintained in
    // `commit` so `syncModalPresentation` can skip its full-tree DFS on
    // batches that cannot change any presentation.
    private var modalNodeCount = 0
    private var eventDeferralDepth = 0
    private var deferredEvents: [LUIEvent] = []
    private var interactionLockedDrawers: Set<Int> = []
    private var images: [Int: CGImage] = [:]
    private var mediaSurfaces: [Int: CGImage] = [:]
    private let appIcons: [String: LUIAppleIconSource]
    let appIconBundle: Bundle?
    private let extensionRegistry: LUIAppleExtensionRegistry
    let tooltipSession = LUITooltipSession()
    let modalPresentation = LUIModalPresentationStore()
    let filePreviewPresentation = LUIFilePreviewStore()

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

    /// Debug snapshot of the retained store — whether patch commits actually
    /// materialized view models. Used by LOGSEQ_PERF diagnostics.
    public var debugModelCounts: String {
        "n=\(models.count) e=\(extensionModels.count) roots=\(tree.rootIDs.sorted())"
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
        _ = lookupObservation[id]
        return models[id]
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
        _ = lookupObservation[id]
        return extensionModels[id]
    }

    func extensionView(nodeID: Int) -> AnyView {
        if ProcessInfo.processInfo.environment["LOGSEQ_PERF"] != nil,
           nodeID < 700 {
            let m = extensionModels[nodeID]
            let ok = m != nil
                && extensionRegistry.registration(m!.identifier) != nil
            FileHandle.standardError.write(
                "PERF extview id=\(nodeID) model=\(m != nil) ok=\(ok) ident=\(m?.identifier ?? "-")\n"
                    .data(using: .utf8)!)
        }
        guard let model = extensionModels[nodeID],
              let registration = extensionRegistry.registration(model.identifier) else {
            return AnyView(EmptyView())
        }
        let v = registration.viewFactory(
            LUIAppleExtensionViewContext(nodeID: nodeID, backend: self)
        )
        if ProcessInfo.processInfo.environment["LOGSEQ_PERF"] != nil,
           nodeID < 700 {
            return AnyView(v.onAppear {
                FileHandle.standardError.write(
                    "PERF extview-appear id=\(nodeID) t=\(CFAbsoluteTimeGetCurrent())\n"
                        .data(using: .utf8)!)
            })
        }
        return v
    }

    func anyNodeView(nodeID: Int) -> AnyView {
        AnyView(LUIAnyNodeView(nodeID: nodeID, backend: self).equatable())
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

    /// A patch batch decoded ahead of application — the JSON parse is pure,
    /// so hosts running a 120Hz UI can decode on a background executor and
    /// hand the result to `apply(decoded:)` on the main actor.
    public struct DecodedPatchBatch: Sendable {
        let batch: LUIPatchBatch

        /// Patch generation, exposed for host-side perf diagnostics.
        public var generation: Int { batch.generation }
    }

    /// Decodes a patch batch. Pure and `nonisolated` — safe to call off the
    /// main actor; pair with `apply(decoded:)` which preserves generation
    /// ordering and must still run on the main actor.
    public nonisolated static func decode(_ json: String) throws -> DecodedPatchBatch {
        guard let data = json.data(using: .utf8) else {
            throw LUIBackendError.invalidBatch("patch batch is not UTF-8")
        }
        do {
            let batch = try JSONDecoder().decode(LUIPatchBatch.self, from: data)
            return DecodedPatchBatch(batch: batch)
        } catch let error as LUIBackendError {
            throw error
        } catch {
            throw LUIBackendError.invalidBatch(error.localizedDescription)
        }
    }

    public func apply(json: String) throws {
        try apply(decoded: try Self.decode(json))
    }

    public func apply(decoded: DecodedPatchBatch) throws {
        let batch = decoded.batch
        // A received generation is consumed whether or not its ops
        // land — the OCaml runtime advances its own generation even
        // when apply fails, so holding `generation` at the last
        // success would reject every later batch and deafen the
        // session permanently. Stale or repeated batches are dropped;
        // a forward gap applies best-effort (ops that reference nodes
        // a dropped batch created simply fail validation, keeping the
        // tree consistent).
        guard batch.generation > generation else { return }
        generation = batch.generation

        let tA = CFAbsoluteTimeGetCurrent()
        let effects = try tree.applying(
            batch.ops,
            extensionRegistry: extensionRegistry
        )
        let tB = CFAbsoluteTimeGetCurrent()
        withDeferredEventDelivery {
            pendingCommitTouched.formUnion(effects.touched)
            pendingCommitDropped.formUnion(effects.dropped)
            pendingCommitStructural = pendingCommitStructural || effects.structural
            pendingCommitModalRelevant.formUnion(effects.modalRelevant)

            var tC = tB
            var tD = tB
            let updatesVirtualWindow = effects.touched.contains { id in
                tree.nodes[id]?.properties[.virtualTotalCount] != nil ||
                tree.nodes[id]?.properties[.dataAttrs]?.stringValue?
                    .contains("data-virtual-count\u{1f}") == true
            }
            if coalescesCommits, !updatesVirtualWindow,
               CFAbsoluteTimeGetCurrent() < coalesceWindowUntil {
                // Inside a burst window: this patch's mutations merge into the
                // pending commit and land as one view update once the stream
                // quiets down. iOS's update-coalescing collection view replays
                // rapid successive commits as a single batch against stale
                // section state and asserts; collapsing them avoids that.
                scheduleCommitFlush()
            } else {
                tC = CFAbsoluteTimeGetCurrent()
                flushPendingCommit()
                tD = CFAbsoluteTimeGetCurrent()
            }
            if ProcessInfo.processInfo.environment["LOGSEQ_PERF"] != nil {
                FileHandle.standardError.write(
                    "PERF apply-split gen=\(batch.generation) applying=\(Int((tB-tA)*1000))ms commit=\(Int((tC-tB)*1000))ms modal=\(Int((tD-tC)*1000))ms touched=\(effects.touched.count) dropped=\(effects.dropped.count)\n"
                        .data(using: .utf8)!)
            }
        }
    }

    /// When true, commits that follow another commit within
    /// `commitCoalesceWindow` are merged and materialized as a single view
    /// update after a short quiet delay (`commitQuietDelay`). The retained
    /// tree still advances on every `apply`, so queries and event dispatch
    /// always see the latest state; only the observable view models lag by at
    /// most the window. Off by default; consumers that emit back-to-back
    /// patches across runloop turns (multi-RPC effects) should opt in.
    public var coalescesCommits = false
    private let commitCoalesceWindow: CFAbsoluteTime = 0.15
    private let commitQuietDelay: CFAbsoluteTime = 0.05
    private var coalesceWindowUntil: CFAbsoluteTime = 0
    private var commitFlushTimer: CFRunLoopTimer?
    private var pendingCommitTouched = Set<Int>()
    private var pendingCommitDropped = Set<Int>()
    private var pendingCommitStructural = false
    private var pendingCommitModalRelevant = Set<Int>()

    private func scheduleCommitFlush() {
        if let timer = commitFlushTimer {
            CFRunLoopTimerInvalidate(timer)
            commitFlushTimer = nil
        }
        let timer = CFRunLoopTimerCreateWithHandler(
            nil,
            CFAbsoluteTimeGetCurrent() + commitQuietDelay,
            .infinity,
            0,
            0
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.commitFlushTimer = nil
                self.withDeferredEventDelivery {
                    self.flushPendingCommit()
                }
            }
        }
        commitFlushTimer = timer
        CFRunLoopAddTimer(CFRunLoopGetMain(), timer, .commonModes)
    }

    private func flushPendingCommit() {
        if let timer = commitFlushTimer {
            CFRunLoopTimerInvalidate(timer)
            commitFlushTimer = nil
        }
        guard !(pendingCommitTouched.isEmpty && pendingCommitDropped.isEmpty
            && pendingCommitModalRelevant.isEmpty && !pendingCommitStructural)
        else { return }
        let touched = pendingCommitTouched
        let dropped = pendingCommitDropped
        let structural = pendingCommitStructural
        let modalRelevant = pendingCommitModalRelevant
        pendingCommitTouched.removeAll(keepingCapacity: true)
        pendingCommitDropped.removeAll(keepingCapacity: true)
        pendingCommitStructural = false
        pendingCommitModalRelevant.removeAll(keepingCapacity: true)

        withTransaction(Transaction(animation: nil)) {
            commit(tree, touched: touched, dropped: dropped)
        }
        // A dialog/sheet's membership, anchor, or nesting only changes when
        // the structure moves or a presentation-relevant node mutates —
        // property-only patches elsewhere never do, so skip the tree walk.
        if structural || !modalRelevant.isEmpty {
            if modalNodeCount > 0 {
                syncModalPresentation()
            } else {
                // No dialog/sheet/filePreview is mounted, so the DFS
                // could only produce empty presentations — clear any
                // stale state directly instead of walking the tree.
                if !modalPresentation.nestedSheets.isEmpty {
                    modalPresentation.nestedSheets = [:]
                }
                modalPresentation.synchronize(with: nil)
                filePreviewPresentation.synchronize(with: nil)
            }
        }
        coalesceWindowUntil = CFAbsoluteTimeGetCurrent() + commitCoalesceWindow
    }

    func performPress(node: Int) throws {
        guard allowsControlInteraction(node: node) else { return }
        guard let model = models[node],
              model.kind == .button || model.kind == .toggleButton ||
                (model.kind == .column && model.supportsPress) ||
                (model.kind == .row && model.supportsPress) ||
                (model.kind == .box && model.supportsPress) ||
                (model.kind == .text && model.supportsPress) ||
                (model.kind == .bottomTab && model.supportsPress) ||
                (model.kind == .tableCell && model.supportsPress) ||
                model.kind == .select ||
                model.kind == .combobox || model.kind == .menuItem ||
                model.kind == .listItem || model.kind == .swipeAction ||
                (model.kind == .timelineItem && model.supportsPress) ||
                (model.kind == .fileImage && model.supportsPress) ||
                (model.isTreeItem && model.supportsPress),
              model.isEnabled else {
            throw invalid("node \(node) is not an enabled pressable control")
        }
        emit(.press(node: node))
        // SwiftUI's tap gestures expose no hit position, so the press detail
        // reports zero coordinates/modifiers — a real tap with real fields
        // unavailable on this host.
        if model.supportsPointer {
            emit(.pressDetail(
                node: node, x: 0, y: 0, modifiers: 0, button: 0, targetClass: ""))
        }
    }

    /// Nearest ancestor (or self) of `node` that opted into pointer events.
    /// Web attaches the pointer listeners on the listener-owning ancestor and
    /// lets events bubble up to it; host monitors hit-test the deepest node
    /// and retarget through this lookup for the same effect.
    public func pointerEventTarget(of node: Int) -> Int? {
        var current: Int? = node
        while let id = current, let model = models[id] {
            if model.isEnabled, model.supportsPointer { return id }
            current = model.parent
        }
        return nil
    }

    /// Press/pointer details report the deepest hit's style class (web
    /// `event.target.className`), not the listener node's class.
    public func styleClass(of node: Int) -> String? {
        models[node]?.properties[.styleClass]?.stringValue
    }

    /// Real-coordinate pointer-detail entry points. SwiftUI tap gestures
    /// carry no position, so the host's event monitor resolves the hit and
    /// supplies x/y/modifiers/button/targetClass itself.
    public func performPointerDown(
        node: Int, x: Double, y: Double, modifiers: Int, button: Int,
        targetClass: String
    ) throws {
        guard let model = models[node], model.isEnabled, model.supportsPointer else {
            throw invalid("node \(node) is not enabled for pointer events")
        }
        emit(.pointerDown(
            node: node, x: x, y: y, modifiers: modifiers, button: button,
            targetClass: targetClass))
    }

    public func performPointerUp(
        node: Int, x: Double, y: Double, modifiers: Int, button: Int,
        targetClass: String
    ) throws {
        guard let model = models[node], model.isEnabled, model.supportsPointer else {
            throw invalid("node \(node) is not enabled for pointer events")
        }
        emit(.pointerUp(
            node: node, x: x, y: y, modifiers: modifiers, button: button,
            targetClass: targetClass))
    }

    public func performPressDetail(
        node: Int, x: Double, y: Double, modifiers: Int, button: Int,
        targetClass: String
    ) throws {
        guard allowsControlInteraction(node: node) else { return }
        guard let model = models[node], model.isEnabled, model.supportsPointer else {
            throw invalid("node \(node) is not enabled for pointer events")
        }
        emit(.pressDetail(
            node: node, x: x, y: y, modifiers: modifiers, button: button,
            targetClass: targetClass))
    }

    public func performContextMenuPress(
        node: Int, x: Double, y: Double, modifiers: Int, button: Int,
        targetClass: String
    ) throws {
        guard allowsControlInteraction(node: node) else { return }
        guard let model = models[node], model.isEnabled, model.supportsPointer else {
            throw invalid("node \(node) is not enabled for pointer events")
        }
        emit(.contextMenuPress(
            node: node, x: x, y: y, modifiers: modifiers, button: button,
            targetClass: targetClass))
    }

    public func performPointerEnter(node: Int) throws {
        guard let model = models[node], model.isEnabled, model.supportsPointer else {
            throw invalid("node \(node) is not enabled for pointer events")
        }
        emit(.pointerEnter(node: node))
    }

    public func performPointerLeave(node: Int) throws {
        guard let model = models[node], model.isEnabled, model.supportsPointer else {
            throw invalid("node \(node) is not enabled for pointer events")
        }
        emit(.pointerLeave(node: node))
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
        guard model.property(.readOnly)?.boolValue != true else { return }
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

    func performScrollCompleted(node: Int, token: Int, outcome: String) {
        emit(.scrollCompleted(node: node, token: token, outcome: outcome))
    }

    func performVisibleRange(node: Int, first: Int, last: Int) {
        emit(.visibleRange(node: node, first: first, last: last))
    }

    func performVirtualWindow(model: LUINodeModel, generation: Int, first: Int, last: Int, pins: [Int]) {
        guard models[model.id] === model, model.property(.virtualGeneration)?.intValue == generation,
              let count = model.property(.virtualTotalCount)?.intValue,
              first >= 0, first <= last, last <= count else { return }
        let children = Set(model.children)
        emit(.virtualWindow(node: model.id, generation: generation, first: first, last: last,
                            pins: pins.filter { $0 > 0 && children.contains($0) }))
    }

    var virtualPresentationIDs: [Int] {
        var ids = modalPresentation.nestedSheets.values.map(\.id)
        if let item = modalPresentation.item { ids.append(item.id) }
        if let item = filePreviewPresentation.item { ids.append(item.id) }
        return ids.sorted()
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
                model.kind == .accordion || model.kind == .drawer ||
                model.kind == .listItem || model.isTreeItem,
              model.isEnabled,
              (model.kind != .accordion && model.kind != .drawer &&
                model.kind != .listItem && !model.isTreeItem) ||
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
              model.kind == .slider || model.kind == .split ||
                model.kind == .numberStepper,
              model.isEnabled,
              value.isFinite else {
            throw invalid("node \(node) is not an enabled value control")
        }
        if model.kind == .numberStepper {
            emit(.valueChanged(
                node: node,
                value: min(max(value, model.stepperRange.lowerBound), model.stepperRange.upperBound)
            ))
        } else {
            emit(.valueChanged(node: node, value: min(max(value, 0.0), 1.0)))
        }
    }

    func performDismiss(node: Int) throws {
        guard let model = models[node],
              model.kind == .select || model.kind == .combobox ||
                model.kind == .dropdownMenu || model.kind == .dialog ||
                model.kind == .sheet || model.kind == .toast ||
                model.kind == .filePreview ||
                model.kind == .filePicker else {
            throw invalid("node \(node) is not dismissible")
        }
        emit(.dismiss(node: node))
    }

    func performPicked(node: Int, payload: String) throws {
        guard let model = models[node], model.kind == .filePicker else {
            throw invalid("node \(node) is not a file-picker")
        }
        emit(.picked(node: node, payload: payload))
    }

    func performAction(node: Int) throws {
        guard let model = models[node] else { throw invalid("unknown node") }
        if model.isTreeItem {
            if model.supportsPress { try performPress(node: node) }
            return
        }
        switch model.kind {
        case .button, .select, .combobox, .menuItem, .listItem, .timelineItem,
             .swipeAction, .fileImage:
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

    private func commit(
        _ tree: LUIRetainedTree,
        touched: Set<Int>,
        dropped: Set<Int>
    ) {
        commitSequence += 1
        // Untouched nodes are identical by construction (ops only mutate the
        // nodes they name), so reconciliation only walks the patched set.
        let perf = ProcessInfo.processInfo.environment["LOGSEQ_PERF"] != nil
        var tDrop: Double = 0
        var tNodeApply: Double = 0
        var tExtApply: Double = 0
        var tChildData: Double = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        var nodeChanges: [Int: (LUINodeModel, LUIModelChanges)] = [:]
        var extensionChanges: [Int: (LUIExtensionNodeModel, LUIModelChanges)] = [:]
        var membershipChanges = Set<Int>()
        /// Nodes whose child data or subtree stamp must be restaged: every
        /// touched node plus its ancestors, collected on both the pre- and
        /// post-stage parent chains so reparents cover the old side too.
        var descendantsRefresh = Set<Int>()
        for id in dropped { collectAncestors(of: id, into: &descendantsRefresh) }
        for id in dropped {
            if models[id] != nil || extensionModels[id] != nil {
                membershipChanges.insert(id)
            }
            if let model = models[id], Self.isModalKind(model.kind) {
                modalNodeCount -= 1
            }
            models[id] = nil
            extensionModels[id] = nil
            clearFilePickerOperation(node: id)
        }
        if perf { tDrop = CFAbsoluteTimeGetCurrent() - t0 }
        for id in touched where !dropped.contains(id) {
            collectAncestors(of: id, into: &descendantsRefresh)
            if let state = tree.nodes[id] {
                descendantsRefresh.insert(id)
                let t1 = CFAbsoluteTimeGetCurrent()
                if let model = models[id] {
                    let changes = model.stage(state: state)
                    if !changes.isEmpty {
                        nodeChanges[id] = (model, changes)
                    }
                } else {
                    if Self.isModalKind(state.kind) {
                        modalNodeCount += 1
                    }
                    membershipChanges.insert(id)
                    models[id] = LUINodeModel(id: id, state: state)
                }
                if perf { tNodeApply += CFAbsoluteTimeGetCurrent() - t1 }
            }
            if let state = tree.extensionNodes[id] {
                descendantsRefresh.insert(id)
                let t2 = CFAbsoluteTimeGetCurrent()
                if let model = extensionModels[id] {
                    let changes = model.stage(state: state)
                    if !changes.isEmpty { extensionChanges[id] = (model, changes) }
                } else {
                    membershipChanges.insert(id)
                    extensionModels[id] = LUIExtensionNodeModel(
                        id: id,
                        state: state
                    )
                }
                if perf { tExtApply += CFAbsoluteTimeGetCurrent() - t2 }
            }
            // Post-stage chain: a reparent also invalidates the new side.
            collectAncestors(of: id, into: &descendantsRefresh)
        }
        let t3 = CFAbsoluteTimeGetCurrent()
        // Child data reads the staged state of every child, so it stages
        // after the main pass: parents refresh even when only a child's
        // props (grow, alignment, anchor, enabled, style-class) changed.
        descendantsRefresh.subtract(dropped)
        for id in descendantsRefresh {
            guard let model = models[id] else { continue }
            let changes = model.stageChildData(makeChildData(for: model))
            if !changes.isEmpty {
                let merged = (nodeChanges[id]?.1 ?? []).union(changes)
                nodeChanges[id] = (model, merged)
            }
        }
        // Subtree stamps fold descendant revisions bottom-up; memoized over
        // the refreshed set so refreshed parents reuse fresh child values
        // and untouched children contribute their stored stamp.
        var stampMemo: [Int: Int] = [:]
        var stampVisiting = Set<Int>()
        func stamp(_ id: Int) -> Int {
            if let memo = stampMemo[id] { return memo }
            let value: Int
            guard descendantsRefresh.contains(id), !stampVisiting.contains(id) else {
                value = models[id]?.subtreeStamp
                    ?? extensionModels[id]?.subtreeStamp ?? -1
                stampMemo[id] = value
                return value
            }
            stampVisiting.insert(id)
            var folded = (models[id]?.revision
                ?? extensionModels[id]?.revision ?? -1) &* 31
            for childID in models[id]?.children
                ?? extensionModels[id]?.children ?? []
            {
                folded = folded &* 31 &+ stamp(childID)
            }
            stampVisiting.remove(id)
            value = folded
            stampMemo[id] = value
            return value
        }
        for id in descendantsRefresh {
            let folded = stamp(id)
            if let model = models[id] {
                let changes = model.stageSubtreeStamp(folded)
                if !changes.isEmpty {
                    let merged = (nodeChanges[id]?.1 ?? []).union(changes)
                    nodeChanges[id] = (model, merged)
                }
            } else if let model = extensionModels[id] {
                let changes = model.stageSubtreeStamp(folded)
                if !changes.isEmpty {
                    let merged = (extensionChanges[id]?.1 ?? []).union(changes)
                    extensionChanges[id] = (model, merged)
                }
            }
        }
        if perf { tChildData = CFAbsoluteTimeGetCurrent() - t3 }
        // Every state, revision and lookup now belongs to the same commit.
        // Observation willSet can synchronously flush SwiftUI transactions;
        // publish only after that flush can traverse the complete new graph.
        for (model, changes) in nodeChanges.values { model.publish(changes) }
        for (model, changes) in extensionChanges.values { model.publish(changes) }
        for id in membershipChanges { lookupObservation.publish(id: id) }
        if perf {
            FileHandle.standardError.write(
                "PERF commit-split drop=\(Int(tDrop*1000))ms nodeApply=\(Int(tNodeApply*1000))ms extApply=\(Int(tExtApply*1000))ms childData=\(Int(tChildData*1000))ms\n"
                    .data(using: .utf8)!)
        }
    }

    /// Walks the model parent chain of `nodeID`, collecting every ancestor.
    /// Both sides of a reparent need a child-data/stamp restage, so callers
    /// run this before and after `stage` updates `parent`.
    private func collectAncestors(of nodeID: Int, into set: inout Set<Int>) {
        var cursor = models[nodeID]?.parent ?? extensionModels[nodeID]?.parent
        while let parentID = cursor {
            set.insert(parentID)
            cursor = models[parentID]?.parent ?? extensionModels[parentID]?.parent
        }
    }

    /// Commit-time children data for `model`: the visible-child filter plus
    /// per-child layout fields and auxiliary-slot capabilities parent views
    /// used to recompute by scanning child models on every body evaluation.
    private func makeChildData(for model: LUINodeModel) -> LUIChildData {
        var data = LUIChildData()
        var sawWireChild = false
        var sawContextMenu = false
        var allEnabledButtons = true
        for childID in model.children {
            guard let child = models[childID] else {
                // Extension and unmounted children stay visible, carry no
                // layout entry and are ignored for segmented support —
                // matching the old `compactMap(model)` child scans.
                data.visible.append(childID)
                continue
            }
            sawWireChild = true
            data.layout[childID] = LUIChildLayout(kind: child.kind, derived: child.derived)
            switch child.kind {
            case .contextMenu:
                if !sawContextMenu {
                    sawContextMenu = true
                    // Menu membership can change before a native list row
                    // is removed. Its presentation anchor must retain the
                    // same lifetime as the context-menu node itself.
                    data.contextMenuID = childID
                }
            case .swipeActions, .listSectionHeader, .listSectionFooter:
                break
            case .dropdownMenu:
                data.visible.append(childID)
                if child.derived.hasAnchor, data.anchoredMenuID == nil {
                    data.anchoredMenuID = childID
                }
            case .tooltip:
                data.visible.append(childID)
                if child.derived.hasAnchor, data.anchoredTooltipID == nil {
                    data.anchoredTooltipID = childID
                }
            case .combobox:
                data.visible.append(childID)
                data.hasComboboxChild = true
            case .select:
                data.visible.append(childID)
                data.hasSelectChild = true
            default:
                data.visible.append(childID)
            }
            if child.kind != .button || !child.derived.isEnabled {
                allEnabledButtons = false
            }
        }
        data.segmentedTabsSupported = sawWireChild && allEnabledButtons
        if model.derived.styleClassTokens.contains("scroll-section-titles") {
            data.sectionTitles = sectionTitles(over: data.visible)
        }
        return data
    }

    /// Maps each visible child of a `scroll-section-titles` list to the
    /// title in effect at that row — the nearest preceding descendant
    /// carrying `scroll-section-title`, resolved with one commit-time DFS
    /// instead of a per-evaluation subtree walk.
    private func sectionTitles(over childIDs: [Int]) -> [Int: String]? {
        var titles: [Int: String] = [:]
        var current: String?

        func title(in nodeID: Int) -> String? {
            guard let node = models[nodeID] else { return nil }
            if node.derived.styleClassTokens.contains("scroll-section-title") {
                return node.text.isEmpty ? nil : node.text
            }
            return node.children.lazy.compactMap { title(in: $0) }.first
        }

        for childID in childIDs {
            if let title = title(in: childID) { current = title }
            if let current { titles[childID] = current }
        }
        return titles.isEmpty ? nil : titles
    }

    private static func isModalKind(_ kind: LUINodeKind) -> Bool {
        kind == .dialog || kind == .sheet || kind == .filePreview
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
        var filePreview: LUIFilePreviewPresentation?
        var visited = Set<Int>()

        func visit(_ nodeID: Int, rootID: Int, dialogAnchorID: Int?, parentSheetID: Int?) {
            guard visited.insert(nodeID).inserted else { return }
            if let model = models[nodeID] {
                if model.kind == .filePreview,
                   let url = LUIFilePath.url(
                        model.property(.path)?.stringValue ?? ""
                   ) {
                    filePreview = LUIFilePreviewPresentation(
                        nodeID: nodeID,
                        rootID: rootID,
                        url: url
                    )
                }
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
        if modalPresentation.nestedSheets != nestedSheets {
            modalPresentation.nestedSheets = nestedSheets
        }
        modalPresentation.synchronize(with: presentation)
        filePreviewPresentation.synchronize(with: filePreview)
    }

    private func invalidateAvatars(imageID: Int) {
        withTransaction(Transaction(animation: nil)) {
            for model in models.values
            where (model.kind == .avatar || model.kind == .image) &&
                model.property(.image)?.intValue == imageID {
                model.invalidateResource()
                invalidateSubtreeStamps(from: model.id)
            }
        }
    }

    private func invalidateMediaSurfaces(surfaceID: Int) {
        withTransaction(Transaction(animation: nil)) {
            for model in models.values
            where model.kind == .mediaSurface &&
                model.property(.surface)?.intValue == surfaceID {
                model.invalidateResource()
                invalidateSubtreeStamps(from: model.id)
            }
        }
    }

    /// `invalidateResource` bumps a revision without a commit, so the
    /// commit-maintained subtree stamps along the node's ancestor chain
    /// would go stale — bump them directly to keep `measureStamp` reads
    /// monotonic.
    private func invalidateSubtreeStamps(from nodeID: Int) {
        var cursor: Int? = nodeID
        while let id = cursor {
            if let model = models[id] {
                model.invalidateSubtreeStamp()
            } else {
                extensionModels[id]?.invalidateSubtreeStamp()
            }
            cursor = models[id]?.parent ?? extensionModels[id]?.parent
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
