import Observation
import SwiftUI
import Testing
@testable import LUIAppleBackend

@MainActor
private final class PublicationReads {
    var snapshots: [String] = []
}

@MainActor
@Suite("Atomic native tree publication", .serialized)
struct LUIPublicationTests {
    private func backend() throws -> LUIAppleBackend {
        let registry = LUIAppleExtensionRegistry()
        try registry.register(LUIAppleExtension(identifier: "publication", fingerprint: "publication-v1",
            acceptsStandardChildren: true, properties: [LUIExtensionProperty(name: "label", kind: .string)]) {
            AnyView($0.content)
        })
        return try LUIAppleBackend(extensionRegistry: registry)
    }

    private func snapshot(_ backend: LUIAppleBackend, id: Int = 1) -> String {
        if let model = backend.model(id: id) {
            return "\(id):\(model.text)[\(model.children.map { snapshot(backend, id: $0) }.joined(separator: ","))]"
        }
        if let model = backend.extensionModel(id: id) {
            return "\(id):\(model.properties["label"]?.stringValue ?? "extension")[\(model.children.map { snapshot(backend, id: $0) }.joined(separator: ","))]"
        }
        return "missing:\(id)"
    }

    @Test("Synchronous field observers see the complete replacement graph and final revisions")
    func replacementGraph() throws {
        let backend = try backend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"old"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        let root = try #require(backend.model(id: 1))
        let reads = PublicationReads()
        for field in 0..<4 {
            withObservationTracking {
                switch field {
                case 0: _ = root.children
                case 1: _ = root.visibleChildren
                case 2: _ = root.properties
                default: _ = root.revision
                }
            } onChange: {
                MainActor.assumeIsolated {
                    reads.snapshots.append(snapshot(backend))
                    #expect(root.revision == 1)
                    #expect(backend.model(id: 2) == nil)
                }
            }
        }
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"remove-child","parent":1,"child":2},
          {"op":"drop-node","id":2},
          {"op":"create-extension","id":3,"identifier":"publication","fingerprint":"publication-v1"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"set-prop","id":4,"property":"text","value":"new"},
          {"op":"insert-child","parent":3,"child":4,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":0},
          {"op":"set-prop","id":1,"property":"width","value":300}
        ]}
        """)
        #expect(reads.snapshots.count == 4)
        #expect(reads.snapshots.allSatisfy { $0 == "1:[3:extension[4:new[]]]" })
        #expect(backend.model(id: 1) === root)
    }

    @Test("Extension content and children publish together with their standard descendants")
    func extensionGraph() throws {
        let backend = try backend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-extension","id":1,"identifier":"publication","fingerprint":"publication-v1"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        let root = try #require(backend.extensionModel(id: 1))
        let reads = PublicationReads()
        withObservationTracking { _ = root.children; _ = root.properties; _ = root.revision } onChange: {
            MainActor.assumeIsolated { reads.snapshots.append(snapshot(backend)) }
        }
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-extension-prop","id":1,"property":"label","value":"updated-root"},
          {"op":"set-prop","id":2,"property":"text","value":"updated"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":3,"property":"text","value":"inserted"},
          {"op":"insert-child","parent":1,"child":3,"index":0}
        ]}
        """)
        #expect(reads.snapshots == ["1:updated-root[3:inserted[],2:updated[]]"])
        #expect(backend.extensionModel(id: 1) === root)
    }

    @Test("Missing lookups are invalidated only for the inserted ID")
    func missingLookup() throws {
        let backend = try backend()
        let reads = PublicationReads()
        for id in [1, 99] {
            withObservationTracking { _ = backend.model(id: id); _ = backend.extensionModel(id: id) } onChange: {
                MainActor.assumeIsolated { reads.snapshots.append(snapshot(backend, id: id)) }
            }
        }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-extension","id":1,"identifier":"publication","fingerprint":"publication-v1"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"ready"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        #expect(reads.snapshots == ["1:extension[2:ready[]]"])
        let deleted = PublicationReads()
        withObservationTracking { _ = backend.extensionModel(id: 1) } onChange: {
            MainActor.assumeIsolated { deleted.snapshots.append(snapshot(backend)) }
        }
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"remove-child","parent":1,"child":2},
          {"op":"drop-node","id":2}, {"op":"drop-node","id":1}
        ]}
        """)
        #expect(deleted.snapshots == ["missing:1"])
    }

    @Test("Content, reorder and reparent preserve identities; noop and unrelated fields stay quiet")
    func localUpdates() throws {
        let backend = try backend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"create-node","id":4,"kind":"column"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":1,"child":4,"index":2}
        ]}
        """)
        let root = try #require(backend.model(id: 1))
        let child = try #require(backend.model(id: 2))
        let sibling = try #require(backend.model(id: 3))
        let quiet = PublicationReads()
        withObservationTracking { _ = root.children; _ = sibling.revision } onChange: {
            MainActor.assumeIsolated { quiet.snapshots.append("unexpected") }
        }
        let content = PublicationReads()
        withObservationTracking { _ = child.text } onChange: {
            MainActor.assumeIsolated {
                content.snapshots.append(child.text)
                #expect(child.revision == 1)
            }
        }
        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"set-prop","id":2,"property":"text","value":"changed"}]}
        """)
        try backend.apply(json: """
        {"generation":3,"ops":[{"op":"set-prop","id":2,"property":"text","value":"changed"}]}
        """)
        #expect(content.snapshots == ["changed"])
        #expect(quiet.snapshots.isEmpty)
        #expect(child.revision == 1)
        let moved = PublicationReads()
        withObservationTracking { _ = child.parent } onChange: {
            MainActor.assumeIsolated {
                moved.snapshots.append(snapshot(backend))
                #expect(child.parent == 4)
            }
        }
        try backend.apply(json: """
        {"generation":4,"ops":[
          {"op":"remove-child","parent":1,"child":2},
          {"op":"insert-child","parent":4,"child":2,"index":0},
          {"op":"remove-child","parent":1,"child":3},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)
        #expect(moved.snapshots == ["1:[4:[2:changed[]],3:[]]"])
        #expect(backend.model(id: 1) === root)
        #expect(backend.model(id: 2) === child)
        #expect(backend.model(id: 3) === sibling)
    }
}
