import SwiftUI

private struct LUISemanticColorsKey: EnvironmentKey {
    static let defaultValue: [String: Color] = [:]
}

extension EnvironmentValues {
    var luiSemanticColors: [String: Color] {
        get { self[LUISemanticColorsKey.self] }
        set { self[LUISemanticColorsKey.self] = newValue }
    }
}

public extension View {
    func luiSemanticColors(_ colors: [String: Color]) -> some View {
        environment(
            \.luiSemanticColors,
            Dictionary(uniqueKeysWithValues: colors.map { key, value in
                (key.lowercased(), value)
            })
        )
    }
}

enum LUIThemeColorPolicy {
    static func menuItemForegroundName(
        explicit: String?,
        destructive: Bool
    ) -> String {
        if destructive {
            return "red"
        }
        return explicit ?? "foreground"
    }

    static func menuItemTextForegroundName(destructive: Bool) -> String {
        destructive ? "red" : "foreground"
    }

    static func isMutedForeground(_ name: String?) -> Bool {
        name?.lowercased() == "muted-foreground"
    }

    static func isAccentForeground(_ name: String?) -> Bool {
        name?.lowercased() == "accent"
    }

    static func isSecondaryForeground(_ name: String?) -> Bool {
        name?.lowercased() == "secondary"
    }

    static func usesDefaultForeground(kind: LUINodeKind) -> Bool {
        switch kind {
        case .panel, .card, .resizable, .alert, .bubble:
            true
        default:
            false
        }
    }
}

enum LUIDropdownMenuLayoutPolicy {
    static let contentPadding: CGFloat = 12
    static let contentSpacing: CGFloat = 4
    static let itemSpacing: CGFloat = 12
    static let iconSize: CGFloat = 24
    static let itemMinimumHeight: CGFloat = 40
    static let trailingSpacing: CGFloat = 16
}

enum LUIModalBackgroundPolicy {
    static func color(
        semanticColors: [String: Color],
        systemBackground: Color
    ) -> Color {
        semanticColors["background"] ?? systemBackground
    }

    static func usesGroupedSystemBackground(styleClass: String?) -> Bool {
        styleClass?.split(separator: " ").contains("navigation-list") == true
    }
}

enum LUIHeadingTypography {
    static func isBold(level: Int) -> Bool {
        (1...6).contains(level)
    }
}

enum LUIAccessibilityPolicy {
    static func shouldContainChildren(hasChildren: Bool, identifier: String?) -> Bool {
        hasChildren && identifier != nil
    }
}
