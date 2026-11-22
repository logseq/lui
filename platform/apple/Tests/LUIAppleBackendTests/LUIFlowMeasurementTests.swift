import SwiftUI
import Testing
@testable import LUIAppleBackend
#if os(macOS)
import AppKit

private final class FlowMeasurements: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

private struct MeasuredFlow<Flow: Layout>: Layout {
    let measurements: FlowMeasurements
    var flow: Flow

    func makeCache(subviews: Subviews) -> Flow.Cache {
        flow.makeCache(subviews: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout Flow.Cache) -> CGSize {
        measurements.increment()
        return flow.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout Flow.Cache) {
        flow.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}

@MainActor
private final class FlowGrowth {
    var grow: (() -> Void)?
    var width: CGFloat = 0
}

private struct StatefulFlowChild: View {
    let growth: FlowGrowth
    @State private var expanded = false

    var body: some View {
        Color.clear.frame(width: expanded ? 180 : 20, height: 20)
            .onAppear { growth.grow = { expanded = true } }
    }
}

@MainActor
struct LUIFlowMeasurementTests {
    @Test(arguments: [false, true])
    func childSizeInvalidatesMemo(backendDriven: Bool) async throws {
        _ = NSApplication.shared
        let growth = FlowGrowth()
        let backend = LUIAppleBackend()
        let content: AnyView
        if backendDriven {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"row"},
              {"op":"create-node","id":2,"kind":"text"},
              {"op":"set-prop","id":2,"property":"text","value":"x"},
              {"op":"insert-child","parent":1,"child":2,"index":0}
            ]}
            """)
            content = AnyView(LUISwiftUIRoot(backend: backend, rootID: 1))
        } else {
            content = AnyView(LUIPositionedFlowLayout(flow: HStackLayout(), direction: .leftToRight) {
                StatefulFlowChild(growth: growth)
            })
        }
        let host = NSHostingView(rootView: content.fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { growth.width = $0 }
            .frame(width: 400, height: 100, alignment: .leading))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 400, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            window.display()
            try await Task.sleep(for: .milliseconds(10))
        }
        let before = growth.width
        #expect(before > 0)
        if backendDriven {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"set-prop","id":2,"property":"text","value":"A much longer updated child"}
            ]}
            """)
        } else {
            let grow = try #require(growth.grow)
            grow()
        }
        for _ in 0..<10 {
            host.layoutSubtreeIfNeeded()
            window.display()
            try await Task.sleep(for: .milliseconds(10))
        }
        print("FLOW invalidation backend=\(backendDriven) before=\(before) after=\(growth.width)")
        #expect(growth.width > before + 50)
    }

    private func nested(_ depth: Int, _ measurements: FlowMeasurements) -> AnyView {
        guard depth > 0 else { return AnyView(Text("Flow")) }
        let flow = depth.isMultiple(of: 2)
            ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
        return AnyView(LUIPositionedFlowLayout(
            flow: MeasuredFlow(measurements: measurements, flow: flow), direction: .leftToRight
        ) {
            Text("Sibling")
            nested(depth - 1, measurements)
        })
    }

    @Test func nestedFlowMeasurement() {
        _ = NSApplication.shared
        for depth in [2, 4, 8, 12, 20] {
            let measurements = FlowMeasurements()
            let root = ScrollView(.horizontal) {
                LazyHStack { nested(depth, measurements) }
            }.frame(width: 400, height: 100)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 400, height: 100),
                styleMask: [.borderless], backing: .buffered, defer: false)
            let start = ContinuousClock.now
            window.contentView = host
            window.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            window.display()
            window.orderOut(nil)
            window.contentView = nil
            print("FLOW depth=\(depth) calls=\(measurements.count) elapsed=\(start.duration(to: .now))")
            #expect(measurements.count < 10_000)
        }
    }
}
#endif
