#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import LUIAppleBackend

/// Exercise public wire properties through the real UIKit hosting boundary.
@MainActor
final class LUIButtonSizeTests: XCTestCase {
    private func size(
        _ properties: [String: Any],
        dynamicType: DynamicTypeSize = .large
    ) throws -> CGSize {
        let backend = LUIAppleBackend()
        var ops: [[String: Any]] = [["op": "create-node", "id": 1, "kind": "button"]]
        for (property, value) in properties {
            ops.append(["op": "set-prop", "id": 1, "property": property, "value": value])
        }
        let data = try JSONSerialization.data(withJSONObject: ["generation": 1, "ops": ops])
        try backend.apply(json: String(decoding: data, as: UTF8.self))
        let controller = UIHostingController(rootView:
            LUISwiftUIRoot(backend: backend, rootID: 1)
                .environment(\.dynamicTypeSize, dynamicType)
                .fixedSize()
        )
        return controller.sizeThatFits(in: CGSize(width: 390, height: 844))
    }

    func testDefaultTextAndIconControlsReserveNonOverlappingTouchCells() throws {
        for properties: [String: Any] in [
            ["text": "A"],
            ["text": "A", "variant": "ghost"],
            ["icon": "plus"],
            ["icon": "plus", "size": "icon"],
            ["icon": "plus", "size": "sm"],
            ["text": "A", "size": "sm"]
        ] {
            let measured = try size(properties)
            XCTAssertGreaterThanOrEqual(measured.width, 44, "\(properties)")
            XCTAssertGreaterThanOrEqual(measured.height, 44, "\(properties)")
        }
    }

    func testDefaultTextHeightGrowsWithDynamicType() throws {
        let normal = try size(["text": "Continue"])
        let accessible = try size(["text": "Continue"], dynamicType: .accessibility5)
        XCTAssertGreaterThanOrEqual(normal.height, 44)
        XCTAssertGreaterThan(accessible.height, normal.height)
    }

    func testRegularTextMinimumDoesNotAccumulateNativePadding() throws {
        for variant in ["default", "primary", "secondary", "outline", "destructive"] {
            let measured = try size(["text": "A", "variant": variant])
            XCTAssertEqual(measured.width, 44, accuracy: 0.5, variant)
            XCTAssertEqual(measured.height, 44, accuracy: 0.5, variant)
        }
    }

    func testTextMinimumAndMaximumConstraintsOwnOnlyTheirAxis() throws {
        for variant in ["default", "ghost"] {
            let narrow = try size(["text": "A", "variant": variant, "max-width": 32])
            XCTAssertLessThanOrEqual(narrow.width, 32)
            XCTAssertGreaterThanOrEqual(narrow.height, 44)
            let short = try size(["text": "A", "variant": variant, "max-height": 32])
            XCTAssertGreaterThanOrEqual(short.width, 44)
            XCTAssertLessThanOrEqual(short.height, 32)
            let wide = try size(["text": "A", "variant": variant, "min-width": 60])
            XCTAssertGreaterThanOrEqual(wide.width, 60)
            XCTAssertEqual(wide.height, 44, accuracy: 0.5)
            let tall = try size(["text": "A", "variant": variant, "min-height": 64])
            XCTAssertEqual(tall.width, 44, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(tall.height, 64)
            let fixed = try size(["text": "A", "variant": variant,
                                  "width": 48, "max-width": 60, "height": 40, "min-height": 30])
            // Preserve existing surface flexible-frame semantics rather than
            // defining a new fixed-versus-bound priority for every node kind.
            XCTAssertGreaterThanOrEqual(fixed.width, 48)
            XCTAssertLessThanOrEqual(fixed.width, 60)
            XCTAssertGreaterThanOrEqual(fixed.height, 30)
            XCTAssertLessThanOrEqual(fixed.height, 40)
        }
    }

    func testExplicitFixedExtentsOverrideDefaultsPerAxis() throws {
        let fixed = try size(["icon": "plus", "width": 28, "height": 30])
        XCTAssertEqual(fixed.width, 28, accuracy: 0.5)
        XCTAssertEqual(fixed.height, 30, accuracy: 0.5)
        let widthOnly = try size(["icon": "plus", "width": 28])
        XCTAssertEqual(widthOnly.width, 28, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(widthOnly.height, 44)
        let heightOnly = try size(["icon": "plus", "height": 30])
        XCTAssertGreaterThanOrEqual(heightOnly.width, 44)
        XCTAssertEqual(heightOnly.height, 30, accuracy: 0.5)
    }

    func testExplicitMinimumAndMaximumExtentsRemainCallerOwned() throws {
        for buttonSize in ["default", "icon"] {
            let small = try size(["icon": "plus", "size": buttonSize,
                                  "min-width": 28, "min-height": 30])
            XCTAssertEqual(small.width, 28, accuracy: 0.5)
            XCTAssertEqual(small.height, 30, accuracy: 0.5)
            let bounded = try size(["icon": "plus", "size": buttonSize,
                                    "max-width": 32, "max-height": 32])
            XCTAssertLessThanOrEqual(bounded.width, 32)
            XCTAssertLessThanOrEqual(bounded.height, 32)
            let large = try size(["icon": "plus", "size": buttonSize,
                                  "min-width": 60, "min-height": 64])
            XCTAssertGreaterThanOrEqual(large.width, 60)
            XCTAssertGreaterThanOrEqual(large.height, 64)
        }
    }
}
#endif
