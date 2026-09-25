import SwiftUI

private struct LUISemanticColorsKey: EnvironmentKey {
    static let defaultValue: [String: Color] = [:]
}

public extension EnvironmentValues {
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

extension View {
    /// Sheets present in a separate window, so the scoped theme environment
    /// does not reach them; re-apply the ambient colors and effective scheme
    /// captured at the presentation site.
    func luiSheetScope(semanticColors: [String: Color], colorScheme: ColorScheme)
        -> some View
    {
        environment(\.luiSemanticColors, semanticColors)
            .preferredColorScheme(colorScheme)
    }
}

// Shared hex resolver for views that style themselves from color-name props
// (avatar background/foreground) and theme tokens. Accepts #rgb, #rrggbb and
// #rrggbbaa (CSS alpha-suffix). Returns nil for non-hex names.
func luiHexColor(_ name: String) -> Color? {
    var value = name.hasPrefix("#") ? String(name.dropFirst()) : name
    if value.count == 3 || value.count == 4 {
        value = value.map { "\($0)\($0)" }.joined()
    }
    guard value.count == 6 || value.count == 8,
          let rgba = UInt64(value, radix: 16)
    else { return nil }
    let rgb = rgba >> (value.count == 8 ? 8 : 0)
    return Color(
        red: Double((rgb >> 16) & 0xff) / 255.0,
        green: Double((rgb >> 8) & 0xff) / 255.0,
        blue: Double(rgb & 0xff) / 255.0,
        opacity: value.count == 8 ? Double(rgba & 0xff) / 255.0 : 1.0
    )
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

enum LUIThemeColorResolver {
    static func color(_ name: String?, semanticColors: [String: Color]) -> Color? {
        if let name, let semanticColor = semanticColors[name.lowercased()] {
            return semanticColor
        }
        if LUIThemeColorPolicy.isMutedForeground(name) {
            return .secondary
        }
        if LUIThemeColorPolicy.isAccentForeground(name) {
            return .accentColor
        }
        if let name, let hex = luiHexColor(name) {
            return hex
        }
        return switch name?.lowercased() {
        case nil: nil
        case "transparent": .clear
        case "background": systemBackground
        case "foreground": .primary
        case "primary": .accentColor
        case "primary-foreground": .white
        case "secondary": .secondary.opacity(0.15)
        case "glass-fallback": .clear
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

    static var systemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
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

enum LUIThemeTokenDecoder {
    /// Parses the `theme` wire prop into semantic-color entries the
    /// resolver consults before platform defaults. A token value is either
    /// a color string used in both modes or a `{"light": ..., "dark": ...}`
    /// object picked by `dark`. Entries that do not decode to a color are
    /// ignored so non-color tokens can join the table later without
    /// breaking hosts.
    static func colors(_ json: String?, dark: Bool) -> [String: Color] {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { return [:] }
        var colors: [String: Color] = [:]
        for (key, value) in dict {
            let raw: String?
            if let string = value as? String {
                raw = string
            } else if let modes = value as? [String: Any] {
                raw = modes[dark ? "dark" : "light"] as? String
            } else {
                raw = nil
            }
            guard let raw, let color = luiHexColor(raw) else { continue }
            colors[key.lowercased()] = color
        }
        return colors
    }

    static func colorScheme(_ value: String?) -> ColorScheme? {
        switch value {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}

/// Applies a node's `theme`/`theme-mode` props: merges decoded tokens over
/// the inherited `luiSemanticColors` environment and optionally overrides
/// the subtree appearance.
struct LUIThemeScopeModifier: ViewModifier {
    let model: LUINodeModel
    @Environment(\.luiSemanticColors) private var inheritedColors
    @Environment(\.colorScheme) private var systemScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let scheme = LUIThemeTokenDecoder.colorScheme(
            model.property(.themeMode)?.stringValue
        )
        let ownColors = LUIThemeTokenDecoder.colors(
            model.property(.theme)?.stringValue,
            dark: (scheme ?? systemScheme) == .dark
        )
        if ownColors.isEmpty && scheme == nil {
            content
        } else {
            content
                .environment(
                    \.luiSemanticColors,
                    inheritedColors.merging(ownColors) { _, new in new }
                )
                .preferredColorScheme(scheme)
        }
    }
}
