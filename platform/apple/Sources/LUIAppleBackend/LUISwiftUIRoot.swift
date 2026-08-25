import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct LUISwiftUIRoot: View {
    private let backend: LUIAppleBackend
    private let rootID: Int

    public init(backend: LUIAppleBackend, rootID: Int) {
        self.backend = backend
        self.rootID = rootID
    }

    public var body: some View {
        if let root = backend.model(id: rootID) {
            LUINodeView(model: root, backend: backend)
        }
    }
}

private struct LUINodeView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        let _ = model.revision
        if model.kind.isModalSurface {
            content
        } else {
            content
                .modifier(LUISurfaceModifier(model: model))
                .modifier(LUIAccessibilityModifier(model: model, backend: backend))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.kind {
        case .row:
            LUIRowView(model: model, backend: backend)
        case .tabs, .buttonGroup, .toggleGroup, .breadcrumb, .pagination:
            LUIHorizontalGroupView(model: model, backend: backend)
        case .column, .list:
            LUIColumnView(model: model, backend: backend)
        case .grid:
            LUIGridView(model: model, backend: backend)
        case .stack, .panel, .card:
            ZStack {
                children
            }
        case .box:
            VStack(
                alignment: .leading,
                spacing: CGFloat(model.property(.gap)?.intValue ?? 0)
            ) {
                children
            }
        case .text:
            LUITextView(model: model, backend: backend)
        case .heading:
            Text(verbatim: model.text)
                .font(headingFont)
                .accessibilityAddTraits(.isHeader)
        case .paragraph:
            Text(verbatim: model.text)
                .font(.body)
        case .label:
            Text(verbatim: model.text)
                .font(.body)
        case .button:
            LUIButtonView(model: model, backend: backend)
        case .toggleButton:
            LUIButtonView(model: model, backend: backend, isToggle: true)
        case .textField, .input, .searchField, .textarea:
            LUITextControlView(model: model, backend: backend)
        case .select:
            LUISelectView(model: model, backend: backend)
        case .combobox:
            LUIComboboxView(model: model, backend: backend)
        case .dropdownMenu:
            LUIDropdownMenuView(model: model, backend: backend)
        case .dialog, .drawer, .sheet:
            LUIModalPresenter(model: model, backend: backend)
        case .menuItem:
            LUIMenuItemView(model: model, backend: backend)
        case .listItem:
            LUIListItemView(model: model, backend: backend)
        case .avatar:
            LUIAvatarView(model: model, backend: backend)
        case .checkbox:
            LUICheckboxView(model: model, backend: backend)
        case .switchControl:
            Toggle(
                model.text,
                isOn: Binding(
                    get: { model.isChecked },
                    set: { try? backend.performToggle(node: model.id, checked: $0) }
                )
            )
            .disabled(!model.isEnabled)
        case .toggle:
            Toggle(
                model.text,
                isOn: Binding(
                    get: { model.isChecked },
                    set: { try? backend.performToggle(node: model.id, checked: $0) }
                )
            )
            .disabled(!model.isEnabled)
        case .radioGroup:
            HStack(alignment: .center) { children }
        case .radio:
            Button {
                try? backend.performChange(node: model.id)
            } label: {
                Label(model.text, systemImage: model.isChecked ? "circle.inset.filled" : "circle")
            }
            .buttonStyle(.plain)
            .disabled(!model.isEnabled)
        case .slider:
            Slider(
                value: Binding(
                    get: { min(max(model.sliderValue, 0), 1) },
                    set: { try? backend.performValueChange(node: model.id, value: $0) }
                ),
                in: 0...1
            )
            .disabled(!model.isEnabled)
        case .progress:
            ProgressView(value: model.progressFraction)
                .accessibilityValue(Text(progressAccessibilityValue))
        case .divider:
            LUISeparatorView(model: model)
        case .scroll:
            ScrollView {
                ZStack {
                    children
                }
            }
        case .spacer:
            Spacer()
        case .spinner:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(model.spinnerControlSize)
                .frame(
                    width: CGFloat(model.spinnerWidth),
                    height: CGFloat(model.spinnerHeight)
                )
        case .icon:
            LUIIconImage(source: backend.iconSource(for: model.iconName))
                .scaledToFit()
                .frame(
                    width: CGFloat(model.iconWidth),
                    height: CGFloat(model.iconHeight)
                )
        }
    }

    @ViewBuilder
    private var children: some View {
        ForEach(model.children, id: \.self) { childID in
            if let child = backend.model(id: childID) {
                LUINodeView(model: child, backend: backend)
            }
        }
    }

    private var headingFont: Font {
        switch model.property(.headingLevel)?.intValue ?? 1 {
        case 1: .largeTitle
        case 2: .title
        case 3: .title2
        case 4: .title3
        case 5: .headline
        default: .subheadline
        }
    }

    private var progressAccessibilityValue: String {
        "\(Int((model.progressFraction * 100).rounded()))%"
    }
}

