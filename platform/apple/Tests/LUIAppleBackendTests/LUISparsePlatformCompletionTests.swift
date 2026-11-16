import Testing
@testable import LUIAppleBackend
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if os(macOS) || os(iOS)
@MainActor
private final class PlatformCompletionFixture {
    let backend = LUIAppleBackend()
    let state = LUISparseVirtualState()
    let scroll = LUIHostNativeScroll(frame: CGRect(x: 0, y: 0, width: 400, height: 320))
    let document: LUISharedSourceMarker
    let source: LUISharedSourceMarker
    let marker: LUISharedRowMarker
    let probe: LUISparseScrollProbe.Probe
    #if os(macOS)
    let window: NSWindow
    #else
    let window: UIWindow
    #endif
    let shared: Bool
    let index: Int
    var batch = 0
    var outcomes: [(Int, String)] = []

    init(shared: Bool, index: Int = 50, documentHeight: CGFloat = 8000) throws {
        self.shared = shared
        self.index = index
        let sourceTop: CGFloat = shared ? 400 : 80
        document = LUISharedSourceMarker(frame: CGRect(x: 0, y: 0, width: 400, height: documentHeight))
        source = LUISharedSourceMarker(frame: CGRect(x: 0, y: sourceTop, width: 400, height: 3200))
        marker = LUISharedRowMarker(frame: CGRect(x: 0, y: index * 32, width: 400, height: 32))
        probe = LUISparseScrollProbe.Probe(state: state)
        #if os(macOS)
        _ = NSApplication.shared
        window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = document
        window.contentView = scroll
        #else
        window = UIWindow(frame: scroll.frame)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(scroll)
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = UIEdgeInsets(top: 40, left: 11, bottom: 24, right: 7)
        scroll.contentSize = document.frame.size
        scroll.addSubview(document)
        #endif
        document.addSubview(source)
        source.addSubview(marker)
        source.addSubview(probe)
        var operations: [[String: Any]] = [
            ["op": "create-node", "id": 2, "kind": "virtual-list"],
            ["op": "create-node", "id": 3, "kind": "box"],
            ["op": "insert-child", "parent": 2, "child": 3, "index": 0],
            set(2, "virtual-total-count", 100), set(2, "virtual-generation", 1),
            set(2, "virtual-indices", "[\(index)]"), set(2, "item-extent", 32),
        ]
        if shared {
            operations += [
                ["op": "create-node", "id": 1, "kind": "scroll"],
                ["op": "insert-child", "parent": 1, "child": 2, "index": 0],
                set(1, "virtual-viewport-epoch", 7), set(2, "virtual-owner-node", 1),
                set(2, "virtual-owner-epoch", 7), set(2, "virtual-row-keys", #"["target-key"]"#),
            ]
        }
        try apply(operations)
        state.configure(model: try #require(backend.model(id: 2)), backend: backend)
        source.configure(state, backend: backend)
        marker.configure(state, row: .init(id: 3, index: index), generation: 1, backend: backend)
        state.measured(.init(id: 3, index: index), height: 32)
        if shared {
            backend.sharedVirtualViewport.owner(model: try #require(backend.model(id: 1)), scroll: scroll)
            backend.sharedVirtualViewport.refresh()
        } else {
            probe.connect()
        }
        backend.onEvent = { [weak self] event in
            if case .scrollCompleted(2, let token, let outcome) = event {
                self?.outcomes.append((token, outcome))
            }
        }
    }

    func set(_ node: Int, _ property: String, _ value: Any) -> [String: Any] {
        ["op": "set-prop", "id": node, "property": property, "value": value]
    }

    func apply(_ operations: [[String: Any]]) throws {
        batch += 1
        let data = try JSONSerialization.data(withJSONObject: ["generation": batch, "ops": operations])
        try backend.apply(json: String(decoding: data, as: UTF8.self))
    }

    func target(_ token: Int) throws {
        try apply([set(2, "virtual-scroll-index", index), set(2, "scroll-target", "target-key"),
            set(2, "scroll-token", token), set(2, "scroll-animated", false)])
        state.configure(model: try #require(backend.model(id: 2)), backend: backend)
        state.flushOwnership()
    }

    func sample() throws -> LUISparseNativeObservation {
        if shared {
            return try #require(backend.sharedVirtualViewport.completionObservation(
                state: state, row: .init(id: 3, index: index), key: "target-key"))
        }
        return try #require(LUISparseNativeObservation.read(scroll: scroll, source: source, marker: marker))
    }

    func settled(_ token: Int) -> [String] {
        outcomes.compactMap { $0.0 == token ? $0.1 : nil }
    }

    func close() {
        backend.onEvent = nil
        state.dispose()
        probe.disconnect()
        #if os(macOS)
        window.contentView = nil
        #else
        window.rootViewController = nil
        #endif
    }
}

@MainActor
@Suite("Sparse completion platform coordinate domains", .serialized)
struct LUISparsePlatformCompletionTests {
    #if os(macOS)
    @Test("AppKit completion geometry matches the native scroll writer under content insets")
    func appKitInsetViewport() throws {
        let fixture = try PlatformCompletionFixture(shared: false)
        defer { fixture.close() }
        fixture.scroll.contentInsets = NSEdgeInsets(top: 1, left: 0, bottom: 2, right: 0)
        fixture.scroll.layoutSubtreeIfNeeded()
        fixture.probe.connect()
        let sample = try fixture.sample()
        let viewport = fixture.scroll.documentVisibleRect.height
        #expect(sample.geometry.height == viewport)
        #expect(sample.geometry.documentHeight - sample.geometry.height
            == fixture.document.bounds.height - viewport)
    }

    #endif

    @Test("shared completion uses nonzero source origins, outer clamping and current owner epochs")
    func sharedOwnerEvidence() async throws {
        for scenario in ["interior", "owner-bottom", "stale-owner"] {
            let fixture = try PlatformCompletionFixture(shared: true,
                index: scenario == "owner-bottom" ? 99 : 50,
                documentHeight: scenario == "owner-bottom" ? 3800 : 8000)
            defer { fixture.close() }
            // Keep outer clamping distinct; center interior rows inside the
            // inset-adjusted native viewport before relying on readiness.
            try fixture.apply([fixture.set(2, "scroll-anchor",
                scenario == "owner-bottom" ? "top" : "center")])
            try fixture.target(1)
            let sample = try fixture.sample()
            #if os(macOS)
            let expectedOrigin: CGFloat = 400
            let expectedLocal: CGFloat = scenario == "owner-bottom" ? 3080 : 1456
            let nativeViewport = fixture.scroll.contentView.bounds
            let nativeRow = fixture.marker.convert(fixture.marker.bounds, to: fixture.scroll.contentView)
            #else
            let expectedOrigin: CGFloat = 440
            let expectedLocal: CGFloat = scenario == "owner-bottom" ? 3104 : 1488
            let nativeViewport = fixture.scroll.bounds.inset(by: fixture.scroll.adjustedContentInset)
            let nativeRow = fixture.marker.convert(fixture.marker.bounds, to: fixture.scroll)
            #endif
            #expect(sample.geometry.origin == expectedOrigin)
            #expect(sample.geometry.localOffset == expectedLocal)
            #expect(sample.geometry.offset == expectedOrigin + expectedLocal)
            #expect(fixture.state.desiredOffset == expectedLocal)
            #expect(sample.anchorRect.minY == expectedOrigin + CGFloat(fixture.index * 32))
            let nativeIntersection = nativeRow.intersection(nativeViewport)
            try #require(!nativeIntersection.isNull
                && nativeIntersection.width > 0 && nativeIntersection.height > 0)
            try #require(sample.intersectsViewport)
            for _ in 0..<16 { await Task.yield() }
            try #require(fixture.settled(1) == ["succeeded"], "native shared target: \(scenario)")
            if scenario == "stale-owner" {
                // Advance both retained epochs atomically after success is
                // queued; the native source registration is still bound to 7.
                try fixture.target(2)
                try fixture.apply([fixture.set(1, "virtual-viewport-epoch", 8),
                    fixture.set(2, "virtual-owner-epoch", 8)])
                for _ in 0..<16 { await Task.yield() }
                #expect(fixture.settled(2).isEmpty)
            }
        }
    }

