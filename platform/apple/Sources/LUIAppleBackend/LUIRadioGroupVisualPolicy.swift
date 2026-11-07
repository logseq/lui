enum LUIRadioGroupVisualPolicy {
    static func usesMenuStyle(_ styleClass: String?) -> Bool {
        styleClass?.split(separator: " ").contains("menu") == true
    }

    static func usesSegmentedStyle(_ styleClass: String?) -> Bool {
        styleClass?.split(separator: " ").contains("segmented") == true
    }

    static func displayText(explicit: String, selected: String?) -> String {
        explicit.isEmpty ? (selected ?? "") : explicit
    }
}
