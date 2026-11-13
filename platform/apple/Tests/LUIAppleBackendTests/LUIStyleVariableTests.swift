import Testing
@testable import LUIAppleBackend

struct LUIStyleVariableTests {
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
