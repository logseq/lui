#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

@available(iOS 16.0, *)
public struct LUISwiftUIRoot: UIViewRepresentable {
    private let backend: LUIUIKitBackend
    private let rootID: Int

    public init(backend: LUIUIKitBackend, rootID: Int) {
        self.backend = backend
        self.rootID = rootID
    }

    public func makeUIView(context: Context) -> LUIRootContainerView {
        let container = LUIRootContainerView()
        container.show(backend.view(id: rootID))
        return container
    }

    public func updateUIView(_ container: LUIRootContainerView, context: Context) {
        container.show(backend.view(id: rootID))
    }
}

@available(iOS 16.0, *)
public final class LUIRootContainerView: UIView {
    private weak var rootView: UIView?

    public func show(_ nextRoot: UIView?) {
        guard rootView !== nextRoot else { return }
        rootView?.removeFromSuperview()
        rootView = nextRoot
        guard let nextRoot else { return }
        addSubview(nextRoot)
        NSLayoutConstraint.activate([
            nextRoot.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            nextRoot.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            nextRoot.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            nextRoot.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}
#endif
