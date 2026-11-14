import Foundation
import Testing

struct LUIRuntimeScrollHandoffTests {
  @Test("IME scroll handoff corrects one reveal only while geometry and ownership survive")
  func boundedHandoff() {
    let geometry = LUIRuntimeScrollHandoff.Geometry(
      generation: 3, contentHeight: 3_200_000, bounds: CGSize(width: 400, height: 320),
      insetTop: 17, insetBottom: 23)
    var handoff = LUIRuntimeScrollHandoff(initial: geometry)
    // Native far write, then reveal near the composing editor before the yielded task delivers.
    #expect(handoff.finish(geometry: geometry, offset: 64, ownsComposingEditor: true,
                           revealsEditor: true) == .restore(3_199_703))
    #expect(handoff.finish(geometry: geometry, offset: 64, ownsComposingEditor: true,
                           revealsEditor: true) == .invalidated)

    var settled = LUIRuntimeScrollHandoff(initial: geometry)
    #expect(settled.finish(geometry: geometry, offset: geometry.bottom, ownsComposingEditor: true,
                           revealsEditor: false) == .settled)
    #expect(settled.finish(geometry: geometry, offset: 64, ownsComposingEditor: true,
                           revealsEditor: true) == .invalidated)

    var nextGeneration = geometry
    nextGeneration.generation += 1
    var nextExtent = geometry
    nextExtent.contentHeight += 32
    var nextInsets = geometry
    nextInsets.insetBottom += 20
    for (sample, offset, ownsEditor, revealsEditor) in [
      (nextGeneration, CGFloat(64), true, true),
      (nextExtent, 64, true, true),
      (nextInsets, 64, true, true),
      (geometry, 64, false, true), // Focus/composition loss or a user gesture takes ownership.
      (geometry, 100_000, true, false), // An unrelated viewport change is not editor reveal.
      (geometry, .nan, true, true),
    ] {
      var invalid = LUIRuntimeScrollHandoff(initial: geometry)
      #expect(invalid.finish(geometry: sample, offset: offset, ownsComposingEditor: ownsEditor,
                             revealsEditor: revealsEditor) == .invalidated)
      #expect(invalid.finish(geometry: geometry, offset: 64, ownsComposingEditor: true,
                             revealsEditor: true) == .invalidated)
    }
  }
}
