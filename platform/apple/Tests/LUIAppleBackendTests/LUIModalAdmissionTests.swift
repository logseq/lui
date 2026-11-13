import Testing
@testable import LUIAppleBackend

@MainActor
struct LUIModalAdmissionTests {
    @Test("Untitled dialogs admit custom content and retain modal ownership")
    func untitledCustomDialog() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"dialog"},
          {"op":"create-node","id":3,"kind":"column"},
          {"op":"create-node","id":4,"kind":"input"},
          {"op":"create-node","id":5,"kind":"button"},
          {"op":"set-prop","id":5,"property":"text","value":"Create"},
          {"op":"insert-child","parent":3,"child":4,"index":0},
          {"op":"insert-child","parent":3,"child":5,"index":1},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        let dialog = try #require(backend.model(id: 2))
        #expect(dialog.text.isEmpty)
        #expect(backend.modalPresentation.item?.id == 2)
        #expect(backend.modalPresentation.item?.rootID == 1)
        #expect(LUIDialogContentPolicy.hasRichContent(dialog: dialog, backend: backend))
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"remove-child","parent":1,"child":2},
          {"op":"detach-subtree","id":2}
        ]}
        """)
        #expect(backend.modalPresentation.item == nil)
    }
}
