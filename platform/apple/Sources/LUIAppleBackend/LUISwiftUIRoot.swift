#if !SKIP
import Foundation
import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LUIModalPresentation: Identifiable {
    let model: LUINodeModel
    let rootID: Int
    let anchorID: Int

    var id: Int { model.id }
}

@Observable
@MainActor
final class LUIModalPresentationStore {
    private(set) var item: LUIModalPresentation?
    var nestedSheets: [Int: LUIModalPresentation] = [:]
    private var interactiveDismissalID: Int?
    private var dialogActionID: Int?

    func synchronize(with item: LUIModalPresentation?) {
        guard self.item?.id != item?.id else { return }
        if item == nil {
            dialogActionID = nil
        }
        self.item = item
    }

    func updateFromPresentation(_ item: LUIModalPresentation?) {
        if item == nil, let presentedID = self.item?.id {
            interactiveDismissalID = presentedID
        }
        self.item = item
    }

    func beginDialogAction(_ id: Int) {
        dialogActionID = id
    }

    func dismissDialogFromPresentation() -> Int? {
        guard let presentedID = item?.id else { return nil }
        item = nil
        if dialogActionID == presentedID {
            dialogActionID = nil
            return nil
        }
        return presentedID
    }

    func consumeInteractiveDismissal() -> Int? {
        defer { interactiveDismissalID = nil }
        return interactiveDismissalID
    }
}

public struct LUISwiftUIRoot: View {
    private let backend: LUIAppleBackend
    private let rootID: Int

    public init(backend: LUIAppleBackend, rootID: Int) {
        self.backend = backend
        self.rootID = rootID
    }

    public var body: some View {
        rootContent
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
    }

    private var rootContent: some View {
        LUIAnyNodeView(nodeID: rootID, backend: backend)
            .sheet(item: sheetBinding, onDismiss: didDismissSheet) { presentation in
                LUIModalSurfaceContent(model: presentation.model, backend: backend)
                    .modifier(LUIModalPresentationStyle(kind: presentation.model.kind))
            }
            .modifier(LUIDialogPresentationModifier(anchorID: rootID, backend: backend))
    }

    private var sheetBinding: Binding<LUIModalPresentation?> {
        Binding(
            get: {
                guard let item = backend.modalPresentation.item,
                      item.rootID == rootID,
                      item.model.kind == .sheet else { return nil }
                return item
            },
            set: { backend.modalPresentation.updateFromPresentation($0) }
        )
    }

    private func didDismissSheet() {
        guard let nodeID = backend.modalPresentation.consumeInteractiveDismissal() else {
            return
        }
        try? backend.performDismiss(node: nodeID)
    }
}

/// Hosts modal presentations (dialogs and sheets) for a traversal root on an
/// arbitrary view. Use this when the app's structure mounts several
/// `LUISwiftUIRoot`s under one backend root (e.g. a sectioned gallery where
/// each detail page is a separate root): modals anchor to the traversal root,
/// so a detail root's own `LUISwiftUIRoot` can never present them.
public struct LUIModalHostModifier: ViewModifier {
    private let rootID: Int
    private let backend: LUIAppleBackend

    public init(rootID: Int, backend: LUIAppleBackend) {
        self.rootID = rootID
        self.backend = backend
    }

    public func body(content: Content) -> some View {
        content
            .sheet(item: sheetBinding, onDismiss: didDismissSheet) { presentation in
                LUIModalSurfaceContent(model: presentation.model, backend: backend)
                    .modifier(LUIModalPresentationStyle(kind: presentation.model.kind))
            }
            .modifier(LUIDialogPresentationModifier(anchorID: rootID, backend: backend))
    }

    private var sheetBinding: Binding<LUIModalPresentation?> {
        Binding(
            get: {
                guard let item = backend.modalPresentation.item,
                      item.rootID == rootID,
                      item.model.kind == .sheet else { return nil }
                return item
            },
            set: { backend.modalPresentation.updateFromPresentation($0) }
        )
    }

    private func didDismissSheet() {
        guard let nodeID = backend.modalPresentation.consumeInteractiveDismissal() else {
            return
        }
        try? backend.performDismiss(node: nodeID)
    }
}

private struct LUIDialogPresentationModifier: ViewModifier {
    let anchorID: Int
    let backend: LUIAppleBackend

    func body(content: Content) -> some View {
        content
            .alert(dialogTitle, isPresented: dialogBinding(for: .alert)) {
                if let presentation = dialogPresentation {
                    LUIDialogActions(presentation: presentation, backend: backend)
                }
            } message: {
                if let presentation = dialogPresentation {
                    Text(verbatim: LUIDialogContentPolicy.message(
                        dialog: presentation.model,
                        backend: backend
                    ))
                }
            }
            .confirmationDialog(
                dialogTitle,
                isPresented: dialogBinding(for: .confirmationDialog),
                titleVisibility: .visible
            ) {
                if let presentation = dialogPresentation {
                    LUIDialogActions(presentation: presentation, backend: backend)
                }
            } message: {
                if let presentation = dialogPresentation {
                    Text(verbatim: LUIDialogContentPolicy.message(
                        dialog: presentation.model,
                        backend: backend
                    ))
                }
            }
    }

    private var dialogPresentation: LUIModalPresentation? {
        guard let item = backend.modalPresentation.item,
              item.anchorID == anchorID,
              item.model.kind == .dialog else { return nil }
        return item
    }

    private var dialogTitle: String {
        dialogPresentation?.model.text ?? ""
    }

    private func dialogBinding(for style: LUIDialogPresentationStyle) -> Binding<Bool> {
        Binding(
            get: {
                guard let presentation = dialogPresentation else { return false }
                return LUIDialogContentPolicy.presentationStyle(
                    styleClass: presentation.model.property(.styleClass)?.stringValue
                ) == style
            },
            set: { isPresented in
                guard !isPresented,
                      let nodeID = backend.modalPresentation.dismissDialogFromPresentation()
                else { return }
                try? backend.performDismiss(node: nodeID)
            }
        )
    }
}

enum LUIDialogPresentationStyle: Equatable {
    case alert
    case confirmationDialog
}

@MainActor
enum LUIDialogContentPolicy {
    static func presentationStyle(styleClass: String?) -> LUIDialogPresentationStyle {
        guard let styleClass else { return .alert }
        let tokens = styleClass.split(separator: " ")
        if tokens.contains("confirmation-dialog") || tokens.contains("action-sheet") {
            return .confirmationDialog
        }
        return .alert
    }

    static func actionIDs(dialog: LUINodeModel, backend: LUIAppleBackend) -> [Int] {
        descendants(of: dialog, backend: backend) { $0.kind == .button }
            .map(\.id)
    }

    static func nonCancelActionIDs(
        dialog: LUINodeModel,
        backend: LUIAppleBackend
    ) -> [Int] {
        actionIDs(dialog: dialog, backend: backend).filter { actionID in
            guard let action = backend.model(id: actionID) else { return false }
            return role(for: action) != .cancel
        }
    }

    static func cancelActionID(
        dialog: LUINodeModel,
        backend: LUIAppleBackend
    ) -> Int? {
        actionIDs(dialog: dialog, backend: backend).first { actionID in
            guard let action = backend.model(id: actionID) else { return false }
            return role(for: action) == .cancel
        }
    }

    static func message(dialog: LUINodeModel, backend: LUIAppleBackend) -> String {
        descendants(of: dialog, backend: backend) { $0.kind == .text }
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func role(for action: LUINodeModel) -> ButtonRole? {
        if action.text.localizedCaseInsensitiveCompare("Cancel") == .orderedSame {
            return .cancel
        }
        if action.buttonVariant == "destructive" ||
            ["Confirm", "Delete"].contains(where: {
                action.text.localizedCaseInsensitiveCompare($0) == .orderedSame
            }) {
            return .destructive
        }
        return nil
    }

    private static func descendants(
        of root: LUINodeModel,
        backend: LUIAppleBackend,
        matching predicate: (LUINodeModel) -> Bool
    ) -> [LUINodeModel] {
        root.children.flatMap { childID -> [LUINodeModel] in
            guard let child = backend.model(id: childID) else { return [] }
            return (predicate(child) ? [child] : []) + descendants(
                of: child,
                backend: backend,
                matching: predicate
            )
        }
    }
}

private struct LUIDialogActions: View {
    let presentation: LUIModalPresentation
    let backend: LUIAppleBackend

    var body: some View {
        ForEach(
            LUIDialogContentPolicy.nonCancelActionIDs(
                dialog: presentation.model,
                backend: backend
            ),
            id: \.self
        ) { actionID in
            actionButton(actionID)
        }
        if let cancelActionID = LUIDialogContentPolicy.cancelActionID(
            dialog: presentation.model,
            backend: backend
        ) {
            actionButton(cancelActionID)
        }
    }

    @ViewBuilder
    private func actionButton(_ actionID: Int) -> some View {
        if let action = backend.model(id: actionID) {
            Button(action.text, role: LUIDialogContentPolicy.role(for: action)) {
                backend.modalPresentation.beginDialogAction(presentation.id)
                try? backend.performPress(node: actionID)
            }
            .buttonStyle(.plain)
            .disabled(!action.isEnabled)
            .accessibilityIdentifier(
                action.property(.accessibilityIdentifier)?.stringValue ?? ""
            )
        }
    }
}

struct LUIRetainedNodeSnapshot: Equatable {
    let nodeID: Int
    let revision: Int
}

enum LUIDirectRevisionObservationPolicy {
    static func requiresRevision(_ kind: LUINodeKind) -> Bool {
        switch kind {
        case .avatar, .image, .mediaSurface:
            true
        default:
            false
        }
    }
}

enum LUIUnmodifiedNodePolicy {
    static func bypassesSurface(kind: LUINodeKind) -> Bool {
        kind == .spacer
    }
}

struct LUIAnyNodeView: View, Equatable {
    let nodeID: Int
    let backend: LUIAppleBackend
    private let retainedSnapshot: LUIRetainedNodeSnapshot

    init(nodeID: Int, backend: LUIAppleBackend) {
        self.nodeID = nodeID
        self.backend = backend
        retainedSnapshot = LUIRetainedNodeSnapshot(
            nodeID: nodeID,
            revision: backend.model(id: nodeID)?.revision
                ?? backend.extensionModel(id: nodeID)?.revision
                ?? -1
        )
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.backend === rhs.backend && lhs.retainedSnapshot == rhs.retainedSnapshot
    }

    @ViewBuilder
    var body: some View {
        if let model = backend.model(id: nodeID) {
            LUINodeView(model: model, backend: backend)
        } else if let model = backend.extensionModel(id: nodeID) {
            LUIExtensionNodeView(model: model, backend: backend)
        }
    }
}

private struct LUIExtensionNodeView: View {
    let model: LUIExtensionNodeModel
    let backend: LUIAppleBackend

    var body: some View {
        let _ = model.revision
        backend.extensionView(nodeID: model.id)
    }
}

private struct LUINodeView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Environment(\.luiTreeContext) private var treeContext

    @ViewBuilder
    var body: some View {
        let _ = LUIDirectRevisionObservationPolicy.requiresRevision(model.kind)
            ? model.revision
            : 0
        Group {
            if model.kind == .root || model.kind == .drawer ||
                LUIUnmodifiedNodePolicy.bypassesSurface(kind: model.kind) {
                content
            } else if model.kind.isModalSurface {
                content
            } else if model.kind == .resizable {
                content
            } else {
                content
                    .modifier(
                        LUISurfaceModifier(model: model)
                    )
                    .modifier(LUIAccessibilityModifier(model: model, backend: backend))
                    .modifier(LUIAppearModifier(model: model, backend: backend))
            }
        }
        .modifier(
            LUITreeItemModifier(
                model: model,
                backend: backend,
                context: treeContext
            )
        )
        .modifier(LUIContextMenuModifier(model: model, backend: backend))
        .modifier(LUIRetainedPaneModifier(model: model))
    }

