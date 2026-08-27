#if SKIP
import SwiftUI

public struct LUISwiftUIRoot: View {
    private let backend: LUIAppleBackend
    private let rootID: Int

    public init(backend: LUIAppleBackend, rootID: Int) {
        self.backend = backend
        self.rootID = rootID
    }

    public var body: some View {
        LUIAnyNodeView(nodeID: rootID, backend: backend)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
    }
}

struct LUIAnyNodeView: View {
    let nodeID: Int
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if let model = backend.model(id: nodeID) {
            LUISkipNodeView(model: model, backend: backend)
        } else if let model = backend.extensionModel(id: nodeID) {
            let _ = model.revision
            backend.extensionView(nodeID: model.id)
        }
    }
}

private struct LUISkipNodeView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @State private var didLongPress = false

    @ViewBuilder
    var body: some View {
        let _ = model.revision
        content
            .disabled(!model.isEnabled)
            .modifier(LUISkipAccessibilityModifier(model: model, backend: backend))
    }

    @ViewBuilder
    private var content: some View {
        switch model.kind {
        case .root:
            if let childID = model.children.first {
                LUIAnyNodeView(nodeID: childID, backend: backend)
            }
        case .row, .tabs, .buttonGroup, .toggleGroup, .breadcrumb, .pagination,
             .inputGroup, .inputGroupActions:
            HStack(spacing: CGFloat(model.property(.gap)?.intValue ?? 0)) {
                children
            }
        case .toolbar:
            toolbar
        case .list:
            LazyVStack(
                alignment: .leading,
                spacing: CGFloat(model.property(.gap)?.intValue ?? 0)
            ) {
                children
            }
        case .column, .box:
            VStack(
                alignment: columnAlignment,
                spacing: CGFloat(model.property(.gap)?.intValue ?? 0)
            ) {
                if !model.text.isEmpty {
                    Text(verbatim: model.text)
                }
                children
            }
            .frame(
                maxWidth: LUIVerticalContainerPolicy.stretchesCrossAxis(columnCross)
                    ? .infinity : nil,
                alignment: columnFrameAlignment
            )
        case .panel, .card, .stack, .grid, .table,
             .tableRow, .tableCell, .tree, .timeline, .timelineItem, .stepper,
             .step, .alert, .bubble, .toast, .accordion,
             .menuItem, .resizable, .split:
            VStack(alignment: .leading, spacing: CGFloat(model.property(.gap)?.intValue ?? 0)) {
                if !model.text.isEmpty {
                    Text(verbatim: model.text)
                }
                children
            }
        case .scroll:
            ScrollView {
                ZStack {
                    children
                }
            }
        case .drawer:
            LUIDrawerView(model: model, backend: backend)
        case .listItem:
            Group {
                switch LUIListItemInteractionPolicy.style(
                    hasVisibleChildren: !visibleListItemChildren.isEmpty
                ) {
                case .button:
                    Button(action: { performListItemPrimaryAction() }) {
                        listItemContent
                    }
                    .buttonStyle(.plain)
                case .composite:
                    listItemContent
                        .onTapGesture { performListItemPrimaryAction() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(model.isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    guard model.supportsLongPress, model.isEnabled else { return }
                    didLongPress = true
                    try? backend.performLongPress(node: model.id)
                }
            )
        case .heading:
            Text(verbatim: model.text).font(.title)
        case .text, .paragraph, .label, .statusBar, .tooltip:
            Text(verbatim: model.text)
        case .button, .toggleButton:
            Button {
                try? backend.performAction(node: model.id)
            } label: {
                Text(verbatim: model.text)
            }
        case .checkbox, .switchControl, .toggle:
            Toggle(
                model.text,
                isOn: Binding(
                    get: { model.isChecked },
                    set: { try? backend.performToggle(node: model.id, checked: $0) }
                )
            )
        case .radio:
            Button {
                try? backend.performChange(node: model.id)
            } label: {
                HStack {
                    Text(verbatim: model.isChecked ? "●" : "○")
                    Text(verbatim: model.text)
                }
            }
        case .textField, .input, .searchField:
            TextField(
                model.property(.placeholder)?.stringValue ?? "",
                text: textBinding
            )
        case .secureField:
            SecureField(
                model.property(.placeholder)?.stringValue ?? "",
                text: textBinding
            )
        case .textarea:
            TextEditor(text: textBinding)
        case .select, .combobox, .dropdownMenu, .radioGroup:
            Menu(model.text) {
                ForEach(model.children, id: \.self) { childID in
                    LUIAnyNodeView(nodeID: childID, backend: backend)
                }
            }
        case .dialog, .sheet:
            if model.kind == .sheet && LUINavigationFormSheetPolicy.isNavigationForm(
                model.property(.styleClass)?.stringValue
            ) {
                NavigationStack {
                    Form { navigationFormRows }
                        .navigationTitle(model.text)
                        .toolbar {
                            if let actionID = navigationActionID(for: .cancellation) {
                                ToolbarItem(placement: .cancellationAction) {
                                    navigationActionView(actionID)
                                }
                            }
                            if let actionID = navigationActionID(for: .confirmation) {
                                ToolbarItem(placement: .confirmationAction) {
                                    navigationActionView(actionID)
                                }
                            }
                        }
                }
            } else {
                VStack(alignment: .leading) { children }
            }
        case .slider:
            Slider(
                value: Binding(
                    get: { min(max(model.sliderValue, 0.0), 1.0) },
                    set: { try? backend.performValueChange(node: model.id, value: $0) }
                ),
                in: 0...1
            )
        case .progress:
            ProgressView(value: model.progressFraction)
        case .divider:
            Divider()
        case .spacer:
            Spacer()
        case .spinner:
            ProgressView()
                .frame(
                    width: CGFloat(model.spinnerWidth),
                    height: CGFloat(model.spinnerHeight)
                )
        case .icon:
            Text(verbatim: model.iconName)
                .frame(
                    width: CGFloat(model.iconWidth),
                    height: CGFloat(model.iconHeight)
                )
        case .avatar, .image, .mediaSurface:
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(
                    width: model.surfaceWidth.map({ CGFloat($0) }),
                    height: model.surfaceHeight.map({ CGFloat($0) })
                )
        case .contextMenu:
            EmptyView()
        }
    }

    @ViewBuilder
    private var navigationFormRows: some View {
        if let contentID = model.children.first(where: {
            backend.model(id: $0)?.kind != .toolbar
        }), let content = backend.model(id: contentID) {
            if LUINavigationFormSheetPolicy.isForm(
                content.property(.styleClass)?.stringValue
            ) {
                ForEach(content.children, id: \.self) { childID in
                    LUIAnyNodeView(nodeID: childID, backend: backend)
                }
            } else {
                LUIAnyNodeView(nodeID: contentID, backend: backend)
            }
        }
    }

    private func navigationActionID(
        for placement: LUINavigationFormActionPlacement
    ) -> Int? {
        guard let toolbarID = model.children.first(where: {
            backend.model(id: $0)?.kind == .toolbar
        }), let toolbar = backend.model(id: toolbarID) else { return nil }
        return toolbar.children.first { childID in
            guard let child = backend.model(id: childID) else { return false }
            return LUINavigationFormSheetPolicy.actionPlacement(
                child.property(.styleClass)?.stringValue
            ) == placement
        }
    }

    @ViewBuilder
    private func navigationActionView(_ actionID: Int) -> some View {
        if let model = backend.model(id: actionID) {
            LUINavigationFormActionView(model: model, backend: backend)
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        let spacing = CGFloat(model.property(.gap)?.intValue ?? 0)
        let layout = LUIToolbarLayoutPolicy.layout(
            orientation: model.property(.orientation)?.stringValue,
            styleClass: model.property(.styleClass)?.stringValue,
            childIDs: model.children
        )
        if layout.axis == .vertical {
            VStack(alignment: .leading, spacing: spacing) {
                children(model.children)
            }
        } else if let fixedChildID = layout.fixedChildID {
            HStack(spacing: spacing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        children(layout.scrollingChildIDs)
                    }
                }
                LUIAnyNodeView(nodeID: fixedChildID, backend: backend)
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

    @ViewBuilder
    private var children: some View {
        ForEach(model.children, id: \.self) { childID in
            LUIAnyNodeView(nodeID: childID, backend: backend)
        }
    }

    private var visibleListItemChildren: [Int] {
        model.children.filter { backend.model(id: $0)?.kind != .contextMenu }
    }

    private var columnCross: String? {
        model.property(.cross)?.stringValue
    }

    private var columnAlignment: HorizontalAlignment {
        switch columnCross {
        case "center": .center
        case "end": .trailing
        default: .leading
        }
    }

    private var columnFrameAlignment: Alignment {
        switch columnCross {
        case "center": .top
        case "end": .topTrailing
        default: .topLeading
        }
    }

    private var listItemContent: some View {
        HStack(spacing: 8) {
            if visibleListItemChildren.isEmpty {
                Text(verbatim: model.text)
            } else {
                ForEach(visibleListItemChildren, id: \.self) { childID in
                    LUIAnyNodeView(nodeID: childID, backend: backend)
                }
            }
            Spacer(minLength: 8)
        }
    }

    private func performListItemPrimaryAction() {
        if didLongPress {
            didLongPress = false
        } else if model.supportsPress {
            try? backend.performPress(node: model.id)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { model.text },
            set: { try? backend.performTextChange(node: model.id, text: $0) }
        )
    }
}

private struct LUISkipAccessibilityModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    func body(content: Content) -> some View {
        let label = model.accessibilityLabel(in: backend)
        let identifier = model.accessibilityIdentifier(in: backend) ?? label
        if let label, let identifier {
            content
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier(identifier)
        } else if let label {
            content.accessibilityLabel(Text(label))
        } else if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
#endif
