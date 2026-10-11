#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import LUIAppleBackend

@MainActor final class LUIMenuTouchTargetTests: XCTestCase {
    private func size(
        text: String = "",
        cell: [String: Any]? = nil,
        enabled: Bool = true,
        capsule: Bool = true,
        dynamicType: DynamicTypeSize = .large
    ) throws -> CGSize {
        let backend = LUIAppleBackend()
        var ops: [[String: Any]] = []
        func node(_ id: Int, _ kind: String, _ props: [String: Any], _ parent: Int?) {
            ops.append(["op": "create-node", "id": id, "kind": kind])
            for (key, value) in props {
                ops.append(["op": "set-prop", "id": id, "property": key, "value": value])
            }
            if let parent {
                ops.append(["op": "insert-child", "parent": parent, "child": id, "index": 0])
            }
        }
        if let cell { node(1, "box", cell, nil) }
        let trigger = cell == nil ? 1 : 2
        var props: [String: Any] = ["accessibility-label": "Options", "enabled": enabled]
        if text.isEmpty { props["icon"] = "plus" } else { props["text"] = text }
        if cell != nil && capsule { props["style-class"] = "capsule" }
        node(trigger, "menu-trigger", props, cell == nil ? nil : 1)
        node(trigger + 1, "dropdown-menu", [:], trigger)
        node(trigger + 2, "menu-item", ["text": "Action", "press-enabled": true], trigger + 1)
        let data = try JSONSerialization.data(withJSONObject: ["generation": 1, "ops": ops])
        try backend.apply(json: String(decoding: data, as: UTF8.self))
        let controller = UIHostingController(rootView:
            LUISwiftUIRoot(backend: backend, rootID: 1)
                .environment(\.dynamicTypeSize, dynamicType).fixedSize()
        )
        return controller.sizeThatFits(in: CGSize(width: 390, height: 844))
    }

    func testDefaultNativeMenuReservesIndependentTouchCell() throws {
        for text in ["", "A"] {
            let measured = try size(text: text)
            XCTAssertGreaterThanOrEqual(measured.width, 44)
            XCTAssertGreaterThanOrEqual(measured.height, 44)
        }
    }

    func testExplicitCapsuleCellDimensionsRemainCallerOwned() throws {
        let fixed = try size(cell: ["width": 28, "height": 30])
        XCTAssertEqual(fixed.width, 28, accuracy: 0.5)
        XCTAssertEqual(fixed.height, 30, accuracy: 0.5)
        let minimum = try size(cell: ["min-width": 28, "min-height": 30])
        XCTAssertEqual(minimum.width, 28, accuracy: 0.5)
        XCTAssertEqual(minimum.height, 30, accuracy: 0.5)
        let maximum = try size(cell: ["max-width": 32, "max-height": 32])
        XCTAssertLessThanOrEqual(maximum.width, 32)
        XCTAssertLessThanOrEqual(maximum.height, 32)
    }

    func testExplicitCellConstraintsOwnOnlyTheirAxis() throws {
        for capsule in [true, false] {
            let width = try size(cell: ["width": 28], capsule: capsule)
            XCTAssertEqual(width.width, 28, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(width.height, 44)
            let height = try size(cell: ["height": 30], capsule: capsule)
            XCTAssertGreaterThanOrEqual(height.width, 44)
            XCTAssertEqual(height.height, 30, accuracy: 0.5)
            let maxWidth = try size(cell: ["max-width": 32], capsule: capsule)
            XCTAssertLessThanOrEqual(maxWidth.width, 32)
            XCTAssertGreaterThanOrEqual(maxWidth.height, 44)
            let maxHeight = try size(cell: ["max-height": 32], capsule: capsule)
            XCTAssertGreaterThanOrEqual(maxHeight.width, 44)
            XCTAssertLessThanOrEqual(maxHeight.height, 32)
        }
    }

    func testTextMenuHeightGrowsWithDynamicType() throws {
        let normal = try size(text: "Options")
        let accessible = try size(text: "Options", dynamicType: .accessibility5)
        XCTAssertGreaterThanOrEqual(normal.height, 44)
        XCTAssertGreaterThan(accessible.height, normal.height)
    }

    func testDisabledMenuKeepsTheSameReservedSize() throws {
        let enabled = try size()
        let disabled = try size(enabled: false)
        XCTAssertEqual(disabled.width, enabled.width)
        XCTAssertEqual(disabled.height, enabled.height)
        XCTAssertGreaterThanOrEqual(disabled.width, 44)
        XCTAssertGreaterThanOrEqual(disabled.height, 44)
    }
}
#endif