    // Each wire node has a stable ID and one concrete control kind. Erase only
    // this dynamic dispatch boundary, rather than building a giant conditional type.
    private var content: AnyView {
        switch model.kind {
        case .root:
            guard let childID = model.children.first else { return AnyView(EmptyView()) }
            return AnyView(LUIAnyNodeView(nodeID: childID, backend: backend))
        case .row:
            return AnyView(LUIRowView(model: model, backend: backend))
        case .tabs, .buttonGroup, .toggleGroup, .breadcrumb, .pagination:
            return AnyView(LUIHorizontalGroupView(model: model, backend: backend))
        case .bottomTabs:
            return AnyView(LUIBottomTabsView(model: model, backend: backend))
        case .bottomTab:
            return AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    children
                }
            )
        case .list:
            return AnyView(LUIListView(model: model, backend: backend)
                .modifier(LUIDialogPresentationModifier(anchorID: model.id, backend: backend)))
        case .column:
            return AnyView(LUIColumnView(model: model, backend: backend))
        case .virtualList:
            return AnyView(LUIVirtualListView(model: model, backend: backend))
        case .grid:
            return AnyView(LUIGridView(model: model, backend: backend))
        case .stack:
            return AnyView(LUIStackView(model: model, backend: backend))
        case .panel, .card:
            return AnyView(
                ZStack {
                    children
                }
            )
        case .alert:
            return AnyView(LUIAlertView(model: model, backend: backend))
        case .bubble:
            return AnyView(LUIBubbleView(model: model, backend: backend))
        case .box:
            return AnyView(
                VStack(
                    alignment: .leading,
                    spacing: CGFloat(model.property(.gap)?.intValue ?? 0)
            ) {
                children
            }
            )
        case .text:
            return AnyView(LUITextView(model: model, backend: backend))
        case .heading:
            return AnyView(
                Text(verbatim: model.text)
                    .font(headingFont)
                    .fontWeight(
                        LUIHeadingTypography.isBold(level: headingLevel) ? .bold : nil
                    )
                    .accessibilityAddTraits(.isHeader)
            )
        case .paragraph:
            return AnyView(
                Text(verbatim: model.text)
                    .font(.body)
            )
        case .label:
            return AnyView(
                Text(verbatim: model.text)
                    .font(.body)
            )
        case .button:
            return AnyView(LUIButtonView(model: model, backend: backend))
        case .toggleButton:
            return AnyView(LUIButtonView(model: model, backend: backend, isToggle: true))
        case .textField, .secureField, .input, .searchField, .textarea:
            return AnyView(LUITextControlView(model: model, backend: backend))
        case .select:
            return AnyView(LUISelectView(model: model, backend: backend))
        case .combobox:
            return AnyView(LUIComboboxView(model: model, backend: backend))
        case .dropdownMenu:
            return AnyView(LUIDropdownMenuView(model: model, backend: backend))
        case .contextMenu:
            return AnyView(EmptyView())
        case .tooltip:
            return AnyView(LUITooltipLabel(model: model))
        case .toast:
            return AnyView(LUIToastView(model: model, backend: backend))
        case .toolbar:
            return AnyView(LUIToolbarView(model: model, backend: backend))
        case .accordion:
            return AnyView(LUIAccordionView(model: model, backend: backend))
        case .dialog, .sheet:
            return AnyView(EmptyView())
        case .menuItem:
            return AnyView(LUIMenuItemView(model: model, backend: backend))
        case .listItem:
            return AnyView(LUIListItemView(model: model, backend: backend))
        case .table:
            return AnyView(LUITableView(model: model, backend: backend))
        case .tree:
            return AnyView(LUITreeView(model: model, backend: backend))
        case .resizable:
            return AnyView(LUIResizableView(model: model, backend: backend))
        case .split:
            return AnyView(LUISplitView(model: model, backend: backend))
        case .drawer:
            return AnyView(LUIDrawerView(model: model, backend: backend))
        case .tableRow:
            return AnyView(LUITableRowView(model: model, backend: backend, isLast: true))
        case .tableCell:
            return AnyView(LUITableCellView(model: model, backend: backend))
        case .avatar:
            return AnyView(LUIAvatarView(model: model, backend: backend))
        case .image:
            return AnyView(LUIImageView(model: model, backend: backend))
        case .mediaSurface:
            return AnyView(LUIMediaSurfaceView(model: model, backend: backend))
        case .stepper:
            return AnyView(LUIStepperView(model: model, backend: backend))
        case .step:
            return AnyView(Text(verbatim: model.text))
        case .timeline:
            return AnyView(LUITimelineView(model: model, backend: backend))
        case .timelineItem:
            return AnyView(LUITimelineItemView(model: model, backend: backend))
        case .inputGroup:
            return AnyView(LUIInputGroupView(model: model, backend: backend))
        case .inputGroupActions:
            return AnyView(LUIInputGroupActionsView(model: model, backend: backend))
        case .checkbox:
            return AnyView(LUICheckboxView(model: model, backend: backend))
        case .switchControl, .toggle:
            return AnyView(LUIBinaryToggleView(model: model, backend: backend))
        case .radioGroup:
            return AnyView(LUIRadioGroupView(model: model, backend: backend))
        case .radio:
            return AnyView(
                Button {
                    try? backend.performChange(node: model.id)
                } label: {
                    Label(model.text, systemImage: model.isChecked ? "circle.inset.filled" : "circle")
                }
                .buttonStyle(.plain)
                .disabled(!model.isEnabled)
                .frame(minHeight: minimumTouchHeight)
                .accessibilityAddTraits(model.isChecked ? .isSelected : [])
            )
        case .slider:
            return AnyView(
                Slider(
                    value: Binding(
                        get: { min(max(model.sliderValue, 0), 1) },
                        set: { try? backend.performValueChange(node: model.id, value: $0) }
                    ),
                    in: 0...1
            )
            .disabled(!model.isEnabled)
            .frame(minHeight: minimumTouchHeight)
            )
        case .progress:
            return AnyView(
                ProgressView(value: model.progressFraction)
                    .accessibilityValue(Text(progressAccessibilityValue))
            )
        case .divider:
            return AnyView(LUISeparatorView(model: model))
        case .scroll:
            return AnyView(
                ScrollView {
                    LUIVerticalScrollContent(model: model, backend: backend)
                        .environment(\.luiInsideScroll, true)
                }
            )
        case .spacer:
            return AnyView(Spacer())
        case .spinner:
            #if !SKIP
            return AnyView(
                LUIActivitySpinnerView(style: model.spinnerStyle)
                    .frame(
                        width: CGFloat(model.spinnerWidth),
                        height: CGFloat(model.spinnerHeight)
                    )
            )
            #else
            return AnyView(
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(model.spinnerControlSize)
                    .frame(
                        width: CGFloat(model.spinnerWidth),
                        height: CGFloat(model.spinnerHeight)
                    )
            )
            #endif
        case .icon:
            return AnyView(
                LUIIconImage(
                    source: backend.iconSource(for: model.iconName),
                    bundle: backend.appIconBundle
            )
                .scaledToFit()
                .frame(
                    width: CGFloat(model.iconWidth),
                    height: CGFloat(model.iconHeight)
                )
            )
        case .statusBar:
            return AnyView(
                Text(verbatim: model.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(messageTextAlignment)
                    .frame(maxWidth: .infinity, alignment: messageFrameAlignment)
            )
        }
    }

    @ViewBuilder
    private var children: some View {
        ForEach(visibleChildren, id: \.self) { childID in
            LUIAnyNodeView(nodeID: childID, backend: backend)
                .equatable()
        }
    }

    private var visibleChildren: [Int] {
        model.children.filter { backend.model(id: $0)?.kind != .contextMenu }
    }

    private var headingFont: Font {
        switch headingLevel {
        case 1: .largeTitle
        case 2: .title
        case 3: .title2
        case 4: .title3
        case 5: .headline
        default: .subheadline
        }
    }

    private var headingLevel: Int {
        model.property(.headingLevel)?.intValue ?? 1
    }

    private var progressAccessibilityValue: String {
        "\(Int((model.progressFraction * 100).rounded()))%"
    }

    private var minimumTouchHeight: CGFloat? {
        #if os(iOS)
        44
        #else
        nil
        #endif
    }

    private var messageTextAlignment: TextAlignment {
        switch model.property(.textAlignment)?.stringValue {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }

    private var messageFrameAlignment: Alignment {
        switch model.property(.textAlignment)?.stringValue {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }
}

private struct LUIBottomTabsView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    private var destinations: [LUINodeModel] {
        model.children.compactMap { backend.model(id: $0) }
    }

    private var selection: Binding<Int> {
        Binding(
            get: {
                destinations.first(where: \.isSelected)?.id ?? destinations.first?.id ?? 0
            },
            set: { nodeID in
                guard let destination = backend.model(id: nodeID),
                      destination.isEnabled, destination.supportsPress else { return }
                try? backend.performPress(node: nodeID)
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(destinations, id: \.id) { destination in
                LUIAnyNodeView(nodeID: destination.id, backend: backend)
                    .tag(destination.id)
                    .tabItem {
                        Label {
                            Text(verbatim: destination.bottomTabTitle)
                        } icon: {
                            Image(systemName: destination.bottomTabSystemIconName)
                        }
                    }
            }
        }
        .accessibilityLabel(model.accessibilityLabel(in: backend) ?? "")
    }
}

private struct LUIRetainedPaneModifier: ViewModifier {
    let model: LUINodeModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRetainedPane {
            content
                .opacity(model.isSelected ? 1.0 : 0.0)
                .allowsHitTesting(model.isSelected)
                .accessibilityHidden(!model.isSelected)
        } else {
            content
        }
    }

    private var isRetainedPane: Bool {
        model.property(.styleClass)?.stringValue?
            .split(separator: " ")
            .contains("retained-pane") == true
    }
}

private struct LUIBinaryToggleView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Environment(\.luiIsNativeFormRow) private var isNativeFormRow

    @ViewBuilder var body: some View {
        if LUIBinaryControlLayoutPolicy.usesAccentTint(
            isNativeFormRow: isNativeFormRow
        ) {
            toggle.tint(.accentColor)
        } else {
            toggle.tint(nil)
        }
    }

    private var toggle: some View {
        Toggle(model.text, isOn: toggleBinding)
            .disabled(!model.isEnabled)
            .frame(minHeight: minimumTouchHeight)
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { model.isChecked },
            set: { try? backend.performToggle(node: model.id, checked: $0) }
        )
    }

    private var minimumTouchHeight: CGFloat? {
        #if os(iOS)
        LUIBinaryControlLayoutPolicy.minimumTouchHeight(
            isIOS: true,
            isNativeFormRow: isNativeFormRow
        ).map { CGFloat($0) }
        #else
        LUIBinaryControlLayoutPolicy.minimumTouchHeight(
            isIOS: false,
            isNativeFormRow: isNativeFormRow
        ).map { CGFloat($0) }
        #endif
    }
}

private struct LUIAlertView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.text.isEmpty {
                Text(verbatim: model.text)
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.children, id: \.self) { childID in
                    LUIAnyNodeView(nodeID: childID, backend: backend)
                }
            }
        }
        .fixedSize(
            horizontal: false,
            vertical: LUIVerticalContainerPolicy.usesIntrinsicHeight(kind: model.kind)
        )
    }
}

private struct LUIBubbleView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        LUIBubbleWidthLayout(isCapped: isCapped) {
            ZStack(alignment: reactionAlignment) {
                ZStack {
                    ForEach(model.children, id: \.self) { childID in
                        LUIAnyNodeView(nodeID: childID, backend: backend)
                    }
                }
                if !model.text.isEmpty {
                    Text(verbatim: model.text)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().stroke(.separator, lineWidth: 1) }
                }
            }
        }
    }

    private var isCapped: Bool {
        model.property(.variant)?.stringValue != "ghost" && model.surfaceWidth == nil
    }

    private var reactionAlignment: Alignment {
        switch model.property(.textAlignment)?.stringValue {
        case "start": .bottomLeading
        case "center": .bottom
        default: .bottomTrailing
        }
    }
}

private struct LUIBubbleWidthLayout: Layout {
    let isCapped: Bool

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let maximum = isCapped ? proposal.width.map { $0 * 0.8 } : proposal.width
        let size = subview.sizeThatFits(
            ProposedViewSize(width: maximum, height: proposal.height)
        )
        return CGSize(
            width: maximum.map { min(size.width, $0) } ?? size.width,
            height: size.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

private struct LUIContextMenuModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    func body(content: Content) -> some View {
        if let menu = model.children.compactMap({ backend.model(id: $0) })
            .first(where: { $0.kind == .contextMenu }),
           menu.children.contains(where: { backend.model(id: $0)?.kind == .menuItem }) {
            content.contextMenu {
                LUIContextMenuActions(model: menu, backend: backend)
            }
        } else {
            content
        }
    }
}

private struct LUIContextMenuActions: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        ForEach(model.children, id: \.self) { childID in
            if let child = backend.model(id: childID) {
                if child.kind == .divider {
                    Divider()
                } else if child.kind == .menuItem {
                    Button(role: child.buttonVariant == "destructive" ? .destructive : nil) {
                        try? backend.performPress(node: child.id)
                    } label: {
                        Label {
                            Text(verbatim: child.text)
                                .modifier(LUIMenuItemForegroundModifier(
                                    model: child,
                                    usesExplicitForeground: false
                                ))
                        } icon: {
                            if !child.buttonIconName.isEmpty {
                                LUIIconImage(
                                    source: backend.iconSource(for: child.buttonIconName),
                                    bundle: backend.appIconBundle
                                )
                                .modifier(LUIMenuItemForegroundModifier(model: child))
                            }
                        }
                    }
                    .disabled(!child.isEnabled)
                    .accessibilityIdentifier(
                        child.property(.accessibilityIdentifier)?.stringValue ?? ""
                    )
                }
            }
        }
    }
}

private struct LUITreeContext: @unchecked Sendable {
    let treeID: Int
    let focus: FocusState<Int?>.Binding
}

private struct LUITreeContextKey: EnvironmentKey {
    static let defaultValue: LUITreeContext? = nil
}

private struct LUIIsNativeFormRowKey: EnvironmentKey {
    static let defaultValue = false
}

private struct LUIIsNativeListRowKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var luiTreeContext: LUITreeContext? {
        get { self[LUITreeContextKey.self] }
        set { self[LUITreeContextKey.self] = newValue }
    }


    var luiIsNativeFormRow: Bool {
        get { self[LUIIsNativeFormRowKey.self] }
        set { self[LUIIsNativeFormRowKey.self] = newValue }
    }

    var luiIsNativeListRow: Bool {
        get { self[LUIIsNativeListRowKey.self] }
        set { self[LUIIsNativeListRowKey.self] = newValue }
    }
}

private struct LUITreeView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @FocusState private var focusedNode: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(model.property(.gap)?.intValue ?? 0)) {
            ForEach(model.children, id: \.self) { childID in
                if let child = backend.model(id: childID) {
                    LUINodeView(model: child, backend: backend)
                }
            }
        }
        .environment(
            \.luiTreeContext,
            LUITreeContext(treeID: model.id, focus: $focusedNode)
        )
        .accessibilityElement(children: .contain)
        .onAppear {
            guard focusedNode == nil,
                  let items = try? backend.treeItemIDs(tree: model.id) else { return }
            let enabled = items.filter { backend.model(id: $0)?.isEnabled == true }
            focusedNode = enabled.first { backend.model(id: $0)?.isSelected == true }
                ?? enabled.first
        }
    }
}

private struct LUITreeItemModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let context: LUITreeContext?

    @ViewBuilder
    func body(content: Content) -> some View {
        if model.isTreeItem, let context {
            content
                .focusable(model.isEnabled)
                .focused(context.focus, equals: model.id)
                .onKeyPress(.upArrow) { handle(.up, context: context) }
                .onKeyPress(.downArrow) { handle(.down, context: context) }
                .onKeyPress(.leftArrow) { handle(.left, context: context) }
                .onKeyPress(.rightArrow) { handle(.right, context: context) }
                .accessibilityAddTraits(model.isSelected ? .isSelected : [])
                .accessibilityValue(Text(accessibilityValue))
        } else {
            content
        }
    }

    private var accessibilityValue: String {
        switch model.isExpanded {
        case true: "expanded"
        case false: "collapsed"
        case nil: ""
        }
    }

    private func handle(_ key: LUITreeKey, context: LUITreeContext) -> KeyPress.Result {
        guard let target = try? backend.performTreeKey(
            tree: context.treeID,
            node: model.id,
            key: key
        ) else { return .ignored }
        context.focus.wrappedValue = target
        return .handled
    }
}

private struct LUIAccordionView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { model.isSelected },
                set: { try? backend.performToggle(node: model.id, checked: $0) }
            )
        ) {
            ForEach(model.children, id: \.self) { childID in
                LUIAnyNodeView(nodeID: childID, backend: backend)
            }
        } label: {
            Text(verbatim: model.text)
        }
        .disabled(!model.supportsToggle)
    }
}

private struct LUITableView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(model.children, id: \.self) { rowID in
                if let row = backend.model(id: rowID) {
                    LUITableRowView(
                        model: row,
                        backend: backend,
                        isLast: rowID == model.children.last
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LUITableRowView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let isLast: Bool

    var body: some View {
        GridRow {
            ForEach(model.children, id: \.self) { cellID in
                if let cell = backend.model(id: cellID) {
                    LUINodeView(model: cell, backend: backend)
                        .padding(.horizontal, CGFloat(model.property(.gap)?.intValue ?? 0) / 2)
                }
            }
        }
        .background(model.isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(model.isSelected ? .isSelected : [])
    }
}

private struct LUITableCellView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        Group {
            if model.supportsPress {
                Button {
                    try? backend.performPress(node: model.id)
                } label: {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label
            }
        }
        .frame(maxWidth: cellMaxWidth, alignment: frameAlignment)
    }

    private var label: some View {
        Text(verbatim: model.text)
            .font(font)
            .multilineTextAlignment(textAlignment)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .contentShape(Rectangle())
            .padding(.vertical, 10)
    }

    private var cellMaxWidth: CGFloat? {
        (model.property(.grow)?.doubleValue ?? 0) > 0 ? .infinity : nil
    }

    private var frameAlignment: Alignment {
        switch model.property(.textAlignment)?.stringValue {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }

    private var textAlignment: TextAlignment {
        switch model.property(.textAlignment)?.stringValue {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }

    private var font: Font {
        switch model.property(.size)?.stringValue {
        case "sm": .caption
        case "lg": .title3
        case "heading": .title
        case "display": .largeTitle
        default: .body
        }
    }
}

private struct LUIStackView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if hasComboboxTrigger {
            LUIAnchoredComboboxMenuHost(model: anchoredMenu, backend: backend) {
                triggerContent(excludingMenu: anchoredMenu?.id)
            }
        } else if hasSelectTrigger || anchoredMenu != nil {
            LUIAnchoredMenuHost(model: anchoredMenu, backend: backend) {
                triggerContent(excludingMenu: anchoredMenu?.id)
            }
        } else {
            triggerContent(excludingMenu: nil)
        }
    }

    private var anchoredMenu: LUINodeModel? {
        model.children
            .compactMap(backend.model)
            .first { $0.kind == .dropdownMenu && $0.property(.anchor) != nil }
    }

    private var anchoredTooltip: LUINodeModel? {
        model.children
            .compactMap(backend.model)
            .first { $0.kind == .tooltip && $0.property(.anchor) != nil }
    }

    private var hasComboboxTrigger: Bool {
        model.children
            .compactMap(backend.model)
            .contains { $0.kind == .combobox }
    }

    private var hasSelectTrigger: Bool {
        model.children
            .compactMap(backend.model)
            .contains { $0.kind == .select }
    }

    @ViewBuilder
    private func triggerContent(excludingMenu menuID: Int?) -> some View {
        if let tooltip = anchoredTooltip {
            LUITooltipHost(model: tooltip, session: backend.tooltipSession) {
                stackChildren(excluding: [menuID, tooltip.id].compactMap { $0 })
            }
        } else {
            stackChildren(excluding: menuID.map { [$0] } ?? [])
        }
    }

    private func stackChildren(excluding excludedIDs: [Int]) -> some View {
        ZStack {
            ForEach(model.children.filter { !excludedIDs.contains($0) }, id: \.self) { childID in
                LUIAnyNodeView(nodeID: childID, backend: backend)
            }
        }
    }
}

private struct LUIAnchoredComboboxMenuHost<Content: View>: View {
    let model: LUINodeModel?
    let backend: LUIAppleBackend
    let content: Content

    init(
        model: LUINodeModel?,
        backend: LUIAppleBackend,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.backend = backend
        self.content = content()
    }

    var body: some View {
        LUIAnchoredComboboxMenuLayout(
            anchor: model?.property(.anchor)?.stringValue ?? "below",
            alignment: model?.property(.anchorAlignment)?.stringValue ?? "start",
            offset: CGFloat(model?.property(.anchorOffset)?.doubleValue ?? 0)
        ) {
            content
            if let model {
                LUIDropdownMenuView(model: model, backend: backend)
                    .zIndex(1)
            }
        }
        .zIndex(model == nil ? 0 : 1)
    }
}

private struct LUIAnchoredComboboxMenuLayout: Layout {
    let anchor: String
    let alignment: String
    let offset: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let trigger = subviews.first else { return }
        let triggerSize = trigger.sizeThatFits(proposal)
        trigger.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(triggerSize)
        )
        guard subviews.count == 2 else { return }

        let menu = subviews[1]
        let menuProposal = ProposedViewSize(
            width: alignment == "stretch" ? triggerSize.width : nil,
            height: nil
        )
        let menuSize = menu.sizeThatFits(menuProposal)
        menu.place(
            at: menuOrigin(
                bounds: bounds,
                triggerSize: triggerSize,
                menuSize: menuSize
            ),
            anchor: .topLeading,
            proposal: menuProposal
        )
    }

