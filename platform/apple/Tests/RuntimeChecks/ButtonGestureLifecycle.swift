import Foundation
import SwiftUI
import UIKit

@testable import LUIAppleBackend

@main struct ButtonGestureLifecycleCheck {
    @MainActor static func main() async throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(
                    domain: "ButtonGestureLifecycle",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
        }

        try require(
            !LUIButtonSupplementaryGesturePolicy.installsLongPress(supportsLongPress: false),
            "ordinary buttons must not install a dormant SwiftUI long-press gesture"
        )
        try require(
            LUIButtonSupplementaryGesturePolicy.installsLongPress(supportsLongPress: true),
            "buttons with a long-press event must keep their supplementary gesture"
        )

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let previous = scenes.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: previous.windowScene!)
        let backend = LUIAppleBackend()
        try backend.apply(json: #"{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"column"},{"op":"create-node","id":2,"kind":"button"},{"op":"set-prop","id":2,"property":"text","value":"Update property"},{"op":"set-prop","id":2,"property":"press-enabled","value":true},{"op":"insert-child","parent":1,"child":2,"index":0}]}"#)
        let hosting = UIHostingController(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previous.makeKeyAndVisible()
        }

        try await Task.sleep(for: .milliseconds(100))
        for generation in 2...250 {
            let next = generation + 1
            let json = #"{"generation":\#(generation),"ops":[{"op":"create-node","id":\#(next),"kind":"button"},{"op":"set-prop","id":\#(next),"property":"text","value":"Update \#(generation)"},{"op":"set-prop","id":\#(next),"property":"press-enabled","value":true},{"op":"insert-child","parent":1,"child":\#(next),"index":0},{"op":"detach-subtree","id":\#(generation)}]}"#
            try backend.apply(json: json)
            hosting.view.layoutIfNeeded()
            await Task.yield()
        }
        try require(backend.model(id: 251)?.supportsPress == true, "the final replacement button is live")
        nativePresentationCheckpoint("BUTTON_GESTURE_REPLACEMENTS_PASS count=249")
        print("PASS: ordinary button replacements keep no dormant long-press gesture graph")
    }
}
