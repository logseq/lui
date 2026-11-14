import XCTest
@testable import LUIAppleBackend
#if os(macOS)
import AppKit

final class LUISharedVirtualRetentionTests: XCTestCase {
    @MainActor
    func testNestedMeasurementsPreserveOneOuterVisibleAnchor() throws {
        _ = NSApplication.shared
        let backend = LUIAppleBackend()
        func set(_ id: Int, _ property: String, _ value: Any) -> [String: Any] {
            ["op": "set-prop", "id": id, "property": property, "value": value]
        }
        let ops: [[String: Any]] = [
            ["op": "create-node", "id": 1, "kind": "scroll"],
            set(1, "virtual-viewport-epoch", 7),
            set(1, "virtual-retentions", #"[{"ticket":9,"path":["root","parent","child"],"key":"first"}]"#),
            ["op": "create-node", "id": 2, "kind": "virtual-list"],
            set(2, "virtual-total-count", 30), set(2, "virtual-generation", 1),
            set(2, "virtual-indices", "[0,10]"), set(2, "item-extent", 100),
            set(2, "virtual-owner-node", 1), set(2, "virtual-owner-epoch", 7),
            set(2, "virtual-source-path", #"["root"]"#),
            set(2, "virtual-row-keys", #"["parent","visible"]"#),
            ["op": "create-node", "id": 3, "kind": "column"],
            ["op": "create-node", "id": 4, "kind": "column"],
            ["op": "create-node", "id": 5, "kind": "virtual-list"],
            set(5, "virtual-total-count", 2), set(5, "virtual-generation", 1),
            set(5, "virtual-indices", "[0,1]"), set(5, "item-extent", 50),
            set(5, "virtual-owner-node", 1), set(5, "virtual-owner-epoch", 7),
            set(5, "virtual-source-path", #"["root","parent","child"]"#),
            set(5, "virtual-row-keys", #"["first","second"]"#),
            ["op": "create-node", "id": 6, "kind": "column"],
            ["op": "create-node", "id": 7, "kind": "column"],
            ["op": "insert-child", "parent": 5, "child": 6, "index": 0],
            ["op": "insert-child", "parent": 5, "child": 7, "index": 1],
            ["op": "insert-child", "parent": 3, "child": 5, "index": 0],
            ["op": "insert-child", "parent": 2, "child": 3, "index": 0],
            ["op": "insert-child", "parent": 2, "child": 4, "index": 1],
            ["op": "insert-child", "parent": 1, "child": 2, "index": 0],
        ]
        let data = try JSONSerialization.data(withJSONObject: ["generation": 1, "ops": ops])
        try backend.apply(json: String(decoding: data, as: UTF8.self))
        let owner = try XCTUnwrap(backend.model(id: 1))
        let outer = LUISparseVirtualState(), child = LUISparseVirtualState()
        outer.configure(model: try XCTUnwrap(backend.model(id: 2)), backend: backend)
        child.configure(model: try XCTUnwrap(backend.model(id: 5)), backend: backend)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let document = LUISharedSourceMarker(frame: CGRect(x: 0, y: 0, width: 400, height: 4000))
        scroll.documentView = document
        window.contentView = scroll
        let query = LUIHostScrollMarker()
        document.addSubview(query)
        query.configure(model: owner, backend: backend, ownsScroll: true)
        let rootAnchor = LUISharedSourceMarker(frame: document.bounds)
        document.addSubview(rootAnchor)
        let parent = LUISharedRowMarker(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
        let visible = LUISharedRowMarker(frame: CGRect(x: 0, y: 1000, width: 400, height: 100))
        rootAnchor.addSubview(parent)
        rootAnchor.addSubview(visible)
        parent.configure(outer, row: .init(id: 3, index: 0), generation: 1, backend: backend)
        visible.configure(outer, row: .init(id: 4, index: 10), generation: 1, backend: backend)
        let childAnchor = LUISharedSourceMarker(frame: parent.bounds)
        parent.addSubview(childAnchor)
        let first = LUISharedRowMarker(frame: CGRect(x: 0, y: 0, width: 400, height: 50))
        let second = LUISharedRowMarker(frame: CGRect(x: 0, y: 50, width: 400, height: 50))
        childAnchor.addSubview(first)
        childAnchor.addSubview(second)
        first.configure(child, row: .init(id: 6, index: 0), generation: 1, backend: backend)
        second.configure(child, row: .init(id: 7, index: 1), generation: 1, backend: backend)
        backend.sharedVirtualViewport.owner(model: owner, scroll: scroll)
        backend.sharedVirtualViewport.sourceAnchor(state: outer, view: rootAnchor)
        backend.sharedVirtualViewport.sourceAnchor(state: child, view: childAnchor)
        outer.measured(.init(id: 3, index: 0), height: 100)
        outer.measured(.init(id: 4, index: 10), height: 100)
        child.measured(.init(id: 6, index: 0), height: 50)
        child.measured(.init(id: 7, index: 1), height: 50)
        XCTAssertTrue(backend.setScrollTop(nodeID: 1, top: 1000))
        backend.sharedVirtualViewport.refresh()
        child.measured(.init(id: 6, index: 0), height: 80)
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(scroll.contentView.bounds.minY, 1000, accuracy: 0.1,
            "Offscreen child measurements must not independently move the outer owner")
        parent.setFrameSize(CGSize(width: 400, height: 130))
        childAnchor.setFrameSize(parent.frame.size)
        first.setFrameSize(CGSize(width: 400, height: 80))
        second.setFrameOrigin(CGPoint(x: 0, y: 80))
        visible.setFrameOrigin(CGPoint(x: 0, y: 1030))
        outer.measured(.init(id: 3, index: 0), height: 130)
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(scroll.contentView.bounds.minY, 1030, accuracy: 0.1)
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(scroll.contentView.bounds.minY, 1030, accuracy: 0.1,
            "Parent propagation of the same growth must not compensate twice")
        XCTAssertTrue(backend.setScrollTop(nodeID: 1, top: 100))
        backend.sharedVirtualViewport.refresh()
        child.measured(.init(id: 6, index: 0), height: 100)
        first.setFrameSize(CGSize(width: 400, height: 100))
        second.setFrameOrigin(CGPoint(x: 0, y: 100))
        parent.setFrameSize(CGSize(width: 400, height: 150))
        childAnchor.setFrameSize(parent.frame.size)
        visible.setFrameOrigin(CGPoint(x: 0, y: 1050))
        outer.measured(.init(id: 3, index: 0), height: 150)
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(scroll.contentView.bounds.minY, 120, accuracy: 0.1,
            "A visible descendant's leading row remains anchored within its ancestor row")
    }

    @MainActor
    func testReleaseRequiresCurrentNativeRowAndPinFeedback() throws {
        _ = NSApplication.shared
        let backend = LUIAppleBackend()
        var generation = 0
        func apply(_ ops: [[String: Any]]) throws {
            generation += 1
            let data = try JSONSerialization.data(withJSONObject: ["generation": generation, "ops": ops])
            try backend.apply(json: String(decoding: data, as: UTF8.self))
        }
        func set(_ id: Int, _ property: String, _ value: Any) -> [String: Any] {
            ["op": "set-prop", "id": id, "property": property, "value": value]
        }
        try apply([
            ["op": "create-node", "id": 1, "kind": "scroll"],
            set(1, "virtual-viewport-epoch", 7),
            set(1, "virtual-retentions", #"[{"ticket":9,"path":["selected"],"key":"target"}]"#),
            ["op": "create-node", "id": 2, "kind": "virtual-list"],
            set(2, "virtual-total-count", 100), set(2, "virtual-generation", 1),
            set(2, "virtual-indices", "[20]"), set(2, "item-extent", 32),
            set(2, "virtual-owner-node", 1), set(2, "virtual-owner-epoch", 7),
            set(2, "virtual-source-path", #"["selected"]"#), set(2, "virtual-row-keys", #"["target"]"#),
            ["op": "create-node", "id": 3, "kind": "text-field"],
            ["op": "insert-child", "parent": 2, "child": 3, "index": 0],
            ["op": "insert-child", "parent": 1, "child": 2, "index": 0],
        ])
        let owner = try XCTUnwrap(backend.model(id: 1))
        let source = try XCTUnwrap(backend.model(id: 2))
        let state = LUISparseVirtualState()
        state.configure(model: source, backend: backend)
        state.measured(.init(id: 3, index: 20), height: 32)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let document = LUISharedSourceMarker(frame: CGRect(x: 0, y: 0, width: 400, height: 4000))
        scroll.documentView = document
        window.contentView = scroll
        let sourceAnchor = LUISharedSourceMarker(frame: CGRect(x: 0, y: 500, width: 400, height: 3200))
        document.addSubview(sourceAnchor)
        let rowAnchor = LUISharedRowMarker(frame: CGRect(x: 0, y: 640, width: 400, height: 32))
        sourceAnchor.addSubview(rowAnchor)
        rowAnchor.configure(state, row: .init(id: 3, index: 20), generation: 1, backend: backend)
        let field = NSTextField(frame: CGRect(x: 10, y: 0, width: 200, height: 24))
        rowAnchor.addSubview(field)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 1000))
        scroll.reflectScrolledClipView(scroll.contentView)
        backend.sharedVirtualViewport.owner(model: owner, scroll: scroll)
        backend.sharedVirtualViewport.sourceAnchor(state: state, view: sourceAnchor)
        backend.sharedVirtualViewport.refresh()
        XCTAssertFalse(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: [.attached, .visible]), "Unregistered views cannot acknowledge")
        let registration = try backend.registerVirtualNativeView(nodeID: 3, view: field)
        defer { backend.unregisterVirtualNativeView(registration) }
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        XCTAssertTrue(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: [.attached, .visible]))
        func receipts() -> [(String, String)] {
            events.compactMap { event in
                guard case let .virtualRetention(_, _, envelope) = event,
                      let receipt = try? JSONDecoder().decode(LUIVirtualReceipt.self, from: Data(envelope.utf8)) else { return nil }
                return (receipt.status, envelope)
            }
        }
        let old = try XCTUnwrap(receipts().last?.1)
        try apply([set(2, "virtual-generation", 2), set(2, "virtual-indices", "[21]")])
        state.configure(model: source, backend: backend)
        backend.sharedVirtualViewport.refresh()
        rowAnchor.configure(state, row: .init(id: 3, index: 21), generation: 2, backend: backend)
        XCTAssertFalse(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: [.attached, .visible]), "Logical generation cannot attest an unmoved physical row")
        let release = try JSONSerialization.data(withJSONObject: [["ticket": 9, "receipt": old]], options: [.sortedKeys])
        let releaseValue = String(decoding: release, as: UTF8.self)
        try apply([set(1, "virtual-retention-releases", releaseValue)])
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(receipts().last?.0, "stale")
        XCTAssertFalse(receipts().contains { $0.0 == "released" })
        rowAnchor.setFrameOrigin(CGPoint(x: 0, y: 672))
        backend.sharedVirtualViewport.refresh()
        events.removeAll()
        XCTAssertTrue(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: [.attached, .visible]))
        let fresh = try XCTUnwrap(receipts().last?.1)
        let freshRelease = try JSONSerialization.data(withJSONObject: [["ticket": 9, "receipt": fresh]], options: [.sortedKeys])
        try apply([set(1, "virtual-retention-releases", String(decoding: freshRelease, as: UTF8.self))])
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(receipts().last?.0, "released")
        let releasedIndex = try XCTUnwrap(events.firstIndex {
            if case let .virtualRetention(_, _, envelope) = $0,
                let receipt = try? JSONDecoder().decode(LUIVirtualReceipt.self, from: Data(envelope.utf8)) {
                return receipt.status == "released"
            }
            return false
        })
        XCTAssertTrue(events[..<releasedIndex].contains {
            if case let .virtualWindow(_, generation, _, _, pins) = $0 { return generation == 2 && pins.contains(3) }
            return false
        }, "Current-generation physical pin feedback must precede release")
        sourceAnchor.frameRotation = 180
        backend.sharedVirtualViewport.refresh()
        XCTAssertFalse(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: .attached), "Rotated sources cannot attest document geometry")
        sourceAnchor.frameRotation = 0
        XCTAssertTrue(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: .attached))
        let retired = try XCTUnwrap(receipts().last?.1)
        backend.unregisterVirtualNativeView(registration)
        backend.sharedVirtualViewport.refresh()
        events.removeAll()
        let retiredRelease = try JSONSerialization.data(withJSONObject: [["ticket": 9, "receipt": retired]])
        try apply([set(1, "virtual-retention-releases", String(decoding: retiredRelease, as: UTF8.self))])
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(receipts().map(\.0), ["stale"], "Retired native proof must explicitly refuse release")
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(receipts().count, 1, "An unchanged refused release is answered once")
        field.removeFromSuperview()
        XCTAssertFalse(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: .attached))
    }
}
#endif
