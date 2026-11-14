import Foundation
import Testing

struct LUIRuntimeScrollReadinessTests {
  @Test("post-reorder bottom scroll waits for current matching stable geometry")
  func postReorderGeometry() {
    var readiness = LUIRuntimeScrollReadiness(expectedGeneration: 3)
    var sample = LUIRuntimeScrollReadiness.Sample(
      generation: 2, virtualContentHeight: 3_200_096, nativeContentHeight: 3_200_096,
      boundsHeight: 300, insetTop: 17, insetBottom: 23, offset: -17)
    #expect(readiness.bottomOffset(sample) == nil)
    #expect(readiness.bottomOffset(sample) == nil)

    sample.generation = 3
    for staleHeight: CGFloat in [3_200_000, 3_200_192] {
      sample.nativeContentHeight = staleHeight
      #expect(readiness.bottomOffset(sample) == nil)
      #expect(readiness.bottomOffset(sample) == nil)
    }
    sample.nativeContentHeight = sample.virtualContentHeight
    #expect(readiness.bottomOffset(sample) == nil)
    sample.boundsHeight = 320
    #expect(readiness.bottomOffset(sample) == nil)
    #expect(readiness.bottomOffset(sample) == 3_199_799)

    // A later measurement invalidates readiness even after a settled sample.
    sample.virtualContentHeight += 64
    #expect(readiness.bottomOffset(sample) == nil)
    sample.nativeContentHeight = sample.virtualContentHeight
    #expect(readiness.bottomOffset(sample) == nil)
    #expect(readiness.bottomOffset(sample) == 3_199_863)
  }
}
