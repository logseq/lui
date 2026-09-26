import SwiftUI
import UniformTypeIdentifiers

/// Bonsplit-style tabbed split panes, driven by the `split-view`,
/// `split-branch`, `split-pane`, and `split-tab` extension nodes.
///
/// The OCaml app owns the tree; these views own gesture-time visuals (drag
/// preview, drop-zone highlight, divider feedback) so interactions run at
/// full display rate, and only committed actions cross the bridge.
@MainActor
public enum LUISplit {
    static let viewFingerprint =
        "lui-extension-v1|10:split-view|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:12:split-branch,10:split-pane|properties:17:divider-thickness:float:optional:none,24:accessibility-identifier:string:optional:none,9:animation:bool:optional:none|events:"
    static let branchFingerprint =
        "lui-extension-v1|12:split-branch|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:12:split-branch,10:split-pane|properties:11:orientation:string:required:none,5:ratio:float:required:none|events:13:ratio-changed[5:ratio:float:required]"
    static let paneFingerprint =
        "lui-extension-v1|10:split-pane|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:9:split-tab|properties:24:accessibility-identifier:string:optional:none,7:focused:bool:optional:none,7:pane-id:string:required:none,8:selected:string:optional:none|events:10:split-drop[3:tab:string:required,4:edge:string:required,9:from-pane:string:required],10:tab-closed[3:tab:string:required],11:pane-closed[],12:pane-focused[],12:tab-selected[3:tab:string:required],15:split-requested[11:orientation:string:required],8:navigate[9:direction:string:required],9:tab-moved[3:tab:string:required,5:index:int:required,9:from-pane:string:required]"
    static let tabFingerprint =
        "lui-extension-v1|9:split-tab|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:1|children:|properties:24:accessibility-identifier:string:optional:none,4:icon:string:optional:none,5:dirty:bool:optional:none,5:title:string:required:none,6:tab-id:string:required:none,8:closable:bool:optional:none|events:"

    private static let accessibilityIdentifier = LUIExtensionProperty(
        name: "accessibility-identifier", kind: .string)

    /// Registers all four split components. Call this alongside the app's
    /// other extension registrations, before the registry freezes.
    public static func register(in registry: LUIAppleExtensionRegistry) throws {
        try registry.register(
            LUIAppleExtension(
                identifier: "split-view",
                fingerprint: viewFingerprint,
                childIdentifiers: ["split-branch", "split-pane"],
                properties: [
                    LUIExtensionProperty(name: "divider-thickness", kind: .double),
                    LUIExtensionProperty(name: "animation", kind: .bool),
                    accessibilityIdentifier,
                ],
                viewFactory: { AnyView(LUISplitViewNode(context: $0)) }
            ))
        try registry.register(
            LUIAppleExtension(
                identifier: "split-branch",
                fingerprint: branchFingerprint,
                childIdentifiers: ["split-branch", "split-pane"],
                properties: [
                    LUIExtensionProperty(
                        name: "orientation", kind: .string, isRequired: true),
                    LUIExtensionProperty(name: "ratio", kind: .double, isRequired: true),
                ],
                events: [
                    LUIExtensionEvent(
                        name: "ratio-changed",
                        fields: [
                            LUIExtensionEventField(
                                name: "ratio", kind: .double, isRequired: true)
                        ])
                ],
                viewFactory: { AnyView(LUISplitBranchNode(context: $0)) }
            ))
        try registry.register(
            LUIAppleExtension(
                identifier: "split-pane",
                fingerprint: paneFingerprint,
                childIdentifiers: ["split-tab"],
                properties: [
                    LUIExtensionProperty(name: "pane-id", kind: .string, isRequired: true),
                    LUIExtensionProperty(name: "selected", kind: .string),
                    LUIExtensionProperty(name: "focused", kind: .bool),
                    accessibilityIdentifier,
                ],
                events: [
                    LUIExtensionEvent(
                        name: "tab-selected",
                        fields: [
                            LUIExtensionEventField(name: "tab", kind: .string, isRequired: true)
                        ]),
                    LUIExtensionEvent(
                        name: "tab-closed",
                        fields: [
                            LUIExtensionEventField(name: "tab", kind: .string, isRequired: true)
                        ]),
                    LUIExtensionEvent(
                        name: "tab-moved",
                        fields: [
                            LUIExtensionEventField(name: "tab", kind: .string, isRequired: true),
                            LUIExtensionEventField(name: "index", kind: .int, isRequired: true),
                            LUIExtensionEventField(
                                name: "from-pane", kind: .string, isRequired: true),
                        ]),
                    LUIExtensionEvent(name: "pane-focused"),
                    LUIExtensionEvent(
                        name: "navigate",
                        fields: [
                            LUIExtensionEventField(
                                name: "direction", kind: .string, isRequired: true)
                        ]),
                    LUIExtensionEvent(
                        name: "split-requested",
                        fields: [
                            LUIExtensionEventField(
                                name: "orientation", kind: .string, isRequired: true)
                        ]),
                    LUIExtensionEvent(
                        name: "split-drop",
                        fields: [
                            LUIExtensionEventField(name: "tab", kind: .string, isRequired: true),
                            LUIExtensionEventField(
                                name: "from-pane", kind: .string, isRequired: true),
                            LUIExtensionEventField(name: "edge", kind: .string, isRequired: true),
                        ]),
                    LUIExtensionEvent(name: "pane-closed"),
                ],
                viewFactory: { AnyView(LUISplitPaneNode(context: $0)) }
            ))
        try registry.register(
            LUIAppleExtension(
                identifier: "split-tab",
                fingerprint: tabFingerprint,
                acceptsStandardChildren: true,
                properties: [
                    LUIExtensionProperty(name: "tab-id", kind: .string, isRequired: true),
                    LUIExtensionProperty(name: "title", kind: .string, isRequired: true),
                    LUIExtensionProperty(name: "icon", kind: .string),
                    LUIExtensionProperty(name: "dirty", kind: .bool),
                    LUIExtensionProperty(name: "closable", kind: .bool),
                    accessibilityIdentifier,
                ],
                // Tab nodes are data carriers; the pane renders their content.
                viewFactory: { AnyView(LUISplitTabNode(context: $0)) }
            ))
    }
}

