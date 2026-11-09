import Foundation

@main
struct RowWrapGeometryChecks {
    static func main() {
        typealias Item = LUIWrappingRowGeometry.Item
        struct Case {
            var name: String
            var items: [Item]
            var width: CGFloat?
            var main = "start"
            var cross = "start"
            var rtl = false
            var measured: [Int: CGSize] = [:]
            var size: CGSize
            var frames: [CGRect]
        }
        let pair = [
            Item(size: CGSize(width: 20, height: 10)), Item(size: CGSize(width: 20, height: 10)),
        ]
        let multiline = [
            Item(size: CGSize(width: 60, height: 10)), Item(size: CGSize(width: 50, height: 20)),
            Item(size: CGSize(width: 30, height: 5)),
        ]
        let cases: [Case] = [
            Case(name: "empty", items: [], width: 100, size: .zero, frames: []),
            Case(
                name: "single", items: [pair[0]], width: 100, size: CGSize(width: 100, height: 10),
                frames: [CGRect(x: 0, y: 0, width: 20, height: 10)]),
            Case(
                name: "natural", items: pair, width: nil, size: CGSize(width: 50, height: 10),
                frames: [
                    CGRect(x: 0, y: 0, width: 20, height: 10),
                    CGRect(x: 30, y: 0, width: 20, height: 10),
                ]),
            Case(
                name: "infinite", items: pair, width: .infinity,
                size: CGSize(width: 50, height: 10),
                frames: [
                    CGRect(x: 0, y: 0, width: 20, height: 10),
                    CGRect(x: 30, y: 0, width: 20, height: 10),
                ]),
            Case(
                name: "zero is bounded", items: pair, width: 0, size: CGSize(width: 0, height: 30),
                frames: [
                    CGRect(x: 0, y: 0, width: 20, height: 10),
                    CGRect(x: 0, y: 20, width: 20, height: 10),
                ]),
            Case(
                name: "fixed oversize owns a line",
                items: [Item(size: CGSize(width: 160, height: 12)), pair[0]], width: 100,
                size: CGSize(width: 100, height: 32),
                frames: [
                    CGRect(x: 0, y: 0, width: 160, height: 12),
                    CGRect(x: 0, y: 22, width: 20, height: 10),
                ]),
            Case(
                name: "oversize remeasures to proposal",
                items: [Item(size: CGSize(width: 160, height: 12))], width: 100,
                measured: [0: CGSize(width: 100, height: 30)], size: CGSize(width: 100, height: 30),
                frames: [CGRect(x: 0, y: 0, width: 100, height: 30)]),
            Case(
                name: "line gap and height reset", items: multiline, width: 100,
                size: CGSize(width: 100, height: 40),
                frames: [
                    CGRect(x: 0, y: 0, width: 60, height: 10),
                    CGRect(x: 0, y: 20, width: 50, height: 20),
                    CGRect(x: 60, y: 20, width: 30, height: 5),
                ]),
            Case(
                name: "cross center", items: multiline, width: 100, cross: "center",
                size: CGSize(width: 100, height: 40),
                frames: [
                    CGRect(x: 0, y: 0, width: 60, height: 10),
                    CGRect(x: 0, y: 20, width: 50, height: 20),
                    CGRect(x: 60, y: 27.5, width: 30, height: 5),
                ]),
            Case(
                name: "cross end", items: multiline, width: 100, cross: "end",
                size: CGSize(width: 100, height: 40),
                frames: [
                    CGRect(x: 0, y: 0, width: 60, height: 10),
                    CGRect(x: 0, y: 20, width: 50, height: 20),
                    CGRect(x: 60, y: 35, width: 30, height: 5),
                ]),
            Case(
                name: "stretch is per line", items: multiline, width: 100, cross: "stretch",
                size: CGSize(width: 100, height: 40),
                frames: [
                    CGRect(x: 0, y: 0, width: 60, height: 10),
                    CGRect(x: 0, y: 20, width: 50, height: 20),
                    CGRect(x: 60, y: 20, width: 30, height: 20),
                ]),
            Case(
                name: "main center", items: pair, width: 100, main: "center",
                size: CGSize(width: 100, height: 10),
                frames: [
                    CGRect(x: 25, y: 0, width: 20, height: 10),
                    CGRect(x: 55, y: 0, width: 20, height: 10),
                ]),
            Case(
                name: "main end", items: pair, width: 100, main: "end",
                size: CGSize(width: 100, height: 10),
                frames: [
                    CGRect(x: 50, y: 0, width: 20, height: 10),
                    CGRect(x: 80, y: 0, width: 20, height: 10),
                ]),
            Case(
                name: "space between", items: pair, width: 100, main: "space_between",
                size: CGSize(width: 100, height: 10),
                frames: [
                    CGRect(x: 0, y: 0, width: 20, height: 10),
                    CGRect(x: 80, y: 0, width: 20, height: 10),
                ]),
            Case(
                name: "logical start RTL", items: pair, width: 100, rtl: true,
                size: CGSize(width: 100, height: 10),
                frames: [
                    CGRect(x: 80, y: 0, width: 20, height: 10),
                    CGRect(x: 50, y: 0, width: 20, height: 10),
                ]),
            Case(
                name: "proportional grow beside fixed",
                items: [
                    pair[0], Item(size: CGSize(width: 10, height: 10), grow: 1),
                    Item(size: CGSize(width: 30, height: 10), grow: 3),
                ], width: 100, size: CGSize(width: 100, height: 10),
                frames: [
                    CGRect(x: 0, y: 0, width: 20, height: 10),
                    CGRect(x: 30, y: 0, width: 15, height: 10),
                    CGRect(x: 55, y: 0, width: 45, height: 10),
                ]),
            Case(
                name: "spacer grows on its line",
                items: [pair[0], Item(size: .zero, grow: 1), pair[1]], width: 100,
                size: CGSize(width: 100, height: 10),
                frames: [
                    CGRect(x: 0, y: 0, width: 20, height: 10),
                    CGRect(x: 30, y: 0, width: 40, height: 0),
                    CGRect(x: 80, y: 0, width: 20, height: 10),
                ]),
            Case(
                name: "grow remeasures height",
                items: [pair[0], Item(size: CGSize(width: 10, height: 30), grow: 1)], width: 100,
                measured: [1: CGSize(width: 70, height: 5)], size: CGSize(width: 100, height: 10),
                frames: [
                    CGRect(x: 0, y: 0, width: 20, height: 10),
                    CGRect(x: 30, y: 0, width: 70, height: 5),
                ]),
        ]
        for check in cases {
            let plan = LUIWrappingRowGeometry.plan(
                items: check.items, width: check.width, gap: 10,
                main: check.main, cross: check.cross, rightToLeft: check.rtl,
                measure: { index, _ in check.measured[index] ?? check.items[index].size }
            )
            precondition(plan.size == check.size, "\(check.name): size \(plan.size)")
            precondition(plan.frames == check.frames, "\(check.name): frames \(plan.frames)")
        }
        print("Row wrapping geometry: \(cases.count) cases passed")
    }
}