    private func menuOrigin(
        bounds: CGRect,
        triggerSize: CGSize,
        menuSize: CGSize
    ) -> CGPoint {
        switch anchor {
        case "above":
            return CGPoint(
                x: horizontalOrigin(bounds: bounds, menuWidth: menuSize.width),
                y: bounds.minY - menuSize.height - offset
            )
        case "left":
            return CGPoint(
                x: bounds.minX - menuSize.width - offset,
                y: verticalOrigin(bounds: bounds, menuHeight: menuSize.height)
            )
        case "right":
            return CGPoint(
                x: bounds.minX + triggerSize.width + offset,
                y: verticalOrigin(bounds: bounds, menuHeight: menuSize.height)
            )
        default:
            return CGPoint(
                x: horizontalOrigin(bounds: bounds, menuWidth: menuSize.width),
                y: bounds.minY + triggerSize.height + offset
            )
        }
    }

    private func horizontalOrigin(bounds: CGRect, menuWidth: CGFloat) -> CGFloat {
        switch alignment {
        case "center": bounds.midX - menuWidth / 2
        case "end": bounds.maxX - menuWidth
        default: bounds.minX
        }
    }

    private func verticalOrigin(bounds: CGRect, menuHeight: CGFloat) -> CGFloat {
        switch alignment {
        case "center": bounds.midY - menuHeight / 2
        case "end": bounds.maxY - menuHeight
        default: bounds.minY
        }
    }
}

private struct LUIAnchoredMenuHost<Content: View>: View {
    let model: LUINodeModel?
    let backend: LUIAppleBackend
    let content: Content

    @State private var isPresented = false

    init(
        model: LUINodeModel?,
        backend: LUIAppleBackend,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.backend = backend
        self.content = content()
    }

    var body: some View {
        content
            .popover(
                isPresented: Binding(
                    get: { isPresented },
                    set: { presented in
                        isPresented = presented
                        if !presented, let model {
                            try? backend.performDismiss(node: model.id)
                        }
                    }
                ),
                attachmentAnchor: .point(attachmentPoint),
                arrowEdge: arrowEdge
            ) {
                if let model {
                    LUIDropdownMenuView(
                        model: model,
                        backend: backend,
                        isPresented: true
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }
            .onChange(of: model?.id, initial: true) { _, menuID in
                isPresented = menuID != nil
            }
    }

    private var attachmentPoint: UnitPoint {
        let alignment = model?.property(.anchorAlignment)?.stringValue ?? "start"
        switch model?.property(.anchor)?.stringValue ?? "below" {
        case "left":
            return UnitPoint(x: 0, y: verticalAlignment(alignment))
        case "right":
            return UnitPoint(x: 1, y: verticalAlignment(alignment))
        case "above":
            return UnitPoint(x: horizontalAlignment(alignment), y: 0)
        default:
            return UnitPoint(x: horizontalAlignment(alignment), y: 1)
        }
    }

    private var arrowEdge: Edge {
        switch model?.property(.anchor)?.stringValue ?? "below" {
        case "above": .bottom
        case "left": .trailing
        case "right": .leading
        default: .top
        }
    }

    private func horizontalAlignment(_ alignment: String) -> CGFloat {
        switch alignment {
        case "center", "stretch": 0.5
        case "end": 1
        default: 0
        }
    }

    private func verticalAlignment(_ alignment: String) -> CGFloat {
        switch alignment {
        case "center", "stretch": 0.5
        case "end": 1
        default: 0
        }
    }
}

private struct LUITooltipLabel: View {
    let model: LUINodeModel

    var body: some View {
        Text(verbatim: model.text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.primary)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 4, y: 2)
    }
}

private struct LUITooltipHost<Content: View>: View {
    let model: LUINodeModel
    let session: LUITooltipSession
    let content: Content

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isFocused: Bool
    @State private var isPresented = false
    @State private var isHovered = false
    @State private var revealTask: Task<Void, Never>?
    @State private var intent: LUITooltipIntent

    init(
        model: LUINodeModel,
        session: LUITooltipSession,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.session = session
        self.content = content()
        _intent = State(initialValue: LUITooltipIntent(session: session))
    }

    var body: some View {
        let _ = model.revision
        content
            .focused($isFocused)
            .onHover(perform: hoverChanged)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .exclusively(before: TapGesture())
                    .onEnded { gesture in
                        switch gesture {
                        case .first:
                            cancelReveal()
                            intent.longPress()
                            syncPresentation()
                        case .second:
                            dismissForPress()
                        }
                    }
            )
            .onChange(of: isFocused) { _, focused in
                cancelReveal()
                if focused {
                    intent.focusEntered()
                } else {
                    intent.focusLeft()
                }
                syncPresentation()
            }
            .onChange(of: delay) {
                if isHovered { hoverChanged(true) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    cancelReveal()
                    intent.viewBlurred()
                    syncPresentation()
                }
            }
            .onKeyPress(.escape) {
                cancelReveal()
                intent.escape()
                syncPresentation()
                return .handled
            }
            .popover(
                isPresented: Binding(
                    get: { isPresented },
                    set: { presented in
                        isPresented = presented
                        if !presented { intent.escape() }
                    }
                ),
                attachmentAnchor: .point(attachmentPoint),
                arrowEdge: arrowEdge
            ) {
                LUITooltipLabel(model: model)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityHint(Text(model.text))
            .onDisappear {
                cancelReveal()
                intent.viewBlurred()
            }
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    private var delay: Double {
        Double(model.property(.tooltipDelay)?.intValue ?? 600) / 1_000
    }

    private var attachmentPoint: UnitPoint {
        switch model.property(.anchorAlignment)?.stringValue ?? "start" {
        case "end": UnitPoint(x: 1, y: anchorY)
        case "stretch": UnitPoint(x: 0.5, y: anchorY)
        default: UnitPoint(x: 0, y: anchorY)
        }
    }

    private var anchorY: CGFloat {
        model.property(.anchor)?.stringValue == "above" ? 0 : 1
    }

    private var arrowEdge: Edge {
        model.property(.anchor)?.stringValue == "above" ? .bottom : .top
    }

    private func hoverChanged(_ hovered: Bool) {
        isHovered = hovered
        cancelReveal()
        if hovered {
            let startedAt = now
            intent.pointerEntered(at: startedAt, delay: delay)
            syncPresentation()
            guard !intent.isPresented else { return }
            revealTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                intent.advance(to: startedAt + delay)
                syncPresentation()
            }
        } else {
            intent.pointerLeft(at: now)
            syncPresentation()
        }
    }

    private func dismissForPress() {
        cancelReveal()
        intent.press()
        syncPresentation()
    }

    private func cancelReveal() {
        revealTask?.cancel()
        revealTask = nil
    }

    private func syncPresentation() {
        isPresented = intent.isPresented
    }
}

private struct LUIModalPresentationStyle: ViewModifier {
    let kind: LUINodeKind

    @ViewBuilder
    func body(content: Content) -> some View {
        if LUIModalPresentationPolicy.showsDragIndicator(kind: kind) {
            content.presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

enum LUIModalPresentationPolicy {
    static func showsDragIndicator(kind: LUINodeKind) -> Bool {
        false
    }
}

private struct LUIModalSurfaceContent: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Environment(\.luiSemanticColors) private var semanticColors

    var body: some View {
        surfaceContent.sheet(item: Binding(
            get: { backend.modalPresentation.nestedSheets[model.id] },
            set: { value in
                if value == nil,
                   let dismissed = backend.modalPresentation.nestedSheets.removeValue(forKey: model.id) {
                    try? backend.performDismiss(node: dismissed.id)
                }
            }
        )) { presentation in
            LUIModalSurfaceContent(model: presentation.model, backend: backend)
                .modifier(LUIModalPresentationStyle(kind: presentation.model.kind))
        }
    }

    @ViewBuilder
    private var surfaceContent: some View {
        let _ = model.revision
        if LUINavigationFormSheetPolicy.isNavigationForm(
            model.property(.styleClass)?.stringValue
        ) || LUINavigationFormSheetPolicy.isNavigationScroll(
            model.property(.styleClass)?.stringValue
        ) || LUINavigationFormSheetPolicy.isNavigationList(
            model.property(.styleClass)?.stringValue
        ) || LUINavigationFormSheetPolicy.isNavigationContent(
            model.property(.styleClass)?.stringValue
        ) {
            NavigationStack {
                navigationContent
                .background(modalBackground)
                .navigationTitle(model.text)
                .modifier(LUINavigationFormTitleStyle(
                    styleClass: model.property(.styleClass)?.stringValue
                ))
                .toolbar {
                    LUINavigationFormToolbar(
                        toolbarID: navigationToolbarID,
                        backend: backend
                    )
                }
            }
            .background(modalBackground.ignoresSafeArea())
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: model.text)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ZStack {
                    ForEach(model.children, id: \.self) { childID in
                        LUIAnyNodeView(nodeID: childID, backend: backend)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(CGFloat(model.property(.padding)?.intValue ?? 24))
            .frame(width: surfaceWidth, height: surfaceHeight)
        }
    }

    private var modalBackground: Color {
        if LUIModalBackgroundPolicy.usesGroupedSystemBackground(
            styleClass: model.property(.styleClass)?.stringValue
        ) {
            return modalGroupedSystemBackground
        }
        return LUIModalBackgroundPolicy.color(
            semanticColors: semanticColors,
            systemBackground: modalSystemBackground
        )
    }

    private var modalGroupedSystemBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }

    private var modalSystemBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }

    private var navigationFormContentID: Int? {
        model.children.first { backend.model(id: $0)?.kind != .toolbar }
    }

    private var navigationToolbarID: Int? {
        model.children.first { backend.model(id: $0)?.kind == .toolbar }
    }

    @ViewBuilder
    private var navigationContent: some View {
        if LUINavigationFormSheetPolicy.isNavigationScroll(
            model.property(.styleClass)?.stringValue
        ) {
            ScrollView {
                if let contentID = navigationFormContentID {
                    LUIAnyNodeView(nodeID: contentID, backend: backend)
                }
            }
            .accessibilityIdentifier(navigationFormAccessibilityIdentifier)
        } else if LUINavigationFormSheetPolicy.isNavigationList(
            model.property(.styleClass)?.stringValue
        ) || LUINavigationFormSheetPolicy.isNavigationContent(
            model.property(.styleClass)?.stringValue
        ) {
            if let contentID = navigationFormContentID {
                LUIAnyNodeView(nodeID: contentID, backend: backend)
            }
        } else {
            Form {
                LUINavigationFormRows(
                    contentID: navigationFormContentID,
                    backend: backend
                )
            }
            .accessibilityIdentifier(navigationFormAccessibilityIdentifier)
        }
    }

    private var navigationFormAccessibilityIdentifier: String {
        guard let contentID = navigationFormContentID,
              let content = backend.model(id: contentID) else {
            return ""
        }
        return content.property(.accessibilityIdentifier)?.stringValue ?? ""
    }

    private var surfaceWidth: CGFloat? {
        switch model.kind {
        case .dialog:
            CGFloat(model.property(.width)?.intValue ?? 420)
        case .sheet:
            model.property(.width).map { CGFloat($0.intValue ?? 0) }
        default:
            nil
        }
    }

    private var surfaceHeight: CGFloat? {
        switch model.kind {
        case .dialog:
            CGFloat(model.property(.height)?.intValue ?? 220)
        case .sheet:
            model.property(.height).map { CGFloat($0.intValue ?? 0) }
        default:
            nil
        }
    }
}

private struct LUINavigationFormRows: View {
    let contentID: Int?
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if let contentID, let content = backend.model(id: contentID) {
            if LUINavigationFormSheetPolicy.isForm(
                content.property(.styleClass)?.stringValue
            ) {
                ForEach(sections(for: content)) { section in
                    if let headerID = section.headerID,
                       let header = backend.model(id: headerID),
                       let footerID = section.footerID,
                       let footer = backend.model(id: footerID) {
                        Section {
                            rows(section.childIDs)
                        } header: {
                            Text(verbatim: header.text)
                        } footer: {
                            Text(verbatim: footer.text)
                        }
                    } else if let headerID = section.headerID,
                              let header = backend.model(id: headerID) {
                        Section {
                            rows(section.childIDs)
                        } header: {
                            Text(verbatim: header.text)
                        }
                    } else if let footerID = section.footerID,
                              let footer = backend.model(id: footerID) {
                        Section {
                            rows(section.childIDs)
                        } footer: {
                            Text(verbatim: footer.text)
                        }
                    } else {
                        Section {
                            rows(section.childIDs)
                        }
                    }
                }
            } else {
                LUIAnyNodeView(nodeID: contentID, backend: backend)
            }
        }
    }

    @ViewBuilder
    private func rows(_ childIDs: [Int]) -> some View {
        ForEach(childIDs, id: \.self) { childID in
            if let child = backend.model(id: childID), child.kind == .listItem {
                LUIListItemView(model: child, backend: backend, isNativeListRow: true)
                    .environment(\.luiIsNativeFormRow, true)
            } else {
                LUIAnyNodeView(nodeID: childID, backend: backend)
                    .environment(\.luiIsNativeFormRow, true)
            }
        }
    }

    private func sections(for content: LUINodeModel) -> [LUIListSection] {
        LUIListSectionPolicy.sections(
            childIDs: content.children,
            isHeading: { childID in
                backend.model(id: childID)?.kind == .heading
            },
            isFooter: { _ in false }
        ).map { section in
            let headerText = section.headerID.flatMap { backend.model(id: $0)?.text }
            return LUIListSection(
                headerID: LUINavigationFormSectionPolicy.visibleHeaderID(
                    section.headerID,
                    text: headerText
                ),
                childIDs: section.childIDs,
                footerID: section.footerID
            )
        }
    }
}

enum LUINavigationFormSectionPolicy {
    static func visibleHeaderID(_ headerID: Int?, text: String?) -> Int? {
        text?.isEmpty == true ? nil : headerID
    }
}

private struct LUINavigationFormToolbar: ToolbarContent {
    let toolbarID: Int?
    let backend: LUIAppleBackend

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if let cancellationActionID {
            ToolbarItem(placement: .cancellationAction) {
                actionView(cancellationActionID)
            }
        }
        if let confirmationActionID {
            ToolbarItem(placement: .confirmationAction) {
                actionView(confirmationActionID)
            }
        }
    }

