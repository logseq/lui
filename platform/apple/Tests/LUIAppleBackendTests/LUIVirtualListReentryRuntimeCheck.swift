#if os(iOS)
import SwiftUI
import UIKit
@testable import LUIAppleBackend

@MainActor
enum LUIVirtualListReentryRuntimeCheck {
    static func main() async throws {
        let backend = LUIAppleBackend()
        let metadata = ["data-virtual-count": "10000", "data-virtual-start": "0",
                        "data-virtual-length": "0", "data-item-extent": "32"]
            .map { "\($0.key)\u{1f}\($0.value)" }.joined(separator: "\u{1e}")
        let operations: [[String: Any]] = [
            ["op": "create-node", "id": 1, "kind": "virtual-list"],
            ["op": "set-prop", "id": 1, "property": "height", "value": 300],
            ["op": "create-node", "id": 2, "kind": "list"],
            ["op": "set-prop", "id": 2, "property": "data-attrs", "value": metadata],
            ["op": "set-prop", "id": 2, "property": "track-visible-range", "value": true],
            ["op": "insert-child", "parent": 1, "child": 2, "index": 0],
            ["op": "create-node", "id": 3, "kind": "box"],
            ["op": "set-prop", "id": 3, "property": "height", "value": 20],
            ["op": "set-prop", "id": 3, "property": "appear-enabled", "value": true],
            ["op": "insert-child", "parent": 1, "child": 3, "index": 1],
            ["op": "create-node", "id": 4, "kind": "box"],
            ["op": "set-prop", "id": 4, "property": "height", "value": 400],
            ["op": "insert-child", "parent": 1, "child": 4, "index": 2],
        ]
        let json = try JSONSerialization.data(withJSONObject: ["generation": 1, "ops": operations])
        try backend.apply(json: String(decoding: json, as: UTF8.self))
        var ranges: [(Int, Int)] = []
        var markerAppearances = 0
        backend.onEvent = { event in
            if case let .visibleRange(node, first, last) = event, node == 2 {
                ranges.append((first, last))
            } else if case .appear(node: 3) = event {
                markerAppearances += 1
            }
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
        func wait(_ message: String, until condition: () -> Bool) async throws {
            for _ in 0..<200 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw NSError(domain: "LUIVirtualListReentry", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        try await wait("The initial virtual rows must report their visible range") { ranges.last?.0 == 0 }
        let scroll = views(window).compactMap { $0 as? UIScrollView }.first { $0.contentSize.height > 100_000 }!
        let scrollMetadata = metadata + "\u{1e}data-scroll-key\u{1f}remote\u{1e}data-scroll-index\u{1f}500"
        let request: [String: Any] = ["generation": 2, "ops": [
            ["op": "set-prop", "id": 2, "property": "data-attrs", "value": scrollMetadata]
        ]]
        try backend.apply(json: String(decoding: JSONSerialization.data(withJSONObject: request), as: UTF8.self))
        try await wait("A request for an unmounted row scrolls and requests its window") {
            guard let range = ranges.last else { return false }
            return scroll.contentOffset.y > 15_900 && range.0 <= 500 && range.1 >= 500
        }
        let bottomOfRows: CGFloat = 320_000
        let markerAtEdge = bottomOfRows - scroll.bounds.height + scroll.adjustedContentInset.bottom
        scroll.setContentOffset(CGPoint(x: 0, y: markerAtEdge - 8), animated: false)
        try await Task.sleep(for: .milliseconds(250))
        guard markerAppearances == 0 else {
            throw NSError(domain: "LUIVirtualListReentry", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The pagination marker fired below the visible edge"])
        }
        scroll.setContentOffset(CGPoint(x: 0, y: markerAtEdge + 8), animated: false)
        try await wait("The pagination marker fires inside the viewport") { markerAppearances == 1 }
        for _ in 0..<2 {
            scroll.setContentOffset(CGPoint(x: 0, y: bottomOfRows - 150), animated: false)
            try await wait("Distant placeholder rows must request their visible window") { (ranges.last?.1 ?? 0) >= 9990 }
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
            try await wait("Reused lazy rows must report visibility again on return") { ranges.last?.0 == 0 }
        }
        print("PASS: distant targets, exact pagination visibility and repeated viewport reentry")
    }
}
#endif
