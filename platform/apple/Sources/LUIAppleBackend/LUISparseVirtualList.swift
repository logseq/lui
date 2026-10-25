import Foundation
import Observation
import SwiftUI

struct LUIVirtualRowOwner: Sendable {
  weak var state: LUISparseVirtualState?
  let row: Int
  @MainActor func presented(_ token: UUID, _ value: Bool) {
    state?.popup(row: row, token: token, presented: value)
  }
}
private struct LUIVirtualRowOwnerKey: EnvironmentKey {
  static let defaultValue: LUIVirtualRowOwner? = nil
}
extension EnvironmentValues {
  var luiVirtualRowOwner: LUIVirtualRowOwner? {
    get { self[LUIVirtualRowOwnerKey.self] }
    set { self[LUIVirtualRowOwnerKey.self] = newValue }
  }
}
struct LUIVirtualPopupOwnership: ViewModifier {
  @Environment(\.luiVirtualRowOwner) private var owner
  @State private var token = UUID()
  let presented: Bool
  func body(content: Content) -> some View {
    content.onChange(of: presented, initial: true) { _, value in owner?.presented(token, value) }
      .onDisappear { owner?.presented(token, false) }
  }
}

/// Sparse prefix sums retain measurements, never views or source records.
private struct LUISparseRowExtents {
  var count = 0
  var estimate: CGFloat = 32
  var gap: CGFloat = 0
  private var heights: [Int: CGFloat] = [:]
  private var sums: [Int: CGFloat] = [:]
  init(count: Int = 0, estimate: CGFloat = 32, gap: CGFloat = 0) {
    self.count = count
    self.estimate = estimate
    self.gap = gap
  }
  mutating func measure(_ index: Int, height: CGFloat) {
    guard index >= 0, index < count, height.isFinite, height > 0 else { return }
    let difference = height - (heights[index] ?? estimate)
    guard abs(difference) > 0.1 else { return }
    heights[index] = height
    var cursor = index + 1
    while cursor <= count {
      sums[cursor, default: 0] += difference
      let step = cursor & -cursor
      guard step <= count - cursor else { break }
      cursor += step
    }
  }
  func origin(_ index: Int) -> CGFloat {
    var cursor = min(max(index, 0), count)
    var correction: CGFloat = 0
    while cursor > 0 {
      correction += sums[cursor, default: 0]
      cursor -= cursor & -cursor
    }
    return CGFloat(index) * (estimate + gap) + correction
  }
  var height: CGFloat { max(0, origin(count) - (count > 0 ? gap : 0)) }
  func height(_ index: Int) -> CGFloat { heights[index] ?? estimate }
  func index(at offset: CGFloat) -> Int {
    guard count > 0 else { return 0 }
    var lower = 0
    var upper = count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if origin(middle) + height(middle) <= offset { lower = middle + 1 } else { upper = middle }
    }
    return min(lower, count - 1)
  }
}

@MainActor @Observable
final class LUISparseVirtualState {
  struct Row: Identifiable, Equatable {
    let id: Int
    let index: Int
  }
  private struct Request: Equatable {
    let generation: Int
    let first: Int
    let last: Int
    let pins: [Int]
  }
  var rows: [Row] = []
  fileprivate var extents = LUISparseRowExtents()
  private(set) var offset: CGFloat = 0
  private(set) var viewportHeight: CGFloat = 0
  @ObservationIgnored private weak var backend: LUIAppleBackend?
  @ObservationIgnored private weak var model: LUINodeModel?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var emitted: Request?
  @ObservationIgnored private var emittedVisible: [Int]?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var completion: Task<Void, Never>?
  @ObservationIgnored private var heights: [Int: CGFloat] = [:]
  @ObservationIgnored private var focused: Int?
  @ObservationIgnored private var pressed: Int?
  @ObservationIgnored private var popups: [Int: Set<UUID>] = [:]
  @ObservationIgnored private var active = false
  @ObservationIgnored private var handledToken: Int?
  @ObservationIgnored private var pendingToken: Int?
  @ObservationIgnored private var targetIndex: Int?
  @ObservationIgnored var scroll: ((CGFloat, Bool) -> Void)?
  @ObservationIgnored var refreshOwners: (() -> Void)?

