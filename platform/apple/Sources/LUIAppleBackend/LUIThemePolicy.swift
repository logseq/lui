enum LUIThemeColorPolicy {
    static func isMutedForeground(_ name: String?) -> Bool {
        name?.lowercased() == "muted-foreground"
    }
}

enum LUIHeadingTypography {
    static func isBold(level: Int) -> Bool {
        level == 1
    }
}
