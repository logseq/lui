import Foundation
import Observation
import Testing
@testable import LUIAppleBackend

private final class SparseChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@MainActor
@Suite("Sparse virtual observation", .serialized)
struct LUISparseVirtualObservationTests {
    private func fixture() throws -> (LUIAppleBackend, LUINodeModel, LUISparseVirtualState) {
        let backend = LUIAppleBackend()
        try backend.apply(json: #"{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"virtual-list"},{"op":"set-prop","id":1,"property":"virtual-total-count","value":1},{"op":"set-prop","id":1,"property":"virtual-generation","value":1},{"op":"set-prop","id":1,"property":"virtual-indices","value":"[0]"},{"op":"create-node","id":2,"kind":"box"},{"op":"insert-child","parent":1,"child":2,"index":0}]}"#)
        let model = try #require(backend.model(id: 1))
        let state = LUISparseVirtualState()
        state.configure(model: model, backend: backend)
        return (backend, model, state)
    }

    @Test("Unchanged source configuration leaves row and size subscriptions quiet")
    func unchangedConfiguration() throws {
        let (backend, model, state) = try fixture()
        defer { state.dispose() }
        let changes = SparseChanges()
        withObservationTracking {
            _ = state.rows
            _ = state.contentHeight
        } onChange: { changes.record() }
        state.configure(model: model, backend: backend)
        #expect(changes.value == 0)
    }

    @Test("A new source generation advances its fence without republishing identical geometry")
    func generationOnly() throws {
        let (backend, model, state) = try fixture()
        defer { state.dispose() }
        let changes = SparseChanges()
        withObservationTracking {
            _ = state.rows
            _ = state.contentHeight
        } onChange: { changes.record() }
        try backend.apply(json: #"{"generation":2,"ops":[{"op":"set-prop","id":1,"property":"virtual-generation","value":2}]}"#)
        state.configure(model: model, backend: backend)
        #expect(state.generation == 2)
        #expect(changes.value == 0)
    }

    @Test("Changing rows still publishes membership and replaces their measured extents")
    func changedMembership() throws {
        let (backend, model, state) = try fixture()
        defer { state.dispose() }
        state.measured(state.rows[0], height: 48)
        let changes = SparseChanges()
        withObservationTracking {
            _ = state.rows
            _ = state.contentHeight
        } onChange: { changes.record() }
        try backend.apply(json: #"{"generation":2,"ops":[{"op":"create-node","id":3,"kind":"box"},{"op":"remove-child","parent":1,"child":2},{"op":"drop-node","id":2},{"op":"insert-child","parent":1,"child":3,"index":0},{"op":"set-prop","id":1,"property":"virtual-generation","value":2}]}"#)
        state.configure(model: model, backend: backend)
        #expect(changes.value == 1)
        #expect(state.rows.map(\.id) == [3])
        #expect(state.contentHeight == 32)
    }

    @Test("Confirming an estimated height does not invalidate the list geometry")
    func unchangedMeasurement() throws {
        let (_, _, state) = try fixture()
        defer { state.dispose() }
        let changes = SparseChanges()
        withObservationTracking {
            _ = state.contentHeight
        } onChange: { changes.record() }
        state.measured(state.rows[0], height: 32)
        #expect(changes.value == 0)
    }
}
