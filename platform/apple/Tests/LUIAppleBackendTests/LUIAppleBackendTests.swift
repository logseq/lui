import SwiftUI
import Testing
@testable import LUIAppleBackend

private struct CapturedAppleEvent: Equatable, Sendable {
    let kind: Int32
    let node: Int32
    let text: String
}

nonisolated(unsafe) private var capturedAppleEvent: CapturedAppleEvent?

private let captureAppleEvent: LUIAppleEventCallback = { kind, node, text in
    capturedAppleEvent = CapturedAppleEvent(
        kind: kind,
        node: node,
        text: text.map(String.init(cString:)) ?? ""
    )
}

@MainActor
@Suite("LUI SwiftUI backend", .serialized)
struct LUISwiftUIBackendTests {
    @Test("builds one retained observable tree for SwiftUI")
    func buildsRetainedTree() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)

        let row = try #require(backend.model(id: 1))
        let label = try #require(backend.model(id: 2))
        let button = try #require(backend.model(id: 3))

        #expect(backend.rootIDs == [1])
        #expect(row.kind == .row)
        #expect(row.children == [2, 3])
        #expect(row.property(.gap) == .int(12))
        #expect(label.property(.text) == .string("Hello from LG"))
        #expect(button.property(.text) == .string("Continue"))
        #expect(button.property(.enabled) == .bool(true))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
    }

    @Test("a property patch invalidates only its retained SwiftUI node")
    func propertyPatchIsLocal() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let row = try #require(backend.model(id: 1))
        let label = try #require(backend.model(id: 2))
        let button = try #require(backend.model(id: 3))
        let rowRevision = row.revision
        let labelRevision = label.revision
        let buttonRevision = button.revision

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"text","value":"Updated"}
        ]}
        """)

        #expect(backend.model(id: 1) === row)
        #expect(backend.model(id: 2) === label)
        #expect(backend.model(id: 3) === button)
        #expect(row.revision == rowRevision)
        #expect(label.revision == labelRevision + 1)
        #expect(button.revision == buttonRevision)
        #expect(label.property(.text) == .string("Updated"))
    }

    @Test("a keyed move changes only the parent child projection")
    func keyedMoveIsLocal() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let row = try #require(backend.model(id: 1))
        let label = try #require(backend.model(id: 2))
        let button = try #require(backend.model(id: 3))
        let rowRevision = row.revision
        let labelRevision = label.revision
        let buttonRevision = button.revision

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"move-child","parent":1,"child":3,"index":0}
        ]}
        """)

        #expect(row.children == [3, 2])
        #expect(row.revision == rowRevision + 1)
        #expect(label.revision == labelRevision)
        #expect(button.revision == buttonRevision)
        #expect(backend.model(id: 2) === label)
        #expect(backend.model(id: 3) === button)
    }

    @Test("rejects invalid batches before observable models change")
    func rejectsInvalidBatchAtomically() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let row = try #require(backend.model(id: 1))
        let children = row.children
        let revision = row.revision

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"create-node","id":4,"kind":"text"},
              {"op":"insert-child","parent":99,"child":4,"index":0}
            ]}
            """)
        }

        #expect(backend.generation == 1)
        #expect(backend.model(id: 4) == nil)
        #expect(row.children == children)
        #expect(row.revision == revision)
    }

    @Test("SwiftUI controls return typed events without owning app state")
    func returnsSemanticEvents() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"button"},
          {"op":"create-node","id":2,"kind":"text-input"},
          {"op":"create-node","id":3,"kind":"switch"},
          {"op":"set-prop","id":1,"property":"enabled","value":true},
          {"op":"set-prop","id":3,"property":"checked","value":false}
        ]}
        """)

        try backend.performPress(node: 1)
        try backend.performTextChange(node: 2, text: "Draft")
        try backend.performToggle(node: 3, checked: true)

        #expect(events == [
            .press(node: 1),
            .textChanged(node: 2, text: "Draft"),
            .toggleChanged(node: 3, checked: true),
        ])
        #expect(backend.model(id: 2)?.property(.text) == nil)
        #expect(backend.model(id: 3)?.property(.checked) == .bool(false))
    }

    @Test("maps Progress to a clamped retained SwiftUI value")
    func mapsProgressControl() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"label"},
          {"op":"create-node","id":2,"kind":"progress"},
          {"op":"set-prop","id":1,"property":"text","value":"Processing"},
          {"op":"set-prop","id":2,"property":"min-value","value":0},
          {"op":"set-prop","id":2,"property":"max-value","value":10},
          {"op":"set-prop","id":2,"property":"value","value":3},
          {"op":"set-prop","id":2,"property":"labelled-by","value":1}
        ]}
        """)

        let label = try #require(backend.model(id: 1))
        let progress = try #require(backend.model(id: 2))
        let progressRevision = progress.revision
        #expect(progress.progressFraction == 0.3)
        #expect(progress.accessibilityLabel(in: backend) == "Processing")

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"value","value":12}
        ]}
        """)
        #expect(backend.model(id: 1) === label)
        #expect(backend.model(id: 2) === progress)
        #expect(progress.progressFraction == 1)
        #expect(progress.revision == progressRevision + 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":2,"property":"min-value","value":10},
              {"op":"set-prop","id":2,"property":"max-value","value":10}
            ]}
            """)
        }
        #expect(backend.generation == 2)
        #expect(progress.progressFraction == 1)
    }

    @Test("maps Separator orientation without replacing its SwiftUI model")
    func mapsSeparatorOrientation() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"divider"},
          {"op":"set-prop","id":1,"property":"orientation","value":"horizontal"}
        ]}
        """)

        let separator = try #require(backend.model(id: 1))
        let revision = separator.revision
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"orientation","value":"vertical"}
        ]}
        """)
        #expect(backend.model(id: 1) === separator)
        #expect(separator.revision == revision + 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"orientation","value":"diagonal"}
            ]}
            """)
        }
        #expect(backend.generation == 2)
        #expect(separator.revision == revision + 1)
    }

    @Test("maps typed Surface size constraints without replacing its SwiftUI model")
    func mapsSurfaceSizeConstraints() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"box"},
          {"op":"set-prop","id":1,"property":"width","value":120},
          {"op":"set-prop","id":1,"property":"height","value":24},
          {"op":"set-prop","id":1,"property":"min-width","value":80},
          {"op":"set-prop","id":1,"property":"max-width","value":160},
          {"op":"set-prop","id":1,"property":"min-height","value":16},
          {"op":"set-prop","id":1,"property":"max-height","value":32}
        ]}
        """)

        let box = try #require(backend.model(id: 1))
        let revision = box.revision
        #expect(box.surfaceWidth == 120)
        #expect(box.surfaceHeight == 24)
        #expect(box.surfaceMinWidth == 80)
        #expect(box.surfaceMaxWidth == 160)
        #expect(box.surfaceMinHeight == 16)
        #expect(box.surfaceMaxHeight == 32)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"width","value":140}
        ]}
        """)
        #expect(backend.model(id: 1) === box)
        #expect(box.surfaceWidth == 140)
        #expect(box.revision == revision + 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"min-width","value":170},
              {"op":"set-prop","id":1,"property":"max-width","value":160}
            ]}
            """)
        }
        #expect(backend.generation == 2)
        #expect(box.surfaceMinWidth == 80)
        #expect(box.revision == revision + 1)
    }

    @Test("maps the Vercel Native layout vocabulary to SwiftUI primitives")
    func mapsVercelLayoutPrimitives() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"row"},
          {"op":"create-node","id":3,"kind":"grid"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"set-prop","id":1,"property":"main","value":"center"},
          {"op":"set-prop","id":1,"property":"cross","value":"stretch"},
          {"op":"set-prop","id":2,"property":"main","value":"space_between"},
          {"op":"set-prop","id":2,"property":"cross","value":"end"},
          {"op":"set-prop","id":3,"property":"columns","value":2},
          {"op":"set-prop","id":3,"property":"gap","value":6},
          {"op":"set-prop","id":4,"property":"grow","value":1.0},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":2,"child":4,"index":0}
        ]}
        """)

        let column = try #require(backend.model(id: 1))
        let row = try #require(backend.model(id: 2))
        let grid = try #require(backend.model(id: 3))
        let text = try #require(backend.model(id: 4))
        #expect(column.property(.main) == .string("center"))
        #expect(column.property(.cross) == .string("stretch"))
        #expect(row.property(.main) == .string("space_between"))
        #expect(row.property(.cross) == .string("end"))
        #expect(grid.property(.columns) == .int(2))
        #expect(text.property(.grow) == .double(1.0))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"set-prop","id":2,"property":"main","value":"between"}
            ]}
            """)
        }
        #expect(backend.generation == 1)
    }

    @Test("maps Vercel Native overlay surfaces to retained SwiftUI nodes")
    func mapsOverlaySurfaces() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"stack"},
          {"op":"create-node","id":2,"kind":"panel"},
          {"op":"create-node","id":3,"kind":"card"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":3,"child":4,"index":0}
        ]}
        """)

        #expect(backend.model(id: 1)?.kind == .stack)
        #expect(backend.model(id: 2)?.kind == .panel)
        #expect(backend.model(id: 3)?.kind == .card)
        #expect(backend.model(id: 1)?.children == [2, 3])
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"set-prop","id":3,"property":"gap","value":8}
            ]}
            """)
        }
        #expect(backend.generation == 1)
        #expect(backend.model(id: 3)?.property(.gap) == nil)
    }

    @Test("C ABI forwards SwiftUI backend events")
    func cABIForwardsEvent() {
        capturedAppleEvent = nil
        luiAppleReset()
        luiAppleSetEventCallback(captureAppleEvent)
        defer {
            luiAppleSetEventCallback(nil)
            luiAppleReset()
        }

        let accepted = """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"button"},
          {"op":"set-prop","id":1,"property":"enabled","value":true}
        ]}
        """.withCString(luiAppleApply)

        #expect(accepted == 1)
        #expect(luiApplePerformAction(1) == 1)
        #expect(capturedAppleEvent == CapturedAppleEvent(kind: 0, node: 1, text: ""))
    }

    private static let initialBatch = """
    {"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"row"},
      {"op":"create-node","id":2,"kind":"text"},
      {"op":"create-node","id":3,"kind":"button"},
      {"op":"set-prop","id":1,"property":"gap","value":12},
      {"op":"set-prop","id":2,"property":"text","value":"Hello from LG"},
      {"op":"set-prop","id":3,"property":"text","value":"Continue"},
      {"op":"set-prop","id":3,"property":"enabled","value":true},
      {"op":"insert-child","parent":1,"child":2,"index":0},
      {"op":"insert-child","parent":1,"child":3,"index":1}
    ]}
    """
}
