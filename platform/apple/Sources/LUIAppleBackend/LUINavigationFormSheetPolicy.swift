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

    static func isForm(_ styleClass: String?) -> Bool {
        hasStyle("form", in: styleClass)
    }

    static func usesInlineTitle(_ styleClass: String?) -> Bool {
        isNavigationForm(styleClass) || isNavigationScroll(styleClass)
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
            Text(verbatim: model.text)
        }
        #else
        Button(action: {}) {
            Text(verbatim: model.text)
        }
        .highPriorityGesture(TapGesture().onEnded(performPress))
        .accessibilityElement(children: .ignore)
        #endif
    }

    private func performPress() {
        guard model.isEnabled else { return }
        try? backend.performPress(node: model.id)
    }
}
