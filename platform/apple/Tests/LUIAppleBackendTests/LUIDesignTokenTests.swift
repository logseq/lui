import Testing
import SwiftUI
@testable import LUIAppleBackend

struct LUIDesignTokenTests {
    @Test("Canonical colors and foreground counterparts resolve")
    func colors() {
        let names = ["background", "surface", "surface-raised", "card", "foreground",
                     "muted-foreground", "primary", "secondary", "accent", "muted",
                     "destructive", "warning", "success", "info", "border", "input",
                     "ring", "glass", "bar", "transparent"]
        for name in names {
            #expect(LUIThemeColorResolver.color(name, semanticColors: [:]) != nil)
            #expect(LUIThemeColorResolver.color(name, semanticColors: [:], foreground: true) != nil)
        }
        #expect(LUIThemeColorResolver.color("secondary", semanticColors: [:], foreground: true) == .primary)
        #expect(LUIThemeColorResolver.color("secondary", semanticColors: ["secondary-foreground": .red], foreground: true) == .red)
        #expect(LUIThemeColorResolver.color("unknown", semanticColors: [:]) == nil)
    }

    @Test("Typography roles preserve legacy aliases and metrics")
    func typography() {
        #expect(LUIDesignTokens.role(in: ["title2"]) == "title")
        #expect(LUIDesignTokens.role(in: []) == "body")
        #expect(LUIDesignTokens.role(in: ["headline", "semibold"]) == "headline")
        #expect(LUIDesignTokens.textRoles["caption"] == .caption)
        #expect(LUIDesignTokens.spaces["none"] == 0)
        #expect(LUIDesignTokens.radii["full"] == 9999)
        #expect(LUITextLinePolicy.lineLimit(styleClass: "caption single-line") == 1)
        #expect(LUITextLinePolicy.lineLimit(styleClass: "not-single-line") == nil)
    }

    @Test("Themed secondary foreground overrides hierarchical styling")
    func themedSecondaryForeground() {
        #expect(LUIThemeColorPolicy.usesSecondaryStyle("secondary", semanticColors: [:]))
        #expect(!LUIThemeColorPolicy.usesSecondaryStyle("secondary",
            semanticColors: ["secondary-foreground": .red]))
        #expect(LUIThemeColorResolver.color("secondary",
            semanticColors: ["secondary-foreground": .red], foreground: true) == .red)
        #expect(LUIThemeColorPolicy.usesSecondaryStyle("secondary",
            semanticColors: ["muted-foreground": .red]))
        #expect(LUIThemeColorPolicy.usesSecondaryStyle("muted-foreground", semanticColors: [:]))
        #expect(!LUIThemeColorPolicy.usesSecondaryStyle("muted-foreground",
            semanticColors: ["muted-foreground": .red]))
        #expect(!LUIThemeColorPolicy.usesSecondaryStyle(nil, semanticColors: [:]))
        #expect(!LUIThemeColorPolicy.usesSecondaryStyle("foreground", semanticColors: [:]))
    }
}
