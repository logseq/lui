import Foundation
import SwiftUI
import UIKit

@testable import LUIAppleBackend

@MainActor private final class BoundedSource {
  let backend = LUIAppleBackend()
  var count = 100000
  var epoch = 1
  var batch = 0
  var swapped = false
  var mounted: [Int: Int] = [:]
  var nextID = 100
  var lastFirst = 0
  var lastLast = 0
  var lastPins: [Int] = []
  var errors: [String] = []
  var texts: [Int: String] = [:]

  init() throws {
    try apply(
      [
        ["op": "create-node", "id": 1, "kind": "virtual-list"],
        prop(1, "height", 320), prop(1, "overscan", 2), prop(1, "item-extent", 32),
      ] + metadata())
    backend.onEvent = { [weak self] event in
      guard let self else { return }
      do {
        switch event {
        case .virtualWindow(let node, let generation, let first, let last, let pins)
        where node == 1 && generation == epoch:
          lastFirst = first
          lastLast = last
          lastPins = pins
          try answer(first: first, last: last, pins: pins)
        case .textChanged(let node, let text):
          if let key = mounted.first(where: { $0.value + 1 == node })?.key {
            texts[key] = text
            try apply([prop(node, "text", text)])
          }
        default: break
        }
      } catch { errors.append(String(describing: error)) }
    }
  }
  func prop(_ id: Int, _ name: String, _ value: Any) -> [String: Any] {
    ["op": "set-prop", "id": id, "property": name, "value": value]
  }
  func position(_ key: Int) -> Int {
    swapped && key == 2 ? 99999 : swapped && key == 99999 ? 2 : key
  }
  func metadata() -> [[String: Any]] {
    let indices = mounted.keys.map(position).sorted()
    return [
      prop(1, "virtual-total-count", count), prop(1, "virtual-generation", epoch),
      prop(
        1, "virtual-indices", String(decoding: try! JSONEncoder().encode(indices), as: UTF8.self)),
    ]
  }
  func apply(_ ops: [[String: Any]]) throws {
    batch += 1
    let data = try JSONSerialization.data(withJSONObject: ["generation": batch, "ops": ops])
    try backend.apply(json: String(decoding: data, as: UTF8.self))
  }
  func answer(first: Int, last: Int, pins: [Int]) throws {
    let pinned = mounted.compactMap { pins.contains($0.value) ? $0.key : nil }
    let desired = Set((max(0, first)..<min(count, max(first, last))).map(position))
      .union(pinned.filter { $0 < count })
    var ops: [[String: Any]] = []
    for (key, id) in mounted where !desired.contains(key) {
      ops.append(["op": "detach-subtree", "id": id])
      mounted.removeValue(forKey: key)
    }
    for key in desired where mounted[key] == nil {
      let root = nextID
      nextID += 3
      mounted[key] = root
      ops += [
        ["op": "create-node", "id": root, "kind": "column"],
        ["op": "create-node", "id": root + 1, "kind": "text-field"],
        prop(root + 1, "text", texts[key] ?? "draft-\(key)"),
        prop(root + 1, "change-enabled", true),
        ["op": "create-node", "id": root + 2, "kind": "text"], prop(root + 2, "text", "Row-\(key)"),
        ["op": "insert-child", "parent": root, "child": root + 1, "index": 0],
        ["op": "insert-child", "parent": root, "child": root + 2, "index": 1],
        ["op": "insert-child", "parent": 1, "child": root, "index": 0],
      ]
    }
    for (index, key) in mounted.keys.sorted(by: { position($0) < position($1) }).enumerated() {
      ops.append(["op": "move-child", "parent": 1, "child": mounted[key]!, "index": index])
    }
    try apply(ops + metadata())
  }
  func reorder() throws {
    swapped.toggle()
    epoch += 1
    try answer(first: lastFirst, last: lastLast, pins: lastPins)
  }
  func clear() throws {
    count = 0
    epoch += 1
    try answer(first: 0, last: 0, pins: [])
  }
}

