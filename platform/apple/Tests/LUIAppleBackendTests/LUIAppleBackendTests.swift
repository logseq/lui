import AppKit
import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("LUI AppKit backend")
struct LUIAppleBackendTests {
    @Test("applies one LG patch batch to real AppKit views")
    func appliesPatchBatch() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)

        let row = try #require(backend.view(id: 1) as? NSStackView)
        let label = try #require(backend.view(id: 2) as? NSTextField)
        let button = try #require(backend.view(id: 3) as? NSButton)

        #expect(row.orientation == .horizontal)
        #expect(row.spacing == 12)
        #expect(label.stringValue == "Hello from LG")
        #expect(button.title == "Continue")
        #expect(button.isEnabled == true)
        #expect(row.arrangedSubviews.map(backend.id(of:)) == [2, 3])
    }

    @Test("moves existing native views without recreating them")
    func preservesIdentityOnMove() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let originalButton = try #require(backend.view(id: 3))

        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"move-child","parent":1,"child":3,"index":0}]}
        """)

        let row = try #require(backend.view(id: 1) as? NSStackView)
        #expect(backend.view(id: 3) === originalButton)
        #expect(row.arrangedSubviews.map(backend.id(of:)) == [3, 2])
    }

    @Test("rejects an invalid batch atomically")
    func rejectsInvalidBatchAtomically() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"create-node","id":4,"kind":"text"},
              {"op":"insert-child","parent":99,"child":4,"index":0}
            ]}
            """)
        }

        #expect(backend.view(id: 4) == nil)
        #expect(backend.generation == 1)
    }

    @Test("native control action returns a semantic event")
    func returnsButtonEvent() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: Self.initialBatch)

        let button = try #require(backend.view(id: 3) as? NSButton)
        button.performClick(nil)

        #expect(events == [.press(node: 3)])
    }

    @Test("native text editing returns each semantic change")
    func returnsTextChangedEvent() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"text-input"},
          {"op":"set-prop","id":1,"property":"text","value":""},
          {"op":"set-prop","id":1,"property":"enabled","value":true}
        ]}
        """)

        let field = try #require(backend.view(id: 1) as? NSTextField)
        field.stringValue = "Write Apple Todos"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: field
        )

        #expect(events == [.textChanged(node: 1, text: "Write Apple Todos")])
    }

    @Test("C ABI accepts the LG wire batch")
    func cABIReceivesWireBatch() {
        luiAppleReset()
        let accepted = Self.initialBatch.withCString(luiAppleApply)
        #expect(accepted == 1)
        luiAppleReset()
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