    private var cancellationActionID: Int? {
        actionID(for: .cancellation)
    }

    private var confirmationActionID: Int? {
        actionID(for: .confirmation)
    }

    @ViewBuilder
    private func actionView(_ actionID: Int) -> some View {
        if let model = backend.model(id: actionID) {
            LUINavigationFormActionView(model: model, backend: backend)
        }
    }

    private func actionID(for placement: LUINavigationFormActionPlacement) -> Int? {
        guard let toolbarID, let toolbar = backend.model(id: toolbarID) else { return nil }
        return toolbar.children.first { childID in
            guard let child = backend.model(id: childID) else { return false }
            return LUINavigationFormSheetPolicy.actionPlacement(
                child.property(.styleClass)?.stringValue
            ) == placement
        }
    }
}

private extension LUINodeKind {
    var isModalSurface: Bool {
        self == .dialog || self == .sheet
    }
}

private struct LUIToolbarView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        let layout = LUIToolbarLayoutPolicy.layout(
            orientation: model.property(.orientation)?.stringValue,
            styleClass: model.property(.styleClass)?.stringValue,
            childIDs: model.children
        )
        if layout.axis == .vertical {
            VStack(alignment: .leading, spacing: spacing) {
                children(model.children)
            }
        } else if !layout.scrollingChildIDs.isEmpty {
            HStack(spacing: CGFloat(LUIToolbarLayoutPolicy.outerSpacing(
                hasFixedChild: layout.fixedChildID != nil,
                requested: Double(spacing)
            ))) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        children(layout.scrollingChildIDs)
                    }
                    .padding(.leading, CGFloat(LUIToolbarLayoutPolicy.leadingInset(
                        model.property(.styleClass)?.stringValue
                    )))
                }
                if let fixedChildID = layout.fixedChildID {
                    LUIAnyNodeView(nodeID: fixedChildID, backend: backend)
                }
            }
        } else {
            HStack(spacing: spacing) {
                children(model.children)
            }
        }
    }

    @ViewBuilder
    private func children(_ childIDs: [Int]) -> some View {
        ForEach(childIDs, id: \.self) { childID in
            LUIAnyNodeView(nodeID: childID, backend: backend)
        }
    }

    private var spacing: CGFloat {
        CGFloat(model.property(.gap)?.intValue ?? 0)
    }

}

private struct LUIToastView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            ForEach(model.children, id: \.self) { childID in
                LUIAnyNodeView(nodeID: childID, backend: backend)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8, y: 4)
        .offset(x: dragOffset)
        .gesture(dismissGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text(verbatim: model.property(.accessibilityLabel)?.stringValue ?? "Notification")
        )
        .task(id: model.property(.duration)?.intValue) {
            let duration = model.property(.duration)?.intValue ?? 0
            guard duration > 0 else { return }
            try? await Task.sleep(for: .milliseconds(duration))
            guard !Task.isCancelled else { return }
            try? backend.performDismiss(node: model.id)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                if abs(value.translation.width) >= 80 {
                    try? backend.performDismiss(node: model.id)
                } else {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        dragOffset = 0
                    }
                }
            }
    }
}

private struct LUIAvatarView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.16)
            if let image = model.avatarDisplayImage(in: backend) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(verbatim: model.text)
                    .font(.callout.weight(.medium))
            }
        }
        .frame(width: 40, height: 40)
        .compositingGroup()
        .clipShape(Circle())
    }
}

private struct LUIImageView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if let image = model.imageDisplayImage(in: backend) {
            Image(decorative: image, scale: 1)
                .resizable()
        } else {
            Color.clear
        }
    }
}

private struct LUIMediaSurfaceView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if let frame = model.mediaSurfaceFrame(in: backend) {
            Image(decorative: frame, scale: 1)
                .resizable()
        } else if model.mediaSurfaceID == 0 {
            Color.clear
        } else {
            let components = model.mediaSurfacePlaceholderComponents
            Color(
                red: Double(components[0]) / 255,
                green: Double(components[1]) / 255,
                blue: Double(components[2]) / 255
            )
        }
    }
}

private struct LUIStepperView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.children.enumerated()), id: \.element) { index, childID in
                if let step = backend.model(id: childID) {
                    LUIStepView(
                        model: step,
                        index: index,
                        count: model.children.count,
                        active: model.activeStepIndex
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LUIStepView: View {
    let model: LUINodeModel
    let index: Int
    let count: Int
    let active: Int

    private var state: String {
        if index < active { return "completed" }
        if index == active { return "active" }
        return "pending"
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(state == "pending" ? Color.clear : Color.accentColor)
                    .stroke(state == "pending" ? Color.secondary : Color.accentColor)
                if state == "completed" {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text(verbatim: "\(index + 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(state == "active" ? .white : .secondary)
                }
            }
            .frame(width: 24, height: 24)
            Text(verbatim: model.text)
                .fontWeight(state == "active" ? .semibold : .regular)
                .foregroundStyle(state == "pending" ? .secondary : .primary)
            if index + 1 < count {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(minWidth: 20, maxWidth: .infinity, maxHeight: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.text) (\(state))")
    }
}

private struct LUITimelineView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(model.property(.gap)?.intValue ?? 0)) {
            ForEach(model.children, id: \.self) { childID in
                if let child = backend.model(id: childID) {
                    LUINodeView(model: child, backend: backend)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LUITimelineItemView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if model.supportsPress {
            Button { try? backend.performPress(node: model.id) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                indicator
                if model.timelineConnector {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1, height: 24)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.timelineTitle).fontWeight(.semibold)
                if !model.timelineDescription.isEmpty {
                    Text(verbatim: model.timelineDescription)
                        .foregroundStyle(.secondary)
                }
                if !model.timelineMeta.isEmpty {
                    Text(verbatim: model.timelineMeta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.supportsPress {
                LUIIconImage(
                    source: backend.iconSource(for: "chevron-right"),
                    bundle: backend.appIconBundle
                )
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(model.isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.timelineTitle)
    }

    @ViewBuilder
    private var indicator: some View {
        if !model.buttonIconName.isEmpty {
            LUIIconImage(
                source: backend.iconSource(for: model.buttonIconName),
                bundle: backend.appIconBundle
            )
                .frame(width: 16, height: 16)
                .padding(4)
                .background(indicatorColor.opacity(0.16), in: Circle())
                .foregroundStyle(indicatorColor)
        } else if !model.timelineIndicator.isEmpty {
            Text(verbatim: model.timelineIndicator)
                .font(.caption2.weight(.semibold))
                .frame(width: 24, height: 24)
                .background(indicatorColor.opacity(0.16), in: Circle())
                .foregroundStyle(indicatorColor)
        } else {
            Circle().fill(indicatorColor).frame(width: 10, height: 10).padding(7)
        }
    }

    private var indicatorColor: Color {
        switch model.buttonVariant {
        case "primary": .accentColor
        case "destructive": .red
        default: .secondary
        }
    }
}

private struct LUIInputGroupView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @FocusState private var focusedChild: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entryID = model.children.first,
               let entry = backend.model(id: entryID) {
                LUITextControlView(model: entry, backend: backend, grouped: true)
                    .focused($focusedChild, equals: entryID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
            }
            if model.children.count == 2,
               let actions = backend.model(id: model.children[1]) {
                LUIInputGroupActionsView(
                    model: actions,
                    backend: backend,
                    focusedChild: $focusedChild
                )
            }
        }
        .background(systemBackground, in: shape)
        .overlay {
            shape.stroke(
                focusedChild == nil ? Color.secondary.opacity(0.35) : Color.accentColor,
                lineWidth: focusedChild == nil ? 1 : 2
            )
        }
        .clipShape(shape)
        .accessibilityElement(children: .contain)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8)
    }

    private var systemBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private struct LUIInputGroupActionsView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    var focusedChild: FocusState<Int?>.Binding?

    init(
        model: LUINodeModel,
        backend: LUIAppleBackend,
        focusedChild: FocusState<Int?>.Binding? = nil
    ) {
        self.model = model
        self.backend = backend
        self.focusedChild = focusedChild
    }

    var body: some View {
        let _ = model.revision
        HStack(spacing: CGFloat(model.property(.gap)?.intValue ?? 6)) {
            ForEach(model.children, id: \.self) { childID in
                if let child = backend.model(id: childID) {
                    if let focusedChild {
                        LUINodeView(model: child, backend: backend)
                            .focused(focusedChild, equals: childID)
                    } else {
                        LUINodeView(model: child, backend: backend)
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

enum LUISelectVisualPolicy {
    static let indicatorSystemName = "chevron.up.chevron.down"
    static let trailingInset: CGFloat = 12
    static let verticalInset: CGFloat = 8
}

private struct LUISelectView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        Button {
            try? backend.performPress(node: model.id)
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: displayText)
                Image(systemName: LUISelectVisualPolicy.indicatorSystemName)
            }
            .foregroundStyle(
                model.text.isEmpty ? Color.secondary : Color.accentColor
            )
            .padding(.trailing, LUISelectVisualPolicy.trailingInset)
            .padding(.vertical, LUISelectVisualPolicy.verticalInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.isEnabled)
        .accessibilityLabel(
            Text(verbatim: model.property(.accessibilityLabel)?.stringValue ?? displayText)
        )
    }

    private var displayText: String {
        model.text.isEmpty
            ? (model.property(.placeholder)?.stringValue ?? "")
            : model.text
    }
}

private struct LUIComboboxView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        HStack(spacing: 4) {
            TextField(
                model.property(.placeholder)?.stringValue ?? "",
                text: Binding(
                    get: { model.text },
                    set: { try? backend.performTextChange(node: model.id, text: $0) }
                )
            )
            .textFieldStyle(.plain)
            .onSubmit {
                if model.supportsSubmit {
                    try? backend.performSubmit(node: model.id)
                } else {
                    try? backend.performPress(node: model.id)
                }
            }
            Button {
                try? backend.performPress(node: model.id)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show options")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator)
        }
        .disabled(!model.isEnabled)
    }
}

private struct LUIDropdownMenuView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    var isPresented = false

    @ViewBuilder
    var body: some View {
        if isPresented {
            ScrollView {
                menuItems
            }
            .frame(maxHeight: 420)
        } else {
            menuItems
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 8, y: 4)
        }
    }

    private var menuItems: some View {
        VStack(
            alignment: .leading,
            spacing: model.property(.gap)?.intValue.map(CGFloat.init) ??
                LUIDropdownMenuLayoutPolicy.contentSpacing
        ) {
            ForEach(model.children, id: \.self) { childID in
                LUIAnyNodeView(nodeID: childID, backend: backend)
            }
        }
        .padding(LUIDropdownMenuLayoutPolicy.contentPadding)
        .frame(
            minWidth: model.surfaceMinWidth.map(CGFloat.init),
            maxWidth: model.surfaceMaxWidth.map(CGFloat.init) ?? (isStretch ? .infinity : nil),
            alignment: .leading
        )
#if os(macOS)
        .onExitCommand {
            try? backend.performDismiss(node: model.id)
        }
#endif
    }

    private var isStretch: Bool {
        model.property(.anchorAlignment)?.stringValue == "stretch"
    }
}

private struct LUIMenuItemView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if let submenu {
            Menu {
                ForEach(submenu.children, id: \.self) { childID in
                    if let child = backend.model(id: childID) {
                        if child.kind == .divider {
                            Divider()
                        } else if child.kind == .menuItem {
                            LUIMenuItemView(model: child, backend: backend)
                        }
                    }
                }
            } label: {
                itemLabel(expands: false)
            }
            .disabled(!model.isEnabled)
        } else {
            Button {
                try? backend.performPress(node: model.id)
            } label: {
                itemLabel(expands: true)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.isSelected ? .isSelected : [])
            .disabled(!model.isEnabled)
        }
    }

    private var submenu: LUINodeModel? {
        model.children
            .compactMap(backend.model)
            .first { $0.kind == .dropdownMenu }
    }

    private var menuItemIconSize: CGFloat {
        switch model.property(.size)?.stringValue {
        case "sm": 16
        case "lg": 28
        default: LUIDropdownMenuLayoutPolicy.iconSize
        }
    }

    private func itemLabel(expands: Bool) -> some View {
        HStack(spacing: LUIDropdownMenuLayoutPolicy.itemSpacing) {
            if !model.buttonIconName.isEmpty {
                LUIIconImage(
                    source: backend.iconSource(for: model.buttonIconName),
                    bundle: backend.appIconBundle
                )
                    .frame(
                        width: menuItemIconSize,
                        height: menuItemIconSize
                    )
                    .modifier(LUIMenuItemForegroundModifier(model: model))
            }
            Text(verbatim: model.text)
                .modifier(LUIMenuItemForegroundModifier(
                    model: model,
                    usesExplicitForeground: false
                ))
            if expands {
                Spacer(minLength: LUIDropdownMenuLayoutPolicy.trailingSpacing)
            }
            if model.isSelected {
                Image(systemName: "checkmark")
                    .modifier(LUIMenuItemForegroundModifier(
                        model: model,
                        usesExplicitForeground: false
                    ))
            }
        }
        .frame(
            maxWidth: expands ? .infinity : nil,
            minHeight: LUIDropdownMenuLayoutPolicy.itemMinimumHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }
}

private struct LUIMenuItemForegroundModifier: ViewModifier {
    let model: LUINodeModel
    var usesExplicitForeground = true

    @Environment(\.luiSemanticColors) private var semanticColors

    func body(content: Content) -> some View {
        content
            .foregroundStyle(resolvedColor)
            .tint(resolvedColor)
    }

    private var resolvedColor: Color {
        let destructive = model.buttonVariant == "destructive"
        let name = usesExplicitForeground
            ? LUIThemeColorPolicy.menuItemForegroundName(
                explicit: model.property(.foreground)?.stringValue,
                destructive: destructive
            )
            : LUIThemeColorPolicy.menuItemTextForegroundName(
                destructive: destructive
            )
        if let semantic = semanticColors[name.lowercased()] {
            return semantic
        }
        #if !SKIP
        if let hex = hexColor(name) {
            return hex
        }
        #endif
        return switch name.lowercased() {
        case "red", "error-foreground": .red
        case "accent": .accentColor
        case "blue": .blue
        case "green", "success-foreground": .green
        case "warning-foreground": .orange
        case "secondary", "muted-foreground": .secondary
        default: .primary
        }
    }

    #if !SKIP
    private func hexColor(_ name: String) -> Color? {
        let value = name.hasPrefix("#") ? String(name.dropFirst()) : name
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else {
            return nil
        }
        return Color(
            red: Double((rgb >> 16) & 0xff) / 255.0,
            green: Double((rgb >> 8) & 0xff) / 255.0,
            blue: Double(rgb & 0xff) / 255.0
        )
    }
    #endif
}

private struct LUIListItemView: View {
    @Environment(\.colorScheme) private var colorScheme
    let model: LUINodeModel
    let backend: LUIAppleBackend
    var isNativeListRow = false
    @State private var didLongPress = false

    var body: some View {
        Group {
            switch LUIListItemInteractionPolicy.style(
                hasInteractiveChildren: hasInteractiveChildren
            ) {
            case .button:
                Button(action: performPrimaryAction) {
                    rowContent
                }
                .buttonStyle(.plain)
            case .composite:
                rowContent
                    .contentShape(Rectangle())
                    .onTapGesture(perform: performPrimaryAction)
                    .accessibilityAction { performPrimaryAction() }
            }
        }
        .padding(.horizontal, usesSystemListInsets || hasExplicitPadding ? 0 : 12)
        .padding(.vertical, usesSystemListInsets || hasExplicitPadding ? 0 : verticalPadding)
        .frame(minHeight: LUIListItemLayoutPolicy.minimumHeight(
            isNativeListRow: isNativeListRow,
            isNavigationRow: isNavigationRow,
            isNavigationHeading: isNavigationHeading,
            explicitMinimumHeight: model.surfaceMinHeight
        ).map { CGFloat($0) })
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            model.isSelected ? selectionBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
        .id(model.isSelected)
        .modifier(
            LUIListItemSupplementaryGesturesModifier(
                model: model,
                backend: backend,
                didLongPress: $didLongPress
            )
        )
        .onKeyPress(.return) {
            guard model.supportsSubmit else { return .ignored }
            try? backend.performSubmit(node: model.id)
            return .handled
        }
        .accessibilityAddTraits(model.isSelected ? .isSelected : [])
        .disabled(!model.isEnabled)
        .modifier(LUIListItemSwipeActionsModifier(menu: contextMenu, backend: backend))
        .modifier(LUINativeListRowAccessibilityModifier(
            model: model,
            backend: backend,
            isNativeListRow: isNativeListRow
        ))
    }

    private var rowContent: some View {
        HStack(spacing: horizontalSpacing) {
            if model.isTreeItem, model.supportsToggle {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(model.isExpanded == true ? 90 : 0))
                    .animation(.snappy, value: model.isExpanded)
                    .accessibilityHidden(true)
            }
            if !model.buttonIconName.isEmpty && model.buttonIconPlacement != "trailing" {
                LUIIconImage(
                    source: backend.iconSource(for: model.buttonIconName),
                    bundle: backend.appIconBundle
                )
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .frame(width: isNativeListRow ? 24 : (isNavigationRow ? 22 : iconSize))
                    .foregroundStyle(
                        isNativeListRow
                            ? Color.primary
                            : Color.secondary
                    )
            }
            if visibleChildren.isEmpty {
                Text(verbatim: model.text)
                    .font(isNavigationHeading ? .title3 : .body)
                    .fontWeight(
                        isNavigationHeading
                            ? .bold
                            : ((isNavigationRow && model.isSelected) ? .semibold : .regular)
                    )
                    .lineLimit(1)
            } else {
                ForEach(visibleChildren, id: \.self) { childID in
                    let child = backend.model(id: childID)
                    LUIAnyNodeView(nodeID: childID, backend: backend)
                        .environment(\.luiIsNativeListRow, isNativeListRow)
                        .frame(
                            maxWidth: LUIListItemLayoutPolicy.stretchesChild(
                                kind: child?.kind,
                                grow: child?.property(.grow)?.doubleValue
                            ) ? .infinity : nil,
                            alignment: .leading
                        )
                        .layoutPriority(child?.property(.grow)?.doubleValue ?? 0)
                }
            }
            if usesInlineTrailingIcon {
                trailingIcon
            }
            if LUIListItemLayoutPolicy.showsTrailingSpacer(
                childGrows: hasGrowingVisibleChild
            ) {
                Spacer(minLength: 8)
            }
            if let contextMenu {
                Menu {
                    LUIContextMenuActions(model: contextMenu, backend: backend)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More actions")
                .accessibilityIdentifier(
                    contextMenu.property(.accessibilityIdentifier)?.stringValue ?? ""
                )
            }
            if !usesInlineTrailingIcon {
                trailingIcon
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingIcon: some View {
        if !model.buttonIconName.isEmpty && model.buttonIconPlacement == "trailing" {
            LUIIconImage(
                source: backend.iconSource(for: model.buttonIconName),
                bundle: backend.appIconBundle
            )
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.secondary)
        }
    }

    private var role: String { model.property(.role)?.stringValue ?? "" }
    private var hasExplicitPadding: Bool { model.property(.padding) != nil }
    private var usesSystemListInsets: Bool { isNativeListRow }
    private var isNavigationRow: Bool {
        role == "navigation" || role == "navigation-heading"
    }
    private var isNavigationHeading: Bool { role == "navigation-heading" }
    private var usesInlineTrailingIcon: Bool {
        LUIListItemLayoutPolicy.usesInlineTrailingIcon(
            isNavigationHeading: isNavigationHeading
        )
    }
    private var horizontalSpacing: CGFloat {
        if isNavigationHeading {
            return CGFloat(LUIListItemLayoutPolicy.navigationHeadingSpacing)
        }
        return isNativeListRow ? 12 : (isNavigationRow ? 10 : 8)
    }
    private var verticalPadding: CGFloat {
        isNavigationHeading ? 6 : (isNavigationRow ? 10 : 8)
    }
    private var cornerRadius: CGFloat { isNavigationRow ? 10 : 6 }
    private var selectionBackground: Color {
        if isNavigationRow && colorScheme == .light {
            return Color.primary.opacity(0.06)
        }
        return Color.accentColor.opacity(isNavigationRow ? 0.12 : 0.16)
    }
    private var iconSize: CGFloat { isNativeListRow ? 18 : (isNavigationRow ? 18 : 16) }

    private func performPrimaryAction() {
        if didLongPress {
            didLongPress = false
        } else if model.isTreeItem {
            try? backend.performTreeTap(node: model.id)
        } else if model.supportsPress {
            try? backend.performPress(node: model.id)
        }
    }

    private var visibleChildren: [Int] {
        model.children.filter { backend.model(id: $0)?.kind != .contextMenu }
    }

    private var hasInteractiveChildren: Bool {
        visibleChildren.contains(where: containsInteractiveControl)
    }

    private var hasGrowingVisibleChild: Bool {
        visibleChildren.contains { childID in
            LUIListItemLayoutPolicy.stretchesChild(
                kind: backend.model(id: childID)?.kind,
                grow: backend.model(id: childID)?.property(.grow)?.doubleValue
            )
        }
    }

    private func containsInteractiveControl(_ nodeID: Int) -> Bool {
        guard let child = backend.model(id: nodeID) else { return true }
        switch child.kind {
        case .button, .toggleButton, .toggle, .radio, .slider, .textField,
             .secureField, .input, .searchField, .textarea, .checkbox,
             .switchControl, .select, .combobox, .menuItem, .listItem:
            return true
        default:
            return child.children.contains(where: containsInteractiveControl)
        }
    }

    private var contextMenu: LUINodeModel? {
        model.children.compactMap(backend.model).first { menu in
            menu.kind == .contextMenu && menu.children.contains { childID in
                backend.model(id: childID)?.kind == .menuItem
            }
        }
    }
}

private struct LUINativeListRowAccessibilityModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let isNativeListRow: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isNativeListRow {
            content.modifier(LUIAccessibilityModifier(model: model, backend: backend))
        } else {
            content
        }
    }
}

private struct LUIListItemSupplementaryGesturesModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Binding var didLongPress: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if model.supportsDoublePress && model.supportsLongPress {
            content
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard model.supportsDoublePress, model.isEnabled else { return }
                        try? backend.performDoublePress(node: model.id)
                    }
                )
                .onLongPressGesture(
                    minimumDuration: LUIListItemInteractionPolicy.longPressMinimumDuration
                ) {
                    guard model.supportsLongPress, model.isEnabled else { return }
                    didLongPress = true
                    try? backend.performLongPress(node: model.id)
                }
        } else if model.supportsDoublePress {
            content.simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard model.isEnabled else { return }
                    try? backend.performDoublePress(node: model.id)
                }
            )
        } else if model.supportsLongPress {
            content.onLongPressGesture(
                minimumDuration: LUIListItemInteractionPolicy.longPressMinimumDuration
            ) {
                guard model.isEnabled else { return }
                didLongPress = true
                try? backend.performLongPress(node: model.id)
            }
        } else {
            content
        }
    }
}

