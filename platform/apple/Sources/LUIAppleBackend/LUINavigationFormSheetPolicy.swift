enum LUINavigationFormActionPlacement: Equatable {
    case cancellation
    case confirmation
}

enum LUINavigationFormSheetPolicy {
    static func isNavigationForm(_ styleClass: String?) -> Bool {
        hasStyle("navigation-form", in: styleClass)
    }

    static func isForm(_ styleClass: String?) -> Bool {
        hasStyle("form", in: styleClass)
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
