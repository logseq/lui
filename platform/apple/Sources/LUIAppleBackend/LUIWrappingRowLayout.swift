import SwiftUI

enum LUIWrappingRowGeometry {
    struct Item {
        var size: CGSize
        var grow: CGFloat = 0
    }

    struct Plan {
        var size: CGSize
        var frames: [CGRect]
    }

    static func plan(
        items: [Item], width: CGFloat?, gap: CGFloat,
        main: String, cross: String, rightToLeft: Bool,
        measure: (Int, CGFloat) -> CGSize
    ) -> Plan {
        guard !items.isEmpty else { return Plan(size: .zero, frames: []) }
        let width = width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let gap = max(0, gap)
        var sizes = items.enumerated().map { index, item in
            if let width, item.size.width > width {
                return measure(index, width)
            }
            return item.size
        }
        var lines: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0
        for index in items.indices {
            let next = (index == start ? 0 : gap) + sizes[index].width
            if let width, index > start, used + next > width {
                lines.append(start..<index)
                start = index
                used = sizes[index].width
            } else {
                used += next
            }
        }
        lines.append(start..<items.count)
        let naturalWidth = lines.reduce(CGFloat.zero) { maximum, line in
            max(
                maximum,
                line.reduce(CGFloat.zero) { $0 + sizes[$1].width }
                    + gap * CGFloat(line.count - 1))
        }
        let rowWidth = width ?? naturalWidth
        var frames = Array(repeating: CGRect.zero, count: items.count)
        var y: CGFloat = 0
        for line in lines {
            let contentWidth =
                line.reduce(CGFloat.zero) { $0 + sizes[$1].width }
                + gap * CGFloat(line.count - 1)
            let remaining = max(0, rowWidth - contentWidth)
            let totalGrow = line.reduce(CGFloat.zero) { $0 + max(0, items[$1].grow) }
            if width != nil, totalGrow > 0, remaining > 0 {
                for index in line where items[index].grow > 0 {
                    let allocated = sizes[index].width + remaining * items[index].grow / totalGrow
                    sizes[index] = CGSize(
                        width: allocated, height: measure(index, allocated).height)
                }
            }
            let occupied =
                line.reduce(CGFloat.zero) { $0 + sizes[$1].width }
                + gap * CGFloat(line.count - 1)
            let free = max(0, rowWidth - occupied)
            let height = line.reduce(CGFloat.zero) { max($0, sizes[$1].height) }
            var x: CGFloat = main == "end" ? free : (main == "center" ? free / 2 : 0)
            let spacing =
                gap
                + (main == "space_between" && line.count > 1
                    ? free / CGFloat(line.count - 1) : 0)
            for index in line {
                let size = sizes[index]
                let offset: CGFloat =
                    cross == "end"
                    ? height - size.height
                    : (cross == "center" ? (height - size.height) / 2 : 0)
                frames[index] = CGRect(
                    x: rightToLeft ? rowWidth - x - size.width : x,
                    y: y + offset, width: size.width,
                    height: cross == "stretch" ? height : size.height
                )
                x += size.width + spacing
            }
            y += height + gap
        }
        return Plan(size: CGSize(width: rowWidth, height: y - gap), frames: frames)
    }
}

struct LUIWrappingRowTraits: LayoutValueKey {
    struct Value {
        var grow: CGFloat = 0
        var spacer = false
    }
    static let defaultValue = Value()
}

struct LUIWrappingRowLayout: Layout {
    var gap: CGFloat
    var main: String
    var cross: String
    var rightToLeft: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        plan(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let frames = plan(width: bounds.width, subviews: subviews).frames
        for index in subviews.indices {
            let frame = frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: UnitPoint(x: 0, y: 0), proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func plan(width: CGFloat?, subviews: Subviews) -> LUIWrappingRowGeometry.Plan {
        LUIWrappingRowGeometry.plan(
            items: subviews.map { subview in
                let traits = subview[LUIWrappingRowTraits.self]
                return LUIWrappingRowGeometry.Item(
                    size: traits.spacer ? .zero : subview.sizeThatFits(.unspecified),
                    grow: traits.spacer ? max(1, traits.grow) : traits.grow
                )
            },
            width: width, gap: gap, main: main, cross: cross, rightToLeft: rightToLeft,
            measure: { index, width in
                subviews[index][LUIWrappingRowTraits.self].spacer
                    ? .zero
                    : subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
        )
    }
}