private struct LUIListItemSwipeActionsModifier: ViewModifier {
    let menu: LUINodeModel?
    let backend: LUIAppleBackend

    @ViewBuilder
    func body(content: Content) -> some View {
        if let menu, menu.children.contains(where: {
            backend.model(id: $0)?.kind == .menuItem
        }) {
            content.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                LUIContextMenuActions(model: menu, backend: backend)
            }
        } else {
            content
        }
    }
}

enum LUIButtonIconPlacementPolicy {
    static func usesVerticalLayout(_ placement: String) -> Bool {
        placement == "top"
    }
}

enum LUIButtonVisualPolicy {
    static func usesBorderedStyle(variant: String) -> Bool {
        variant == "primary" || variant == "secondary" ||
            variant == "outline" || variant == "destructive"
    }

    static func iconExtent(buttonSize: String) -> CGFloat {
        switch buttonSize {
        case "sm": 16
        case "lg", "icon": 24
        default: 18
        }
    }

    static func usesIntrinsicHeight(
        variant: String,
        buttonSize: String,
        hasIcon: Bool
    ) -> Bool {
        variant == "ghost" && buttonSize != "icon" && !hasIcon
    }

    static func fillsAvailableWidth(grow: Double?) -> Bool {
        (grow ?? 0) > 0
    }

    static func contentHorizontalPadding(explicit: Int?) -> CGFloat {
        CGFloat(explicit ?? 0)
    }

    static func labelAlignment(textAlignment: String?) -> Alignment {
        switch textAlignment {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }

    static func usesSemiboldLabel(styleClass: String?) -> Bool {
        styleClass?.split(separator: " ").contains("semibold") == true
    }

    static func usesCaptionLabel(styleClass: String?) -> Bool {
        styleClass?.split(separator: " ").contains("caption") == true
    }

    static func resolvedExtent(explicit: Int?, fallback: CGFloat?) -> CGFloat? {
        if let explicit {
            return CGFloat(explicit)
        }
        return fallback
    }

    static func defaultHeight(isNativeFormRow: Bool) -> CGFloat? {
        isNativeFormRow ? nil : 44
    }

    static func defaultWidth(
        buttonSize: String,
        usesMinimumTouchTarget: Bool
    ) -> CGFloat? {
        guard buttonSize == "icon" else { return nil }
        return usesMinimumTouchTarget ? 44 : 40
    }
}

private struct LUIButtonView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let isToggle: Bool
    @FocusState private var focused: Bool
    @State private var held = false
    @State private var selected: Bool
    @Environment(\.luiIsNativeFormRow) private var isNativeFormRow
    @Environment(\.luiIsNativeListRow) private var isNativeListRow
    init(model: LUINodeModel, backend: LUIAppleBackend, isToggle: Bool = false) {
        self.model = model
        self.backend = backend
        self.isToggle = isToggle
        _selected = State(initialValue: model.isSelected)
    }

    var body: some View {
        styledButton
            .controlSize(controlSize)
            .frame(
                maxWidth: LUIButtonVisualPolicy.fillsAvailableWidth(
                    grow: model.property(.grow)?.doubleValue
                ) ? .infinity : nil,
                alignment: LUIButtonVisualPolicy.labelAlignment(
                    textAlignment: model.property(.textAlignment)?.stringValue
                )
            )
            .frame(
                width: buttonWidth,
                height: buttonHeight
            )
            .accessibilityElement(children: .ignore)
            .disabled(!model.isEnabled)
            .focused($focused)
            .onAppear { requestFocusIfNeeded() }
            .onChange(of: model.requestsAutofocus) { _, requested in
                if requested { focused = true }
            }
            .onChange(of: model.isSelected) { _, modelSelected in
                if isToggle, model.property(.selected) != nil {
                    selected = modelSelected
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        guard model.supportsLongPress, model.isEnabled else { return }
                        held = true
                        try? backend.performLongPress(node: model.id)
                    }
            )
            .modifier(
                LUISecondaryLongPressModifier(
                    enabled: model.supportsLongPress && model.isEnabled,
                    action: { try? backend.performLongPress(node: model.id) }
                )
            )
            .modifier(
                LUISelectedButtonModifier(
                    selected: isToggle ? selected : model.isSelected
                )
            )
    }

    @ViewBuilder
    private var styledButton: some View {
        if isTabTrigger {
            button
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    model.isSelected ? tabBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .shadow(
                    color: model.isSelected ? .black.opacity(0.08) : .clear,
                    radius: model.isSelected ? 1 : 0,
                    y: model.isSelected ? 1 : 0
                )
        } else {
            switch model.buttonVariant {
        case "primary":
            button.buttonStyle(.borderedProminent)
        case "secondary":
            button.buttonStyle(.bordered).tint(.secondary)
        case "outline":
            button.buttonStyle(.bordered)
        case "destructive":
            button.buttonStyle(.borderedProminent).tint(.red)
        case "ghost":
            button.buttonStyle(.borderless)
        default:
            if LUINavigationFormRowPolicy.usesBorderlessButtonStyle(
                isNativeListRow: isNativeListRow,
                variant: model.buttonVariant
            ) {
                button.buttonStyle(.borderless)
            } else if LUINavigationFormRowPolicy.usesAutomaticButtonStyle(
                isNativeFormRow: isNativeFormRow,
                variant: model.buttonVariant
            ) {
                button.foregroundStyle(.tint)
            } else {
                button.buttonStyle(.bordered)
            }
            }
        }
    }

    @ViewBuilder
    private var button: some View {
        if let contextMenu {
            Menu {
                LUIContextMenuActions(model: contextMenu, backend: backend)
            } label: {
                buttonLabel
            }
        } else {
            Button {
                if held {
                    held = false
                } else if isToggle {
                    selected.toggle()
                    try? backend.performToggle(node: model.id, checked: selected)
                } else {
                    try? backend.performPress(node: model.id)
                }
            } label: {
                buttonLabel
            }
        }
    }

    private var buttonLabel: some View {
        label
            .font(
                LUIButtonVisualPolicy.usesCaptionLabel(
                    styleClass: model.property(.styleClass)?.stringValue
                ) ? .caption : .body
            )
            .padding(
                .horizontal,
                LUIButtonVisualPolicy.contentHorizontalPadding(
                    explicit: model.property(.paddingHorizontal)?.intValue
                )
            )
            .fontWeight(
                LUIButtonVisualPolicy.usesSemiboldLabel(
                    styleClass: model.property(.styleClass)?.stringValue
                ) ? .semibold : nil
            )
            .lineLimit(1)
            .frame(
                maxWidth: LUIButtonVisualPolicy.fillsAvailableWidth(
                    grow: model.property(.grow)?.doubleValue
                ) ? .infinity : nil,
                alignment: LUIButtonVisualPolicy.labelAlignment(
                    textAlignment: model.property(.textAlignment)?.stringValue
                )
            )
            .frame(
                width: buttonWidth,
                height: buttonHeight
            )
            .contentShape(Rectangle())
    }

    private var contextMenu: LUINodeModel? {
        model.children
            .compactMap { backend.model(id: $0) }
            .first { $0.kind == .contextMenu }
    }

