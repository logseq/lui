import Foundation

// Shared by the unit test and the standalone UIKit runtime check.
struct LUIRuntimeScrollReadiness {
  struct Sample: Equatable {
    var generation: Int
    var virtualContentHeight: CGFloat
    var nativeContentHeight: CGFloat
    var boundsHeight: CGFloat
    var insetTop: CGFloat
    var insetBottom: CGFloat
    var offset: CGFloat
  }

  let expectedGeneration: Int
  private var previous: Sample?

  init(expectedGeneration: Int) {
    self.expectedGeneration = expectedGeneration
  }

  mutating func bottomOffset(_ sample: Sample) -> CGFloat? {
    let values = [
      sample.virtualContentHeight, sample.nativeContentHeight, sample.boundsHeight,
      sample.insetTop, sample.insetBottom, sample.offset,
    ]
    guard sample.generation == expectedGeneration, values.allSatisfy(\.isFinite),
      sample.virtualContentHeight > 0,
      sample.boundsHeight - sample.insetTop - sample.insetBottom > 0,
      abs(sample.nativeContentHeight - sample.virtualContentHeight) <= 1
    else {
      previous = nil
      return nil
    }
    // Polls are separated by the runtime check's existing run-loop wait.
    defer { previous = sample }
    guard previous == sample else { return nil }
    return max(-sample.insetTop,
               sample.nativeContentHeight - sample.boundsHeight + sample.insetBottom)
  }
}
