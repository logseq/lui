enum LUIVerticalContainerPolicy {
    static func isLazy(kind: LUINodeKind) -> Bool {
        kind == .list
    }
}
