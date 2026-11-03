#if os(macOS)
  import AppKit
  import Darwin
  import Foundation
  import SwiftUI
  import Testing
  @testable import LUIAppleBackend

  private typealias SparsePatch = @convention(c) (UnsafePointer<CChar>?) -> Void
  private typealias SparseStart = @convention(c) (SparsePatch?, Int32, Int32) -> Int32
  private typealias SparseStop = @convention(c) () -> Int32
  private typealias SparseNode = @convention(c) (Int64) -> Int32
  private typealias SparseVersion = @convention(c) () -> Int32
  private typealias SparseWindow =
    @convention(c) (Int64, Int64, Int64, Int64, UnsafePointer<Int64>?, Int32) -> Int32
  private typealias SparseText = @convention(c) (Int64, UnsafePointer<CChar>?, Int32) -> Int32

  nonisolated(unsafe) private var sparseActive: SparseNativeHarness?
  nonisolated(unsafe) private let sparseReceive: SparsePatch = { source in
    guard let source else { return }
    let json = String(cString: source)
    MainActor.assumeIsolated { sparseActive?.receive(json) }
  }

  @MainActor
  private final class SparseNativeHarness {
    var backend = LUIAppleBackend()
    let library: UnsafeMutableRawPointer
    let stop: SparseStop
    let press: SparseNode
    let windowEvent: SparseWindow
    let textEvent: SparseText
    let resync: SparseStop
    var errors: [String] = []
    var events: [LUIEvent] = []
    var snapshotBatches: [String]?
    var measurements: [[String: Any]] = []
    var hosting: NSHostingView<LUISwiftUIRoot>!
    var window: NSWindow!

    init(path: String, negotiate: Bool = true) throws {
      guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
        throw NSError(
          domain: "SparseNativeTest", code: 1,
          userInfo: [NSLocalizedDescriptionKey: String(cString: dlerror())])
      }
      self.library = library
      func load<T>(_ name: String, _: T.Type) throws -> T {
        guard let symbol = dlsym(library, name) else {
          throw NSError(
            domain: "SparseNativeTest", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
        }
        return unsafeBitCast(symbol, to: T.self)
      }
      let start = try load("lui_ocaml_start", SparseStart.self)
      stop = try load("lui_ocaml_stop", SparseStop.self)
      resync = try load("lui_ocaml_resync", SparseStop.self)
      press = try load("lui_ocaml_press", SparseNode.self)
      textEvent = try load("lui_ocaml_text_changed_utf8", SparseText.self)
      windowEvent = try load("lui_ocaml_virtual_window", SparseWindow.self)
      let version =
        dlsym(library, "lui_ocaml_virtual_rows_version").map {
          unsafeBitCast($0, to: SparseVersion.self)()
        } ?? 0
      backend.onEvent = { [weak self] event in self?.dispatch(event) }
      sparseActive = self
      let result = start(sparseReceive, 1, negotiate && version == 1 ? 258 : 2)
      #expect(result == 1)
      try checkErrors()
      let root = try #require(backend.rootIDs.first)
      _ = NSApplication.shared
      hosting = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: root))
      window = NSWindow(
        contentRect: NSRect(x: -10000, y: 0, width: 800, height: 600),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.contentView = hosting
      window.orderFrontRegardless()
    }

    func receive(_ json: String) {
      if snapshotBatches != nil {
        snapshotBatches!.append(json)
        return
      }
      do { try backend.apply(json: json) } catch {
        errors.append(String(describing: error))
        try? json.write(
          toFile: "/tmp/lui-apple-sparse-invalid-batch.json", atomically: true, encoding: .utf8)
      }
    }

    func restoreAuthoritativeSnapshot() throws {
      snapshotBatches = []
      #expect(resync() == 1)
      let batches = try #require(snapshotBatches)
      snapshotBatches = nil
      #expect(!batches.isEmpty)
      let restored = LUIAppleBackend()
      for batch in batches { try restored.apply(json: batch) }
      backend.onEvent = nil
      backend = restored
      backend.onEvent = { [weak self] event in self?.dispatch(event) }
      let root = try #require(backend.rootIDs.first)
      hosting = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: root))
      window.contentView = hosting
    }

    func dispatch(_ event: LUIEvent) {
      events.append(event)
      switch event {
      case .virtualWindow(let node, let generation, let first, let last, let pins):
        let ids = pins.map(Int64.init)
        let result = ids.withUnsafeBufferPointer {
          windowEvent(
            Int64(node), Int64(generation), Int64(first), Int64(last),
            $0.baseAddress, Int32($0.count))
        }
        if result != 1 { errors.append("virtual window rejected: \(event)") }
      case .press(let node): _ = press(Int64(node))
      case .textChanged(let node, let text):
        text.withCString { _ = textEvent(Int64(node), $0, Int32(text.utf8.count)) }
      default: break
      }
    }

    func close() {
      window.orderOut(nil)
      window.contentView = nil
      backend.onEvent = nil
      _ = stop()
      sparseActive = nil
      // The process owns the OCaml runtime; unloading its code is unsafe.
    }

    func checkErrors() throws {
      #expect(errors.isEmpty)
      if !errors.isEmpty { throw Failure.errors(errors) }
    }
    enum Failure: Error {
      case errors([String])
      case timeout(String)
    }

    func pump(until name: String, _ predicate: () -> Bool) async throws {
      let deadline = ContinuousClock.now + .seconds(8)
      repeat {
        hosting.layoutSubtreeIfNeeded()
        try checkErrors()
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(15))
      } while ContinuousClock.now < deadline
      let diagnostic =
        "\(name)\n\(backend.debugModelCounts)\nindices=\(indices)\noffset=\(scroll?.contentView.bounds.minY ?? -1) height=\(documentHeight)\ntarget=\(String(describing: list?.property(.virtualScrollIndex))) token=\(String(describing: list?.scrollToken))\n\(events.suffix(20))"
      try? diagnostic.write(
        toFile: "/tmp/lui-apple-sparse-timeout.txt", atomically: true, encoding: .utf8)
      throw Failure.timeout(name)
    }

    var ids: [Int] {
      var stack = backend.rootIDs
      var found: [Int] = []
      while let id = stack.popLast() {
        found.append(id)
        if let model = backend.model(id: id) { stack += model.children }
      }
      return found
    }
    func identified(_ identifier: String) throws -> Int {
      try #require(
        ids.first {
          backend.model(id: $0)?.property(.accessibilityIdentifier)?.stringValue == identifier
        })
    }
    var list: LUINodeModel? {
      ids.compactMap { backend.model(id: $0) }.first { $0.kind == .virtualList }
    }
    var indices: [Int] {
      guard let text = list?.property(.virtualIndices)?.stringValue,
        let data = text.data(using: .utf8),
        let indices = try? JSONDecoder().decode([Int].self, from: data)
      else { return [] }
      return indices
    }
    func action(_ identifier: String) throws {
      try backend.performPress(node: identified(identifier))
      try checkErrors()
    }
    func descendants<T: NSView>(_ type: T.Type, in root: NSView? = nil) -> [T] {
      guard let root = root ?? hosting else { return [] }
      return ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { descendants(type, in: $0) }
    }
    var scroll: NSScrollView? { descendants(NSScrollView.self).first { $0.documentView != nil } }
    func editor(_ value: String) -> NSTextField? {
      descendants(NSTextField.self).first { $0.stringValue == value && $0.isEditable }
    }
    func scrollTo(_ y: CGFloat) throws {
      let scroll = try #require(scroll)
      scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
      scroll.reflectScrolledClipView(scroll.contentView)
    }
    var documentHeight: CGFloat { scroll?.documentView?.bounds.height ?? 0 }
    func bounded(_ maximum: Int = 300) {
      #expect(ids.count < maximum)
      #expect(list?.children.count ?? Int.max < 80)
      #expect(descendants(NSTextField.self).count < 80)
    }
    func checkpoint(_ label: String) throws {
      let entry: [String: Any] = [
        "phase": label, "nodes": ids.count,
        "rowRoots": list?.children.count ?? 0, "nativeFields": descendants(NSTextField.self).count,
        "indices": indices, "offset": scroll?.contentView.bounds.minY ?? 0,
      ]
      measurements.append(entry)
      print(
        "Apple bounded rows \(label): nodes=\(entry["nodes"]!) rows=\(entry["rowRoots"]!) nativeFields=\(entry["nativeFields"]!)"
      )
      if let path = ProcessInfo.processInfo.environment["LUI_APPLE_BOUNDED_REPORT"] {
        try JSONSerialization.data(
          withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]
        ).write(to: URL(fileURLWithPath: path))
      }
    }
  }

  @MainActor
  @Suite("Actual OCaml SwiftUI bounded rows", .serialized)
  struct LUISparseVirtualNativeTests {
    @Test("real 100k source stays bounded through scroll, focus, IME, reorder and repeated clear")
    func actualOCaml100kLifecycle() async throws {
      guard let path = ProcessInfo.processInfo.environment["LUI_APPLE_BOUNDED_LIBRARY"] else {
        return  // CI runs this explicitly with the portable fixture path.
      }
      let h = try SparseNativeHarness(path: path)
      defer { h.close() }
      try await h.pump(until: "initial empty source") { h.list != nil }
      let idle = h.ids.count
      for cycle in 0..<2 {
        try h.action("sparse-load")
        try await h.pump(until: "100k source bounded initial window") {
          h.list?.property(.virtualTotalCount)?.intValue == 100000 && !h.indices.isEmpty
        }
        h.bounded()
        #expect(h.documentHeight > 3_000_000)
        try await h.pump(until: "real initial editor") { h.editor("draft-2") != nil }
        try h.checkpoint("loaded-\(cycle)")
        let field = try #require(h.editor("draft-2"))
        field.selectText(nil)
        let input = try #require(field.currentEditor() as? NSTextView)
        input.setSelectedRange(NSRange(location: 2, length: 0))
        input.setMarkedText(
          "你", selectedRange: NSRange(location: 1, length: 0),
          replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(input.hasMarkedText())
        try h.action("sparse-reorder")
        try await h.pump(until: "stationary top retains the editor moved to logical index99999") {
          h.indices.contains(99999) && field.currentEditor() === input
        }
        #expect((h.scroll?.contentView.bounds.minY ?? 10000) < 1000)
        #expect(input.hasMarkedText())
        try h.action("sparse-reorder")
        try await h.pump(until: "focused row returns to index2 without remount") {
          h.indices.contains(2) && field.currentEditor() === input
        }
        try h.scrollTo(h.documentHeight - 320)
        try await h.pump(until: "bottom requested without spanning focused pin") {
          h.indices.contains(99999)
        }
        h.bounded()
        #expect(field.currentEditor() === input)
        #expect(input.hasMarkedText())
        #expect(
          h.events.contains {
            if case .virtualWindow(_, _, let first, _, let pins) = $0 {
              return first > 99000 && !pins.isEmpty
            }
            return false
          })
        try h.action("sparse-reorder")
        try await h.pump(until: "reordered focused row retains native identity") {
          h.indices.contains(99999) && field.currentEditor() === input
        }
        #expect(input.hasMarkedText())
        input.unmarkText()
        h.window.makeFirstResponder(nil)
        try h.action("sparse-variable")
        try await h.pump(until: "variable rows laid out") { h.documentHeight > 3_000_000 }
        try h.scrollTo(0)
        try await h.pump(until: "native scroll returns to top") { h.indices.contains(0) }
        h.bounded()
        try h.action("sparse-target-bottom")
        try await h.pump(until: "far scroll target has actual geometry") {
          h.indices.contains(99999) && (h.scroll?.contentView.bounds.minY ?? 0) > 1_000_000
        }
        try await h.pump(until: "accepted native composition survives eviction and remount") {
          h.editor("dr你aft-2") != nil
        }
        try h.checkpoint("bottom-\(cycle)")
        h.bounded()
        let requestsBeforeResync = h.events.filter {
          if case .virtualWindow = $0 { return true }
          return false
        }.count
        try h.restoreAuthoritativeSnapshot()
        try await h.pump(until: "authoritative snapshot reissues current viewport") {
          h.events.filter {
            if case .virtualWindow = $0 { return true }
            return false
          }.count > requestsBeforeResync
        }
        h.bounded()
        try h.action("sparse-shrink")
        try await h.pump(until: "shrunk count and geometry") {
          h.list?.property(.virtualTotalCount)?.intValue == 10 && h.indices.allSatisfy { $0 < 10 }
        }
        try h.action("sparse-clear")
        try await h.pump(until: "clear cycle \(cycle) returns model graph to idle") {
          h.list?.property(.virtualTotalCount)?.intValue == 0 && h.ids.count == idle
        }
        #expect(h.indices.isEmpty)
        #expect(h.list?.children.isEmpty == true)
        try h.checkpoint("cleared-\(cycle)")
        h.bounded()
      }
      #expect(
        h.events.contains {
          if case .virtualWindow = $0 { return true }
          return false
        })
      try h.checkErrors()
    }
  }
#endif