  func configure(model: LUINodeModel, backend: LUIAppleBackend) {
    guard
      let metadata = try? LUISparseVirtualMetadata(
        properties: model.properties, children: model.children)
    else { return }
    let isNew = self.model !== model
    let oldFirst = rows.first { $0.index == extents.index(at: offset) }
    let relative = oldFirst.map { extents.origin($0.index) - offset }
    let changed = isNew || generation != metadata.generation
    self.model = model
    self.backend = backend
    active = true
    rows = zip(model.children, metadata.indices).map { Row(id: $0.0, index: $0.1) }
    let extent = model.property(.itemExtent)?.doubleValue ?? 32
    let gap = CGFloat(model.property(.gap)?.intValue ?? 0)
    if changed || extents.count != metadata.count || extents.estimate != extent
      || extents.gap != gap
    {
      var next = LUISparseRowExtents(count: metadata.count, estimate: extent, gap: gap)
      for row in rows {
        if let height = heights[row.id] { next.measure(row.index, height: height) }
      }
      extents = next
      emitted = nil
      emittedVisible = nil
      if !isNew, let oldFirst, let relative, let moved = rows.first(where: { $0.id == oldFirst.id })
      {
        setOffset(extents.origin(moved.index) - relative, animated: false)
      }
    }
    generation = metadata.generation
    let live = Set(rows.map(\.id))
    heights = heights.filter { live.contains($0.key) }
    if let focused, !live.contains(focused) { self.focused = nil }
    if let pressed, !live.contains(pressed) { self.pressed = nil }
    popups = popups.filter { live.contains($0.key) }
    if isNew {
      handledToken = nil
      pendingToken = nil
    }
    handleTarget(metadata.scrollIndex)
    if let token = pendingToken {
      if let index = metadata.scrollIndex, index >= 0 {
        if targetIndex != index {
          completion?.cancel()
          completion = nil
          targetIndex = index
        }
      } else {
        completion?.cancel()
        completion = nil
        pendingToken = nil
        targetIndex = nil
        backend.performScrollCompleted(node: model.id, token: token, outcome: "missing-target")
      }
    }
    refreshOwners?()
    schedule()
  }
  func viewport(offset: CGFloat, height: CGFloat) {
    guard offset.isFinite, height.isFinite else { return }
    let nextOffset = max(0, offset)
    let nextHeight = max(0, height)
    if self.offset != nextOffset { self.offset = nextOffset }
    if viewportHeight != nextHeight { viewportHeight = nextHeight }
    refreshOwners?()
    schedule()
  }
  func measured(_ row: Row, height: CGFloat) {
    guard rows.contains(row), height.isFinite, height > 0,
      abs((heights[row.id] ?? -1) - height) > 0.1
    else { return }
    let first = extents.index(at: offset)
    let before = extents.origin(first)
    heights[row.id] = height
    extents.measure(row.index, height: height)
    let difference = extents.origin(first) - before
    if abs(difference) > 0.1 { setOffset(offset + difference, animated: false) }
    schedule()
  }
  func row(at position: CGFloat) -> Int? {
    let index = extents.index(at: position)
    return rows.first { $0.index == index }?.id
  }
  func focus(_ id: Int?) {
    if focused != id {
      focused = id
      schedule()
    }
  }
  func pointer(_ id: Int?) {
    if pressed != id {
      pressed = id
      schedule()
    }
  }
  func contains(_ id: Int) -> Bool { rows.contains { $0.id == id } }
  func flushOwnership() { deliver() }
  func presentationsChanged() { schedule() }
  private func presentedRows() -> Set<Int> {
    guard let backend, let model else { return [] }
    let direct = Set(rows.map(\.id))
    var owners: Set<Int> = []
    for id in backend.virtualPresentationIDs {
      var current: Int? = id
      while let value = current, value != model.id {
        if direct.contains(value) {
          owners.insert(value)
          break
        }
        current = backend.model(id: value)?.parent ?? backend.extensionModel(id: value)?.parent
      }
    }
    return owners
  }
  func popup(row: Int, token: UUID, presented: Bool) {
    guard contains(row) else { return }
    if presented {
      popups[row, default: []].insert(token)
    } else {
      popups[row]?.remove(token)
      if popups[row]?.isEmpty == true { popups.removeValue(forKey: row) }
    }
    schedule()
  }
  private func schedule() {
    guard active, task == nil else { return }
    task = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self else { return }
      task = nil
      deliver()
    }
  }
  private func deliver() {
    guard active, viewportHeight > 0, let backend, let model,
      backend.model(id: model.id) === model,
      model.property(.virtualGeneration)?.intValue == generation
    else { return }
    refreshOwners?()
    let count = extents.count
    let first = count > 0 ? extents.index(at: offset) : 0
    let last = count > 0 ? min(count, extents.index(at: offset + viewportHeight - 0.01) + 1) : 0
    let overscan = model.property(.overscan)?.intValue ?? 5
    let presented = presentedRows()
    let pins = rows.filter {
      $0.id == focused || $0.id == pressed || popups[$0.id] != nil || presented.contains($0.id)
    }.map(\.id).sorted()
    let request = Request(
      generation: generation, first: max(0, first - min(overscan, first)),
      last: last + min(overscan, count - last), pins: pins)
    if emitted != request {
      emitted = request
      backend.performVirtualWindow(
        model: model, generation: generation, first: request.first, last: request.last,
        pins: request.pins)
    }
    guard active, backend.model(id: model.id) === model else { return }
    if model.property(.trackVisibleRange)?.boolValue == true {
      let visible = [first, last - 1]
      if emittedVisible != visible {
        emittedVisible = visible
        backend.performVisibleRange(node: model.id, first: first, last: last - 1)
      }
    }
    finishTargetIfReady()
  }
  private func setOffset(_ value: CGFloat, animated: Bool) {
    let next = max(0, min(value, max(0, extents.height - viewportHeight)))
    offset = next
    scroll?(next, animated)
  }
  private func handleTarget(_ index: Int?) {
    guard let model, let token = model.scrollToken, handledToken != token else { return }
    if let pendingToken {
      backend?.performScrollCompleted(node: model.id, token: pendingToken, outcome: "cancelled")
    }
    completion?.cancel()
    completion = nil
    pendingToken = nil
    targetIndex = nil
    handledToken = token
    guard let target = model.scrollTarget, !target.isEmpty else { return }
    guard let index, index >= 0 else {
      backend?.performScrollCompleted(node: model.id, token: token, outcome: "missing-target")
      return
    }
    pendingToken = token
    targetIndex = index
    setOffset(targetOffset(index), animated: model.scrollAnimated)
  }
  private func targetOffset(_ index: Int) -> CGFloat {
    let adjustment: CGFloat
    switch model?.property(.scrollAnchor)?.stringValue {
    case "center": adjustment = (viewportHeight - extents.height(index)) / 2
    case "bottom": adjustment = viewportHeight - extents.height(index)
    default: adjustment = 0
    }
    return extents.origin(index) - adjustment
  }
  private func finishTargetIfReady() {
    guard let token = pendingToken, let index = targetIndex, completion == nil else { return }
    let desired = max(0, min(targetOffset(index), max(0, extents.height - viewportHeight)))
    if abs(offset - desired) > 1 {
      setOffset(desired, animated: false)
      schedule()
      return
    }
    guard let row = rows.first(where: { $0.index == index }), heights[row.id] != nil else { return }
    completion = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled, active, pendingToken == token, let backend, let model,
        backend.model(id: model.id) === model
      else { return }
      pendingToken = nil
      targetIndex = nil
      completion = nil
      backend.performScrollCompleted(node: model.id, token: token, outcome: "succeeded")
    }
  }
  func dispose() {
    active = false
    task?.cancel()
    task = nil
    completion?.cancel()
    completion = nil
    if let token = pendingToken, let model {
      backend?.performScrollCompleted(node: model.id, token: token, outcome: "cancelled")
    }
    pendingToken = nil
    emitted = nil
    emittedVisible = nil
    refreshOwners = nil
    scroll = nil
  }
}

struct LUISparseVirtualListView: View {
  let model: LUINodeModel
  let backend: LUIAppleBackend
  @State private var state = LUISparseVirtualState()
  var body: some View {
    ScrollView {
      ZStack(alignment: .topLeading) {
        Color.clear.frame(height: state.extents.height).accessibilityHidden(true)
        ForEach(state.rows) { row in
          LUIAnyNodeView(nodeID: row.id, backend: backend).equatable()
            .environment(\.luiVirtualRowOwner, LUIVirtualRowOwner(state: state, row: row.id))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) {
              $0.size.height
            } action: {
              state.measured(row, height: $0)
            }
            .accessibilitySortPriority(-Double(row.index))
            .offset(y: state.extents.origin(row.index))
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background { LUISparseScrollProbe(state: state).frame(width: 0, height: 0) }
    }
    .onChange(of: model.revision, initial: true) { _, _ in
      state.configure(model: model, backend: backend)
    }
    .onChange(of: backend.virtualPresentationIDs) { _, _ in state.presentationsChanged() }
    .onAppear { state.configure(model: model, backend: backend) }
    .onDisappear { state.dispose() }
  }
}
