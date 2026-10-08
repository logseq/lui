import Testing
import Foundation
@testable import LUIAppleBackend

@MainActor
@Suite("LUI file-picker backend")
struct LUIFilePickerTests {
    @Test("ordered batches retain files until acknowledgement, stale results release their own copies")
    func batchSelectionLifetime() throws {
        let backend = try makeBackend()
        func file(_ name: String) throws -> LUIRetainedFile {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + name)
            try Data(name.utf8).write(to: url)
            return LUIRetainedFile(url: url, securityScoped: false, temporary: true)
        }
        let first = try file("first.txt"), second = try file("second.txt")
        let stale = try file("stale.txt")
        defer { for f in [first, second, stale] { try? FileManager.default.removeItem(at: f.url) } }
        backend.setFilePickerOperation(node: 2, LUIFilePickerOperation(token: .int(2), phase: .presenting))
        #expect(!backend.acceptFilePickerSelection(node: 2, token: .int(1), files: [stale]))
        #expect(!FileManager.default.fileExists(atPath: stale.url.path))
        #expect(backend.filePickerOperation(node: 2)?.phase == .presenting)
        #expect(backend.acceptFilePickerSelection(node: 2, token: .int(2), files: [second, first]))
        #expect(backend.filePickerOperation(node: 2)?.files.map(\.url) == [second.url, first.url])
        #expect(FileManager.default.fileExists(atPath: first.url.path))
        backend.clearFilePickerOperation(node: 2)
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        #expect(!FileManager.default.fileExists(atPath: second.url.path))
        let late = try file("late.txt")
        #expect(!backend.acceptFilePickerSelection(node: 2, token: .int(2), files: [late]))
        #expect(!FileManager.default.fileExists(atPath: late.url.path))
    }
    private func makeBackend() throws -> LUIAppleBackend {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"file-picker"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        return backend
    }

    @Test("file-picker accepts its property set")
    func filePickerAcceptsPickerProperties() throws {
        let backend = try makeBackend()
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"request","value":"op-1"},
          {"op":"set-prop","id":2,"property":"types","value":"public.image,public.movie"},
          {"op":"set-prop","id":2,"property":"multiple","value":true},
          {"op":"set-prop","id":2,"property":"source","value":"photos"},
          {"op":"set-prop","id":2,"property":"enabled","value":true},
          {"op":"set-prop","id":2,"property":"appear-enabled","value":true}
        ]}
        """)
        #expect(backend.model(id: 2) != nil)
    }

    @Test("request and completion accept string or int tokens")
    func requestAndCompletionAcceptStringOrInt() throws {
        let backend = try makeBackend()
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"request","value":7}
        ]}
        """)
        try backend.apply(json: """
        {"generation":3,"ops":[
          {"op":"set-prop","id":2,"property":"completion","value":"op-1"}
        ]}
        """)
        #expect(backend.model(id: 2) != nil)
    }

    @Test("file-picker rejects unknown sources and foreign properties")
    func filePickerRejectsInvalidProperties() throws {
        let backend = try makeBackend()
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"set-prop","id":2,"property":"source","value":"screen"}
            ]}
            """)
        }
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":2,"property":"text","value":"nope"}
            ]}
            """)
        }
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":4,"ops":[
              {"op":"set-prop","id":2,"property":"multiple","value":"yes"}
            ]}
            """)
        }
    }

    @Test("performPicked emits the payload only for file-picker nodes")
    func performPickedEmitsForFilePickerOnly() throws {
        let backend = try makeBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }

        try backend.performPicked(
            node: 2,
            payload: #"{"request":"op-1","files":[{"path":"/tmp/a.png","name":"a.png","content-type":"image/png"}]}"#
        )
        #expect(events == [
            .picked(
                node: 2,
                payload: #"{"request":"op-1","files":[{"path":"/tmp/a.png","name":"a.png","content-type":"image/png"}]}"#
            ),
        ])

        #expect(throws: LUIBackendError.self) {
            try backend.performPicked(node: 1, payload: "{}")
        }
    }

    @Test("file-picker presentations report cancellation through dismiss")
    func filePickerIsDismissible() throws {
        let backend = try makeBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }

        try backend.performDismiss(node: 2)
        #expect(events == [.dismiss(node: 2)])

        #expect(throws: LUIBackendError.self) {
            try backend.performPicked(node: 0, payload: "{}")
        }
    }

    @Test("dropping the node releases its file-picker operation")
    func droppingNodeReleasesOperation() throws {
        let backend = try makeBackend()
        backend.setFilePickerOperation(
            node: 2,
            LUIFilePickerOperation(token: .string("op-1"), phase: .presenting)
        )
        #expect(backend.filePickerOperation(node: 2) != nil)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"remove-child","parent":1,"child":2},
          {"op":"drop-node","id":2}
        ]}
        """)
        #expect(backend.filePickerOperation(node: 2) == nil)
    }
}
