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
        ]
        let json = try JSONSerialization.data(withJSONObject: ["generation": 1, "ops": operations])
        try backend.apply(json: String(decoding: json, as: UTF8.self))
        var ranges: [(Int, Int)] = []
        backend.onEvent = { event in
            if case let .visibleRange(node, first, last) = event, node == 2 {
                ranges.append((first, last))
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
        for _ in 0..<2 {
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height), animated: false)
            try await wait("Distant placeholder rows must request their visible window") { (ranges.last?.1 ?? 0) >= 9990 }
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
            try await wait("Reused lazy rows must report visibility again on return") { ranges.last?.0 == 0 }
        }
        print("PASS: virtual list rows re-register visibility on repeated distant scrolls and returns")
    }
}
#endif
