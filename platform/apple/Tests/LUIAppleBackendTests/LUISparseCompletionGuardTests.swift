#if os(macOS)
import AppKit
import Testing
@testable import LUIAppleBackend

@MainActor
private final class SparseCompletionFixture {
    let backend = LUIAppleBackend()
    let state = LUISparseVirtualState()
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 320))
    let source = LUISharedSourceMarker(frame: NSRect(x: 0, y: 0, width: 400, height: 3200))
    let marker = LUISharedRowMarker(frame: NSRect(x: 0, y: 0, width: 400, height: 32))
    let probe: LUISparseScrollProbe.Probe
    let window: NSWindow
    var batch = 0
    var outcomes: [(Int, String)] = []

    init() throws {
        _ = NSApplication.shared
        probe = LUISparseScrollProbe.Probe(state: state)
        window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        try apply([
            ["op": "create-node", "id": 1, "kind": "virtual-list"],
            ["op": "create-node", "id": 2, "kind": "box"],
            ["op": "insert-child", "parent": 1, "child": 2, "index": 0],
            set("virtual-total-count", 100), set("virtual-generation", 1),
            set("virtual-indices", "[0]"), set("item-extent", 32),
        ])
        state.configure(model: try #require(backend.model(id: 1)), backend: backend)
        scroll.documentView = source
        window.contentView = scroll
        source.addSubview(marker)
        source.addSubview(probe)
        source.configure(state, backend: backend)
        marker.configure(state, row: .init(id: 2, index: 0), generation: 1, backend: backend)
        state.measured(.init(id: 2, index: 0), height: 32)
        probe.connect()
        backend.onEvent = { [weak self] event in
            if case .scrollCompleted(_, let token, let outcome) = event { self?.outcomes.append((token, outcome)) }
        }
    }

    func set(_ property: String, _ value: Any) -> [String: Any] {
        ["op": "set-prop", "id": 1, "property": property, "value": value]
    }

    func apply(_ operations: [[String: Any]]) throws {
        batch += 1
        let data = try JSONSerialization.data(withJSONObject: ["generation": batch, "ops": operations])
        try backend.apply(json: String(decoding: data, as: UTF8.self))
    }

    func target(_ token: Int, index: Int = 0) throws {
        try apply([set("virtual-indices", "[\(index)]"), set("virtual-scroll-index", index),
            set("scroll-target", "key-\(index)"), set("scroll-token", token), set("scroll-animated", false)])
        state.configure(model: try #require(backend.model(id: 1)), backend: backend)
        marker.configure(state, row: .init(id: 2, index: index), generation: 1, backend: backend)
        state.flushOwnership()
    }

    func settled(_ token: Int) -> [String] { outcomes.compactMap { $0.0 == token ? $0.1 : nil } }

    func close() {
        backend.onEvent = nil
        state.dispose()
        probe.disconnect()
        window.orderOut(nil)
        window.contentView = nil
    }
}

@MainActor
@Suite("Sparse completion current-evidence boundary", .serialized)
struct LUISparseCompletionGuardTests {
    @Test("queued success rejects stale source, row and connection evidence, including optimistic writes")
    func currentNativeEvidence() async throws {
        for scenario in ["generation", "key", "rect", "row-detached", "writer-unavailable"] {
            let fixture = try SparseCompletionFixture()
            defer { fixture.close() }
            // A native no-op really at its target must succeed: rejection cannot
            // be implemented by requiring an offset-change notification.
            try fixture.target(1)
            for _ in 0..<16 { await Task.yield() }
            #expect(fixture.settled(1) == ["succeeded"], "positive control: \(scenario)")

            if scenario == "writer-unavailable" {
                fixture.probe.removeFromSuperview()
                fixture.probe.disconnect()
                fixture.marker.frame.origin.y = 1600
                try fixture.target(2, index: 50)
            } else {
                // flushOwnership queues completion synchronously; the following
                // mutation precedes its first possible MainActor resumption.
                try fixture.target(2)
                switch scenario {
                case "generation": try fixture.apply([fixture.set("virtual-generation", 2)])
                case "key": try fixture.apply([fixture.set("scroll-target", "another-key")])
                case "rect": fixture.marker.frame.origin.y = 500
                default: fixture.marker.removeFromSuperview()
                }
            }
            for _ in 0..<16 { await Task.yield() }
            #expect(fixture.settled(2).isEmpty, "stale native/source evidence: \(scenario)")
        }
    }
}
#endif
