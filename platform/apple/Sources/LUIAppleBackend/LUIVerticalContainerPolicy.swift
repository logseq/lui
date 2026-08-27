enum LUIVerticalContainerPolicy {
    static func isLazy(kind: LUINodeKind) -> Bool {
        kind == .list
    }

    static func stretchesCrossAxis(_ cross: String?) -> Bool {
        cross == nil || cross == "stretch"
    }

    static func usesIntrinsicHeight(kind: LUINodeKind) -> Bool {
        kind == .alert
    }
}

enum LUIExplicitFramePolicy {
    static func width(kind: LUINodeKind, requested: Int?) -> Int? {
        switch kind {
        case .drawer, .resizable:
            nil
        default:
            requested
        }
    }
}
