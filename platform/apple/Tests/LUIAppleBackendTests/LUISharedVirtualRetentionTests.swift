import XCTest
@testable import LUIAppleBackend
#if os(macOS)
import AppKit

final class LUISharedVirtualRetentionTests: XCTestCase {
    @MainActor
    func testFlatMeasurementsPreserveOneVisibleAnchor() throws {
        _ = NSApplication.shared
        let backend = LUIAppleBackend()
        var batch = 0
        func set(_ id: Int, _ property: String, _ value: Any) -> [String: Any] {
            ["op": "set-prop", "id": id, "property": property, "value": value]
        }
        func apply(_ ops: [[String: Any]]) throws {
            batch += 1
            let data = try JSONSerialization.data(withJSONObject: ["generation": batch, "ops": ops])
            try backend.apply(json: String(decoding: data, as: UTF8.self))
        }
        try apply([
            ["op": "create-node", "id": 1, "kind": "scroll"],
            set(1, "virtual-viewport-epoch", 7),
            ["op": "create-node", "id": 2, "kind": "virtual-list"],
            set(2, "virtual-total-count", 3), set(2, "virtual-generation", 1),
            set(2, "virtual-indices", "[0,1,2]"), set(2, "item-extent", 100),
            set(2, "virtual-owner-node", 1), set(2, "virtual-owner-epoch", 7),
            set(2, "virtual-row-keys", #"["first","visible","tail"]"#),
            ["op": "create-node", "id": 3, "kind": "column"],
            ["op": "create-node", "id": 4, "kind": "column"],
            ["op": "create-node", "id": 5, "kind": "column"],
            ["op": "insert-child", "parent": 2, "child": 3, "index": 0],
            ["op": "insert-child", "parent": 2, "child": 4, "index": 1],
            ["op": "insert-child", "parent": 2, "child": 5, "index": 2],
            ["op": "insert-child", "parent": 1, "child": 2, "index": 0],
        ])
        let owner = try XCTUnwrap(backend.model(id: 1))
        let model = try XCTUnwrap(backend.model(id: 2))
        let state = LUISparseVirtualState()
        state.configure(model: model, backend: backend)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let document = LUISharedSourceMarker(frame: CGRect(x: 0, y: 0, width: 400, height: 4000))
        scroll.documentView = document
        window.contentView = scroll
        let anchor = LUISharedSourceMarker(frame: document.bounds)
        document.addSubview(anchor)
        let first = LUISharedRowMarker(frame: CGRect(x: 0, y: 0, width: 400, height: 90))
        let wrapper = LUISharedSourceMarker(frame: CGRect(x: 0, y: 100, width: 400, height: 100))
        let visible = LUISharedRowMarker(frame: wrapper.bounds)
        let tail = LUISharedRowMarker(frame: CGRect(x: 0, y: 200, width: 400, height: 100))
        anchor.addSubview(first)
        anchor.addSubview(wrapper)
        wrapper.addSubview(visible)
        anchor.addSubview(tail)
        first.configure(state, row: .init(id: 3, index: 0), generation: 1, backend: backend)
        visible.configure(state, row: .init(id: 4, index: 1), generation: 1, backend: backend)
        tail.configure(state, row: .init(id: 5, index: 2), generation: 1, backend: backend)
        backend.sharedVirtualViewport.owner(model: owner, scroll: scroll)
        backend.sharedVirtualViewport.sourceAnchor(state: state, view: anchor)
        window.orderFrontRegardless()
        for variation in ["crossing", "gap", "horizontal clip", "ancestor clip", "transparent row",
            "setScrollTop", "scrollIntoView", "surviving generation"] {
            wrapper.frame = CGRect(x: 0, y: 100, width: variation == "ancestor clip" ? 100 : 400, height: 100)
            wrapper.clipsToBounds = variation == "ancestor clip"
            visible.frame = CGRect(x: variation == "horizontal clip" ? 500 : variation == "ancestor clip" ? 200 : 0,
                y: 0, width: 400, height: 100)
            visible.alphaValue = variation == "transparent row" ? 0 : 1
            first.setFrameSize(CGSize(width: 400, height: 90))
            tail.setFrameOrigin(CGPoint(x: 0, y: 200))
            state.measured(.init(id: 3, index: 0), height: 90)
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            backend.sharedVirtualViewport.refresh()
            let initial: CGFloat = variation == "gap" ? 95 : 100
            scroll.contentView.scroll(to: CGPoint(x: 0, y: initial))
            scroll.reflectScrolledClipView(scroll.contentView)
            backend.sharedVirtualViewport.refresh()
            if variation == "surviving generation" {
                try apply([
                    ["op": "create-node", "id": 6, "kind": "column"],
                    ["op": "insert-child", "parent": 2, "child": 6, "index": 1],
                    set(2, "virtual-total-count", 4), set(2, "virtual-indices", "[0,1,2,3]"),
                    set(2, "virtual-row-keys", #"["first","inserted","visible","tail"]"#),
                    set(2, "virtual-generation", 2),
                ])
                backend.sharedVirtualViewport.refresh()
                XCTAssertEqual(scroll.contentView.bounds.minY, initial, accuracy: 0.1,
                    "Insertion before source.configure must retain the surviving reading anchor")
                state.configure(model: model, backend: backend)
            }
            let clipped = variation.hasSuffix("clip") || variation == "transparent row"
            first.setFrameSize(CGSize(width: 400, height: 120))
            wrapper.setFrameOrigin(CGPoint(x: 0, y: 130))
            if !clipped { tail.setFrameOrigin(CGPoint(x: 0, y: 230)) }
            state.measured(.init(id: 3, index: 0), height: 120)
            let query = LUIHostScrollMarker(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            if variation == "setScrollTop" {
                document.addSubview(query)
                query.configure(model: owner, backend: backend, ownsScroll: true)
                XCTAssertTrue(backend.setScrollTop(nodeID: 1, top: initial))
            } else if variation == "scrollIntoView" {
                // Keep the target in view so this is an explicit same-offset intent.
                first.addSubview(query)
                query.setFrameOrigin(CGPoint(x: 0, y: initial))
                query.configure(model: try XCTUnwrap(backend.model(id: 3)), backend: backend, ownsScroll: false)
                XCTAssertTrue(backend.scrollIntoView(nodeID: 3))
            }
            let expected = clipped || variation == "setScrollTop" || variation == "scrollIntoView"
                ? initial : initial + 30
            backend.sharedVirtualViewport.refresh()
            XCTAssertEqual(scroll.contentView.bounds.minY, expected, accuracy: 0.1, variation)
            if variation == "surviving generation" {
                first.configure(state, row: .init(id: 3, index: 0), generation: 2, backend: backend)
                visible.configure(state, row: .init(id: 4, index: 2), generation: 2, backend: backend)
                tail.configure(state, row: .init(id: 5, index: 3), generation: 2, backend: backend)
            }
            backend.sharedVirtualViewport.refresh()
            XCTAssertEqual(scroll.contentView.bounds.minY, expected, accuracy: 0.1,
                "Repeated refresh must not compensate twice: \(variation)")
            query.removeFromSuperview()
        }
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
            set(1, "virtual-retentions", #"[{"ticket":9,"key":"target"}]"#),
            ["op": "create-node", "id": 2, "kind": "virtual-list"],
            set(2, "virtual-total-count", 100), set(2, "virtual-generation", 1),
            set(2, "virtual-indices", "[20]"), set(2, "item-extent", 32),
            set(2, "virtual-owner-node", 1), set(2, "virtual-owner-epoch", 7),
            set(2, "virtual-row-keys", #"["target"]"#),
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
        let attested = try JSONDecoder().decode(LUIVirtualReceipt.self, from: Data(old.utf8))
        XCTAssertEqual(attested.rows.map(\.source), [2])
        XCTAssertEqual(attested.rows.map(\.row), [3], "A flat receipt attests exactly one live source row")
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
        let replacement = try backend.registerVirtualNativeView(nodeID: 3, view: field)
        defer { backend.unregisterVirtualNativeView(replacement) }
        XCTAssertTrue(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: .attached))
        let replacementProof = try XCTUnwrap(receipts().last?.1)
        XCTAssertNotEqual(replacementProof, retired, "Re-registering the same row requires fresh physical proof")
        let replacementRelease = try JSONSerialization.data(withJSONObject: [["ticket": 9, "receipt": replacementProof]])
        try apply([set(1, "virtual-retention-releases", String(decoding: replacementRelease, as: UTF8.self))])
        backend.sharedVirtualViewport.refresh()
        XCTAssertEqual(receipts().last?.0, "released")
        field.removeFromSuperview()
        XCTAssertFalse(try backend.acknowledgeVirtualRetention(ownerNode: 1, ticket: 9,
            view: field, requirements: .attached))
    }
}
#endif
