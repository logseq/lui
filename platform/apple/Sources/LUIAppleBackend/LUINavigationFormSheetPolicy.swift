import SwiftUI

enum LUINavigationFormActionPlacement: Equatable {
    case cancellation
    case confirmation
}

enum LUINavigationFormSheetPolicy {
    static func isNavigationForm(_ styleClass: String?) -> Bool {
        hasStyle("navigation-form", in: styleClass)
    }

    static func isNavigationScroll(_ styleClass: String?) -> Bool {
        hasStyle("navigation-scroll", in: styleClass)
    }

    static func isNavigationList(_ styleClass: String?) -> Bool {
        hasStyle("navigation-list", in: styleClass)
    }

    static func isNavigationContent(_ styleClass: String?) -> Bool {
        hasStyle("navigation-content", in: styleClass)
    }

    static func isForm(_ styleClass: String?) -> Bool {
        hasStyle("form", in: styleClass)
    }

    static func usesInlineTitle(_ styleClass: String?) -> Bool {
        hasStyle("navigation-inline-title", in: styleClass)
    }

    static func usesNavigationBackIcon(_ styleClass: String?) -> Bool {
        hasStyle("navigation-back-action", in: styleClass)
    }

    static func actionPlacement(
        _ styleClass: String?
    ) -> LUINavigationFormActionPlacement? {
        if hasStyle("cancellation-action", in: styleClass) {
            return .cancellation
        }
        if hasStyle("confirmation-action", in: styleClass) {
            return .confirmation
        }
        return nil
    }

    private static func hasStyle(_ target: String, in styleClass: String?) -> Bool {
        guard let styleClass else { return false }
        return styleClass.split(separator: " ").contains { String($0) == target }
    }
}

enum LUINavigationFormRowPolicy {
    static func usesAutomaticButtonStyle(
        isNativeFormRow: Bool,
        variant: String
    ) -> Bool {
        isNativeFormRow && (variant.isEmpty || variant == "default")
    }

    static func usesBorderlessButtonStyle(
        isNativeListRow: Bool,
        variant: String
    ) -> Bool {
        isNativeListRow && variant == "ghost"
    }
}

struct LUINavigationFormTitleStyle: ViewModifier {
    let styleClass: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if LUINavigationFormSheetPolicy.usesInlineTitle(styleClass) {
            content.navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct LUINavigationFormActionView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    var body: some View {
        let _ = model.revision
        actionButton
        .disabled(!model.isEnabled)
        .foregroundStyle(model.isEnabled ? Color.primary : Color.secondary)
        .accessibilityIdentifier(
            model.property(.accessibilityIdentifier)?.stringValue ?? ""
        )
        .accessibilityLabel(
            Text(verbatim: model.property(.accessibilityLabel)?.stringValue ?? model.text)
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        #if SKIP
        Button(action: performPress) {
            actionLabel
        }
        #else
        Button(action: {}) {
            actionLabel
        }
        .highPriorityGesture(TapGesture().onEnded(performPress))
        .accessibilityElement(children: .ignore)
        #endif
    }

    @ViewBuilder
    private var actionLabel: some View {
        if LUINavigationFormSheetPolicy.usesNavigationBackIcon(
            model.property(.styleClass)?.stringValue
        ) {
            #if SKIP
            Text(verbatim: "‹")
            #else
            Image(systemName: "chevron.backward")
            #endif
        } else {
            Text(verbatim: model.text)
        }
    }

    private func performPress() {
        guard model.isEnabled else { return }
        try? backend.performPress(node: model.id)
    }
}