private struct LUIModalPresenter: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @State private var isPresented = false

    @ViewBuilder
    var body: some View {
        Group {
            switch model.kind {
            case .dialog, .drawer:
                presentationAnchor
                    .sheet(isPresented: $isPresented) {
                        LUIModalSurfaceContent(model: model, backend: backend)
                    }
            case .sheet:
                presentationAnchor
                    .inspector(isPresented: $isPresented) {
                        LUIModalSurfaceContent(model: model, backend: backend)
                            .inspectorColumnWidth(
                                CGFloat(model.property(.width)?.intValue ?? 320)
                            )
                    }
            default:
                EmptyView()
            }
        }
        .onAppear { isPresented = true }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                try? backend.performDismiss(node: model.id)
            }
        }
    }

    private var presentationAnchor: some View {
        Color.clear.frame(width: 0, height: 0)
    }
}

private struct LUIModalSurfaceContent: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        let _ = model.revision
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: model.text)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ZStack {
                ForEach(model.children, id: \.self) { childID in
                    if let child = backend.model(id: childID) {
                        LUINodeView(model: child, backend: backend)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(CGFloat(model.property(.padding)?.intValue ?? 24))
        .frame(width: surfaceWidth, height: surfaceHeight)
    }

    private var surfaceWidth: CGFloat? {
        switch model.kind {
        case .dialog:
            CGFloat(model.property(.width)?.intValue ?? 420)
        case .sheet:
            CGFloat(model.property(.width)?.intValue ?? 320)
        case .drawer:
            model.property(.width).map { CGFloat($0.intValue ?? 0) }
        default:
            nil
        }
    }

    private var surfaceHeight: CGFloat? {
        switch model.kind {
        case .dialog:
            CGFloat(model.property(.height)?.intValue ?? 220)
        case .drawer:
            CGFloat(model.property(.height)?.intValue ?? 260)
        case .sheet:
            model.property(.height).map { CGFloat($0.intValue ?? 0) }
        default:
            nil
        }
    }
}

private extension LUINodeKind {
    var isModalSurface: Bool {
        self == .dialog || self == .drawer || self == .sheet
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

private struct LUISelectView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        Button {
            try? backend.performPress(node: model.id)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: displayText)
                    .foregroundStyle(model.text.isEmpty ? .secondary : .primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .disabled(!model.isEnabled)
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

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(model.property(.gap)?.intValue ?? 2)) {
            ForEach(model.children, id: \.self) { childID in
                if let child = backend.model(id: childID) {
                    LUINodeView(model: child, backend: backend)
                }
            }
        }
        .padding(4)
        .frame(
            minWidth: model.surfaceMinWidth.map(CGFloat.init),
            maxWidth: isStretch ? .infinity : nil,
            alignment: .leading
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8, y: 4)
        .offset(y: anchorDisplacement)
        .zIndex(1)
#if os(macOS)
        .onExitCommand {
            try? backend.performDismiss(node: model.id)
        }
#endif
    }

    private var isStretch: Bool {
        model.property(.anchorAlignment)?.stringValue == "stretch"
    }

    private var anchorDisplacement: CGFloat {
        let offset = CGFloat(model.property(.anchorOffset)?.doubleValue ?? 0)
        return (model.property(.anchor)?.stringValue ?? "below") == "above"
            ? -(40 + offset)
            : 40 + offset
    }
}

private struct LUIMenuItemView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        Button {
            try? backend.performPress(node: model.id)
        } label: {
            HStack(spacing: 8) {
                if !model.buttonIconName.isEmpty {
                    LUIIconImage(source: backend.iconSource(for: model.buttonIconName))
                        .frame(width: 16, height: 16)
                }
                Text(verbatim: model.text)
                Spacer(minLength: 12)
                if model.isSelected {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .disabled(!model.isEnabled)
    }
}

private struct LUIListItemView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        Button {
            if model.supportsPress {
                try? backend.performPress(node: model.id)
            }
        } label: {
            HStack(spacing: 8) {
                if !model.buttonIconName.isEmpty {
                    LUIIconImage(source: backend.iconSource(for: model.buttonIconName))
                        .frame(width: 16, height: 16)
                }
                if model.children.isEmpty {
                    Text(verbatim: model.text)
                } else {
                    ForEach(model.children, id: \.self) { childID in
                        if let child = backend.model(id: childID) {
                            LUINodeView(model: child, backend: backend)
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            model.isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if model.supportsDoublePress {
                    try? backend.performDoublePress(node: model.id)
                }
            }
        )
        .onKeyPress(.return) {
            guard model.supportsSubmit else { return .ignored }
            try? backend.performSubmit(node: model.id)
            return .handled
        }
        .accessibilityAddTraits(model.isSelected ? .isSelected : [])
        .disabled(!model.isEnabled)
    }
}

private struct LUIButtonView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let isToggle: Bool
    @FocusState private var focused: Bool
    @State private var held = false
    @State private var selected: Bool

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
                width: model.buttonSize == "icon" ? 40 : nil,
                height: buttonHeight
            )
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
                        guard model.supportsHold, model.isEnabled else { return }
                        held = true
                        try? backend.performHold(node: model.id)
                    }
            )
            .modifier(
                LUISecondaryHoldModifier(
                    enabled: model.supportsHold && model.isEnabled,
                    action: { try? backend.performHold(node: model.id) }
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
        case "secondary", "outline", "default":
            button.buttonStyle(.bordered)
        case "destructive":
            button.buttonStyle(.borderedProminent).tint(.red)
        default:
            button.buttonStyle(.plain)
            }
        }
    }

    private var button: some View {
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
            label
        }
    }

    @ViewBuilder
    private var label: some View {
        if model.buttonIconName.isEmpty {
            Text(verbatim: model.text)
        } else if model.text.isEmpty {
            icon
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
        LUIIconImage(source: backend.iconSource(for: model.buttonIconName))
            .scaledToFit()
            .frame(width: 16, height: 16)
    }

    private var controlSize: ControlSize {
        switch model.buttonSize {
        case "sm": .small
        case "lg": .large
        default: .regular
        }
    }

    private var buttonHeight: CGFloat? {
        switch model.buttonSize {
        case "sm": 36
        case "lg": 44
        case "icon": 40
        default: 40
        }
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

private struct LUISecondaryHoldModifier: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        content.overlay {
            LUISecondaryHoldCapture(enabled: enabled, action: action)
        }
#else
        content
#endif
    }
}

