import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("LUI shared backend parity")
struct LUIBackendParityTests {
    @Test("retains nodes and patches properties")
    func retainsNodesAndPatchesProperties() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"root"},
          {"op":"create-node","id":2,"kind":"row"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":2,"property":"gap","value":12},
          {"op":"set-prop","id":3,"property":"text","value":"Before"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}
        """)

        let root = try #require(backend.model(id: 1))
        let row = try #require(backend.model(id: 2))
        let text = try #require(backend.model(id: 3))
        #expect(root.children == [2])
        #expect(row.children == [3])
        #expect(row.property(LUIProperty.gap) == LUIWireValue.int(12))
        #expect(text.property(LUIProperty.text) == LUIWireValue.string("Before"))

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":3,"property":"text","value":"After"}
        ]}
        """)

        #expect(backend.model(id: 1) === root)
        #expect(backend.model(id: 2) === row)
        #expect(backend.model(id: 3) === text)
        #expect(text.property(LUIProperty.text) == LUIWireValue.string("After"))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
    }

    @Test("dispatches text, press, and toggle events")
    func dispatchesControlEvents() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"text-field"},
          {"op":"create-node","id":2,"kind":"button"},
          {"op":"create-node","id":3,"kind":"toggle"},
          {"op":"set-prop","id":1,"property":"text","value":""},
          {"op":"set-prop","id":2,"property":"text","value":"Save"},
          {"op":"set-prop","id":3,"property":"text","value":"Pinned"},
          {"op":"set-prop","id":3,"property":"checked","value":false}
        ]}
        """)

        try backend.performTextChange(node: 1, text: "Draft")
        try backend.performPress(node: 2)
        try backend.performToggle(node: 3, checked: true)

        #expect(events == [
            LUIEvent.textChanged(node: 1, text: "Draft"),
            LUIEvent.press(node: 2),
            LUIEvent.toggleChanged(node: 3, checked: true),
        ])
    }
}
