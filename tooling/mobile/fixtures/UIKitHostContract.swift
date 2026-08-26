import LUIAppleBackend
import UIKit

@MainActor
func embedLUIRoot(
    backend: LUIAppleBackend,
    rootID: Int
) -> UINavigationController {
    let hostedRoot: UIViewController = LUIUIKitHost.makeViewController(
        backend: backend,
        rootID: rootID
    )
    return UINavigationController(rootViewController: hostedRoot)
}