// MARK: - Shared environment

/// Visual settings the `split-view` root broadcasts to every descendant.
private struct LUISplitSettings: Equatable, Sendable {
    var dividerThickness: CGFloat = 9
    var animationEnabled = true

    static let fallback = LUISplitSettings()
}

private struct LUISplitSettingsKey: EnvironmentKey {
    static let defaultValue = LUISplitSettings.fallback
}

private extension EnvironmentValues {
    var splitSettings: LUISplitSettings {
        get { self[LUISplitSettingsKey.self] }
        set { self[LUISplitSettingsKey.self] = newValue }
    }
}

private extension LUIAppleExtensionViewContext {
    func string(_ name: String) -> String? {
        guard case .string(let value)? = property(name) else { return nil }
        return value
    }
    func bool(_ name: String, default fallback: Bool = false) -> Bool {
        guard case .bool(let value)? = property(name) else { return fallback }
        return value
    }
    func double(_ name: String, default fallback: Double = 0) -> Double {
        guard case .double(let value)? = property(name) else { return fallback }
        return value
    }
    func childString(node: Int, _ name: String) -> String? {
        guard case .string(let value)? = childProperty(node: node, name) else { return nil }
        return value
    }
    func childBool(node: Int, _ name: String, default fallback: Bool = false) -> Bool {
        guard case .bool(let value)? = childProperty(node: node, name) else { return fallback }
        return value
    }
    func tryEmit(_ name: String, values: [String: LUIExtensionValue] = [:]) {
        guard isUserInteractionEnabled else { return }
        try? emit(name: name, values: values)
    }
}

private var luiSplitSeparatorColor: Color {
    #if os(macOS)
    Color(nsColor: .separatorColor)
    #else
    Color(uiColor: .separator)
    #endif
}

private var luiSplitTabStripColor: Color {
    #if os(macOS)
    Color(nsColor: .windowBackgroundColor)
    #else
    Color(uiColor: .secondarySystemBackground)
    #endif
}

private var luiSplitSelectedTabColor: Color {
    #if os(macOS)
    Color(nsColor: .controlBackgroundColor)
    #else
    Color(uiColor: .systemBackground)
    #endif
}

