#if os(macOS)
  import AppKit
  import Foundation
  import SwiftUI
  import Testing
  @testable import LUIAppleBackend

  @MainActor
  private final class SparseRowLifetimes {
    var views: [Int: WeakView] = [:]
    final class WeakView {
      weak var value: SparsePointerView?
      init(_ view: SparsePointerView) { value = view }
    }
  }

  private final class SparsePointerView: NSView {
    var held = false
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { held = true }
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { held = false }
  }

  @MainActor
  private struct SparsePointerRow: NSViewRepresentable {
    let id: Int
    let lifetimes: SparseRowLifetimes
    func makeNSView(context: Context) -> SparsePointerView {
      let view = SparsePointerView()
      lifetimes.views[id] = .init(view)
      return view
    }
    func updateNSView(_ nsView: SparsePointerView, context: Context) {}
  }

  @MainActor
  private final class SparseHostFixture {
    let backend: LUIAppleBackend
    let lifetimes = SparseRowLifetimes()
    var batch = 0
    var epoch = 1
    var count = 100000
    var roots: [Int: Int] = [:]
    var nextID = 100
    var events: [LUIEvent] = []
    var errors: [String] = []
    var responses = true
    var variable = false
    var rowHeight = 32
    var trackingMenu: NSMenu?
    let hosting: NSHostingView<LUISwiftUIRoot>
    let window: NSWindow

    init(itemExtent: Int = 32, gap: Int = 0) throws {
      rowHeight = itemExtent
      let registry = LUIAppleExtensionRegistry()
      let lifetimes = self.lifetimes
      try registry.register(
        LUIAppleExtension(
          identifier: "sparse-pointer", fingerprint: "v1",
          properties: [.init(name: "row-height", kind: .int, defaultValue: .int(32))]
        ) { context in
          let height: Int
          if case .int(let value)? = context.property("row-height") {
            height = value
          } else {
            height = 32
          }
          return AnyView(
            SparsePointerRow(id: context.nodeID, lifetimes: lifetimes).frame(
              height: CGFloat(height)))
        })
      backend = try LUIAppleBackend(extensionRegistry: registry)
      _ = NSApplication.shared
      hosting = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
      window = NSWindow(
        contentRect: NSRect(x: -10000, y: 0, width: 400, height: 320),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = hosting
      try apply(
        [
          ["op": "create-node", "id": 1, "kind": "virtual-list"],
          ["op": "set-prop", "id": 1, "property": "height", "value": 320],
          ["op": "set-prop", "id": 1, "property": "overscan", "value": 2],
          ["op": "set-prop", "id": 1, "property": "item-extent", "value": itemExtent],
          ["op": "set-prop", "id": 1, "property": "gap", "value": gap],
        ] + metadata([]))
      backend.onEvent = { [weak self] event in
        guard let self else { return }
        events.append(event)
        if case .virtualWindow(let node, let generation, let first, let last, let pins) = event,
          responses, node == 1, generation == epoch
        {
          do { try answer(first: first, last: last, pins: pins) } catch {
            errors.append(String(describing: error))
          }
        }
      }
      window.orderFrontRegardless()
    }
    func close() {
      backend.onEvent = nil
      window.orderOut(nil)
      window.contentView = nil
    }
    func apply(_ ops: [[String: Any]]) throws {
      batch += 1
      let data = try JSONSerialization.data(withJSONObject: ["generation": batch, "ops": ops])
      try backend.apply(json: String(decoding: data, as: UTF8.self))
    }
    func metadata(_ indices: [Int]) -> [[String: Any]] {
      let vector = String(decoding: try! JSONEncoder().encode(indices), as: UTF8.self)
      return [
        ("virtual-total-count", count as Any), ("virtual-generation", epoch as Any),
        ("virtual-indices", vector as Any),
      ].map {
        ["op": "set-prop", "id": 1, "property": $0.0, "value": $0.1]
      }
    }
    var indices: [Int] { roots.keys.sorted() }
    func answer(first: Int, last: Int, pins: [Int], extra: [[String: Any]] = []) throws {
      let pinnedIndices = roots.compactMap { pins.contains($0.value) ? $0.key : nil }
      let desired = Set(max(0, first)..<min(count, max(first, last))).union(
        pinnedIndices.filter { $0 < count })
      var ops: [[String: Any]] = []
      for (index, root) in roots where !desired.contains(index) {
        ops.append(["op": "detach-subtree", "id": root])
        roots.removeValue(forKey: index)
      }
      for index in desired.sorted() where roots[index] == nil {
        let id = nextID
        nextID += 1
        roots[index] = id
        ops += [
          [
            "op": "create-extension", "id": id, "identifier": "sparse-pointer", "fingerprint": "v1",
          ],
          [
            "op": "set-extension-prop", "id": id, "property": "row-height",
            "value": variable && index % 2 == 1 ? rowHeight * 2 : rowHeight,
          ],
          ["op": "insert-child", "parent": 1, "child": id, "index": 0],
        ]
      }
      for (offset, index) in indices.enumerated() {
        ops.append(["op": "move-child", "parent": 1, "child": roots[index]!, "index": offset])
      }
      try apply(ops + extra + metadata(indices))
    }
    func wait(_ description: String, until predicate: () -> Bool) async throws {
      let deadline = ContinuousClock.now + .seconds(5)
      repeat {
        hosting.layoutSubtreeIfNeeded()
        #expect(errors.isEmpty)
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(15))
      } while ContinuousClock.now < deadline
      throw NSError(
        domain: "SparseHostTest", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
    func nativeScroll(_ root: NSView? = nil) -> NSScrollView? {
      let root = root ?? hosting
      if let scroll = root as? NSScrollView { return scroll }
      return root.subviews.lazy.compactMap { self.nativeScroll($0) }.first
    }
    func scrollTo(_ y: CGFloat) throws {
      let scroll = try #require(nativeScroll())
      scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
      scroll.reflectScrolledClipView(scroll.contentView)
    }
    func send(_ type: NSEvent.EventType, to view: NSView) throws {
      let point = view.convert(NSPoint(x: 10, y: 10), to: nil)
      let event = try #require(
        NSEvent.mouseEvent(
          with: type, location: point, modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
          context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
      NSApp.sendEvent(event)
    }
  }

  @MainActor
  @Suite("Sparse native geometry and ownership", .serialized)
  struct LUISparseVirtualHostTests {
    @Test("whole-valued extent and gap determine actual native geometry and requested rows")
    func wholeNumericGeometry() async throws {
      let h = try SparseHostFixture(itemExtent: 64, gap: 7)
      defer { h.close() }
      try await h.wait("native rows at nondefault extent") { h.roots[2] != nil }
      let scroll = try #require(h.nativeScroll())
      try await h.wait("full logical extent includes authored gap") {
        abs((scroll.documentView?.frame.height ?? 0) - 7_099_993) < 1
      }
      try h.scrollTo(7100)
      try await h.wait("row 100 occupies authored offset") {
        guard let id = h.roots[100], let view = h.lifetimes.views[id]?.value else { return false }
        let origin = view.convert(view.bounds, to: scroll.contentView).minY
        return abs(origin - scroll.contentView.bounds.minY) < 1 && abs(view.frame.height - 64) < 1
      }
      guard
        case .virtualWindow(_, _, let first, let last, _) = h.events.last(where: {
          if case .virtualWindow = $0 { return true }
          return false
        })
      else {
        Issue.record("missing native viewport feedback")
        return
      }
      #expect(first == 98)
      #expect(last == 107)
      #expect(h.indices == Array(98..<107))
    }

    @Test("pointer hold pins an arbitrary extension root without user pointer subscriptions")
    func pointerAndDragOwnership() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try await h.wait("initial rows") { h.roots[2] != nil }
      let id = try #require(h.roots[2])
      try await h.wait("native extension") { h.lifetimes.views[id]?.value != nil }
      let view = try #require(h.lifetimes.views[id]?.value)
      try h.send(.leftMouseDown, to: view)
      #expect(view.held)
      try h.scrollTo(3_200_000 - 320)
      try await h.wait("far viewport with one pressed pin") {
        h.indices.contains(99999) && h.roots[2] == id
      }
      #expect(h.indices.count < 32)
      #expect(h.lifetimes.views[id]?.value === view)
      try h.send(.leftMouseDragged, to: view)
      #expect(h.roots[2] == id)
      try h.send(.leftMouseUp, to: view)
      try await h.wait("released owner evicted") { h.roots[2] == nil }
      #expect(
        h.events.contains {
          if case .virtualWindow(_, _, let first, _, let pins) = $0 {
            return first > 99000 && pins == [id]
          }
          return false
        })
    }

    @Test("visible range excludes overscan and pins while internal requests remain half open")
    func visibleRangeAndDeduplication() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try h.apply([["op": "set-prop", "id": 1, "property": "track-visible-range", "value": true]])
      try await h.wait("requested rows") { !h.indices.isEmpty }
      let requests = h.events.filter {
        if case .virtualWindow = $0 { return true }
        return false
      }
      #expect(!requests.isEmpty)
      try h.scrollTo(3200)
      try await h.wait("100th row viewport") { h.indices.contains(100) }
      guard
        case .virtualWindow(_, let generation, let first, let last, _) = h.events.last(where: {
          if case .virtualWindow = $0 { return true }
          return false
        })
      else {
        Issue.record("missing half-open request")
        return
      }
      #expect(generation == h.epoch)
      #expect(first <= 98 && last >= 112 && last - first < 32)
      #expect(
        h.events.contains {
          if case .visibleRange(_, let a, let b) = $0 {
            return a >= 100 && b < 110
          }
          return false
        })
      let before = h.events.count
      for _ in 0..<5 {
        h.hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
      }
      #expect(h.events.count == before)
    }

    @Test("source epochs reissue stationary requests and stale queued work cannot resurrect rows")
    func sourceEpochAndUnmount() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try await h.wait("initial rows") { !h.indices.isEmpty }
      let old = Set(h.roots.values)
      h.epoch += 1
      try h.apply(h.metadata(h.indices))
      try await h.wait("new epoch request") {
        h.events.contains {
          if case .virtualWindow(_, let generation, _, _, _) = $0 { return generation == h.epoch }
          return false
        }
      }
      h.responses = false
      try h.scrollTo(3_200_000 - 320)
      h.count = 0
      h.epoch += 1
      try h.answer(first: 0, last: 0, pins: [])
      try await h.wait("empty graph") { h.roots.isEmpty }
      #expect(old.allSatisfy { h.backend.extensionModel(id: $0) == nil })
      try h.apply([["op": "detach-subtree", "id": 1]])
      let count = h.events.count
      for _ in 0..<5 { try await Task.sleep(for: .milliseconds(20)) }
      #expect(
        h.events.dropFirst(count).allSatisfy {
          if case .virtualWindow = $0 { return false }
          return true
        })
    }

    @Test("measured rows change extent and preserve the actual reading anchor")
    func variableHeightsAndAnchor() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      h.variable = true
      try await h.wait("initial measured rows") { !h.indices.isEmpty && h.nativeScroll() != nil }
      try h.scrollTo(3200)
      try await h.wait("measured viewport") { h.indices.contains(100) }
      let scroll = try #require(h.nativeScroll())
      let visible = h.indices.compactMap { index -> (Int, NSView, CGFloat)? in
        guard let id = h.roots[index], let view = h.lifetimes.views[id]?.value else { return nil }
        let rect = view.convert(view.bounds, to: scroll.contentView).offsetBy(
          dx: 0, dy: -scroll.contentView.bounds.minY)
        return rect.minY >= 0 && rect.minY < 320 ? (index, view, rect.minY) : nil
      }
      let anchor = try #require(visible.first)
      let anchorID = try #require(h.roots[anchor.0])
      let preceding = try #require(
        h.indices.first(where: { $0 < anchor.0 }).flatMap { h.roots[$0] })
      let precedingView = try #require(h.lifetimes.views[preceding]?.value)
      let oldHeight = precedingView.bounds.height
      let oldOffset = scroll.contentView.bounds.minY
      try h.apply([
        ["op": "set-extension-prop", "id": preceding, "property": "row-height", "value": 128]
      ])
      try await h.wait("height correction") {
        abs(precedingView.bounds.height - 128) < 1
          && abs(scroll.contentView.bounds.minY - oldOffset - (128 - oldHeight)) < 2
          && abs(
            anchor.1.convert(anchor.1.bounds, to: scroll.contentView).minY
              - scroll.contentView.bounds.minY - anchor.2) < 2
      }
      #expect(h.roots[anchor.0] == anchorID)
      #expect(h.indices.count < 32)
    }

    @Test(
      "far targets acknowledge native geometry, supersession, missing targets and reused tokens")
    func scrollTokens() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try await h.wait("initial rows") { !h.indices.isEmpty }
      func target(_ index: Int, token: Int, animated: Bool = false) throws {
        try h.apply([
          ["op": "set-prop", "id": 1, "property": "virtual-scroll-index", "value": index],
          ["op": "set-prop", "id": 1, "property": "scroll-token", "value": token],
          ["op": "set-prop", "id": 1, "property": "scroll-target", "value": "key-\(index)"],
          ["op": "set-prop", "id": 1, "property": "scroll-animated", "value": animated],
        ])
      }
      func outcomes(_ token: Int) -> [String] {
        h.events.compactMap {
          if case .scrollCompleted(_, let value, let outcome) = $0, value == token {
            return outcome
          }
          return nil
        }
      }
      try target(99999, token: 1)
      try await h.wait("far geometry and completion") {
        h.indices.contains(99999) && outcomes(1) == ["succeeded"]
      }
      #expect((h.nativeScroll()?.contentView.bounds.minY ?? 0) > 3_000_000)
      try target(99999, token: 1)
      try target(-1, token: 2)
      try await h.wait("missing target settles once") { outcomes(2) == ["missing-target"] }
      #expect(outcomes(1) == ["succeeded"])
      h.responses = false
      try target(0, token: 3, animated: true)
      try await h.wait("third request is pending native row materialization") {
        h.events.contains {
          if case .virtualWindow(_, _, let first, _, _) = $0 { return first == 0 }
          return false
        } && (h.nativeScroll()?.contentView.bounds.minY ?? 1) < 1
      }
      h.responses = true
      try target(50000, token: 4)
      try await h.wait("superseded and current tokens") {
        !outcomes(3).isEmpty && !outcomes(4).isEmpty
      }
      #expect(outcomes(3) == ["cancelled"])
      #expect(outcomes(4) == ["succeeded"])
      #expect(h.indices.count < 32)
      h.responses = false
      try target(99999, token: 5)
      try await h.wait("fifth request is pending") {
        (h.nativeScroll()?.contentView.bounds.minY ?? 0) > 3_000_000
      }
      h.count = 0
      h.epoch += 1
      try h.answer(
        first: 0, last: 0, pins: [],
        extra: [
          ["op": "set-prop", "id": 1, "property": "virtual-scroll-index", "value": -1]
        ])
      try await h.wait("removed target completes once") { outcomes(5) == ["missing-target"] }
    }

    @Test("a mounted popup retains its row anchor until dismissal")
    func popupOwnership() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try await h.wait("initial rows") { h.roots[2] != nil }
      let previous = try #require(h.roots[2])
      let root = h.nextID
      h.nextID += 4
      h.roots[2] = root
      var ops: [[String: Any]] = [["op": "detach-subtree", "id": previous]]
      for (id, kind) in [
        (root, "stack"), (root + 1, "select"), (root + 2, "dropdown-menu"), (root + 3, "menu-item"),
      ] {
        ops.append(["op": "create-node", "id": id, "kind": kind])
      }
      ops += [
        ["op": "set-prop", "id": root + 1, "property": "text", "value": "Popup anchor"],
        ["op": "set-prop", "id": root + 2, "property": "anchor", "value": "below"],
        ["op": "set-prop", "id": root + 3, "property": "text", "value": "Popup choice"],
        ["op": "insert-child", "parent": root, "child": root + 1, "index": 0],
        ["op": "insert-child", "parent": root, "child": root + 2, "index": 1],
        ["op": "insert-child", "parent": root + 2, "child": root + 3, "index": 0],
        ["op": "insert-child", "parent": 1, "child": root, "index": 2],
      ]
      try h.apply(ops + h.metadata(h.indices))
      try await h.wait("native popup window") {
        NSApp.windows.contains {
          $0 !== h.window && $0.isVisible && String(describing: type(of: $0)).contains("Popover")
        }
      }
      try h.scrollTo(3_200_000 - 320)
      try await h.wait("popup anchor retained offscreen") {
        h.indices.contains(99999) && h.roots[2] == root
      }
      #expect(h.indices.count < 32)
      #expect(h.backend.model(id: root + 2) != nil)
      try h.apply([["op": "detach-subtree", "id": root + 2]])
      try await h.wait("dismissed popup releases row") { h.roots[2] == nil }
    }

    @Test("closed native menu children do not pin historical rows")
    func closedMenusAreEvicted() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try await h.wait("initial rows") { h.roots[2] != nil }
      let previous = try #require(h.roots[2])
      let root = h.nextID
      h.nextID += 3
      h.roots[2] = root
      try h.apply(
        [
          ["op": "detach-subtree", "id": previous],
          ["op": "create-node", "id": root, "kind": "menu-trigger"],
          ["op": "set-prop", "id": root, "property": "text", "value": "Closed menu"],
          ["op": "create-node", "id": root + 1, "kind": "dropdown-menu"],
          ["op": "create-node", "id": root + 2, "kind": "menu-item"],
          ["op": "set-prop", "id": root + 2, "property": "text", "value": "Choice"],
          ["op": "insert-child", "parent": root + 1, "child": root + 2, "index": 0],
          ["op": "insert-child", "parent": root, "child": root + 1, "index": 0],
          ["op": "insert-child", "parent": 1, "child": root, "index": 2],
        ] + h.metadata(h.indices))
      try h.scrollTo(3_200_000 - 320)
      try await h.wait("closed menu is retired outside the viewport") {
        h.indices.contains(99999) && h.roots[2] == nil
      }
      #expect(h.backend.model(id: root) == nil)
    }

    @Test("an actual tracking NSMenu owns its extension row until native tracking ends")
    func nativeMenuTrackingOwnership() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try await h.wait("initial native row") {
        h.roots[2].flatMap { h.lifetimes.views[$0]?.value } != nil
      }
      let id = try #require(h.roots[2])
      let view = try #require(h.lifetimes.views[id]?.value)
      let menu = NSMenu(title: "Native row menu")
      h.trackingMenu = menu
      defer { h.trackingMenu = nil }
      menu.addItem(withTitle: "Choice", action: nil, keyEquivalent: "")
      view.menu = menu
      var retainedWhileTracking = false
      var requestedFar = false
      let deadline = ContinuousClock.now + .seconds(3)
      let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
        MainActor.assumeIsolated {
          if !requestedFar {
            requestedFar = true
            let pins =
              h.events.reversed().compactMap { event -> [Int]? in
                if case .virtualWindow(_, _, _, _, let pins) = event { return pins }
                return nil
              }.first ?? []
            // Native menus run a tracking loop. A source replacement may
            // arrive there before deferred SwiftUI layout resumes.
            try? h.answer(first: 99990, last: 100000, pins: pins)
            retainedWhileTracking = pins.contains(id) && h.roots[2] == id
            h.trackingMenu?.cancelTrackingWithoutAnimation()
          } else if ContinuousClock.now >= deadline {
            h.trackingMenu?.cancelTrackingWithoutAnimation()
          }
        }
      }
      RunLoop.main.add(timer, forMode: .eventTracking)
      RunLoop.main.add(timer, forMode: .common)
      menu.popUp(positioning: nil, at: NSPoint(x: 10, y: 10), in: view)
      timer.invalidate()
      #expect(requestedFar)
      #expect(retainedWhileTracking)
      try h.scrollTo(3_200_000 - 320)
      try await h.wait("native menu closure releases its row") { h.roots[2] == nil }
    }

    @Test("a tracked empty source reports the canonical empty visible range")
    func emptyVisibleRange() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try h.apply([["op": "set-prop", "id": 1, "property": "track-visible-range", "value": true]])
      try await h.wait("initial rows") { !h.indices.isEmpty }
      h.count = 0
      h.epoch += 1
      try h.answer(first: 0, last: 0, pins: [])
      try await h.wait("empty visible range") {
        h.events.contains {
          if case .visibleRange(_, let first, let last) = $0 { return first == 0 && last == -1 }
          return false
        }
      }
    }

    @Test("an actual root-hosted sheet retains its source row without text or pointer focus")
    func sheetOwnership() async throws {
      let h = try SparseHostFixture()
      defer { h.close() }
      try await h.wait("initial rows") { h.roots[2] != nil }
      let old = try #require(h.roots[2])
      let root = h.nextID
      h.nextID += 4
      h.roots[2] = root
      try h.apply(
        [
          ["op": "detach-subtree", "id": old],
          ["op": "create-node", "id": root, "kind": "column"],
          ["op": "create-node", "id": root + 1, "kind": "text"],
          ["op": "set-prop", "id": root + 1, "property": "text", "value": "Sheet anchor"],
          ["op": "create-node", "id": root + 2, "kind": "sheet"],
          ["op": "set-prop", "id": root + 2, "property": "text", "value": "Native sheet"],
          ["op": "create-node", "id": root + 3, "kind": "text"],
          ["op": "set-prop", "id": root + 3, "property": "text", "value": "Actual sheet content"],
          ["op": "insert-child", "parent": root, "child": root + 1, "index": 0],
          ["op": "insert-child", "parent": root, "child": root + 2, "index": 1],
          ["op": "insert-child", "parent": root + 2, "child": root + 3, "index": 0],
          ["op": "insert-child", "parent": 1, "child": root, "index": 2],
        ] + h.metadata(h.indices))
      try await h.wait("actual native sheet") { h.window.attachedSheet != nil }
      let sheet = try #require(h.window.attachedSheet)
      try h.scrollTo(3_200_000 - 320)
      try await h.wait("sheet row retained offscreen") {
        h.indices.contains(99999) && h.roots[2] == root
      }
      #expect(h.window.attachedSheet === sheet)
      #expect(h.indices.count < 32)
      try h.apply([["op": "detach-subtree", "id": root + 2]])
      try await h.wait("dismissed sheet releases row") { h.roots[2] == nil }
    }

    @Test("a fresh view reissues geometry instead of reusing an earlier view's deduplication")
    func freshViewReissuesGeometry() async throws {
      let old = try SparseHostFixture()
      try await old.wait("old geometry") { !old.indices.isEmpty }
      old.close()
      let restored = try SparseHostFixture()
      defer { restored.close() }
      try await restored.wait("restored geometry requests materialization") {
        !restored.indices.isEmpty
      }
      #expect(
        restored.events.contains {
          if case .virtualWindow = $0 { return true }
          return false
        })
      #expect(restored.roots.count < 32)
    }
  }
#endif
