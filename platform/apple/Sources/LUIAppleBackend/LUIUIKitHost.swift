#if canImport(UIKit)
import SwiftUI
import UIKit

/// UIKit integration for the shared SwiftUI renderer.
@MainActor
public enum LUIUIKitHost {
    /// Creates a view controller that hosts one retained LUI root.
    public static func makeViewController(
        backend: LUIAppleBackend,
        rootID: Int
    ) -> UIViewController {
        UIHostingController(
            rootView: LUISwiftUIRoot(backend: backend, rootID: rootID)
        )
    }
}
#endif
