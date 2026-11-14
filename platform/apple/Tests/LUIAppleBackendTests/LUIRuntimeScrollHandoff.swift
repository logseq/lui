import Foundation

// Used only by the bounded runtime fixture, which owns the native scroll write.
struct LUIRuntimeScrollHandoff {
  struct Geometry: Equatable {
    var generation: Int
    var contentHeight: CGFloat
    var bounds: CGSize
    var insetTop: CGFloat
    var insetBottom: CGFloat

    var bottom: CGFloat { max(-insetTop, contentHeight - bounds.height + insetBottom) }
    var isValid: Bool {
      [contentHeight, bounds.width, bounds.height, insetTop, insetBottom].allSatisfy(\.isFinite)
        && contentHeight > 0 && bounds.width > 0 && bounds.height - insetTop - insetBottom > 0
    }
  }
  enum Outcome: Equatable {
    case settled
    case restore(CGFloat)
    case invalidated
  }

  let initial: Geometry
  private var consumed = false

  init(initial: Geometry) { self.initial = initial }

  // One decision after one yield; changed geometry or ownership never earns a retry.
  mutating func finish(
    geometry: Geometry, offset: CGFloat, ownsComposingEditor: Bool, revealsEditor: Bool
  ) -> Outcome {
    guard !consumed else { return .invalidated }
    consumed = true
    guard initial.isValid, geometry == initial, offset.isFinite, ownsComposingEditor else {
      return .invalidated
    }
    if abs(offset - initial.bottom) <= 1 { return .settled }
    guard revealsEditor else { return .invalidated }
    return .restore(initial.bottom)
  }
}
