#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import LUIAppleBackend

@MainActor
final class LUIContainerPaddingTests: XCTestCase {
    func testPlainContainersHonorEdgeOverridesLikeDecoratedContainers() throws {
        for kind in ["box", "row", "column"] {
            for decorated in [false, true] {
                let backend = LUIAppleBackend()
                var ops: [[String: Any]] = [
                    ["op": "create-node", "id": 1, "kind": kind],
                    ["op": "create-node", "id": 2, "kind": "box"],
                    ["op": "set-prop", "id": 2, "property": "width", "value": 10],
                    ["op": "set-prop", "id": 2, "property": "height", "value": 12],
                    ["op": "insert-child", "parent": 1, "child": 2, "index": 0]
                ]
                for (property, value) in ["padding": 2, "padding-horizontal": 5, "padding-vertical": 7,
                                          "padding-left": 26, "padding-right": 8, "padding-top": 3, "padding-bottom": 4] {
                    ops.append(["op": "set-prop", "id": 1, "property": property, "value": value])
                }
                if decorated { ops.append(["op": "set-prop", "id": 1, "property": "background", "value": "transparent"]) }
                let data = try JSONSerialization.data(withJSONObject: ["generation": 1, "ops": ops])
                try backend.apply(json: String(decoding: data, as: UTF8.self))
                let host = UIHostingController(rootView: LUISwiftUIRoot(backend: backend, rootID: 1).fixedSize())
                let size = host.sizeThatFits(in: CGSize(width: 390, height: 844))
                XCTAssertEqual(size.width, 44, accuracy: 0.5, "\(kind), decorated=\(decorated)")
                XCTAssertEqual(size.height, 19, accuracy: 0.5, "\(kind), decorated=\(decorated)")
            }
        }
    }
}
#endif
