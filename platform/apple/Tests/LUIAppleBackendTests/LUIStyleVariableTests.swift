import Testing
import SwiftUI
@testable import LUIAppleBackend

struct LUIStyleVariableTests {
    @Test("Semantic color variables preserve override and nested fallback precedence")
    func semanticColorVariables() {
        let cases: [(String, [String: Color], Color?)] = [
            ("var(--caret, var(--ink))", ["--ink": .blue], .blue),
            ("var(--caret, var(--ink))", ["var(--ink)": .blue], .blue),
            ("var(--caret, var(--ink))", ["--caret": .green, "--ink": .blue], .green),
            ("var(--caret, var(--ink))", ["var(--caret, var(--ink))": .red, "--ink": .blue], .red),
            ("var(--caret, #1234)", [:], luiHexColor("#1234")),
            ("hsl(var(--border))", [:], .secondary.opacity(0.35)),
            ("hsl(var(--border))", ["border": .blue], .blue),
            ("hsl(var(--border))", ["--border": .green, "border": .blue], .green),
            ("var(--lui-border)", ["--lui-border": .red], .red),
            ("var(--missing, var(--border, #ff0000))", [:], .secondary.opacity(0.35)),
            ("var(--missing, hsl(var(--border)))", [:], .secondary.opacity(0.35)),
            ("var(--missing, #ff0000)", [:], luiHexColor("#ff0000")),
            ("hsl(0, 100%, 50%)", [:], nil),
            ("hsl(border)", [:], nil),
            ("var(--missing, hsl(border))", [:], nil),
            ("var(--abcdef)", [:], nil),
            ("var(--missing)", [:], nil),
            ("var(--missing", [:], nil)
        ]
        for (raw, colors, expected) in cases {
            #expect(LUIThemeColorResolver.color(raw, semanticColors: colors) == expected)
        }
    }

    @Test("Typography variable chains, fallbacks and cycles preserve inherited values")
    func typographyVariables() {
        let cases: [(String, [String: String], Double?)] = [
            ("36px", [:], 36),
            ("var(--title, 32px)", [:], 32),
            ("var(--title, 32px)", ["--title": "36px"], 36),
            ("var(--title)", ["--title": "var(--base)", "--base": "36px"], 36),
            ("var(--title, var(--base, 32px))", ["--base": "30px"], 30),
            ("var(--title)", [:], nil),
            ("var(--title, 32px)", ["--title": "var(--title)"], 32),
            ("var(--a, 32px)", ["--a": "var(--b, 20px)", "--b": "var(--a, 40px)"], 32),
            ("var(--title", [:], nil)
        ]
        var inherited = LUITypographySpec()
        inherited.fontSize = 17
        inherited.fontWeight = 500
        for (raw, variables, expected) in cases {
            let own = LUITypographySpec(properties: [.fontSize: .string(raw)])
                .resolving(variables: variables)
            #expect(own.fontSize.map(Double.init) == expected)
            let merged = inherited.merged(with: own)
            #expect(merged.fontSize.map(Double.init) == (expected ?? 17))
            #expect(merged.fontWeight == 500)
        }
    }
}
