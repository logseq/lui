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