    @ViewBuilder
    private var label: some View {
        if model.buttonIconName.isEmpty {
            Text(verbatim: model.text)
        } else if model.text.isEmpty {
            icon
        } else if LUIButtonIconPlacementPolicy.usesVerticalLayout(
            model.buttonIconPlacement
        ) {
            VStack(spacing: 2) {
                icon
                Text(verbatim: model.text)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 14)
            }
        } else if model.buttonIconPlacement == "trailing" {
            HStack(spacing: 8) {
                Text(verbatim: model.text)
                icon
            }
        } else {
            HStack(spacing: 8) {
                icon
                Text(verbatim: model.text)
            }
        }
    }

    private var icon: some View {
        LUIIconImage(
            source: backend.iconSource(for: model.buttonIconName),
            bundle: backend.appIconBundle
        )
            .scaledToFit()
            .frame(
                width: iconExtent,
                height: iconExtent
            )
    }

    private var iconExtent: CGFloat {
        min(LUIButtonVisualPolicy.iconExtent(buttonSize: model.buttonSize),
            buttonWidth ?? .greatestFiniteMagnitude,
            buttonHeight ?? .greatestFiniteMagnitude)
    }

    private var controlSize: ControlSize {
        switch model.buttonSize {
        case "sm": .small
        case "lg": .large
        default: .regular
        }
    }

    private var buttonHeight: CGFloat? {
        if model.surfaceHeight != nil {
            return LUIButtonVisualPolicy.resolvedExtent(
                explicit: model.surfaceHeight,
                fallback: nil
            )
        }
        #if os(iOS)
        if LUIButtonVisualPolicy.usesIntrinsicHeight(
            variant: model.buttonVariant,
            buttonSize: model.buttonSize,
            hasIcon: !model.buttonIconName.isEmpty
        ) {
            return nil
        }
        return LUIButtonVisualPolicy.defaultHeight(isNativeFormRow: isNativeFormRow)
        #else
        return switch model.buttonSize {
        case "sm": 36
        case "lg": 44
        case "icon": 40
        default: 40
        }
        #endif
    }

    private var buttonWidth: CGFloat? {
        LUIButtonVisualPolicy.resolvedExtent(
            explicit: model.surfaceWidth,
            fallback: LUIButtonVisualPolicy.defaultWidth(
                buttonSize: model.buttonSize,
                usesMinimumTouchTarget: usesMinimumTouchTarget
            )
        )
    }

    private var usesMinimumTouchTarget: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private func requestFocusIfNeeded() {
        if model.requestsAutofocus { focused = true }
    }

    private var isTabTrigger: Bool {
        guard let parent = model.parent else { return false }
        return backend.model(id: parent)?.kind == .tabs
    }

    private var tabBackground: Color {
#if os(macOS)
        Color(nsColor: .controlBackgroundColor)
#else
        Color(uiColor: .secondarySystemBackground)
#endif
    }
}

enum LUIHorizontalFocusKey {
    case left
    case right
    case home
    case end
}

enum LUIHorizontalFocus {
    static func isEligible(parent: LUINodeKind, child: LUINodeKind) -> Bool {
        switch parent {
        case .tabs: child == .button
        case .buttonGroup: child == .button || child == .toggleButton
        case .toggleGroup: child == .toggleButton
        case .breadcrumb, .pagination: child == .button
        default: false
        }
    }

    static func nextIndex(
        current: Int?,
        key: LUIHorizontalFocusKey,
        enabled: [Bool]
    ) -> Int? {
        let candidates = enabled.indices.filter { enabled[$0] }
        guard let first = candidates.first, let last = candidates.last else { return nil }
        switch key {
        case .home: return first
        case .end: return last
        case .left, .right:
            guard let current, let position = candidates.firstIndex(of: current) else {
                return first
            }
            let offset = key == .right ? 1 : candidates.count - 1
            return candidates[(position + offset) % candidates.count]
        }
    }
}

enum LUIHorizontalGroupDefaults {
    static func gap(for kind: LUINodeKind) -> Int {
        kind == .pagination ? 2 : 4
    }
}

private struct LUIHorizontalGroupView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @FocusState private var focusedChild: Int?

    var body: some View {
        HStack(
            alignment: verticalAlignment,
            spacing: spacing
        ) {
            if main == "center" || main == "end" {
                Spacer(minLength: 0)
            }
            ForEach(Array(model.children.enumerated()), id: \.element) { index, childID in
                if let child = backend.model(id: childID) {
                    if model.kind == .breadcrumb && index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    groupChild(child)
                        .frame(
                            maxWidth: child.property(.grow)?.doubleValue ?? 0 > 0
                                ? .infinity : nil
                        )
                        .layoutPriority(child.property(.grow)?.doubleValue ?? 0)
                }
                if main == "space_between" && index < model.children.count - 1 {
                    Spacer(minLength: gap)
                }
            }
            if main == "start" || main == "center" {
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            if focusedChild == nil,
               let requested = eligibleChildren.first(where: { $0.requestsAutofocus }) {
                focusedChild = requested.id
            }
        }
        .onKeyPress { press in
            guard let key = focusKey(press.key) else { return .ignored }
            let children = eligibleChildren
            let current = focusedChild.flatMap { focused in
                children.firstIndex(where: { $0.id == focused })
            }
            let target = LUIHorizontalFocus.nextIndex(
                current: current,
                key: key,
                enabled: children.map(\.isEnabled)
            )
            guard let target else { return .ignored }
            focusedChild = children[target].id
            return .handled
        }
    }

    @ViewBuilder
    private func groupChild(_ child: LUINodeModel) -> some View {
        if isEligible(child) {
            LUINodeView(model: child, backend: backend)
                .focused($focusedChild, equals: child.id)
        } else {
            LUINodeView(model: child, backend: backend)
        }
    }

    private var eligibleChildren: [LUINodeModel] {
        model.children.compactMap(backend.model).filter(isEligible)
    }

    private func isEligible(_ child: LUINodeModel) -> Bool {
        LUIHorizontalFocus.isEligible(parent: model.kind, child: child.kind)
    }

    private func focusKey(_ key: KeyEquivalent) -> LUIHorizontalFocusKey? {
        switch key {
        case .leftArrow: .left
        case .rightArrow: .right
        case KeyEquivalent(Character("\u{F729}")): .home
        case KeyEquivalent(Character("\u{F72B}")): .end
        default: nil
        }
    }

    private var gap: CGFloat {
        CGFloat(
            model.property(.gap)?.intValue ??
                LUIHorizontalGroupDefaults.gap(for: model.kind)
        )
    }

    private var main: String? {
        model.property(.main)?.stringValue
    }

    private var spacing: CGFloat {
        main == "space_between" ? 0 : gap
    }

    private var verticalAlignment: VerticalAlignment {
        switch model.property(.cross)?.stringValue ?? "center" {
        case "start": .top
        case "end": .bottom
        default: .center
        }
    }
}

private struct LUISecondaryLongPressModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        content.overlay {
            LUISecondaryLongPressCapture(enabled: enabled, action: action)
        }
#else
        content
#endif
    }
}

#if os(macOS)
private struct LUISecondaryLongPressCapture: NSViewRepresentable {
    let enabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> LUISecondaryLongPressView {
        let view = LUISecondaryLongPressView()
        view.isLongPressEnabled = enabled
        view.onLongPress = action
        return view
    }

    func updateNSView(_ view: LUISecondaryLongPressView, context: Context) {
        view.isLongPressEnabled = enabled
        view.onLongPress = action
    }
}

final class LUISecondaryLongPressView: NSView {
    var isLongPressEnabled = false
    var onLongPress: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isLongPressEnabled, bounds.contains(point), let event = window?.currentEvent else {
            return nil
        }
        if event.type == .rightMouseDown ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            return self
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        handleSecondaryActivation()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            handleSecondaryActivation()
        } else {
            super.mouseDown(with: event)
        }
    }

    func handleSecondaryActivation() {
        if isLongPressEnabled { onLongPress() }
    }
}
#endif

private struct LUISelectedButtonModifier: ViewModifier {
    let selected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if selected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content
        }
    }
}

private struct LUIIconImage: View {
    let source: LUIAppleIconSource
    let bundle: Bundle?

    @ViewBuilder
    var body: some View {
        switch source {
        case let .systemName(name):
            Image(systemName: name)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case let .assetName(name):
            Image(name, bundle: bundle)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

enum LUITextLinePolicy {
    static func lineLimit(styleClass: String?) -> Int? {
        if hasStyle("single-line", in: styleClass) { return 1 }
        return hasStyle("line-clamp-3", in: styleClass) ? 3 : nil
    }

    static func layoutPriority(styleClass: String?) -> Double {
        hasStyle("single-line", in: styleClass) ? 1.0 : 0.0
    }

    private static func hasStyle(_ target: String, in styleClass: String?) -> Bool {
        guard let styleClass else { return false }
        return styleClass.split(separator: " ").contains { String($0) == target }
    }
}

private struct LUITextView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Environment(\.luiTextHighlightQuery) private var highlightQuery

    @ViewBuilder
    var body: some View {
        if model.supportsPress {
            Button {
                try? backend.performPress(node: model.id)
            } label: {
                textContent
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(lineLimit)
                    .frame(maxWidth: alignedMaxWidth, alignment: frameAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(layoutPriority)
            }
            .buttonStyle(.plain)
        } else {
            textContent
                .font(font)
                .multilineTextAlignment(textAlignment)
                .lineLimit(lineLimit)
                .frame(maxWidth: alignedMaxWidth, alignment: frameAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(layoutPriority)
        }
    }

    private var textContent: Text {
        let classes = model.property(.styleClass)?.stringValue?.split(separator: " ") ?? []
        if classes.contains("search-match") {
            return Text(LUITextHighlight.preview(model.text, query: highlightQuery))
        }
        return Text(verbatim: model.text)
    }

    private var lineLimit: Int? {
        LUITextLinePolicy.lineLimit(
            styleClass: model.property(.styleClass)?.stringValue
        )
    }

    private var layoutPriority: Double {
        LUITextLinePolicy.layoutPriority(
            styleClass: model.property(.styleClass)?.stringValue
        )
    }

    private var isFootnote: Bool {
        model.property(.styleClass)?.stringValue?
            .split(separator: " ")
            .contains("footnote") ?? false
    }

    private var font: Font {
        let classes = model.property(.styleClass)?.stringValue?.split(separator: " ") ?? []
        if classes.contains("title2") {
            return classes.contains("semibold") ? .title2.weight(.semibold) : .title2
        }
        if classes.contains("headline") { return .headline }
        if classes.contains("subheadline") { return .subheadline.weight(.semibold) }
        if classes.contains("caption") {
            return classes.contains("semibold") ? .caption.weight(.semibold) : .caption
        }
        if classes.contains("semibold") { return .body.weight(.semibold) }
        if isFootnote { return .footnote }
        return .body
    }

    private var alignedMaxWidth: CGFloat? {
        model.property(.textAlignment) == nil ? nil : .infinity
    }

    private var textAlignment: TextAlignment {
        switch model.property(.textAlignment)?.stringValue {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }

    private var frameAlignment: Alignment {
        switch model.property(.textAlignment)?.stringValue {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }
}

enum LUIRowLayoutPolicy {
    static func isFlexibleChild(kind: LUINodeKind?, grow: Double?) -> Bool {
        kind == .spacer || (grow ?? 0) > 0
    }

    static func childLayoutPriority(
        grow: Double?,
        styleClass: String?
    ) -> Double {
        _ = grow
        return LUITextLinePolicy.layoutPriority(styleClass: styleClass)
    }

    static func showsTrailingSpacer(
        main: String?,
        hasGrowingChild: Bool
    ) -> Bool {
        if main == "center" { return true }
        return (main == nil || main == "start") && !hasGrowingChild
    }
}

private struct LUIRowView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        HStack(alignment: alignment, spacing: spacing) {
            if model.property(.main)?.stringValue == "center" ||
                model.property(.main)?.stringValue == "end" {
                Spacer(minLength: 0)
            }
            ForEach(Array(model.children.enumerated()), id: \.element) { index, childID in
                let child = backend.model(id: childID)
                if child?.kind == .spacer {
                    Spacer(minLength: 0)
                } else {
                    LUIAnyNodeView(nodeID: childID, backend: backend)
                        .equatable()
                        .frame(
                            maxWidth: child?.property(.grow)?.doubleValue ?? 0 > 0
                                ? .infinity : nil,
                            maxHeight: cross == "stretch" ? .infinity : nil
                        )
                        .layoutPriority(LUIRowLayoutPolicy.childLayoutPriority(
                            grow: child?.property(.grow)?.doubleValue,
                            styleClass: child?.property(.styleClass)?.stringValue
                        ))
                }
                if model.property(.main)?.stringValue == "space_between" &&
                    index < model.children.count - 1 {
                    Spacer(minLength: gap)
                }
            }
            if LUIRowLayoutPolicy.showsTrailingSpacer(
                main: model.property(.main)?.stringValue,
                hasGrowingChild: hasGrowingChild
            ) {
                Spacer(minLength: 0)
            }
        }
    }

    private var hasGrowingChild: Bool {
        model.children.contains { childID in
            let child = backend.model(id: childID)
            return LUIRowLayoutPolicy.isFlexibleChild(
                kind: child?.kind,
                grow: child?.property(.grow)?.doubleValue
            )
        }
    }

    private var gap: CGFloat { CGFloat(model.property(.gap)?.intValue ?? 0) }
    private var cross: String {
        model.property(.cross)?.stringValue ?? "stretch"
    }
    private var spacing: CGFloat {
        model.property(.main)?.stringValue == "space_between" ? 0 : gap
    }
    private var alignment: VerticalAlignment {
        switch cross {
        case "start": .top
        case "end": .bottom
        default: .center
        }
    }
}

enum LUIColumnLayoutPolicy {
    static func fillsAvailableWidth(cross: String?, grow: Double?) -> Bool {
        LUIVerticalContainerPolicy.stretchesCrossAxis(cross) || (grow ?? 0) > 0
    }

    static func showsTrailingSpacer(main: String?) -> Bool {
        main == "center"
    }
}

private struct LUIColumnView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            columnChildren
        }
        .frame(
            maxWidth: LUIColumnLayoutPolicy.fillsAvailableWidth(
                cross: cross,
                grow: model.property(.grow)?.doubleValue
            )
                ? .infinity : nil,
            alignment: frameAlignment
        )
    }

    @ViewBuilder
    private var columnChildren: some View {
        if model.property(.main)?.stringValue == "center" ||
            model.property(.main)?.stringValue == "end" {
            Spacer(minLength: 0)
        }
        ForEach(Array(model.children.enumerated()), id: \.element) { index, childID in
            let child = backend.model(id: childID)
            LUIAnyNodeView(nodeID: childID, backend: backend)
                .equatable()
                .frame(
                    maxWidth: LUIVerticalContainerPolicy.stretchesCrossAxis(cross)
                        ? .infinity : nil,
                    maxHeight: child?.property(.grow)?.doubleValue ?? 0 > 0
                        ? .infinity : nil,
                    alignment: .topLeading
                )
                .layoutPriority(child?.property(.grow)?.doubleValue ?? 0)
            if model.property(.main)?.stringValue == "space_between" &&
                index < model.children.count - 1 {
                Spacer(minLength: gap)
            }
        }
        if LUIColumnLayoutPolicy.showsTrailingSpacer(
            main: model.property(.main)?.stringValue
        ) {
            Spacer(minLength: 0)
        }
    }

    private var gap: CGFloat { CGFloat(model.property(.gap)?.intValue ?? 0) }
    private var cross: String {
        model.property(.cross)?.stringValue ?? "stretch"
    }
    private var spacing: CGFloat {
        model.property(.main)?.stringValue == "space_between" ? 0 : gap
    }
    private var alignment: HorizontalAlignment {
        switch cross {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }

    private var frameAlignment: Alignment {
        switch cross {
        case "center": .top
        case "end": .topTrailing
        default: .topLeading
        }
    }
}

struct LUIListSection: Equatable, Identifiable {
    let headerID: Int?
    let childIDs: [Int]
    let footerID: Int?

    var id: Int { headerID ?? childIDs.first ?? footerID ?? Int.min }
}

enum LUIListSurfacePolicy {
    static let scrollContentBackground: Visibility = .visible
}

public struct LUIListSurfacePreferenceKey: PreferenceKey {
    public static let defaultValue = false

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

enum LUIListSectionPolicy {
    static func sections(
        childIDs: [Int],
        isHeading: (Int) -> Bool,
        isFooter: (Int) -> Bool
    ) -> [LUIListSection] {
        var result: [LUIListSection] = []
        var headerID: Int?
        var rows: [Int] = []
        var footerID: Int?

        func appendCurrentSection() {
            guard headerID != nil || !rows.isEmpty || footerID != nil else { return }
            result.append(LUIListSection(
                headerID: headerID,
                childIDs: rows,
                footerID: footerID
            ))
        }

        for childID in childIDs {
            if isHeading(childID) {
                appendCurrentSection()
                headerID = childID
                rows = []
                footerID = nil
            } else if isFooter(childID), headerID != nil || !rows.isEmpty {
                footerID = childID
                appendCurrentSection()
                headerID = nil
                rows = []
                footerID = nil
            } else {
                rows.append(childID)
            }
        }
        appendCurrentSection()
        return result
    }
}

private struct LUIListView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Environment(\.luiSemanticColors) private var semanticColors
    @Environment(\.luiInsideScroll) private var insideScroll

    var body: some View {
        if insideScroll {
            // A nested scrolling List collapses inside an outer ScrollView;
            // lay rows out statically instead.
            LazyVStack(
                alignment: .leading,
                spacing: CGFloat(model.property(.gap)?.intValue ?? 0)
            ) {
                ForEach(sections) { section in
                    if let headerID = section.headerID,
                       let header = backend.model(id: headerID) {
                        Text(verbatim: header.text)
                            .font(.headline)
                    }
                    rows(section.childIDs)
                    if let footerID = section.footerID,
                       let footer = backend.model(id: footerID) {
                        Text(verbatim: footer.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            nativeList
        }
    }

    private var nativeList: some View {
        List {
            ForEach(sections) { section in
                if let headerID = section.headerID,
                   let header = backend.model(id: headerID),
                   let footerID = section.footerID,
                   let footer = backend.model(id: footerID) {
                    Section {
                        rows(section.childIDs)
                    } header: {
                        Text(verbatim: header.text)
                    } footer: {
                        Text(verbatim: footer.text)
                    }
                } else if let headerID = section.headerID,
                          let header = backend.model(id: headerID) {
                    Section {
                        rows(section.childIDs)
                    } header: {
                        Text(verbatim: header.text)
                    }
                } else if let footerID = section.footerID,
                          let footer = backend.model(id: footerID) {
                    Section {
                        rows(section.childIDs)
                    } footer: {
                        Text(verbatim: footer.text)
                    }
                } else {
                    rows(section.childIDs)
                }
            }
        }
        #if !SKIP
        .scrollContentBackground(
            semanticColors["background"] == nil
                ? LUIListSurfacePolicy.scrollContentBackground : .hidden
        )
        .background(semanticColors["background"])
        .foregroundStyle(.primary)
        .preference(
            key: LUIListSurfacePreferenceKey.self,
            value: semanticColors["background"] == nil
        )
        #endif
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    private func rows(_ childIDs: [Int]) -> some View {
        ForEach(childIDs, id: \.self) { childID in
            Group {
                if let child = backend.model(id: childID), child.kind == .listItem {
                    LUIListItemView(model: child, backend: backend, isNativeListRow: true)
                } else {
                    LUIAnyNodeView(nodeID: childID, backend: backend)
                }
            }
            .listRowBackground(semanticColors["surface"])
        }
    }

    private var sections: [LUIListSection] {
        LUIListSectionPolicy.sections(
            childIDs: model.children,
            isHeading: { childID in
                backend.model(id: childID)?.kind == .heading
            },
            isFooter: { childID in
                guard let child = backend.model(id: childID), child.kind == .text else {
                    return false
                }
                return (child.property(.styleClass)?.stringValue ?? "")
                    .split(separator: " ")
                    .contains("footnote") == true
            }
        )
    }
}

private struct LUIVirtualListView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @State private var unobscuredHeight: CGFloat?
    @State private var titleTracker = LUIScrollSectionTitleTracker()

    var body: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: CGFloat(model.property(.gap)?.intValue ?? 0)
            ) {
                ForEach(sectionRows, id: \.id) { row in
                    LUIAnyNodeView(nodeID: row.id, backend: backend)
                        .equatable()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(LUIScrollSectionFrameModifier(
                            index: row.index, title: row.title,
                            coordinateSpace: titleCoordinateSpace,
                            onVisibilityChange: { index, title in
                                titleTracker.update(index: index, title: title)
                            }
                        ))
                }
            }
            .environment(\.luiUnobscuredScrollHeight, unobscuredHeight)
        }
        .coordinateSpace(name: titleCoordinateSpace)
        .environment(\.luiInsideScroll, true)
        .background {
            LUIScrollSectionTitleEmitter(tracker: titleTracker,
                                         isActive: tracksSectionTitles && model.isSelected)
        }
        .background {
            GeometryReader { _ in
                // Minimum-height content uses the viewport before keyboard avoidance.
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        unobscuredHeight = height
                    }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private var tracksSectionTitles: Bool {
        model.property(.styleClass)?.stringValue?.split(separator: " ").contains("scroll-section-titles") == true
    }

    private var titleCoordinateSpace: LUIScrollTitleCoordinateSpace {
        LUIScrollTitleCoordinateSpace(nodeID: model.id)
    }

    private struct SectionRow {
        let id: Int
        let index: Int
        let title: String?
    }

    private var sectionRows: [SectionRow] {
        var currentTitle: String?
        return model.children.enumerated().map { index, id in
            if tracksSectionTitles, let title = sectionTitle(in: id) { currentTitle = title }
            return SectionRow(id: id, index: index, title: currentTitle)
        }
    }

    private func sectionTitle(in nodeID: Int) -> String? {
        guard let node = backend.model(id: nodeID) else { return nil }
        if node.property(.styleClass)?.stringValue?.split(separator: " ").contains("scroll-section-title") == true {
            return node.text.isEmpty ? nil : node.text
        }
        return node.children.lazy.compactMap { sectionTitle(in: $0) }.first
    }

}

struct LUIVerticalScrollContent: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: CGFloat(model.property(.gap)?.intValue ?? 0)
        ) {
            ForEach(model.children, id: \.self) { childID in
                LUIAnyNodeView(nodeID: childID, backend: backend)
            }
        }
    }
}

private struct LUIGridView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: gap) {
            ForEach(model.children, id: \.self) { childID in
                LUIAnyNodeView(nodeID: childID, backend: backend)
            }
        }
    }

    private var gap: CGFloat { CGFloat(model.property(.gap)?.intValue ?? 0) }
    private var columnCount: Int {
        let requested = model.property(.columns)?.intValue ?? 0
        return max(1, requested > 0 ? requested : model.children.count)
    }
    private var gridItems: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: gap),
            count: columnCount
        )
    }
}

