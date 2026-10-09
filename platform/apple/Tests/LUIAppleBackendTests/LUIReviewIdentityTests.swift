import SwiftUI
import Testing
#if os(macOS)
import AppKit
#endif
@testable import LUIAppleBackend

#if os(macOS)
@MainActor
private final class ReviewRowLifetime {
    var appearances: [UUID] = []
}

@MainActor
private struct ReviewStatefulRow: View {
    let lifetime: ReviewRowLifetime
    @State private var draftIdentity = UUID()

    var body: some View {
        Text("Retained draft")
            .onAppear { lifetime.appearances.append(draftIdentity) }
    }
}

@MainActor
@Suite("Review list identity", .serialized)
struct LUIReviewIdentityTests {
    @Test("List updates preserve row-local SwiftUI state")
    func listCommitPreservesRowState() async throws {
        let lifetime = ReviewRowLifetime()
        let registry = LUIAppleExtensionRegistry()
        try registry.register(LUIAppleExtension(
            identifier: "review-stateful-row", fingerprint: "review-v1"
        ) { _ in AnyView(ReviewStatefulRow(lifetime: lifetime)) })
        let backend = try LUIAppleBackend(extensionRegistry: registry)
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"list"},
          {"op":"create-node","id":2,"kind":"list-item"},
          {"op":"set-prop","id":2,"property":"text","value":"Row"},
          {"op":"create-extension","id":3,"identifier":"review-stateful-row","fingerprint":"review-v1"},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: 0, width: 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        for _ in 0..<50 where lifetime.appearances.isEmpty {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let initial = try #require(lifetime.appearances.first)
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"width","value":350}
        ]}
        """)
        for _ in 0..<20 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!lifetime.appearances.isEmpty)
        #expect(lifetime.appearances.allSatisfy { $0 == initial })
    }
}
#endif