// MARK: - split-view

private struct LUISplitViewNode: View {
    let context: LUIAppleExtensionViewContext

    var body: some View {
        let settings = LUISplitSettings(
            dividerThickness: max(CGFloat(context.double("divider-thickness", default: 9)), 1),
            animationEnabled: context.bool("animation", default: true)
        )
        context.content
            .environment(\.splitSettings, settings)
            .accessibilityIdentifier(context.string("accessibility-identifier") ?? "")
    }
}

// MARK: - split-branch

private struct LUISplitBranchNode: View {
    let context: LUIAppleExtensionViewContext
    @Environment(\.splitSettings) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fractionState: LUISplitFractionState
    @State private var dragStartFraction: Double?

    init(context: LUIAppleExtensionViewContext) {
        self.context = context
        _fractionState = State(
            initialValue: LUISplitFractionState(
                sourceFraction: context.double("ratio", default: 0.5)))
    }

    private var isHorizontal: Bool {
        context.string("orientation") != "vertical"
    }

    private var animation: Animation? {
        guard settings.animationEnabled, !reduceMotion, dragStartFraction == nil else {
            return nil
        }
        return .spring(duration: 0.25, bounce: 0.1)
    }

    var body: some View {
        GeometryReader { geometry in
            let childIDs = context.childIDs
            let firstID = childIDs.first
            let secondID = childIDs.dropFirst().first
            let axis = isHorizontal ? geometry.size.width : geometry.size.height
            let gap = settings.dividerThickness
            let available = max(axis - gap, 0)
            let fraction = LUISplitGeometry.effectiveFraction(
                value: fractionState.fraction,
                available: Double(available),
                firstMinimum: 0,
                secondMinimum: 0
            )
            let firstLength = available * CGFloat(fraction)

            ZStack(alignment: .topLeading) {
                Group {
                    if isHorizontal {
                        HStack(spacing: gap) {
                            child(firstID, length: firstLength)
                            child(secondID, length: max(available - firstLength, 0))
                        }
                    } else {
                        VStack(spacing: gap) {
                            child(firstID, length: firstLength)
                            child(secondID, length: max(available - firstLength, 0))
                        }
                    }
                }
                .animation(animation, value: firstLength)

                divider(
                    offset: firstLength,
                    geometry: geometry.size,
                    available: available
                )
            }
        }
        .onAppear { reconcile(sourceRatio: context.double("ratio", default: 0.5)) }
        .onChange(of: context.double("ratio", default: 0.5)) { _, value in
            reconcile(sourceRatio: value)
        }
    }

    @ViewBuilder
    private func child(_ id: Int?, length: CGFloat) -> some View {
        Group {
            if let id {
                context.content(for: id)
            } else {
                Color.clear
            }
        }
        .frame(
            width: isHorizontal ? length : nil,
            height: isHorizontal ? nil : length
        )
    }

    private func divider(offset: CGFloat, geometry: CGSize, available: CGFloat) -> some View {
        let gap = settings.dividerThickness
        let visible = min(gap, 1)
        return ZStack {
            Color.clear
            Rectangle()
                .fill(luiSplitSeparatorColor)
                .frame(
                    width: isHorizontal ? visible : nil,
                    height: isHorizontal ? nil : visible
                )
        }
        .frame(
            width: isHorizontal ? gap : geometry.width,
            height: isHorizontal ? geometry.height : gap
        )
        .contentShape(Rectangle())
        .offset(x: isHorizontal ? offset : 0, y: isHorizontal ? 0 : offset)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStartFraction ?? fractionState.fraction
                    dragStartFraction = start
                    let delta = isHorizontal ? value.translation.width : value.translation.height
                    fractionState.applyUserFraction(start + Double(delta / max(available, 1)))
                }
                .onEnded { _ in
                    dragStartFraction = nil
                    context.tryEmit(
                        "ratio-changed", values: ["ratio": .double(fractionState.fraction)])
                }
        )
        .focusable()
        .onKeyPress(.leftArrow) { adjustDivider(by: -0.05) }
        .onKeyPress(.rightArrow) { adjustDivider(by: 0.05) }
        .onKeyPress(.upArrow) { adjustDivider(by: -0.05) }
        .onKeyPress(.downArrow) { adjustDivider(by: 0.05) }
        .accessibilityElement()
        .accessibilityLabel("Split divider")
        .accessibilityValue("\(Int((fractionState.fraction * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            _ = adjustDivider(by: direction == .increment ? 0.05 : -0.05)
        }
    }

    private func adjustDivider(by delta: Double) -> KeyPress.Result {
        fractionState.applyUserFraction(fractionState.fraction + delta)
        context.tryEmit("ratio-changed", values: ["ratio": .double(fractionState.fraction)])
        return .handled
    }

    private func reconcile(sourceRatio: Double) {
        fractionState.reconcile(sourceFraction: sourceRatio)
    }
}

