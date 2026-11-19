import Foundation
import SwiftUI
import UIKit

@testable import LUIAppleBackend

private struct ReadOnlyFieldHost: View {
    @State var text = "Read-only"

    var body: some View {
        // Two read-only probes resolve the same UIKit field, as happens when a
        // retained or replacement probe reaches a field another probe owns.
        TextField("Field", text: $text)
            .modifier(LUIReadOnlyTextControl(readOnly: true))
            .modifier(LUIReadOnlyTextControl(readOnly: true))
    }
}

@main struct ReadOnlyFieldDelegateCheck {
    @MainActor static func main() async throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(
                    domain: "ReadOnlyFieldDelegate",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
        }
        func fields(in view: UIView) -> [UITextField] {
            if let field = view as? UITextField { return [field] }
            return view.subviews.flatMap { fields(in: $0) }
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let previous = scenes.flatMap(\.windows).first { $0.isKeyWindow }!
        let window = UIWindow(windowScene: previous.windowScene!)
        let hosting = UIHostingController(rootView: ReadOnlyFieldHost())
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previous.makeKeyAndVisible()
        }

        for _ in 0..<5 {
            hosting.view.setNeedsLayout()
            hosting.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        let mounted = fields(in: hosting.view)
        try require(mounted.count == 1, "expected one native text field, found \(mounted.count)")
        let field = mounted[0]
        guard let delegate = field.delegate else {
            throw NSError(domain: "ReadOnlyFieldDelegate", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "the read-only delegate is installed"])
        }
        nativePresentationCheckpoint("READ_ONLY_DELEGATES_INSTALLED")

        // UIKit asks the delegate about optional methods; a delegate chain that
        // loops back on itself recurses here until the stack overflows.
        let unimplemented = NSSelectorFromString("luiReadOnlyCheckUnimplemented:")
        try require(!delegate.responds(to: unimplemented), "unimplemented selectors resolve to false")
        nativePresentationCheckpoint("READ_ONLY_DELEGATE_RESPONDS_PASS")

        let edit = delegate.textField?(
            field, shouldChangeCharactersIn: NSRange(location: 0, length: 0),
            replacementString: "x"
        )
        try require(edit == false, "the read-only delegate rejects edits, got \(String(describing: edit))")
        nativePresentationCheckpoint("READ_ONLY_DELEGATE_EDIT_PASS")
        print("PASS: stacked read-only probes keep an acyclic delegate chain and block edits")
    }
}
