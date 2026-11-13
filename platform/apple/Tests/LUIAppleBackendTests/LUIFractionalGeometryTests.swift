import Testing
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@testable import LUIAppleBackend

@MainActor
@Suite("Fractional point geometry")
struct LUIFractionalGeometryTests {
    private func fixture() throws -> LUIAppleBackend {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"image"},
          {"op":"set-prop","id":1,"property":"url","value":"file:///tmp/lui-fractional-image.png"},
          {"op":"set-prop","id":1,"property":"width","value":92},
          {"op":"set-prop","id":1,"property":"height","value":63.25},
          {"op":"set-prop","id":1,"property":"max-width","value":127.75},
          {"op":"set-prop","id":1,"property":"max-height","value":200.5}
        ]}
        """)
        return backend
    }

    @Test("integer accessors keep their types while numeric frames retain fractions")
    func numericAccessorsAndRetainedUpdates() throws {
        let backend = try fixture()
        let model = try #require(backend.model(id: 1))
        let integerHeight: Int? = model.surfaceHeight
        #expect(integerHeight == nil)
        #expect(model.surfaceHeightPoints == 63.25)
        #expect(model.surfaceMaxWidthPoints == 127.75)
        #expect(model.surfaceMaxHeightPoints == 200.5)
        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"set-prop","id":1,"property":"height","value":63}]}
        """)
        #expect(backend.model(id: 1) === model)
        #expect(model.surfaceHeight == 63)
        try backend.apply(json: """
        {"generation":3,"ops":[{"op":"set-prop","id":1,"property":"height","value":64.125}]}
        """)
        #expect(backend.model(id: 1) === model)
        #expect(model.surfaceHeightPoints == 64.125)
        #expect(throws: (any Error).self) {
            try backend.apply(json: """
            {"generation":4,"ops":[{"op":"set-prop","id":1,"property":"max-height","value":64}]}
            """)
        }
        #expect(model.surfaceMaxHeightPoints == 200.5)
    }

    @Test("the actual image frame uses 63.25 points without integer coercion")
    func fractionalImageFrame() throws {
        let backend = try fixture()
        let content = LUIAnyNodeView(nodeID: 1, backend: backend).fixedSize()
        #if os(macOS) || os(iOS)
        // Measure SwiftUI's logical layout before the native hosting view
        // rounds its enclosing intrinsic size to device pixels.
        let renderer = ImageRenderer(content: content)
        var renderedSize: CGSize?
        renderer.render { size, _ in renderedSize = size }
        let measured = try #require(renderedSize)
        #expect(abs(measured.width - 92) < 0.01)
        #expect(abs(measured.height - 63.25) < 0.01)
        #endif
    }

    @Test("resizable maximums accept points while old integer state remains available")
    func fractionalResizableMaximum() {
        var state = LUIResizableWidthState(sourceWidth: 100, minimumWidth: 10,
            maximumWidth: nil, maximumWidthPoints: 92.75)
        #expect(state.maximumWidth == nil)
        #expect(state.maximumWidthPoints == 92.75)
        #expect(state.width == 92.75)
        state.drag(by: 100, fallbackWidth: 0)
        #expect(state.width == 92.75)
    }
}
