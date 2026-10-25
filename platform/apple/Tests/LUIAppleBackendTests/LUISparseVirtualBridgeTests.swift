#if os(macOS)
  import AppKit
  import Foundation
  import Testing
  @testable import LUIAppleBackend

  nonisolated(unsafe) private var sparseWirePayloads: [(Int32, Int32, String)] = []
  nonisolated(unsafe) private let sparseWireCallback: LUIAppleEventCallback = { kind, node, text in
    sparseWirePayloads.append((kind, node, text.map(String.init(cString:)) ?? ""))
  }

  @MainActor
  extension LUISwiftUIBackendTests {
    @Test(
      "legacy callback preserves full parent, generation and pinned row IDs in authoritative JSON")
    func fullWidthIdentifiers() async throws {
      luiAppleReset()
      defer {
        luiAppleSetEventCallback(nil)
        luiAppleReset()
      }
      sparseWirePayloads = []
      luiAppleSetEventCallback(sparseWireCallback)
      let parent = 9_007_199_254_740_993
      let row = parent + 1
      let generation = parent + 2
      let json = """
        {"generation":1,"ops":[
          {"op":"create-node","id":\(parent),"kind":"virtual-list"},
          {"op":"set-prop","id":\(parent),"property":"height","value":200},
          {"op":"create-node","id":\(row),"kind":"text-field"},
          {"op":"set-prop","id":\(row),"property":"text","value":"Full width IDs"},
          {"op":"insert-child","parent":\(parent),"child":\(row),"index":0},
          {"op":"set-prop","id":\(parent),"property":"virtual-total-count","value":100000},
          {"op":"set-prop","id":\(parent),"property":"virtual-generation","value":\(generation)},
          {"op":"set-prop","id":\(parent),"property":"virtual-indices","value":"[0]"}
        ]}
        """
      #expect(json.withCString { luiAppleApply($0) } == 1)
      luiAppleShow()
      let window = try #require(NSApp.windows.first { $0.title == "LUI" && $0.isVisible })
      #expect(!window.isReleasedWhenClosed, "The Swift bridge owns the window until reset completes")
      window.setFrameOrigin(NSPoint(x: -10000, y: 0))
      func field(_ view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.stringValue == "Full width IDs" { return field }
        for child in view.subviews { if let found = field(child) { return found } }
        return nil
      }
      let deadline = ContinuousClock.now + .seconds(5)
      while field(window.contentView!) == nil && ContinuousClock.now < deadline {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(15))
      }
      let native = try #require(field(window.contentView!))
      native.selectText(nil)
      while !sparseWirePayloads.contains(where: { $0.0 == 20 && $0.2.contains("\(row)") })
        && ContinuousClock.now < deadline
      {
        try await Task.sleep(for: .milliseconds(15))
      }
      let callback = try #require(sparseWirePayloads.last { $0.0 == 20 })
      #expect(callback.1 == 0)
      struct Payload: Decodable {
        let node: Int
        let generation: Int
        let first: Int
        let last: Int
        let pins: [Int]
      }
      let payload = try JSONDecoder().decode(Payload.self, from: Data(callback.2.utf8))
      #expect(payload.node == parent)
      #expect(payload.generation == generation)
      #expect(payload.pins == [row])
      #expect(payload.first == 0 && payload.last > 0 && payload.last < 32)
      luiAppleReset()
      #expect(!window.isVisible)
    }
  }
#endif
