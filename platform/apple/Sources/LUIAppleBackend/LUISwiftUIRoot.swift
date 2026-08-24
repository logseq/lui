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

    var body: some View {
        let _ = model.revision
        content
            .modifier(LUISurfaceModifier(model: model))
            .modifier(LUIAccessibilityModifier(model: model, backend: backend))
    }

    @ViewBuilder
    private var content: some View {
        switch model.kind {
        case .row:
            LUIRowView(model: model, backend: backend)
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
            Text(verbatim: model.text)
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
        case .textInput:
            LUITextControlView(model: model, backend: backend, multiline: false)
        case .textArea:
            LUITextControlView(model: model, backend: backend, multiline: true)
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

private struct LUIButtonView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @FocusState private var focused: Bool
    @State private var held = false

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
            .modifier(LUISelectedButtonModifier(selected: model.isSelected))
    }

    @ViewBuilder
    private var styledButton: some View {
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

    private var button: some View {
        Button {
            if held {
                held = false
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
    let multiline: Bool
    @State private var draft: String

    init(model: LUINodeModel, backend: LUIAppleBackend, multiline: Bool) {
        self.model = model
        self.backend = backend
        self.multiline = multiline
        _draft = State(initialValue: model.text)
    }

    var body: some View {
        field
            .disabled(!model.isEnabled || model.isReadOnly)
            .onChange(of: model.text) { _, next in
                if draft != next {
                    draft = next
                }
            }
    }

    @ViewBuilder
    private var field: some View {
        if multiline {
            multilineField
        } else if model.property(.inputType)?.stringValue == "password" {
            SecureField(model.property(.placeholder)?.stringValue ?? "", text: binding)
        } else {
            TextField(model.property(.placeholder)?.stringValue ?? "", text: binding)
        }
    }

    @ViewBuilder
    private var multilineField: some View {
        let minimum = model.property(.minLines)?.intValue ?? 2
        let maximum = model.property(.maxLines)?.intValue
        if let maximum {
            TextField(
                model.property(.placeholder)?.stringValue ?? "",
                text: binding,
                axis: .vertical
            )
            .lineLimit(minimum...maximum)
        } else {
            TextField(
                model.property(.placeholder)?.stringValue ?? "",
                text: binding,
                axis: .vertical
            )
            .lineLimit(minimum...)
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
        let padding = model.property(.padding)?.intValue ?? (model.kind == .card ? 24 : 0)
        let horizontal = model.property(.paddingHorizontal)?.intValue ?? padding
        let vertical = model.property(.paddingVertical)?.intValue ?? padding
        let radius = CGFloat(model.property(.cornerRadius)?.intValue ?? (isSurface ? 12 : 0))
        let borderWidth = CGFloat(model.property(.borderWidth)?.intValue ?? (isSurface ? 1 : 0))
        let shape = RoundedRectangle(cornerRadius: radius)
        let background = color(model.property(.background)?.stringValue) ??
            (isSurface ? systemBackground : .clear)
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
