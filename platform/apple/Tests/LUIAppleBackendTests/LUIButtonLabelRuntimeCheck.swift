#if os(iOS)
import SwiftUI
import UIKit
import Vision
@testable import LUIAppleBackend

@MainActor
enum LUIButtonLabelRuntimeCheck {
    static func main() async throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: #"{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"column"},{"op":"create-node","id":2,"kind":"button"},{"op":"set-prop","id":2,"property":"text","value":"Fallback"},{"op":"set-prop","id":2,"property":"variant","value":"ghost"},{"op":"set-prop","id":2,"property":"press-enabled","value":true},{"op":"set-prop","id":2,"property":"accessibility-label","value":"Results"},{"op":"create-node","id":3,"kind":"row"},{"op":"create-node","id":4,"kind":"icon"},{"op":"set-prop","id":4,"property":"name","value":"chevron-right"},{"op":"set-prop","id":4,"property":"width","value":10},{"op":"set-prop","id":4,"property":"height","value":10},{"op":"create-node","id":5,"kind":"text"},{"op":"set-prop","id":5,"property":"text","value":"Results"},{"op":"insert-child","parent":3,"child":4,"index":0},{"op":"insert-child","parent":3,"child":5,"index":1},{"op":"insert-child","parent":2,"child":3,"index":0},{"op":"insert-child","parent":1,"child":2,"index":0},{"op":"create-node","id":6,"kind":"context-menu"},{"op":"create-node","id":7,"kind":"menu-item"},{"op":"set-prop","id":7,"property":"text","value":"MetadataOnly"},{"op":"set-prop","id":7,"property":"press-enabled","value":true},{"op":"insert-child","parent":6,"child":7,"index":0},{"op":"insert-child","parent":2,"child":6,"index":1},{"op":"create-node","id":8,"kind":"button"},{"op":"set-prop","id":8,"property":"text","value":"Plain"},{"op":"insert-child","parent":1,"child":8,"index":1},{"op":"create-node","id":9,"kind":"toggle-button"},{"op":"create-node","id":10,"kind":"text"},{"op":"set-prop","id":10,"property":"text","value":"ToggleChild"},{"op":"insert-child","parent":9,"child":10,"index":0},{"op":"insert-child","parent":1,"child":9,"index":2}]}"#)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: LUISwiftUIRoot(backend: backend, rootID: 1).padding(24))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func text() async throws -> String {
            try await Task.sleep(for: .milliseconds(350))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: image.cgImage!, options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }
        let initial = try await text()
        guard initial.contains("Results"), initial.contains("ToggleChild"), initial.contains("Plain"),
              !initial.contains("Fallback"), !initial.contains("MetadataOnly") else {
            throw failure("Native buttons must display content children and exclude context metadata: \(initial)")
        }
        try backend.apply(json: #"{"generation":2,"ops":[{"op":"set-prop","id":5,"property":"text","value":"Two results"}]}"#)
        guard try await text().contains("Two results") else { throw failure("Child label updates must remain visible") }
        try backend.apply(json: #"{"generation":3,"ops":[{"op":"remove-child","parent":2,"child":3},{"op":"detach-subtree","id":3}]}"#)
        guard try await text().contains("Fallback") else { throw failure("Removing content children must restore text fallback") }
        print("PASS: native Button/ToggleButton labels render children, update, exclude metadata and restore fallback")
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "LUIButtonLabelRuntimeCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
