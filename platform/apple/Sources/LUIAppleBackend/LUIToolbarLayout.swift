enum LUIToolbarAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

struct LUIToolbarLayout: Equatable, Sendable {
    let axis: LUIToolbarAxis
    let scrollingChildIDs: [Int]
    let fixedChildID: Int?
}

enum LUIToolbarLayoutPolicy {
    static func layout(
        orientation: String?,
        styleClass: String?,
        childIDs: [Int]
    ) -> LUIToolbarLayout {
        guard orientation != "vertical" else {
            return LUIToolbarLayout(
                axis: .vertical,
                scrollingChildIDs: [],
                fixedChildID: nil
            )
        }
        if hasStyle("scroll", in: styleClass) {
            return LUIToolbarLayout(
                axis: .horizontal,
                scrollingChildIDs: childIDs,
                fixedChildID: nil
            )
        }
        guard hasStyle("scroll-leading", in: styleClass),
              let fixedChildID = childIDs.last else {
            return LUIToolbarLayout(
                axis: .horizontal,
                scrollingChildIDs: [],
                fixedChildID: nil
            )
        }
        var scrollingChildIDs: [Int] = []
        for index in 0..<(childIDs.count - 1) {
            scrollingChildIDs.append(childIDs[index])
        }
        return LUIToolbarLayout(
            axis: .horizontal,
            scrollingChildIDs: scrollingChildIDs,
            fixedChildID: fixedChildID
        )
    }

    private static func hasStyle(_ target: String, in styleClass: String?) -> Bool {
        guard let styleClass else { return false }
        return styleClass.split(separator: " ").contains { String($0) == target }
    }
}
