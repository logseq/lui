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
            HStack(spacing: CGFloat(model.property(.gap)?.intValue ?? 0)) {
                children
            }
        case .column, .box:
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
            Button(model.text) {
                try? backend.performPress(node: model.id)
            }
            .disabled(!model.isEnabled)
        case .textInput:
            LUITextControlView(model: model, backend: backend, multiline: false)
        case .textArea:
            LUITextControlView(model: model, backend: backend, multiline: true)
        case .checkbox:
            LUICheckboxView(model: model, backend: backend)
        case .switchControl:
            Toggle(
                "",
                isOn: Binding(
                    get: { model.isChecked },
                    set: { try? backend.performToggle(node: model.id, checked: $0) }
                )
            )
            .labelsHidden()
            .disabled(!model.isEnabled)
        case .progress:
            ProgressView(value: model.progressFraction)
                .accessibilityValue(Text(progressAccessibilityValue))
        case .divider:
            LUISeparatorView(model: model)
        case .scroll:
            ScrollView {
                children
            }
        case .spacer:
            Spacer()
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
            "",
            isOn: Binding(
                get: { model.isChecked },
                set: { try? backend.performToggle(node: model.id, checked: $0) }
            )
        )
        .toggleStyle(.checkbox)
        .labelsHidden()
        .disabled(!model.isEnabled)
        #else
        Button {
            try? backend.performToggle(
                node: model.id,
                checked: model.isIndeterminate || !model.isChecked
            )
        } label: {
            Image(systemName: checkboxImageName)
        }
        .buttonStyle(.plain)
        .disabled(!model.isEnabled)
        .accessibilityValue(
            Text(model.isIndeterminate ? "mixed" : (model.isChecked ? "1" : "0"))
        )
        #endif
    }

    private var checkboxImageName: String {
        if model.isIndeterminate { return "minus.square.fill" }
        return model.isChecked ? "checkmark.square.fill" : "square"
    }
}

private struct LUISurfaceModifier: ViewModifier {
    let model: LUINodeModel

    func body(content: Content) -> some View {
        let padding = model.property(.padding)?.intValue ?? 0
        let horizontal = model.property(.paddingHorizontal)?.intValue ?? padding
        let vertical = model.property(.paddingVertical)?.intValue ?? padding
        let radius = CGFloat(model.property(.cornerRadius)?.intValue ?? 0)
        let borderWidth = CGFloat(model.property(.borderWidth)?.intValue ?? 0)
        let shape = RoundedRectangle(cornerRadius: radius)

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
            .background(
                color(model.property(.background)?.stringValue) ?? .clear,
                in: shape
            )
            .overlay {
                shape.stroke(
                    color(model.property(.borderColor)?.stringValue) ?? .clear,
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