@main struct BoundedVirtualRowsCheck {
  @MainActor static func main() async throws {
    nativePresentationCheckpoint("BOUNDED_BEGIN")
    func require(_ value: Bool, _ message: String) throws {
      if !value {
        throw NSError(
          domain: "BoundedVirtualRows", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
      }
    }
    func wait(_ label: String, _ predicate: () -> Bool) async throws {
      let deadline = ContinuousClock.now + .seconds(6)
      repeat {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(15))
      } while ContinuousClock.now < deadline
      try require(false, label)
    }
    // Real UIKit geometry, independent of SwiftUI's current safe-area policy.
    let geometry = LUISparseVirtualState()
    let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.contentInset = UIEdgeInsets(top: 17, left: 0, bottom: 23, right: 0)
    scroll.contentSize = CGSize(width: 300, height: 10000)
    scroll.contentOffset = CGPoint(x: 0, y: 100)
    let probe = LUISparseScrollProbe.Probe(state: geometry)
    scroll.addSubview(probe)
    probe.connect()
    try require(abs(geometry.offset - 117) < 0.1, "UIKit viewport must include adjusted top inset")
    try require(
      abs(geometry.viewportHeight - 260) < 0.1, "UIKit viewport must exclude obscured inset area")
    probe.disconnect()

    nativePresentationCheckpoint("BOUNDED_INSETS_PASS scenes=\(UIApplication.shared.connectedScenes.count)")
    let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows).first { $0.isKeyWindow }!
    let window = UIWindow(windowScene: previous.windowScene!)
    let source = try BoundedSource()
    let hosting = UIHostingController(rootView: LUISwiftUIRoot(backend: source.backend, rootID: 1))
    window.rootViewController = hosting
    window.makeKeyAndVisible()
    nativePresentationCheckpoint("BOUNDED_WINDOW_VISIBLE")
    defer {
      window.isHidden = true
      source.backend.onEvent = nil
      previous.makeKeyAndVisible()
    }
    func descendants<T: UIView>(_ type: T.Type, _ root: UIView) -> [T] {
      ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { descendants(type, $0) }
    }
    func editor() -> UITextField? {
      descendants(UITextField.self, hosting.view).first { $0.text == "draft-2" }
    }
    try await wait("initial bounded native editor") {
      hosting.view.layoutIfNeeded()
      return editor() != nil
    }
    let native = editor()!
    nativePresentationCheckpoint("BOUNDED_INITIAL_ROWS count=\(source.mounted.count)")
    let list = descendants(UIScrollView.self, hosting.view).first {
      $0.contentSize.height > 3_000_000
    }!
    try require(source.mounted.count < 80, "100k must not mount all source rows")
    try require(native.becomeFirstResponder(), "native editor receives focus")
    native.setMarkedText("你", selectedRange: NSRange(location: 1, length: 0))
    try require(native.markedTextRange != nil, "native composition starts")
    let rowID = source.mounted[2]!
    try await wait("focus pin is reported before reordering") { source.lastPins.contains(rowID) }
    try source.reorder()
    try await wait("far reordered focused row stays mounted") {
      hosting.view.layoutIfNeeded()
      return source.mounted[2] == rowID && source.mounted.count < 80
        && native.convert(native.bounds, to: list).minY > 3_000_000
        && list.contentOffset.y < 1000
    }
    try require(
      native.isFirstResponder && native.markedTextRange != nil,
      "far reorder preserves native focus and composition")
    nativePresentationCheckpoint("BOUNDED_FAR_REORDER_PASS")
    try source.reorder()
    try await wait("focused row returns without remount") {
      hosting.view.layoutIfNeeded()
      return native.convert(native.bounds, to: list).minY < 1000 && native.isFirstResponder
    }
    list.setContentOffset(
      CGPoint(
        x: 0, y: list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom),
      animated: false)
    try await wait("true native far scroll") {
      source.lastFirst > 99000 && source.mounted[99999] != nil
    }
    try require(
      source.lastLast - source.lastFirst < 80, "focus pins must not inflate the requested viewport")
    try require(
      source.mounted[2] == rowID && native.isFirstResponder && native.markedTextRange != nil,
      "offscreen native editor is retained without promotion")
    native.unmarkText()
    native.resignFirstResponder()
    list.setContentOffset(CGPoint(x: 0, y: -list.adjustedContentInset.top), animated: false)
    try await wait("native top return") { source.lastFirst == 0 && source.mounted[0] != nil }
    try source.clear()
    try await wait("clear releases all row models") {
      source.mounted.isEmpty && source.backend.model(id: 1)?.children.isEmpty == true
    }
    try require(source.errors.isEmpty, "feedback batches remain valid: \(source.errors)")
    nativePresentationCheckpoint("BOUNDED_CLEAR_PASS")
    print(
      "PASS: adjusted-inset geometry, 100k bounded native views, real far/top scrolling, focused UIKit IME reorder, and Clear"
    )
  }
}