private struct LUISeparatorView: View {
    let model: LUINodeModel

    @ViewBuilder
    var body: some View {
        if model.property(.orientation)?.stringValue == "vertical" {
            Divider()
                .frame(maxHeight: .infinity)
                .frame(width: 1)
        } else {
            Divider()
                .frame(maxWidth: .infinity)
                .frame(height: 1)
        }
    }
}

struct LUITextDraftState: Equatable {
    private(set) var text: String

    init(source: String) {
        text = source
    }

    mutating func edit(_ next: String) {
        text = next
    }

    mutating func reconcile(source: String, focused: Bool) {
        if (!focused || source.isEmpty), text != source {
            text = source
        }
    }
}

private struct LUITextControlView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let grouped: Bool
    @State private var draftState: LUITextDraftState
    @FocusState private var focused: Bool

    init(model: LUINodeModel, backend: LUIAppleBackend, grouped: Bool = false) {
        self.model = model
        self.backend = backend
        self.grouped = grouped
        _draftState = State(initialValue: LUITextDraftState(source: model.text))
    }

    var body: some View {
        Group {
            if grouped {
                field.textFieldStyle(.plain)
            } else if model.kind == .searchField {
                field
            } else {
                field.textFieldStyle(.roundedBorder)
            }
        }
            .disabled(!model.isEnabled)
            .focused($focused)
            .onSubmit { try? backend.performSubmit(node: model.id) }
            .onAppear { if model.requestsAutofocus { focused = true } }
            .onChange(of: model.requestsAutofocus) { _, requested in
                if requested { focused = true }
            }
            .onChange(of: model.text) { _, next in
                draftState.reconcile(source: next, focused: focused)
            }
            .onChange(of: focused) { _, next in
                if !next {
                    draftState.reconcile(source: model.text, focused: false)
                }
            }
    }

    @ViewBuilder
    private var field: some View {
        if model.kind == .secureField {
            SecureField(
                model.property(.placeholder)?.stringValue ?? "",
                text: binding
            )
        } else if model.kind == .textarea {
            TextField(
                model.property(.placeholder)?.stringValue ?? "",
                text: binding,
                axis: .vertical
            )
            .lineLimit(1...(model.property(.styleClass)?.stringValue == "composer-input" ? 6 : Int.max))
        } else if model.kind == .searchField {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    model.property(.placeholder)?.stringValue ?? "",
                    text: binding
                )
                if !draftState.text.isEmpty {
                    Button {
                        draftState.edit("")
                        try? backend.performTextChange(node: model.id, text: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        } else {
            TextField(model.property(.placeholder)?.stringValue ?? "", text: binding)
        }
    }

    private var binding: Binding<String> {
        Binding(
            get: { draftState.text },
            set: { next in
                draftState.edit(next)
                try? backend.performTextChange(node: model.id, text: next)
            }
        )
    }
}

private struct LUIRadioGroupView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if LUIRadioGroupVisualPolicy.usesMenuStyle(
            model.property(.styleClass)?.stringValue
        ) {
            picker.pickerStyle(.menu)
        } else {
            #if os(macOS)
            picker.pickerStyle(.radioGroup)
            #else
            picker.pickerStyle(.segmented)
            #endif
        }
    }

    private var picker: some View {
        Picker(groupLabel, selection: selection) {
            ForEach(choices) { choice in
                Text(verbatim: choice.text)
                    .tag(Optional(choice.id))
            }
        }
        .disabled(!choices.contains(where: \.isEnabled))
    }

    private var choices: [LUINodeModel] {
        model.children.compactMap { childID in
            guard let child = backend.model(id: childID), child.kind == .radio else {
                return nil
            }
            return child
        }
    }

    private var selection: Binding<Int?> {
        Binding(
            get: { choices.first(where: \.isChecked)?.id },
            set: { selectedID in
                guard let selectedID,
                      let choice = backend.model(id: selectedID),
                      choice.isEnabled else { return }
                try? backend.performChange(node: selectedID)
            }
        )
    }

    private var groupLabel: String {
        model.property(.accessibilityLabel)?.stringValue ?? "Options"
    }
}

private struct LUICheckboxView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        #if os(macOS)
        Toggle(
            model.text,
            isOn: Binding(
                get: { model.isChecked },
                set: { try? backend.performToggle(node: model.id, checked: $0) }
            )
        )
        .toggleStyle(.checkbox)
        .disabled(!model.isEnabled)
        #else
        Button {
            try? backend.performToggle(
                node: model.id,
                checked: !model.isChecked
            )
        } label: {
            Label(model.text, systemImage: checkboxImageName)
        }
        .buttonStyle(.plain)
        .disabled(!model.isEnabled)
        .frame(minHeight: 44)
        .accessibilityValue(Text(model.isChecked ? "1" : "0"))
        #endif
    }

    private var checkboxImageName: String {
        return model.isChecked ? "checkmark.square.fill" : "square"
    }
}

enum LUIIntrinsicSurfacePolicy {
    static func fillsWidth(kind: LUINodeKind, grow: Double) -> Bool {
        kind == .box && grow > 0
    }
}

enum LUISurfaceFramePolicy {
    static func usesTopLeadingAlignment(kind: LUINodeKind) -> Bool {
        kind == .textarea
    }
}

enum LUISurfaceEmphasisPolicy {
    static func opacity(
        kind: LUINodeKind,
        isEnabled: Bool,
        hasExplicitBackground: Bool
    ) -> Double {
        kind == .button && !isEnabled && hasExplicitBackground ? 0.5 : 1.0
    }
}

enum LUIBorderRenderingPolicy {
    static func drawsBorder(width: CGFloat) -> Bool {
        width > 0
    }
}

enum LUIClipRenderingPolicy {
    static func clipsContent(
        kind: LUINodeKind,
        background: String?,
        cornerRadius: CGFloat,
        borderWidth: CGFloat
    ) -> Bool {
        let isSemanticSurface = switch kind {
        case .panel, .card, .resizable, .alert, .bubble, .tabs: true
        default: false
        }
        let hasVisibleBackground = background != nil && background != "transparent"
        return isSemanticSurface || hasVisibleBackground || cornerRadius > 0 || borderWidth > 0
    }
}

private struct LUIOptionalClipModifier: ViewModifier {
    let cornerRadius: CGFloat
    let clipsContent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if clipsContent {
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}

private struct LUISurfaceModifier: ViewModifier {
    let model: LUINodeModel
    @Environment(\.luiSemanticColors) private var semanticColors

    func body(content: Content) -> some View {
        let isSurface = model.kind == .panel || model.kind == .card ||
            model.kind == .resizable || model.kind == .alert || model.kind == .bubble
        let isTabs = model.kind == .tabs
        let defaultPadding = switch model.kind {
        case .card: 24
        case .alert: 16
        case .bubble: 12
        default: isTabs ? 2 : 0
        }
        let padding = model.property(.padding)?.intValue ?? defaultPadding
        let horizontal = model.kind == .button
            ? 0
            : model.property(.paddingHorizontal)?.intValue ?? padding
        let vertical = model.property(.paddingVertical)?.intValue ?? padding
        let radius = CGFloat(
            model.property(.cornerRadius)?.intValue ?? (isSurface ? 12 : (isTabs ? 8 : 0))
        )
        let borderWidth = CGFloat(model.property(.borderWidth)?.intValue ?? (isSurface ? 1 : 0))
        let shape = RoundedRectangle(cornerRadius: radius)
        let backgroundName = model.property(.background)?.stringValue
        let background = color(backgroundName) ??
            defaultBackground(isSurface: isSurface, isTabs: isTabs)
        let border = color(model.property(.borderColor)?.stringValue) ??
            (isSurface ? Color.secondary.opacity(0.35) : .clear)
        let castsShadow = model.kind == .panel &&
            model.property(.background)?.stringValue != "transparent"

        content
            .padding(.horizontal, CGFloat(horizontal))
            .padding(.vertical, CGFloat(vertical))
            .frame(
                maxWidth: LUIIntrinsicSurfacePolicy.fillsWidth(
                    kind: model.kind,
                    grow: model.property(.grow)?.doubleValue ?? 0
                ) ? .infinity : nil,
                alignment: .leading
            )
            .frame(
                width: LUIExplicitFramePolicy.width(
                    kind: model.kind,
                    requested: model.surfaceWidth
                ).map(CGFloat.init),
                height: model.surfaceHeight.map(CGFloat.init)
            )
            .modifier(LUIBodyLineControlModifier(
                enabled: model.property(.styleClass)?.stringValue?.split(separator: " ").contains("body-line") == true,
                width: model.surfaceWidth.map(CGFloat.init),
                minimumHeight: CGFloat(model.surfaceHeight ?? 24)
            ))
            .frame(
                minWidth: model.kind == .resizable ? nil : model.surfaceMinWidth.map(CGFloat.init),
                maxWidth: model.kind == .resizable ? nil : model.surfaceMaxWidth.map(CGFloat.init),
                minHeight: model.surfaceMinHeight.map(CGFloat.init),
                maxHeight: model.surfaceMaxHeight.map(CGFloat.init),
                alignment: LUISurfaceFramePolicy.usesTopLeadingAlignment(kind: model.kind)
                    ? .topLeading
                    : .center
            )
            .modifier(
                LUIContainerRelativeFrameModifier(
                    axes: model.containerRelativeFrame,
                    inset: CGFloat(model.containerRelativeFrameInset)
                )
            )
            .modifier(
                LUIOptionalForegroundModifier(
                    usesSecondaryStyle:
                        LUIThemeColorPolicy.isSecondaryForeground(model.property(.foreground)?.stringValue) ||
                        (LUIThemeColorPolicy.isMutedForeground(model.property(.foreground)?.stringValue) &&
                         semanticColors["muted-foreground"] == nil),
                    foreground: foregroundColor(model.property(.foreground)?.stringValue) ??
                        (LUIThemeColorPolicy.usesDefaultForeground(kind: model.kind)
                            ? defaultForeground
                            : nil)
                )
            )
            .background(background, in: shape)
            .shadow(
                color: castsShadow ? .black.opacity(0.12) : .clear,
                radius: castsShadow ? 4 : 0,
                y: castsShadow ? 2 : 0
            )
            .overlay {
                if LUIBorderRenderingPolicy.drawsBorder(width: borderWidth) {
                    shape.stroke(
                        border,
                        lineWidth: borderWidth
                    )
                }
            }
            .opacity(LUISurfaceEmphasisPolicy.opacity(
                kind: model.kind,
                isEnabled: model.isEnabled,
                hasExplicitBackground: backgroundName != nil
            ))
            .modifier(LUIOptionalClipModifier(
                cornerRadius: radius,
                clipsContent: LUIClipRenderingPolicy.clipsContent(
                    kind: model.kind,
                    background: backgroundName,
                    cornerRadius: radius,
                    borderWidth: borderWidth
                )
            ))
    }

