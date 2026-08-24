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
