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

/// Inherited typography overrides — the `font-*`, `line-height`,
/// `letter-spacing` and `text-decoration` props, mirroring the CSS-typed
/// web props. nil fields leave the inherited value untouched so a node
/// only replaces the facets it sets; merging is child-wins per field.
struct LUITypographySpec: Equatable {
    var fontSize: CGFloat?
    var fontWeight: Int?
    var italic: Bool?
    var fontFamily: String?
    /// Absolute line height in points.
    var lineHeight: CGFloat?
    /// Unitless `line-height` multiplier (CSS semantics).
    var lineHeightFactor: CGFloat?
    var letterSpacing: CGFloat?
    var underline: Bool?
    var strikethrough: Bool?

    init() {}

    var isEmpty: Bool {
        fontSize == nil && fontWeight == nil && italic == nil &&
            fontFamily == nil && lineHeight == nil &&
            lineHeightFactor == nil && letterSpacing == nil &&
            underline == nil && strikethrough == nil
    }

    func merged(with own: LUITypographySpec) -> LUITypographySpec {
        var result = self
        if let value = own.fontSize { result.fontSize = value }
        if let value = own.fontWeight { result.fontWeight = value }
        if let value = own.italic { result.italic = value }
        if let value = own.fontFamily { result.fontFamily = value }
        if let value = own.lineHeight { result.lineHeight = value }
        if let value = own.lineHeightFactor { result.lineHeightFactor = value }
        if let value = own.letterSpacing { result.letterSpacing = value }
        if let value = own.underline { result.underline = value }
        if let value = own.strikethrough { result.strikethrough = value }
        return result
    }

    private static func cssLength(_ raw: String) -> (value: Double, unit: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        var end = trimmed.startIndex
        while end < trimmed.endIndex {
            let c = trimmed[end]
            if c.isNumber || c == "." || c == "-" || c == "+" {
                end = trimmed.index(after: end)
            } else {
                break
            }
        }
        guard end > trimmed.startIndex,
              let value = Double(trimmed[..<end])
        else { return nil }
        return (value, String(trimmed[end...]))
    }

    /// px/pt/unitless resolve to points; em/rem scale the 17pt body
    /// default both mobile hosts share.
    private static func points(_ raw: String) -> CGFloat? {
        guard let (value, unit) = cssLength(raw) else { return nil }
        return switch unit {
        case "", "px", "pt", "sp": CGFloat(value)
        case "em", "rem": CGFloat(value * 17)
        default: nil
        }
    }

    /// First family in the CSS list wins; generic keywords map to the
    /// system designs, anything else resolves as an installed face name.
    private static func familyName(_ raw: String?) -> String? {
        guard let raw,
              let first = raw.split(separator: ",").first
        else { return nil }
        let name = first.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return name.isEmpty ? nil : name
    }

    static func isMonospaced(_ name: String) -> Bool {
        switch name.lowercased() {
        case "monospace", "ui-monospace": true
        default: false
        }
    }

    static func isSerif(_ name: String) -> Bool {
        switch name.lowercased() {
        case "serif", "ui-serif": true
        default: false
        }
    }

    static func isSystemFamily(_ name: String) -> Bool {
        switch name.lowercased() {
        case "system-ui", "-apple-system", "sans-serif", "ui-sans-serif": true
        default: false
        }
    }