#if os(macOS)
private struct LUISecondaryHoldCapture: NSViewRepresentable {
    let enabled: Bool
    let action: () -> Void

    func makeNSView(context: Context) -> LUISecondaryHoldView {
        let view = LUISecondaryHoldView()
        view.isHoldEnabled = enabled
        view.onHold = action
        return view
    }

    func updateNSView(_ view: LUISecondaryHoldView, context: Context) {
        view.isHoldEnabled = enabled
        view.onHold = action
    }
}

final class LUISecondaryHoldView: NSView {
    var isHoldEnabled = false
    var onHold: () -> Void = {}

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isHoldEnabled, bounds.contains(point), let event = window?.currentEvent else {
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
        if isHoldEnabled { onHold() }
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

    @ViewBuilder
    var body: some View {
        switch source {
        case let .systemName(name):
            Image(systemName: name)
                .resizable()
        case let .assetName(name):
            Image(name)
                .resizable()
        }
    }
}

private struct LUITextView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    var body: some View {
        if model.supportsPress {
            Button {
                try? backend.performPress(node: model.id)
            } label: {
                Text(verbatim: model.text)
            }
            .buttonStyle(.plain)
        } else {
            Text(verbatim: model.text)
        }
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
                if let child = backend.model(id: childID) {
                    LUINodeView(model: child, backend: backend)
                        .frame(
                            maxWidth: child.property(.grow)?.doubleValue ?? 0 > 0
                                ? .infinity : nil,
                            maxHeight: cross == "stretch"
                                ? .infinity : nil
                        )
                        .layoutPriority(child.property(.grow)?.doubleValue ?? 0)
                }
                if model.property(.main)?.stringValue == "space_between" &&
                    index < model.children.count - 1 {
                    Spacer(minLength: gap)
                }
            }
            if model.property(.main)?.stringValue == nil ||
                model.property(.main)?.stringValue == "start" ||
                model.property(.main)?.stringValue == "center" {
                Spacer(minLength: 0)
            }
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

private struct LUIColumnView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            if model.property(.main)?.stringValue == "center" ||
                model.property(.main)?.stringValue == "end" {
                Spacer(minLength: 0)
            }
            ForEach(Array(model.children.enumerated()), id: \.element) { index, childID in
                if let child = backend.model(id: childID) {
                    LUINodeView(model: child, backend: backend)
                        .frame(
                            maxWidth: cross == "stretch"
                                ? .infinity : nil,
                            maxHeight: child.property(.grow)?.doubleValue ?? 0 > 0
                                ? .infinity : nil
                        )
                        .layoutPriority(child.property(.grow)?.doubleValue ?? 0)
                }
                if model.property(.main)?.stringValue == "space_between" &&
                    index < model.children.count - 1 {
                    Spacer(minLength: gap)
                }
            }
            if model.property(.main)?.stringValue == nil ||
                model.property(.main)?.stringValue == "start" ||
                model.property(.main)?.stringValue == "center" {
                Spacer(minLength: 0)
            }
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
}

