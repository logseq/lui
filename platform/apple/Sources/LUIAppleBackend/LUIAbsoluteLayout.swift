import SwiftUI

/// Physical edge offsets for an absolute child. Kept in commit-decoded child
/// layout data so a property change also invalidates its positioning parent.
struct LUIAbsoluteInsets: Equatable {
    let top: CGFloat?
    let right: CGFloat?
    let bottom: CGFloat?
    let left: CGFloat?
    let stretchesWidth: Bool
    let stretchesHeight: Bool

    init?(properties: [LUIProperty: LUIWireValue]) {
        guard properties[.position]?.stringValue == "absolute" else { return nil }
        let inset = properties[.inset]?.doubleValue.map { CGFloat($0) }
        top = properties[.insetTop]?.doubleValue.map { CGFloat($0) } ?? inset
        right = properties[.insetRight]?.doubleValue.map { CGFloat($0) } ?? inset
        bottom = properties[.insetBottom]?.doubleValue.map { CGFloat($0) } ?? inset
        left = properties[.insetLeft]?.doubleValue.map { CGFloat($0) } ?? inset
        stretchesWidth = left != nil && right != nil && properties[.width]?.doubleValue == nil
        stretchesHeight = top != nil && bottom != nil && properties[.height]?.doubleValue == nil
    }
}

struct LUIAbsoluteInsetsKey: LayoutValueKey {
    static let defaultValue: LUIAbsoluteInsets? = nil
}

private struct LUIPositionedChildKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    /// Only the direct child stretches its surface; descendants retain their
    /// own sizing, backgrounds and committed geometry.
    var luiPositionedChildID: Int? {
        get { self[LUIPositionedChildKey.self] }
        set { self[LUIPositionedChildKey.self] = newValue }
    }
}

/// Normal children retain centered stack placement. Positioned children take
/// their proposal and offsets from the finite containing block, never from a
/// previous geometry report, and do not contribute to intrinsic size.
struct LUIPositionedStackLayout: Layout {
    let direction: LayoutDirection

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var intrinsic = CGSize.zero
        for child in subviews where child[LUIAbsoluteInsetsKey.self] == nil {
            let size = child.sizeThatFits(proposal)
            intrinsic.width = max(intrinsic.width, size.width)
            intrinsic.height = max(intrinsic.height, size.height)
        }
        return CGSize(
            width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? intrinsic.width,
            height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? intrinsic.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for child in subviews {
            guard let insets = child[LUIAbsoluteInsetsKey.self] else {
                child.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                            proposal: ProposedViewSize(bounds.size))
                continue
            }
            let available = ProposedViewSize(
                width: max(0, bounds.width - (insets.left ?? 0) - (insets.right ?? 0)),
                height: max(0, bounds.height - (insets.top ?? 0) - (insets.bottom ?? 0))
            )
            let size = child.sizeThatFits(available)
            var x = if let left = insets.left { bounds.minX + left }
                else if let right = insets.right { bounds.maxX - right - size.width }
                else { bounds.midX - size.width / 2 }
            let y = if let top = insets.top { bounds.minY + top }
                else if let bottom = insets.bottom { bounds.maxY - bottom - size.height }
                else { bounds.midY - size.height / 2 }
            // SwiftUI mirrors custom layouts in RTL. Canonical left/right
            // insets are physical, so cancel that mirror for absolute children.
            if direction == .rightToLeft { x = bounds.minX + bounds.maxX - x - size.width }
            child.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: available)
        }
    }
}

/// Native stack layout owns flow measurement and placement. Positioned siblings
/// share its paint scope, but are excluded from every native flow calculation.
struct LUIPositionedFlowLayout<Flow: Layout>: Layout {
    var flow: Flow
    static var layoutProperties: LayoutProperties { Flow.layoutProperties }
    let direction: LayoutDirection
    var padding: EdgeInsets = EdgeInsets()
    var fillsSurfaceWidth = false
    var fillsSurfaceHeight = false
    var minimumWidth: CGFloat = 0
    var minimumHeight: CGFloat = 0

    struct Cache {
        var flow: Flow.Cache
    }

    private func flowSubviews(_ subviews: Subviews) -> Subviews {
        subviews[subviews.indices.filter { subviews[$0][LUIAbsoluteInsetsKey.self] == nil }]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(flow: flow.makeCache(subviews: flowSubviews(subviews)))
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        flow.updateCache(&cache.flow, subviews: flowSubviews(subviews))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let children = flowSubviews(subviews)
        let size = flow.sizeThatFits(proposal: proposal, subviews: children, cache: &cache.flow)
        guard children.count != subviews.count else { return size }
        // The outer native surface frames supply the constrained proposal.
        // Accept it on constrained axes so absolute offsets use that surface,
        // rather than the smaller ideal extent of its flow children.
        return CGSize(
            width: max(minimumWidth, fillsSurfaceWidth ? finite(proposal.width) ?? size.width : size.width),
            height: max(minimumHeight, fillsSurfaceHeight ? finite(proposal.height) ?? size.height : size.height)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        flow.placeSubviews(in: bounds, proposal: proposal, subviews: flowSubviews(subviews), cache: &cache.flow)
        // Padding belongs to the containing block, not to its positioned
        // children's offsets. It remains a native surface modifier outside us.
        let leading = direction == .rightToLeft ? padding.trailing : padding.leading
        let containing = CGRect(x: bounds.minX - leading, y: bounds.minY - padding.top,
            width: bounds.width + padding.leading + padding.trailing,
            height: bounds.height + padding.top + padding.bottom)
        let positioned = subviews[subviews.indices.filter { subviews[$0][LUIAbsoluteInsetsKey.self] != nil }]
        var empty: () = ()
        LUIPositionedStackLayout(direction: direction).placeSubviews(
            in: containing, proposal: ProposedViewSize(containing.size), subviews: positioned, cache: &empty)
    }

    private func finite(_ value: CGFloat?) -> CGFloat? {
        value.flatMap { $0.isFinite ? max(0, $0) : nil }
    }
}
