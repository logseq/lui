import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("Controlled navigation")
struct LUINavigationTests {
    @Test("programmatic paths preserve duplicate route identities without echo")
    func programmatic() {
        let state = LUINavigationState()
        state.apply(path: ["a", "b"], revision: 10)
        #expect(state.path == ["a", "b"])
        #expect(state.revision == 10)
        #expect(state.propose(["a", "b"]) == nil)
        #expect(state.propose(["x"]) == nil)
        #expect(state.propose(["a", "b", "c"]) == nil)
    }

    @Test("cancelled interactive pop commits no event")
    func cancellation() throws {
        let state = LUINavigationState()
        state.apply(path: ["a", "b"], revision: 10)
        let token = try #require(state.propose(["a"]))
        #expect(state.path == ["a"])
        var events = 0
        state.complete(token, cancelled: true) { _, _ in events += 1 }
        #expect(events == 0)
        #expect(state.path == ["a", "b"])
    }

    @Test("completed pop emits once and permits synchronous authoritative replacement")
    func synchronousReplacement() throws {
        let state = LUINavigationState()
        state.apply(path: ["a", "b"], revision: 10)
        let token = try #require(state.propose(["a"]))
        var events: [[Int]] = []
        state.complete(token, cancelled: false) { revision, length in
            events.append([revision, length])
            state.apply(path: ["a", "new"], revision: 11)
        }
        state.complete(token, cancelled: false) { r, n in events.append([r, n]) }
        #expect(events == [[10, 1]])
        #expect(state.path == ["a", "new"])
    }

    @Test("new revision supersedes old transition and rejected pop restores authoritative state")
    func superseded() throws {
        let state = LUINavigationState()
        state.apply(path: ["a", "b"], revision: 10)
        let token = try #require(state.propose([]))
        state.apply(path: ["new graph"], revision: 11)
        var events = 0
        state.complete(token, cancelled: false) { _, _ in events += 1 }
        #expect(events == 0)
        #expect(state.path == ["new graph"])
        let rejected = try #require(state.propose([]))
        state.complete(rejected, cancelled: false) { _, _ in
            state.apply(path: ["new graph"], revision: 12)
        }
        #expect(state.path == ["new graph"])
    }
}