private struct LUIGridView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: gap) {
            ForEach(model.children, id: \.self) { childID in
                if let child = backend.model(id: childID) {
                    LUINodeView(model: child, backend: backend)
                }
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

private struct LUITextControlView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @State private var draft: String
    @FocusState private var focused: Bool

    init(model: LUINodeModel, backend: LUIAppleBackend) {
        self.model = model
        self.backend = backend
        _draft = State(initialValue: model.text)
    }

    var body: some View {
        field
            .disabled(!model.isEnabled)
            .focused($focused)
            .onSubmit { try? backend.performSubmit(node: model.id) }
            .onAppear { if model.requestsAutofocus { focused = true } }
            .onChange(of: model.requestsAutofocus) { _, requested in
                if requested { focused = true }
            }
            .onChange(of: model.text) { _, next in
                if draft != next {
                    draft = next
                }
            }
    }

    @ViewBuilder
    private var field: some View {
        if model.kind == .textarea {
            TextField(
                model.property(.placeholder)?.stringValue ?? "",
                text: binding,
                axis: .vertical
            )
            .lineLimit(1...)
        } else if model.kind == .searchField {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    model.property(.placeholder)?.stringValue ?? "",
                    text: binding
                )
                if !draft.isEmpty {
                    Button {
                        draft = ""
                        try? backend.performTextChange(node: model.id, text: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            TextField(model.property(.placeholder)?.stringValue ?? "", text: binding)
        }
    }

    private var binding: Binding<String> {
        Binding(
            get: { draft },
            set: { next in
                draft = next
                try? backend.performTextChange(node: model.id, text: next)
            }
        )
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
        .accessibilityValue(Text(model.isChecked ? "1" : "0"))
        #endif
    }

    private var checkboxImageName: String {
        return model.isChecked ? "checkmark.square.fill" : "square"
    }
}

private struct LUISurfaceModifier: ViewModifier {
    let model: LUINodeModel

    func body(content: Content) -> some View {
        let isSurface = model.kind == .panel || model.kind == .card
        let isTabs = model.kind == .tabs
        let defaultPadding = model.kind == .card ? 24 : (isTabs ? 2 : 0)
        let padding = model.property(.padding)?.intValue ?? defaultPadding
        let horizontal = model.property(.paddingHorizontal)?.intValue ?? padding
        let vertical = model.property(.paddingVertical)?.intValue ?? padding
        let radius = CGFloat(
            model.property(.cornerRadius)?.intValue ?? (isSurface ? 12 : (isTabs ? 8 : 0))
        )
        let borderWidth = CGFloat(model.property(.borderWidth)?.intValue ?? (isSurface ? 1 : 0))
        let shape = RoundedRectangle(cornerRadius: radius)
        let background = color(model.property(.background)?.stringValue) ??
            (isSurface ? systemBackground : (isTabs ? Color.secondary.opacity(0.12) : .clear))
        let border = color(model.property(.borderColor)?.stringValue) ??
            (isSurface ? Color.secondary.opacity(0.35) : .clear)
        let castsShadow = model.kind == .panel &&
            model.property(.background)?.stringValue != "transparent"

        content
            .padding(.horizontal, CGFloat(horizontal))
            .padding(.vertical, CGFloat(vertical))
            .frame(
                width: model.surfaceWidth.map(CGFloat.init),
                height: model.surfaceHeight.map(CGFloat.init)
            )
            .frame(
                minWidth: model.surfaceMinWidth.map(CGFloat.init),
                maxWidth: model.surfaceMaxWidth.map(CGFloat.init),
                minHeight: model.surfaceMinHeight.map(CGFloat.init),
                maxHeight: model.surfaceMaxHeight.map(CGFloat.init)
            )
            .foregroundStyle(color(model.property(.foreground)?.stringValue) ?? .primary)
            .background(background, in: shape)
            .shadow(
                color: castsShadow ? .black.opacity(0.12) : .clear,
                radius: castsShadow ? 4 : 0,
                y: castsShadow ? 2 : 0
            )
            .overlay {
                shape.stroke(
                    border,
                    lineWidth: borderWidth
                )
            }
            .clipShape(shape)
    }

    private func color(_ name: String?) -> Color? {
        switch name?.lowercased() {
        case nil: nil
        case "transparent": .clear
        case "background": systemBackground
        case "foreground": .primary
        case "primary": .accentColor
        case "primary-foreground": .white
        case "secondary": .secondary.opacity(0.15)
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
        default: .clear
        }
    }

    private var systemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

private struct LUIAccessibilityModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    func body(content: Content) -> some View {
        let label = model.accessibilityLabel(in: backend)
        let hint = model.accessibilityHint(in: backend)
        if let label, let hint {
            content
                .accessibilityLabel(Text(label))
                .accessibilityHint(Text(hint))
        } else if let label {
            content.accessibilityLabel(Text(label))
        } else if let hint {
            content.accessibilityHint(Text(hint))
        } else {
            content
        }
    }
}
