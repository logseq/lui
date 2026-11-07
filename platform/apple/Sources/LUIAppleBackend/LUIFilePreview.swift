import SwiftUI
#if os(iOS)
import UIKit
#else
import QuickLook
#endif

extension View {
    @ViewBuilder
    func luiFilePreview(_ url: Binding<URL?>) -> some View {
        #if os(iOS)
        background(LUIFilePreviewAnchor(url: url).frame(width: 0, height: 0))
        #else
        quickLookPreview(url)
        #endif
    }
}

#if os(iOS)
// UIKit loads its native Quick Look preview when requested. Linking the
// SwiftUI QuickLook overlay eagerly loads the entire preview dependency graph.
private struct LUIFilePreviewAnchor: UIViewControllerRepresentable {
    @Binding var url: URL?

    func makeUIViewController(context: Context) -> LUIFilePreviewController {
        LUIFilePreviewController()
    }

    func updateUIViewController(_ controller: LUIFilePreviewController, context: Context) {
        controller.update(url: url) { dismissedURL in
            if url == dismissedURL { url = nil }
        }
    }

    static func dismantleUIViewController(_ controller: LUIFilePreviewController, coordinator: ()) {
        controller.stop()
    }
}

private final class LUIFilePreviewController: UIViewController, @preconcurrency UIDocumentInteractionControllerDelegate {
    private var requestedURL: URL?
    private var activeURL: URL?
    private var document: UIDocumentInteractionController?
    private var isDismissing = false
    private var onDismiss: ((URL) -> Void)?

    func update(url: URL?, onDismiss: @escaping (URL) -> Void) {
        requestedURL = url
        self.onDismiss = onDismiss
        reconcile()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reconcile()
    }

    private func reconcile() {
        guard !isDismissing else { return }
        if let document {
            if requestedURL != activeURL {
                if let transition = parent?.presentedViewController?.transitionCoordinator {
                    transition.animate(alongsideTransition: nil) { [weak self] _ in
                        self?.reconcile()
                    }
                    return
                }
                isDismissing = true
                document.dismissPreview(animated: true)
            }
            return
        }
        guard viewIfLoaded?.window != nil, let url = requestedURL else { return }
        let document = UIDocumentInteractionController(url: url)
        document.delegate = self
        self.document = document
        activeURL = url
        if !document.presentPreview(animated: true) {
            self.document = nil
            activeURL = nil
            requestedURL = nil
            onDismiss?(url)
        }
    }

    func documentInteractionControllerViewControllerForPreview(
        _ controller: UIDocumentInteractionController
    ) -> UIViewController {
        parent ?? self
    }

    func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        guard document === controller else { return }
        let dismissedURL = activeURL
        document = nil
        activeURL = nil
        isDismissing = false
        if let dismissedURL, requestedURL == dismissedURL {
            requestedURL = nil
            onDismiss?(dismissedURL)
        } else {
            reconcile()
        }
    }

    func stop() {
        requestedURL = nil
        onDismiss = nil
        document?.delegate = nil
        document?.dismissPreview(animated: false)
        document = nil
        activeURL = nil
        isDismissing = false
    }
}
#endif