    private func foregroundColor(_ name: String?) -> Color? {
        if LUIThemeColorPolicy.isSecondaryForeground(name) {
            return .secondary
        }
        return color(name)
    }

    private func color(_ name: String?) -> Color? {
        if let name, let semanticColor = semanticColors[name.lowercased()] {
            return semanticColor
        }
        if LUIThemeColorPolicy.isMutedForeground(name) {
            return .secondary
        }
        if LUIThemeColorPolicy.isAccentForeground(name) {
            return .accentColor
        }
        return switch name?.lowercased() {
        case nil: nil
        case "transparent": .clear
        case "background": systemBackground
        case "foreground": .primary
        case "primary": .accentColor
        case "primary-foreground": .white
        case "secondary": .secondary.opacity(0.15)
        case "glass-fallback": glassFallbackBackground
        case "secondary-foreground": .primary
        case "success": .green.opacity(0.15)
        case "success-foreground": .green
        case "warning": .orange.opacity(0.15)
        case "warning-foreground": .orange
        case "error": .red.opacity(0.15)
        case "error-foreground": .red
        case "border": .secondary.opacity(0.35)
        case "black": .black
        case "white": .white
        case "red": .red
        case "blue": .blue
        case "green": .green
        default: nil
        }
    }

    private var glassFallbackBackground: Color {
        #if SKIP
        Color.white.opacity(0.9)
        #else
        .clear
        #endif
    }

    private func defaultBackground(isSurface: Bool, isTabs: Bool) -> Color {
        if model.kind == .bubble && model.property(.variant)?.stringValue == "primary" {
            return .accentColor
        }
        if model.kind == .bubble && model.property(.variant)?.stringValue == "ghost" {
            return .clear
        }
        if model.kind == .alert && model.property(.variant)?.stringValue == "destructive" {
            return .red.opacity(0.1)
        }
        return isSurface ? systemBackground : (isTabs ? .secondary.opacity(0.12) : .clear)
    }

    private var defaultForeground: Color {
        if model.kind == .bubble && model.property(.variant)?.stringValue == "primary" {
            return .white
        }
        if model.kind == .alert && model.property(.variant)?.stringValue == "destructive" {
            return .red
        }
        return .primary
    }

    private var systemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

private struct LUIOptionalForegroundModifier: ViewModifier {
    var usesSecondaryStyle = false
    let foreground: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesSecondaryStyle {
            content.foregroundStyle(.secondary)
        } else if let foreground {
            content.foregroundStyle(foreground)
        } else {
            content
        }
    }
}

enum LUISplitGeometry {
    static func effectiveFraction(
        value: Double,
        available: Double,
        firstMinimum: Double,
        secondMinimum: Double
    ) -> Double {
        guard available > 0, available.isFinite else { return 0.5 }
        let base = value.isFinite && value > 0 ? min(value, 1) : 0.5
        let low = max(firstMinimum, 0) / available
        let high = 1 - (max(secondMinimum, 0) / available)
        if low > high {
            return low / max(low + (1 - high), 0.0001)
        }
        return min(max(base, low), high)
    }
}

struct LUISplitFractionState: Equatable {
    private(set) var sourceFraction: Double
    private(set) var fraction: Double

    init(sourceFraction: Double) {
        let normalized = Self.normalized(sourceFraction)
        self.sourceFraction = sourceFraction
        fraction = normalized
    }

    mutating func applyUserFraction(_ value: Double) {
        fraction = Self.normalized(value)
    }

    mutating func reconcile(sourceFraction: Double) {
        if sourceFraction == self.sourceFraction { return }
        self.sourceFraction = sourceFraction
        if abs(Self.normalized(sourceFraction) - fraction) > 0.000_001 {
            fraction = Self.normalized(sourceFraction)
        }
    }

    private static func normalized(_ value: Double) -> Double {
        value.isFinite && value > 0 ? min(value, 1) : 0.5
    }
}

private struct LUISplitView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fractionState: LUISplitFractionState
    @State private var dragStartFraction: Double?

    init(model: LUINodeModel, backend: LUIAppleBackend) {
        self.model = model
        self.backend = backend
        _fractionState = State(
            initialValue: LUISplitFractionState(
                sourceFraction: model.splitResizeOrigin ?? model.splitFraction
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let gap = max(CGFloat(model.splitGap), 0)
            let available = max(geometry.size.width - gap, 0)
            let firstID = model.children.first
            let secondID = model.children.dropFirst().first
            let firstModel = firstID.flatMap(backend.model(id:))
            let secondModel = secondID.flatMap(backend.model(id:))
            let fraction = LUISplitGeometry.effectiveFraction(
                value: fractionState.fraction,
                available: Double(available),
                firstMinimum: Double(firstModel?.surfaceMinWidth ?? 0),
                secondMinimum: Double(secondModel?.surfaceMinWidth ?? 0)
            )
            let firstWidth = available * CGFloat(fraction)
            let secondWidth = available - firstWidth

            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    if let firstID {
                        LUIAnyNodeView(nodeID: firstID, backend: backend)
                            .frame(width: firstWidth)
                    }
                    if let secondID {
                        LUIAnyNodeView(nodeID: secondID, backend: backend)
                            .frame(width: secondWidth)
                    }
                }

                Color.clear
                    .frame(width: gap, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .offset(x: firstWidth)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let start = dragStartFraction ?? fraction
                                dragStartFraction = start
                                updateFraction(
                                    start + Double(value.translation.width / max(available, 1)),
                                    available: available,
                                    firstMinimum: firstModel?.surfaceMinWidth ?? 0,
                                    secondMinimum: secondModel?.surfaceMinWidth ?? 0
                                )
                            }
                            .onEnded { _ in dragStartFraction = nil }
                    )
                    .focusable()
                    .onKeyPress(.leftArrow) {
                        adjust(
                            by: -0.05,
                            available: available,
                            firstMinimum: firstModel?.surfaceMinWidth ?? 0,
                            secondMinimum: secondModel?.surfaceMinWidth ?? 0
                        )
                    }
                    .onKeyPress(.rightArrow) {
                        adjust(
                            by: 0.05,
                            available: available,
                            firstMinimum: firstModel?.surfaceMinWidth ?? 0,
                            secondMinimum: secondModel?.surfaceMinWidth ?? 0
                        )
                    }
                    .accessibilityElement()
                    .accessibilityLabel(
                        Text("\(model.property(.accessibilityLabel)?.stringValue ?? "Split") divider")
                    )
                    .accessibilityValue(Text("\(Int((fraction * 100).rounded()))%"))
                    .accessibilityAdjustableAction { direction in
                        _ = adjust(
                            by: direction == .increment ? 0.05 : -0.05,
                            available: available,
                            firstMinimum: firstModel?.surfaceMinWidth ?? 0,
                            secondMinimum: secondModel?.surfaceMinWidth ?? 0
                        )
                    }
            }
        }
        .onAppear { reconcile(sourceFraction: model.splitFraction) }
        .onChange(of: model.splitFraction) { _, value in reconcile(sourceFraction: value) }
    }

    private var splitAnimation: Animation? {
        guard !reduceMotion, model.splitResizeDuration > 0 else { return nil }
        let duration = Double(model.splitResizeDuration) / 1_000
        switch model.splitResizeEasing {
        case "linear": return .linear(duration: duration)
        case "emphasized": return .timingCurve(0.2, 0, 0, 1, duration: duration)
        case "spring": return .spring(duration: duration, bounce: 0.25)
        default: return .easeInOut(duration: duration)
        }
    }

    private func reconcile(sourceFraction: Double) {
        withAnimation(splitAnimation) {
            fractionState.reconcile(sourceFraction: sourceFraction)
        }
    }

    private func adjust(
        by delta: Double,
        available: CGFloat,
        firstMinimum: Int,
        secondMinimum: Int
    ) -> KeyPress.Result {
        updateFraction(
            fractionState.fraction + delta,
            available: available,
            firstMinimum: firstMinimum,
            secondMinimum: secondMinimum
        )
        return .handled
    }

    private func updateFraction(
        _ value: Double,
        available: CGFloat,
        firstMinimum: Int,
        secondMinimum: Int
    ) {
        let effective = LUISplitGeometry.effectiveFraction(
            value: value,
            available: Double(available),
            firstMinimum: Double(firstMinimum),
            secondMinimum: Double(secondMinimum)
        )
        fractionState.applyUserFraction(effective)
        try? backend.performValueChange(node: model.id, value: effective)
    }
}

struct LUIResizableWidthState: Equatable {
    private(set) var sourceWidth: Int?
    private(set) var minimumWidth: Int?
    private(set) var maximumWidth: Int?
    private(set) var width: CGFloat?

    init(sourceWidth: Int?, minimumWidth: Int?, maximumWidth: Int?) {
        self.sourceWidth = sourceWidth
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        width = Self.clamp(sourceWidth.map(CGFloat.init), minimumWidth, maximumWidth)
    }

    mutating func reconcile(
        sourceWidth: Int?,
        minimumWidth: Int?,
        maximumWidth: Int?
    ) {
        let sourceChanged = self.sourceWidth != sourceWidth
        self.sourceWidth = sourceWidth
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        width = Self.clamp(
            sourceChanged ? sourceWidth.map(CGFloat.init) : width,
            minimumWidth,
            maximumWidth
        )
    }

    mutating func drag(by delta: CGFloat, fallbackWidth: CGFloat) {
        width = Self.clamp((width ?? fallbackWidth) + delta, minimumWidth, maximumWidth)
    }

    private static func clamp(_ width: CGFloat?, _ minimum: Int?, _ maximum: Int?) -> CGFloat? {
        guard var width else { return nil }
        if let minimum { width = max(width, CGFloat(minimum)) }
        if let maximum { width = min(width, CGFloat(maximum)) }
        return width
    }
}

private struct LUIResizableView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @State private var widthState: LUIResizableWidthState
    @State private var previousTranslation: CGFloat = 0

    init(model: LUINodeModel, backend: LUIAppleBackend) {
        self.model = model
        self.backend = backend
        _widthState = State(
            initialValue: LUIResizableWidthState(
                sourceWidth: model.surfaceWidth,
                minimumWidth: model.surfaceMinWidth,
                maximumWidth: model.surfaceMaxWidth
            )
        )
    }

    var body: some View {
        ZStack {
            ForEach(model.children, id: \.self) { childID in
                LUIAnyNodeView(nodeID: childID, backend: backend)
            }
        }
        .modifier(LUISurfaceModifier(model: model))
        .frame(width: widthState.width)
        .overlay(alignment: .trailing) {
            GeometryReader { geometry in
                Color.clear
                    .frame(width: 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let delta = value.translation.width - previousTranslation
                                previousTranslation = value.translation.width
                                widthState.drag(by: delta, fallbackWidth: geometry.size.width)
                            }
                            .onEnded { _ in previousTranslation = 0 }
                    )
            }
        }
        .accessibilityLabel(model.property(.accessibilityLabel)?.stringValue ?? "Resizable")
        .accessibilityAdjustableAction { direction in
            widthState.drag(
                by: direction == .increment ? 16 : -16,
                fallbackWidth: CGFloat(model.surfaceWidth ?? model.surfaceMinWidth ?? 0)
            )
        }
        .onChange(of: model.surfaceWidth) { _, value in reconcile(sourceWidth: value) }
        .onChange(of: model.surfaceMinWidth) { _, _ in reconcile(sourceWidth: model.surfaceWidth) }
        .onChange(of: model.surfaceMaxWidth) { _, _ in reconcile(sourceWidth: model.surfaceWidth) }
    }

    private func reconcile(sourceWidth: Int?) {
        widthState.reconcile(
            sourceWidth: sourceWidth,
            minimumWidth: model.surfaceMinWidth,
            maximumWidth: model.surfaceMaxWidth
        )
    }
}

private struct LUIAccessibilityModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    func body(content: Content) -> some View {
        let label = model.accessibilityLabel(in: backend)
        let hint = model.accessibilityHint(in: backend)
        let identifier = model.accessibilityIdentifier(in: backend) ?? label
        let accessibleContent = content.modifier(
            LUIAccessibilityContainmentModifier(
                containsChildren: LUIAccessibilityPolicy.shouldContainChildren(
                    hasChildren: !model.children.isEmpty,
                    identifier: identifier
                )
            )
        )
        .modifier(LUIAppearanceTraceModifier(identifier: identifier))
        if let label, let hint, let identifier {
            accessibleContent
                .accessibilityLabel(Text(label))
                .accessibilityHint(Text(hint))
                .accessibilityIdentifier(identifier)
        } else if let label, let identifier {
            accessibleContent
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier(identifier)
        } else if let label, let hint {
            accessibleContent
                .accessibilityLabel(Text(label))
                .accessibilityHint(Text(hint))
        } else if let label {
            accessibleContent.accessibilityLabel(Text(label))
        } else if let identifier {
            accessibleContent.accessibilityIdentifier(identifier)
        } else if let hint {
            accessibleContent.accessibilityHint(Text(hint))
        } else {
            accessibleContent
        }
    }
}

private struct LUIAppearanceTraceModifier: ViewModifier {
    let identifier: String?
    private static let target = ProcessInfo.processInfo.environment["LUI_TRACE_APPEAR_IDENTIFIER"]

    @ViewBuilder func body(content: Content) -> some View {
        if let identifier, identifier == Self.target {
            content.onAppear {
                print(String(format: "LUI_APPEAR_METRIC identifier=%@ timestamp=%.6f", identifier, Date().timeIntervalSince1970))
            }
        } else {
            content
        }
    }
}

private struct LUIAccessibilityContainmentModifier: ViewModifier {
    let containsChildren: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if containsChildren {
            content.accessibilityElement(children: .contain)
        } else {
            content
        }
    }
}
#endif

#if !SKIP
/// Indeterminate spinner backed by the platform activity indicator instead of
/// `ProgressView`: inside `List`/`Form` cells the SwiftUI progress view keeps
/// invalidating the collection layout and can pin the main thread at 100%.
private struct LUIActivitySpinnerView: View {
    let style: LUISpinnerStyle

    var body: some View {
        #if os(iOS)
        IOSActivityIndicator(style: style)
        #else
        MacActivityIndicator(style: style)
        #endif
    }
}

#if os(iOS)
private struct IOSActivityIndicator: UIViewRepresentable {
    let style: LUISpinnerStyle

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: style == .large ? .large : .medium)
        view.startAnimating()
        return view
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {}
}
#else
private struct MacActivityIndicator: NSViewRepresentable {
    let style: LUISpinnerStyle

    func makeNSView(context: Context) -> NSProgressIndicator {
        let view = NSProgressIndicator()
        view.style = .spinning
        view.controlSize = style == .large ? .large : .regular
        view.isIndeterminate = true
        view.isDisplayedWhenStopped = false
        view.startAnimation(nil)
        return view
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {}
}
#endif
#endif
