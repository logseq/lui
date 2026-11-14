import XCTest
@testable import LUIAppleBackend
#if os(macOS)
import AppKit

final class LUISharedVirtualRetentionTests: XCTestCase {
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
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: [.attached, .visible]), "An ordered-out window cannot attest visibility")
        XCTAssertTrue(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: .attached), "Window ordering does not change native attachment")
        window.orderFrontRegardless()
        XCTAssertTrue(window.isVisible)
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
        let presentations: [(String, () -> Void, () -> Void)] = [
            ("ordered-out window", { window.orderOut(nil) }, { window.orderFrontRegardless() }),
            ("transparent window", { window.alphaValue = 0 }, { window.alphaValue = 1 }),
            ("transparent ancestor", { sourceAnchor.alphaValue = 0 }, { sourceAnchor.alphaValue = 1 }),
            ("transparent control", { field.alphaValue = 0 }, { field.alphaValue = 1 }),
        ]
        for (name, hide, show) in presentations {
            XCTAssertTrue(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
                view: field, requirements: [.attached, .visible]))
            let visibleReceipt = try XCTUnwrap(receipts().last?.1)
            hide()
            defer { show() }
            events.removeAll()
            let invisibleRelease = try JSONSerialization.data(withJSONObject: [["ticket": 9, "receipt": visibleReceipt]])
            try apply([set(1, "virtual-retention-releases", String(decoding: invisibleRelease, as: UTF8.self))])
            backend.sharedVirtualViewport.refresh()
            XCTAssertEqual(receipts().map(\.0), ["stale"], "Invisible release must be refused: \(name)")
            XCTAssertFalse(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
                view: field, requirements: [.attached, .visible]), name)
            XCTAssertTrue(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
                view: field, requirements: .attached), "Attachment remains valid: \(name)")
        }
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