// MARK: - split-pane

/// Where a pending drop would land on this pane.
private enum LUISplitDropZone: Equatable {
    case center
    case edge(String)  // "left" | "right" | "top" | "bottom"
}

/// Splits a drag payload of the form "<pane-id>\t<tab-id>".
private func luiSplitUnpackDragPayload(_ raw: String) -> (pane: String, tab: String) {
    if let sep = raw.firstIndex(of: "\t") {
        return (String(raw[raw.startIndex..<sep]), String(raw[raw.index(after: sep)...]))
    }
    return ("", raw)
}

private struct LUISplitTabInfo: Identifiable {
    let node: Int
    let tabID: String
    let title: String
    let dirty: Bool
    let closable: Bool
    let accessibilityIdentifier: String?

    var id: String { tabID }
}

private struct LUISplitPaneNode: View {
    let context: LUIAppleExtensionViewContext
    @Environment(\.splitSettings) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dropZone: LUISplitDropZone?
    @State private var tabDropIndex: Int?
    @State private var paneSize: CGSize = .zero
    @FocusState private var hasKeyFocus: Bool

    private var paneID: String { context.string("pane-id") ?? "" }
    private var isFocused: Bool { context.bool("focused") }

    private var tabs: [LUISplitTabInfo] {
        context.childIDs.compactMap { child in
            guard let tabID = context.childString(node: child, "tab-id") else { return nil }
            return LUISplitTabInfo(
                node: child,
                tabID: tabID,
                title: context.childString(node: child, "title") ?? tabID,
                dirty: context.childBool(node: child, "dirty"),
                closable: context.childBool(node: child, "closable", default: true),
                accessibilityIdentifier: context.childString(
                    node: child, "accessibility-identifier")
            )
        }
    }

    private var selectedTabID: String {
        if let selected = context.string("selected"), !selected.isEmpty { return selected }
        return tabs.first?.tabID ?? ""
    }

