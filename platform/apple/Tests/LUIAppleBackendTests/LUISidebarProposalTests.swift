#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("Native sidebar proposal synchronization", .serialized)
struct LUISidebarProposalTests {
    @Test("Native sidebar reconciles paired fraction and parent-width changes without clipping")
    func parentProposal() async throws {
        _ = NSApplication.shared
        let backend = LUIAppleBackend()
        backend.frameReportingEnabled = true
        var frames: [Int: CGRect] = [:]
        backend.onFramesReport = { frames = $0 }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"split"},
          {"op":"set-prop","id":1,"property":"value","value":1.0},
          {"op":"set-prop","id":1,"property":"gap","value":0},
          {"op":"set-prop","id":1,"property":"resize-handle-width","value":3},
          {"op":"set-prop","id":1,"property":"resize-duration","value":300},
          {"op":"create-node","id":2,"kind":"split"},
          {"op":"set-prop","id":2,"property":"value","value":0.2875},
          {"op":"create-node","id":3,"kind":"box"},
          {"op":"create-node","id":4,"kind":"box"},
          {"op":"set-prop","id":4,"property":"min-width","value":240},
          {"op":"set-prop","id":4,"property":"max-width","value":460},
          {"op":"create-node","id":5,"kind":"box"},
          {"op":"create-node","id":6,"kind":"text"},
          {"op":"set-prop","id":6,"property":"text","value":"Journals"},
          {"op":"set-prop","id":6,"property":"width","value":459},
          {"op":"insert-child","parent":4,"child":6,"index":0},
          {"op":"insert-child","parent":2,"child":4,"index":0},
          {"op":"insert-child","parent":2,"child":5,"index":1},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)
        let host = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 1600, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }

        func settle() async throws {
            for _ in 0..<50 {
                host.layoutSubtreeIfNeeded()
                window.display()
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        try await settle()
        let initial = try #require(frames[4])
        #expect(initial.width >= 440, "\(frames)")
        for (generation, fraction) in [(2, 0.6), (3, 1.0)] {
            try backend.apply(json: """
            {"generation":\(generation),"ops":[
              {"op":"set-prop","id":1,"property":"value","value":\(fraction)},
              {"op":"set-prop","id":2,"property":"value","value":\(460 / (1600 * fraction))}
            ]}
            """)
            try await settle()
            let sidebar = try #require(frames[4])
            let text = try #require(frames[6])
            #expect(abs(sidebar.width - initial.width) < 2, "\(frames)")
            #expect(text.minX >= sidebar.minX - 1, "\(frames)")
            #expect(text.maxX <= sidebar.maxX + 1, "\(frames)")
        }
        window.setContentSize(CGSize(width: 1200, height: 600))
        host.setFrameSize(CGSize(width: 1200, height: 600))
        try await settle()
        #expect(abs(try #require(frames[4]).width - initial.width) < 2)
    }
}
#endif
