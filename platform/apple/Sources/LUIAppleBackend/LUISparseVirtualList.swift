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
  private struct CompletionFence: Equatable {
    let attempt: UUID
    let token: Int
    let key: String
    let generation: Int
    let source: ObjectIdentifier
    let row: Row
    let rowModel: ObjectIdentifier
    let owner: ObjectIdentifier?
    let ownerNode: Int?
    let ownerEpoch: Int?
    let mutation: UInt64
    let anchor: String?
  }
  var rows: [Row] = []
  fileprivate var extents = LUISparseRowExtents()
  var contentHeight: CGFloat { extents.height }
  private(set) var offset: CGFloat = 0
  private(set) var viewportHeight: CGFloat = 0
  @ObservationIgnored private weak var backend: LUIAppleBackend?
  @ObservationIgnored private weak var model: LUINodeModel?
  @ObservationIgnored private(set) var generation = 0
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
  @ObservationIgnored private var pendingKey: String?
  @ObservationIgnored private var pendingAnimated = false
  @ObservationIgnored private var attempt = UUID()
  @ObservationIgnored private var mutation: UInt64 = 0
  @ObservationIgnored private var configuration: UInt64 = 0
  @ObservationIgnored private var completionID: UUID?
  @ObservationIgnored private var observationSerial: UInt64 = 0
  @ObservationIgnored private var observed: LUISparseNativeObservation?
  @ObservationIgnored private(set) var desiredOffset: CGFloat?
  @ObservationIgnored private(set) var observedOffset: CGFloat?
  @ObservationIgnored private weak var sourceAnchor: LUISharedSourceMarker?
  @ObservationIgnored private var rowAnchors: [Int: LUIWeakSharedRowAnchor] = [:]
  @ObservationIgnored private weak var nativeProbe: AnyObject?
  @ObservationIgnored private var observeNative: ((LUISharedSourceMarker, LUISharedRowMarker) -> LUISparseNativeObservation?)?
  @ObservationIgnored private var lastCorrection: (CompletionFence, LUISparseNativeObservation, CGFloat)?
  @ObservationIgnored private var configuredAnchor: String?
  @ObservationIgnored private var nativeViewport: CGSize?
  @ObservationIgnored private var unmeasuredWrite: (UInt64, CGFloat)?
  @ObservationIgnored private(set) var sharedBinding: LUISharedSourceBinding?
  @ObservationIgnored private var sharedGeometry: LUISharedViewportGeometry?
  @ObservationIgnored private var sharedPins: Set<Int> = []
  @ObservationIgnored var scroll: ((CGFloat, Bool) -> Bool)?
  @ObservationIgnored var refreshOwners: (() -> Void)?

  func configure(model: LUINodeModel, backend: LUIAppleBackend) {
    guard
      let metadata = try? LUISparseVirtualMetadata(
        properties: model.properties, children: model.children)
    else { return }
    configuration += 1
    let configuring = configuration
    let isNew = self.model !== model
    let nextBinding = try? LUISharedSourceBinding(properties: model.properties, children: model.children)
    let nextRows = zip(model.children, metadata.indices).map { Row(id: $0.0, index: $0.1) }
    let ownerChanged = sharedBinding?.owner != nextBinding?.owner || sharedBinding?.epoch != nextBinding?.epoch
    if isNew || ownerChanged || pendingKey != nil && pendingKey != model.scrollTarget {
      retireTarget(outcome: "cancelled")
    }
    guard configuration == configuring else { return }
    if isNew || ownerChanged || generation != metadata.generation || rows != nextRows
        || sharedBinding != nextBinding || configuredAnchor != model.scrollAnchor {
      invalidateCompletion()
      lastCorrection = nil
    }
    let oldFirst = rows.first { $0.index == extents.index(at: offset) }
    let relative = oldFirst.map { extents.origin($0.index) - offset }
    let changed = isNew || generation != metadata.generation
    self.model = model
    self.backend = backend
    let wasShared = sharedBinding != nil
    sharedBinding = nextBinding
    configuredAnchor = model.scrollAnchor
    if let sharedBinding {
      nativeProbe = nil
      observeNative = nil
      refreshOwners = nil
      backend.sharedVirtualViewport.source(state: self, model: model, binding: sharedBinding)
      if let sourceAnchor { backend.sharedVirtualViewport.sourceAnchor(state: self, view: sourceAnchor) }
      for anchor in rowAnchors.values {
        if let marker = anchor.value {
          backend.sharedVirtualViewport.rowAnchor(state: self, row: marker.row.id,
            view: marker, attached: marker.window != nil)
        }
      }
      scroll = { [weak self, weak backend] offset, animated in
        guard let self else { return false }
        return backend?.sharedVirtualViewport.setOffset(offset, state: self, animated: animated) ?? false
      }
    } else if wasShared {
      backend.sharedVirtualViewport.removeSource(self)
      sharedGeometry = nil
      sharedPins.removeAll()
      scroll = nil
    }
    active = true
    rows = nextRows
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
      if sharedBinding == nil, !isNew, let oldFirst, let relative, let moved = rows.first(where: { $0.id == oldFirst.id })
      {
        setOffset(extents.origin(moved.index) - relative, animated: false)
      }
    }
    generation = metadata.generation
    let live = Set(rows.map(\.id))
    heights = heights.filter { live.contains($0.key) }
    rowAnchors = rowAnchors.filter { live.contains($0.key) && $0.value.value != nil }
    if let focused, !live.contains(focused) { self.focused = nil }
    if let pressed, !live.contains(pressed) { self.pressed = nil }
    popups = popups.filter { live.contains($0.key) }
    if isNew {
      handledToken = nil
      pendingToken = nil
    }
    handleTarget(metadata.scrollIndex)
    guard configuration == configuring else { return }
    if pendingToken != nil {
      if let index = metadata.scrollIndex, index >= 0 {
        if targetIndex != index {
          invalidateCompletion()
          targetIndex = index
        }
      } else {
        retireTarget(outcome: "missing-target")
      }
    }
    refreshOwners?()
    schedule()
  }
  func viewport(offset: CGFloat, height: CGFloat) {
    guard offset.isFinite, height.isFinite else { return }
    let nextOffset = max(0, offset)
    let nextHeight = max(0, height)
    let evidence = CGSize(width: nextOffset, height: nextHeight)
    if nativeViewport != evidence { nativeViewport = evidence; invalidateCompletion() }
    let changed = self.offset != nextOffset || viewportHeight != nextHeight
    if self.offset != nextOffset { self.offset = nextOffset }
    if viewportHeight != nextHeight { viewportHeight = nextHeight }
    refreshOwners?()
    nativeGeometryChanged()
    if changed { schedule() }
  }
  func measured(_ row: Row, height: CGFloat) {
    guard rows.contains(row), height.isFinite, height > 0,
      abs((heights[row.id] ?? -1) - height) > 0.1
    else { return }
    let first = extents.index(at: offset)
    let before = extents.origin(first)
    heights[row.id] = height
    invalidateCompletion()
    lastCorrection = nil
    extents.measure(row.index, height: height)
    let difference = extents.origin(first) - before
    if sharedBinding == nil, abs(difference) > 0.1 { setOffset(offset + difference, animated: false) }
    schedule()
    if sharedBinding != nil { backend?.sharedVirtualViewport.schedule() }
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
  func sharedRowGeometry(_ id: Int) -> (index: Int, origin: CGFloat, height: CGFloat)? {
    guard let row = rows.first(where: { $0.id == id }), heights[id] != nil else { return nil }
    return (row.index, extents.origin(row.index), extents.height(row.index))
  }
  var sharedInteractionRows: Set<Int> { Set(popups.keys).union(presentedRows()) }
  func sharedViewport(_ geometry: LUISharedViewportGeometry?, pins: Set<Int>) {
    let changed = geometry != sharedGeometry || pins != sharedPins
    sharedGeometry = geometry
    sharedPins = pins
    guard let geometry else {
      updateObservation(nil)
      if changed { schedule() }
      return
    }
    offset = geometry.localOffset
    viewportHeight = geometry.height
    if changed { schedule() }
  }
  func flushOwnership() { deliver() }
  func presentationsChanged() { schedule() }

  private func invalidateCompletion() {
    mutation += 1
    completion?.cancel()
    completion = nil
    completionID = nil
  }

  func hasNativeProbe(_ probe: AnyObject) -> Bool { nativeProbe === probe && observeNative != nil }

  func connectNative(_ probe: AnyObject,
      observe: @escaping (LUISharedSourceMarker, LUISharedRowMarker) -> LUISparseNativeObservation?,
      scroll: @escaping (CGFloat, Bool) -> Bool, owners: @escaping () -> Void) {
    guard sharedBinding == nil else { return }
    if nativeProbe !== probe { invalidateCompletion(); updateObservation(nil) }
    nativeProbe = probe
    observeNative = observe
    self.scroll = scroll
    refreshOwners = owners
    nativeGeometryChanged()
    schedule()
  }

  func disconnectNative(_ probe: AnyObject) {
    guard nativeProbe === probe else { return }
    nativeProbe = nil
    observeNative = nil
    scroll = nil
    refreshOwners = nil
    updateObservation(nil)
    invalidateCompletion()
  }

  func nativeSourceAnchor(_ marker: LUISharedSourceMarker, attached: Bool) {
    if attached {
      if sourceAnchor !== marker { invalidateCompletion() }
      sourceAnchor = marker
    } else {
      guard sourceAnchor === marker else { return }
      sourceAnchor = nil
      invalidateCompletion()
    }
    if sharedBinding != nil { backend?.sharedVirtualViewport.sourceAnchor(state: self, view: sourceAnchor) }
    nativeGeometryChanged()
    schedule()
  }

  func nativeRowAnchor(_ marker: LUISharedRowMarker, attached: Bool) {
    if attached {
      if rowAnchors[marker.row.id]?.value !== marker { invalidateCompletion() }
      rowAnchors[marker.row.id] = LUIWeakSharedRowAnchor(marker)
    } else {
      guard rowAnchors[marker.row.id]?.value === marker else { return }
      rowAnchors[marker.row.id] = nil
      invalidateCompletion()
    }
    if sharedBinding != nil {
      backend?.sharedVirtualViewport.rowAnchor(state: self, row: marker.row.id, view: marker, attached: attached)
    }
    nativeGeometryChanged()
    schedule()
  }

  func nativeGeometryChanged() {
    guard active, let index = targetIndex, let row = rows.first(where: { $0.index == index }) else { return }
    _ = acquireObservation(row)
  }

  private func updateObservation(_ sample: LUISparseNativeObservation?) {
    let changed: Bool
    if let sample, let observed { changed = !sample.matches(observed) }
    else { changed = (sample != nil) != (observed != nil) }
    observed = sample
    observedOffset = sample?.geometry.localOffset
    if changed { invalidateCompletion(); schedule() }
  }

  private func acquireObservation(_ row: Row) -> LUISparseNativeObservation? {
    guard let sourceAnchor, let marker = rowAnchors[row.id]?.value,
          marker.row == row, marker.generation == generation else {
      updateObservation(nil)
      return nil
    }
    let sample: LUISparseNativeObservation?
    if sharedBinding != nil, let pendingKey {
      sample = backend?.sharedVirtualViewport.completionObservation(state: self, row: row, key: pendingKey)
    } else { sample = observeNative?(sourceAnchor, marker) }
    observationSerial += 1
    updateObservation(sample)
    return sample
  }
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
    if sharedBinding != nil { backend?.sharedVirtualViewport.schedule() }
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
    guard active, viewportHeight > 0, sharedBinding == nil || sharedGeometry != nil, let backend, let model,
      backend.model(id: model.id) === model,
      model.property(.virtualGeneration)?.intValue == generation
    else { return }
    refreshOwners?()
    let count = extents.count
    let intersects = count > 0 && offset < extents.height && offset + viewportHeight > 0
    let first = intersects ? extents.index(at: max(0, offset)) : (offset > 0 ? count : 0)
    let last = intersects ? min(count, extents.index(at: min(extents.height, offset + viewportHeight) - 0.01) + 1) : first
    let overscan = intersects ? (model.property(.overscan)?.intValue ?? 5) : 0
    let presented = presentedRows()
    let pins = rows.filter {
      $0.id == focused || $0.id == pressed || popups[$0.id] != nil || presented.contains($0.id)
        || sharedPins.contains($0.id)
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
  @discardableResult
  private func setOffset(_ value: CGFloat, animated: Bool,
      geometry: LUISharedViewportGeometry? = nil) -> Bool {
    let next = geometry.map { $0.target(value) - $0.origin } ?? clampedOffset(value)
    // Preserve bounded window prediction without calling a request an observation.
    desiredOffset = next
    offset = next
    return scroll?(next, animated) ?? false
  }
  private func clampedOffset(_ value: CGFloat) -> CGFloat {
    if let geometry = sharedGeometry { return geometry.target(value) - geometry.origin }
    return max(0, min(value, max(0, extents.height - viewportHeight)))
  }
  private func handleTarget(_ index: Int?) {
    guard let model, let token = model.scrollToken, handledToken != token else { return }
    retireTarget(outcome: "cancelled")
    guard self.model === model, model.scrollToken == token, handledToken != token,
          pendingToken == nil else { return }
    handledToken = token
    guard let target = model.scrollTarget, !target.isEmpty else { return }
    guard let index, index >= 0 else {
      backend?.performScrollCompleted(node: model.id, token: token, outcome: "missing-target")
      return
    }
    pendingToken = token
    pendingKey = target
    pendingAnimated = model.scrollAnimated
    attempt = UUID()
    lastCorrection = nil
    targetIndex = index
    setOffset(targetOffset(index), animated: pendingAnimated)
  }
  private func targetOffset(_ index: Int, height: CGFloat? = nil) -> CGFloat {
    let viewport = height ?? viewportHeight
    let adjustment: CGFloat
    switch model?.property(.scrollAnchor)?.stringValue {
    case "center": adjustment = (viewport - extents.height(index)) / 2
    case "bottom": adjustment = viewport - extents.height(index)
    default: adjustment = 0
    }
    return extents.origin(index) - adjustment
  }
  private func finishTargetIfReady() {
    guard completion == nil, let index = targetIndex, let model,
          model.scrollToken == pendingToken, model.scrollTarget == pendingKey,
          model.property(.virtualGeneration)?.intValue == generation,
          model.property(.virtualScrollIndex)?.intValue == index else { return }
    guard let row = rows.first(where: { $0.index == index }), heights[row.id] != nil else {
      let target = clampedOffset(targetOffset(index))
      if let last = unmeasuredWrite, last.0 == mutation, abs(last.1 - target) <= 1 { return }
      unmeasuredWrite = (mutation, target)
      if setOffset(target, animated: pendingAnimated) { schedule() }
      return
    }
    guard
          let sample = acquireObservation(row), let fence = completionFence(row) else { return }
    // Shared sources scroll inside an owner document, so desired/observed
    // offsets are source-local. A standalone list is the whole document and
    // its writer/observer agree on the absolute adjusted offset domain; using
    // the local domain there would miss by the native origin (inset+sourceTop).
    let desired: CGFloat
    let observed: CGFloat
    let correctionGeometry: LUISharedViewportGeometry?
    if sharedBinding == nil {
      desired = clampedOffset(targetOffset(index, height: sample.geometry.height))
      observed = sample.geometry.offset
      correctionGeometry = nil
    } else {
      desired = sample.geometry.target(targetOffset(index, height: sample.geometry.height)) - sample.geometry.origin
      observed = sample.geometry.localOffset
      correctionGeometry = sample.geometry
    }
    desiredOffset = desired
    if abs(observed - desired) > 1 {
      if let last = lastCorrection, last.0 == fence, last.1.matches(sample), abs(last.2 - desired) <= 1 { return }
      lastCorrection = (fence, sample, desired)
      // A writer may produce no notification (including an accepted no-op).
      // One reevaluation is allowed; unchanged failed evidence cannot spin.
      if setOffset(desired, animated: pendingAnimated, geometry: correctionGeometry) { schedule() }
      return
    }
    guard anchorReady(sample, row: row) else { return }
    let serial = observationSerial
    let id = UUID()
    completionID = id
    let sourceModel = model
    let rowModel = backend?.model(id: row.id) as AnyObject? ?? backend?.extensionModel(id: row.id)
    let ownerModel = sharedBinding.flatMap { backend?.model(id: $0.owner) }
    completion = Task { @MainActor [weak self, weak sourceModel, weak rowModel, weak ownerModel] in
      await Task.yield()
      guard let self, !Task.isCancelled, completionID == id else { return }
      guard let sourceModel, sourceModel === model, let rowModel,
            (backend?.model(id: row.id) as AnyObject? ?? backend?.extensionModel(id: row.id)) === rowModel,
            fence.ownerNode.map({ ownerModel != nil && backend?.model(id: $0) === ownerModel }) ?? true,
            completionFence(row) == fence,
            let fresh = acquireObservation(row), observationSerial > serial,
            completionID == id, completionFence(row) == fence,
            sample.matches(fresh), anchorReady(fresh, row: row),
            abs((sharedBinding == nil ? fresh.geometry.offset : fresh.geometry.localOffset)
              - (sharedBinding == nil
                ? clampedOffset(targetOffset(row.index, height: fresh.geometry.height))
                : fresh.geometry.target(targetOffset(row.index, height: fresh.geometry.height))
                  - fresh.geometry.origin)) <= 1
      else {
        if completionID == id { completion = nil; completionID = nil }
        return
      }
      retireTarget(outcome: "succeeded")
    }
  }

  private func completionFence(_ row: Row) -> CompletionFence? {
    guard active, let backend, let model, backend.model(id: model.id) === model,
          let token = pendingToken, model.scrollToken == token,
          let key = pendingKey, model.scrollTarget == key, !key.isEmpty,
          model.property(.virtualGeneration)?.intValue == generation,
          model.property(.virtualScrollIndex)?.intValue == row.index,
          targetIndex == row.index, rows.contains(row),
          let metadata = try? LUISparseVirtualMetadata(properties: model.properties, children: model.children),
          metadata.generation == generation,
          zip(model.children, metadata.indices).contains(where: { $0.0 == row.id && $0.1 == row.index }),
          let marker = rowAnchors[row.id]?.value, marker.row == row, marker.generation == generation,
          let rowModel = backend.model(id: row.id) as AnyObject? ?? backend.extensionModel(id: row.id),
          marker.retainedModel === rowModel else { return nil }
    let owner: ObjectIdentifier?
    if let binding = sharedBinding {
      guard let current = try? LUISharedSourceBinding(properties: model.properties, children: model.children),
            current == binding, let position = model.children.firstIndex(of: row.id),
            current.keys[position] == key,
            let ownerModel = backend.model(id: binding.owner),
            ownerModel.property(.virtualViewportEpoch)?.intValue == binding.epoch else { return nil }
      owner = ObjectIdentifier(ownerModel)
    } else { owner = nil }
    return CompletionFence(attempt: attempt, token: token, key: key, generation: generation,
      source: ObjectIdentifier(model), row: row, rowModel: ObjectIdentifier(rowModel), owner: owner,
      ownerNode: sharedBinding?.owner, ownerEpoch: sharedBinding?.epoch, mutation: mutation, anchor: model.scrollAnchor)
  }

  private func anchorReady(_ sample: LUISparseNativeObservation, row: Row) -> Bool {
    sample.intersectsViewport && heights[row.id] != nil
      && abs(sample.anchorRect.minY - sample.geometry.origin - extents.origin(row.index)) <= 1
      && abs(sample.anchorRect.height - extents.height(row.index)) <= 1
  }

  private func takeTarget() -> (model: LUINodeModel, token: Int)? {
    let token = pendingToken
    let source = model
    pendingToken = nil
    pendingKey = nil
    pendingAnimated = false
    targetIndex = nil
    desiredOffset = nil
    lastCorrection = nil
    attempt = UUID()
    invalidateCompletion()
    guard let token, let source else { return nil }
    return (source, token)
  }
  private func retireTarget(outcome: String) {
    guard let retired = takeTarget(), backend?.model(id: retired.model.id) === retired.model else { return }
    backend?.performScrollCompleted(node: retired.model.id, token: retired.token, outcome: outcome)
  }
  func dispose() {
    configuration += 1
    active = false
    task?.cancel()
    task = nil
    let retired = takeTarget()
    observed = nil
    observedOffset = nil
    nativeProbe = nil
    observeNative = nil
    sourceAnchor = nil
    rowAnchors.removeAll()
    emitted = nil
    emittedVisible = nil
    refreshOwners = nil
    scroll = nil
    if sharedBinding != nil { backend?.sharedVirtualViewport.removeSource(self) }
    sharedBinding = nil
    sharedGeometry = nil
    sharedPins.removeAll()
    if let retired, backend?.model(id: retired.model.id) === retired.model {
      backend?.performScrollCompleted(node: retired.model.id, token: retired.token, outcome: "cancelled")
    }
  }
}

struct LUISparseVirtualListView: View {
  let model: LUINodeModel
  let backend: LUIAppleBackend
  @State private var state = LUISparseVirtualState()
  var body: some View {
    Group {
      if model.property(.virtualOwnerNode) != nil {
        rowsContent.background { LUISharedSourceProbe(state: state, backend: backend) }
      } else {
        ScrollView {
          rowsContent.background { LUISharedSourceProbe(state: state, backend: backend) }
            .background { LUISparseScrollProbe(state: state).frame(width: 0, height: 0) }
        }
      }
    }
    .onChange(of: model.revision, initial: true) { _, _ in
      state.configure(model: model, backend: backend)
    }
    .onChange(of: backend.virtualPresentationIDs) { _, _ in
      state.presentationsChanged()
      if model.property(.virtualOwnerNode) != nil { backend.sharedVirtualViewport.schedule() }
    }
    .onAppear { state.configure(model: model, backend: backend) }
    .onDisappear { state.dispose() }
  }
  private var rowsContent: some View {
      ZStack(alignment: .topLeading) {
        Color.clear.frame(height: state.contentHeight).accessibilityHidden(true)
        ForEach(state.rows) { row in
          LUIAnyNodeView(nodeID: row.id, backend: backend).equatable()
            .environment(\.luiVirtualRowOwner, LUIVirtualRowOwner(state: state, row: row.id))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
              LUISharedRowProbe(state: state, row: row,
                  generation: model.property(.virtualGeneration)?.intValue ?? 0, backend: backend)
            }
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
  }
}