    /// CSS numeric weight (1...1000) to the nearest SwiftUI step.
    static func weight(_ css: Int) -> Font.Weight {
        switch css {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }

    /// Applies size/family/weight over a base font. Family without an
    /// explicit size resolves at the 17pt body default — `Font` carries
    /// no readable point size to preserve.
    func font(base: Font) -> Font {
        var result = base
        if let fontFamily {
            let design: Font.Design =
                if Self.isMonospaced(fontFamily) { .monospaced }
                else if Self.isSerif(fontFamily) { .serif }
                else if Self.isSystemFamily(fontFamily) { .default }
                else { .default }
            result = if Self.isSystemFamily(fontFamily) ||
                Self.isMonospaced(fontFamily) || Self.isSerif(fontFamily)
            {
                if let fontSize {
                    Font.system(size: fontSize, design: design)
                } else {
                    Font.system(.body, design: design)
                }
            } else {
                Font.custom(fontFamily, size: fontSize ?? 17)
            }
        } else if let fontSize {
            result = Font.system(size: fontSize)
        }
        if let fontWeight {
            result = result.weight(Self.weight(fontWeight))
        }
        return result
    }

    /// Extra leading for `lineSpacing`: absolute heights subtract the
    /// effective font size, multipliers scale it.
    func lineSpacing(baseSize: CGFloat) -> CGFloat {
        let size = fontSize ?? baseSize
        if let lineHeight { return max(0, lineHeight - size) }
        if let lineHeightFactor { return size * (lineHeightFactor - 1) }
        return 0
    }
}

extension LUITypographySpec {
    /// Typography delta contributed by a node's own props; merged over
    /// the inherited spec in `LUIThemeScopeModifier`. Parsed once per
    /// commit into `LUINodeModel.derived`.
    init(properties: [LUIProperty: LUIWireValue]) {
        self.init()
        if let raw = properties[.fontSize]?.stringValue {
            fontSize = Self.points(raw)
        }
        fontWeight = properties[.fontWeight]?.intValue
        italic = properties[.fontStyle]?.stringValue.map { $0 != "normal" }
        fontFamily = Self.familyName(properties[.fontFamily]?.stringValue)
        if let raw = properties[.lineHeight]?.stringValue,
           let (value, unit) = Self.cssLength(raw)
        {
            switch unit {
            case "", "em", "rem": lineHeightFactor = CGFloat(value)
            default: lineHeight = CGFloat(value)
            }
        }
        letterSpacing = properties[.letterSpacing]?.doubleValue.map { CGFloat($0) }
        if let raw = properties[.textDecoration]?.stringValue {
            let tokens = raw.split(separator: " ")
            underline = tokens.contains("underline")
            strikethrough = tokens.contains("line-through")
        }
    }
}

extension Text {
    /// Text-level decorations (`italic`/`underline`/`strikethrough`)
    /// from the inherited spec.
    func luiTypography(_ spec: LUITypographySpec) -> Text {
        var text = self
        if spec.italic == true { text = text.italic() }
        if spec.underline == true { text = text.underline() }
        if spec.strikethrough == true { text = text.strikethrough() }
        return text
    }
}

extension View {
    /// Metrics (`letter-spacing`/`line-height`) from the inherited spec.
    /// [baseSize] is the font size the leaf would use without overrides.
    func luiTypographyMetrics(_ spec: LUITypographySpec, baseSize: CGFloat) -> some View {
        tracking(spec.letterSpacing ?? 0)
            .lineSpacing(spec.lineSpacing(baseSize: baseSize))
    }
}

private struct LUITypographyKey: EnvironmentKey {
    static let defaultValue = LUITypographySpec()
}

extension EnvironmentValues {
    var luiTypography: LUITypographySpec {
        get { self[LUITypographyKey.self] }
        set { self[LUITypographyKey.self] = newValue }
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
        case "destructive": .red
        case "destructive-foreground": .white
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
        // Sheets and dialogs are elevated: they sit on the `surface` token,
        // matching the Material `colorScheme.surface` modal default.
        semanticColors["surface"] ?? semanticColors["background"] ?? systemBackground
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
    /// Parses the `theme` wire prop into per-mode semantic-color entries.
    /// A token value is either a color string used in both modes or a
    /// `{"light": ..., "dark": ...}` object picked by mode. Entries that do
    /// not decode to a color in either mode are ignored so non-color
    /// tokens can join the table later without breaking hosts.
    static func tokens(_ json: String?) -> [String: LUIThemeModeColors] {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { return [:] }
        var tokens: [String: LUIThemeModeColors] = [:]
        for (key, value) in dict {
            let light: Color?
            let dark: Color?
            if let string = value as? String {
                light = luiHexColor(string)
                dark = light
            } else if let modes = value as? [String: Any] {
                light = (modes["light"] as? String).flatMap(luiHexColor)
                dark = (modes["dark"] as? String).flatMap(luiHexColor)
            } else {
                continue
            }
            guard light != nil || dark != nil else { continue }
            tokens[key.lowercased()] = LUIThemeModeColors(light: light, dark: dark)
        }
        return tokens
    }

    /// Semantic-color entries for one appearance mode; call sites that
    /// evaluate per frame should prefer the commit-decoded
    /// `LUIThemeScopeContribution` instead.
    static func colors(_ json: String?, dark: Bool) -> [String: Color] {
        tokens(json).compactMapValues { dark ? $0.dark : $0.light }
    }

    static func colorScheme(_ value: String?) -> ColorScheme? {
        switch value {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}

/// Per-mode value of a decoded `theme` token: a plain color string fills
/// both modes, a `{"light": ..., "dark": ...}` object fills each side.
struct LUIThemeModeColors: Equatable {
    var light: Color?
    var dark: Color?
}

/// A node's `theme`/`theme-mode`/typography contribution to the scoped
/// environment, decoded once per commit on `LUINodeModel` so
/// `LUIThemeScopeModifier` only picks a color-scheme entry per evaluation.
struct LUIThemeScopeContribution: Equatable {
    /// Decoded `theme` tokens; entries without a decodable color in either
    /// mode are absent.
    var tokens: [String: LUIThemeModeColors] = [:]
    /// `theme-mode` override, if any.
    var scheme: ColorScheme?
    /// `font-*`/`line-height`/`letter-spacing`/`text-decoration` props.
    var typography = LUITypographySpec()

    /// Whether the node contributes anything to the scope — gates
    /// mounting `LUIThemeScopeModifier` and its environment reads.
    var applies: Bool {
        !tokens.isEmpty || scheme != nil || !typography.isEmpty
    }

    /// Semantic-color entries for one appearance mode, matching the
    /// per-eval `LUIThemeTokenDecoder.colors(_:dark:)` selection.
    func colors(dark: Bool) -> [String: Color] {
        tokens.compactMapValues { dark ? $0.dark : $0.light }
    }
}

/// Applies a node's `theme`/`theme-mode` props: merges decoded tokens over
/// the inherited `luiSemanticColors` environment and optionally overrides
/// the subtree appearance.
struct LUIThemeScopeModifier: ViewModifier {
    let model: LUINodeModel
    @Environment(\.luiSemanticColors) private var inheritedColors
    @Environment(\.luiTypography) private var inheritedTypography
    @Environment(\.colorScheme) private var systemScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let scope = model.derived.themeScope
        let ownColors = scope.colors(
            dark: (scope.scheme ?? systemScheme) == .dark
        )
        if ownColors.isEmpty && scope.scheme == nil && scope.typography.isEmpty {
            content
        } else {
            content
                .environment(
                    \.luiSemanticColors,
                    inheritedColors.merging(ownColors) { _, new in new }
                )
                .environment(
                    \.luiTypography,
                    inheritedTypography.merged(with: scope.typography)
                )
                .preferredColorScheme(scope.scheme)
        }
    }
}