    #if os(iOS)
    @Test("UIKit standalone completion uses adjusted absolute offsets and fresh inset evidence")
    func uiKitInsetEvidence() async throws {
        for scenario in ["native-no-op", "invalidated-insets"] {
            let fixture = try PlatformCompletionFixture(shared: false)
            defer { fixture.close() }
            // Put the native view at the target before issuing the request:
            // completion must not depend on receiving an offset-change event.
            fixture.scroll.setContentOffset(CGPoint(x: 0, y: 1560), animated: false)
            fixture.probe.connect()
            try fixture.target(1)
            let sample = try fixture.sample()
            #expect(sample.insets == [40, 11, 24, 7])
            #expect(sample.geometry.offset == 1600)
            #expect(sample.geometry.origin == 120)
            #expect(sample.geometry.localOffset == 1480)
            #expect(sample.geometry.height == 256)
            #expect(fixture.state.desiredOffset == 1600)
            #expect(fixture.scroll.contentOffset.y == 1560)
            for _ in 0..<16 { await Task.yield() }
            #expect(fixture.settled(1) == ["succeeded"], "native UIKit target: \(scenario)")
            if scenario == "invalidated-insets" {
                try fixture.target(2)
                fixture.scroll.contentInset.bottom = 400
                fixture.probe.connect()
                #expect(fixture.state.observedOffset == nil)
                for _ in 0..<16 { await Task.yield() }
                #expect(fixture.settled(2).isEmpty)
                fixture.scroll.contentInset.bottom = 24
                fixture.scroll.setContentOffset(CGPoint(x: 0, y: 1560), animated: false)
                fixture.probe.connect()
                fixture.state.flushOwnership()
                for _ in 0..<16 { await Task.yield() }
                #expect(fixture.settled(2) == ["succeeded"])
            }
        }
    }
    #endif
}
#endif