    private var animation: Animation? {
        settings.animationEnabled && !reduceMotion ? .spring(duration: 0.25, bounce: 0.1) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            paneContent
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { paneSize = geo.size }
                    .onChange(of: geo.size) { _, size in paneSize = size }
            }
        )
        .overlay { dropZoneOverlay }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .focusable()
        .focused($hasKeyFocus)
        .onTapGesture {
            hasKeyFocus = true
            context.tryEmit("pane-focused")
        }
        .modifier(LUISplitPaneKeys(context: context, selectedTab: selectedTabID))
        .onDrop(of: [UTType.text], delegate: paneDropDelegate)
        .animation(animation, value: selectedTabID)
        .animation(animation, value: dropZone)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(context.string("accessibility-identifier") ?? "")
    }

    private var paneDropDelegate: LUISplitPaneDropDelegate {
        LUISplitPaneDropDelegate(
            paneID: paneID,
            context: context,
            paneSize: paneSize,
            zone: $dropZone,
            tabDropIndex: $tabDropIndex
        )
    }

    // MARK: tab bar

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element.tabID) { index, tab in
                        tabView(tab, index: index)
                        if tabDropIndex == index + 1 { dropIndicator }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 30)
            .background(luiSplitTabStripColor)
            .onChange(of: selectedTabID) { _, id in
                withAnimation(animation) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var dropIndicator: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2, height: 18)
            .transition(.opacity)
    }

    private func tabView(_ tab: LUISplitTabInfo, index: Int) -> some View {
        let isSelected = tab.tabID == selectedTabID
        return HStack(spacing: 4) {
            if tab.dirty {
                Circle().fill(Color.secondary).frame(width: 5, height: 5)
            }
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)
            if tab.closable {
                Button {
                    context.tryEmit("tab-closed", values: ["tab": .string(tab.tabID)])
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
                .accessibilityLabel("Close \(tab.title)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(isSelected ? luiSplitSelectedTabColor : .clear)
        .contentShape(Rectangle())
        .id(tab.tabID)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(tab.accessibilityIdentifier ?? "")
        .onTapGesture {
            hasKeyFocus = true
            context.tryEmit("tab-selected", values: ["tab": .string(tab.tabID)])
            context.tryEmit("pane-focused")
        }
        .onDrag {
            // Payload packs the source pane so the drop target can report an
            // accurate `from-pane` without consulting the app.
            NSItemProvider(object: "\(paneID)\t\(tab.tabID)" as NSString)
        } preview: {
            Text(tab.title)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .onDrop(
            of: [UTType.text],
            delegate: LUISplitTabDropDelegate(
                index: index,
                context: context,
                tabCount: tabs.count,
                tabDropIndex: $tabDropIndex
            )
        )
        .overlay(alignment: .leading) {
            if tabDropIndex == index { dropIndicator.offset(x: -1) }
        }
    }

    // MARK: content + drop zones

    private var paneContent: some View {
        ZStack {
            // Keep every tab mounted so scroll/focus/editor state survives
            // switching; only the selected one is visible.
            ForEach(tabs) { tab in
                context.content(for: tab.node)
                    .opacity(tab.tabID == selectedTabID ? 1 : 0)
                    .allowsHitTesting(tab.tabID == selectedTabID)
                    .accessibilityHidden(tab.tabID != selectedTabID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var dropZoneOverlay: some View {
        if let dropZone {
            ZStack {
                switch dropZone {
                case .center:
                    Color.accentColor.opacity(0.10)
                case .edge(let edge):
                    GeometryReader { geo in
                        let horizontal = edge == "left" || edge == "right"
                        let primary = horizontal ? geo.size.width : geo.size.height
                        let extent = max(primary * 0.35, 48)
                        Color.accentColor.opacity(0.18)
                            .frame(
                                width: horizontal ? extent : geo.size.width,
                                height: horizontal ? geo.size.height : extent
                            )
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: Alignment(
                                    horizontal: edge == "right" ? .trailing
                                        : edge == "left" ? .leading : .center,
                                    vertical: edge == "bottom" ? .bottom
                                        : edge == "top" ? .top : .center
                                ))
                    }
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

/// Pane-level keyboard commands. Semantic intents cross the bridge as
/// extension events so the app decides what each does.
private struct LUISplitPaneKeys: ViewModifier {
    let context: LUIAppleExtensionViewContext
    let selectedTab: String

    func body(content: Content) -> some View {
        // Intermediate lets keep each type-check small enough for the
        // expression solver; modifier filtering happens inside each closure
        // (onKeyPress has no modifiers parameter).
        let navigation = content
            .onKeyPress(.leftArrow, phases: .down) { press in
                navigate(press, modifiers: [.command, .option], direction: "left")
            }
            .onKeyPress(.rightArrow, phases: .down) { press in
                navigate(press, modifiers: [.command, .option], direction: "right")
            }
            .onKeyPress(.upArrow, phases: .down) { press in
                navigate(press, modifiers: [.command, .option], direction: "up")
            }
            .onKeyPress(.downArrow, phases: .down) { press in
                navigate(press, modifiers: [.command, .option], direction: "down")
            }
        let splits = navigation
            .onKeyPress(KeyEquivalent("d"), phases: .down) { press in
                guard press.modifiers.contains([.command, .option]) else { return .ignored }
                return split(press.modifiers.contains(.shift) ? "vertical" : "horizontal")
            }
            .onKeyPress(KeyEquivalent("\\"), phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                return split(press.modifiers.contains(.shift) ? "vertical" : "horizontal")
            }
        return splits
            .onKeyPress(KeyEquivalent("w"), phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                if press.modifiers.contains(.shift) {
                    context.tryEmit("pane-closed")
                    return .handled
                }
                return closeSelectedTab()
            }
    }

    private func navigate(
        _ press: KeyPress, modifiers: EventModifiers, direction: String
    ) -> KeyPress.Result {
        guard press.modifiers == modifiers else { return .ignored }
        context.tryEmit("navigate", values: ["direction": .string(direction)])
        return .handled
    }

    private func split(_ orientation: String) -> KeyPress.Result {
        context.tryEmit("split-requested", values: ["orientation": .string(orientation)])
        return .handled
    }

    private func closeSelectedTab() -> KeyPress.Result {
        guard !selectedTab.isEmpty, context.isUserInteractionEnabled else { return .ignored }
        context.tryEmit("tab-closed", values: ["tab": .string(selectedTab)])
        return .handled
    }
}

// MARK: - Drop delegates

/// Drop on a pane body: center merges the tab into this pane, an edge asks
/// the app to split this pane.
private struct LUISplitPaneDropDelegate: DropDelegate {
    let paneID: String
    let context: LUIAppleExtensionViewContext
    let paneSize: CGSize
    @Binding var zone: LUISplitDropZone?
    @Binding var tabDropIndex: Int?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let size = paneSize
        guard size.width > 0, size.height > 0 else {
            return DropProposal(operation: .move)
        }
        // Edge zone = outer 25%, clamped to [48, 160]pt, matching Bonsplit.
        let edgeX = min(max(size.width * 0.25, 48), 160)
        let edgeY = min(max(size.height * 0.25, 48), 160)
        let location = info.location
        let newZone: LUISplitDropZone
        if location.x < edgeX { newZone = .edge("left") } else if location.x > size.width - edgeX
        { newZone = .edge("right") } else if location.y < edgeY { newZone = .edge("top") }
        else if location.y > size.height - edgeY { newZone = .edge("bottom") }
        else { newZone = .center }
        if newZone != zone { zone = newZone }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        zone = nil
        tabDropIndex = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            zone = nil
            tabDropIndex = nil
        }
        guard let zone,
            let provider = info.itemProviders(for: [UTType.text]).first
        else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let tabID =
                (item as? String)
                ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
            guard let raw = tabID else { return }
            let payload = luiSplitUnpackDragPayload(raw)
            Task { @MainActor in
                switch zone {
                case .center:
                    context.tryEmit(
                        "tab-moved",
                        values: [
                            "tab": .string(payload.tab),
                            "index": .int(Int.max),  // append
                            "from-pane": .string(payload.pane),
                        ])
                case .edge(let edge):
                    context.tryEmit(
                        "split-drop",
                        values: [
                            "tab": .string(payload.tab),
                            "from-pane": .string(payload.pane),
                            "edge": .string(edge),
                        ])
                }
            }
        }
        return true
    }
}

/// Drop on a specific tab: inserts the dragged tab at this index.
private struct LUISplitTabDropDelegate: DropDelegate {
    let index: Int
    let context: LUIAppleExtensionViewContext
    let tabCount: Int
    @Binding var tabDropIndex: Int?

    private var resolvedIndex: Int { tabDropIndex ?? index }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Top half of the 30pt tab strip inserts before, bottom half after.
        let before = info.location.y < 15
        tabDropIndex = min(before ? index : index + 1, tabCount)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if tabDropIndex == index || tabDropIndex == index + 1 { tabDropIndex = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = resolvedIndex
        defer { tabDropIndex = nil }
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let tabID =
                (item as? String)
                ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
            guard let raw = tabID else { return }
            let payload = luiSplitUnpackDragPayload(raw)
            Task { @MainActor in
                context.tryEmit(
                    "tab-moved",
                    values: [
                        "tab": .string(payload.tab),
                        "index": .int(target),
                        "from-pane": .string(payload.pane),
                    ])
            }
        }
        return true
    }
}

// MARK: - split-tab

/// Tab nodes only exist so the pane can render their content; a bare
/// `split-tab` outside a pane renders its own children stacked.
private struct LUISplitTabNode: View {
    let context: LUIAppleExtensionViewContext

    var body: some View {
        VStack(spacing: 0) {
            ForEach(context.childIDs, id: \.self) { childID in
                context.content(for: childID)
            }
        }
    }
}
