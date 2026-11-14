import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("Minimum-height column frame policy")
struct LUIColumnFramePolicyTests {
    enum Scenario: CaseIterable, Sendable {
        case dialogWithGrowingScroll
        case narrowWrappedText
        case emptyMinimum
        case finiteHeightAncestor
        case verticalRelativeFrame
        case bothRelativeFrame
        case growingColumn

        var minimumHeight: Int {
            self == .dialogWithGrowingScroll ? 0 : 60
        }

        var operations: String {
            switch self {
            case .dialogWithGrowingScroll:
                """
                {"op":"create-node","id":3,"kind":"scroll"},
                {"op":"set-prop","id":3,"property":"grow","value":1.0},
                {"op":"create-node","id":4,"kind":"text"},
                {"op":"set-prop","id":4,"property":"text","value":"Dialog content"},
                {"op":"insert-child","parent":3,"child":4,"index":0},
                {"op":"insert-child","parent":2,"child":3,"index":0}
                """
            case .narrowWrappedText:
                """
                {"op":"set-prop","id":2,"property":"width","value":96},
                {"op":"create-node","id":3,"kind":"text"},
                {"op":"set-prop","id":3,"property":"text","value":"A narrow column keeps the ideal height of this wrapped text."},
                {"op":"insert-child","parent":2,"child":3,"index":0}
                """
            case .emptyMinimum:
                ""
            case .finiteHeightAncestor:
                """
                {"op":"set-prop","id":1,"property":"height","value":120},
                {"op":"create-node","id":3,"kind":"text"},
                {"op":"set-prop","id":3,"property":"text","value":"Content taller than the ancestor"},
                {"op":"set-prop","id":3,"property":"height","value":240},
                {"op":"insert-child","parent":2,"child":3,"index":0}
                """
            case .verticalRelativeFrame, .bothRelativeFrame:
                """
                {"op":"set-prop","id":1,"property":"height","value":120},
                {"op":"set-prop","id":1,"property":"width","value":96},
                {"op":"set-prop","id":2,"property":"container-relative-frame","value":"\(self == .verticalRelativeFrame ? "vertical" : "both")"}
                """
            case .growingColumn:
                """
                {"op":"set-prop","id":2,"property":"grow","value":1.0}
                """
            }
        }
    }

    // These fixtures exercise policy eligibility, not SwiftUI measurement or
    // viewport geometry. The same unhosted model path compiles on macOS and iOS.
    @Test("Intrinsic-height eligibility depends on the column's own constraints",
          arguments: Scenario.allCases)
    func minimumHeightColumnEligibility(_ scenario: Scenario) throws {
        let backend = LUIAppleBackend()
        let extra = scenario.operations
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"column"},
          {"op":"set-prop","id":2,"property":"min-height","value":\(scenario.minimumHeight)},
          {"op":"insert-child","parent":1,"child":2,"index":0}
          \(extra.isEmpty ? "" : "," + extra)
        ]}
        """)

        let column = try #require(backend.model(id: 2))
        #expect(LUISurfaceFramePolicy.columnIsIntrinsicHeight(model: column)
                == (scenario != .growingColumn))
    }
}
