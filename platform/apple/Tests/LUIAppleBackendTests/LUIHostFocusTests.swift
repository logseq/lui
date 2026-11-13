#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("Standard input focus lifecycle", .serialized)
struct LUIHostFocusTests {
    @Test("Focus requests survive mounting and cannot transfer to a replacement node")
    func mountedFocus() async throws {
        _ = NSApplication.shared
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"input"},
          {"op":"set-prop","id":2,"property":"text","value":"alpha"},
          {"op":"create-node","id":3,"kind":"text-field"},
          {"op":"set-prop","id":3,"property":"text","value":"beta"},
          {"op":"create-node","id":4,"kind":"input"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)
        #expect(!backend.requestFocus(nodeID: 999))
        #expect(!backend.requestFocus(nodeID: 1))
        #expect(backend.requestFocus(nodeID: 2))
        #expect(backend.focusedNodeID == nil)
        let host = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 220, height: 180),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        func settle() async throws {
            for _ in 0..<25 {
                host.layoutSubtreeIfNeeded()
                window.display()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await settle()
        #expect(backend.focusedNodeID == 2)
        #expect((window.firstResponder as? NSTextView)?.string == "alpha")
        for (id, text) in [(3, "beta"), (2, "alpha")] {
            #expect(backend.requestFocus(nodeID: id))
            try await settle()
            #expect(backend.focusedNodeID == id)
            #expect((window.firstResponder as? NSTextView)?.string == text)
        }
        #expect(backend.requestFocus(nodeID: 4))
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"drop-node","id":4},
          {"op":"create-node","id":4,"kind":"input"},
          {"op":"set-prop","id":4,"property":"text","value":"replacement"},
          {"op":"insert-child","parent":1,"child":4,"index":2}
        ]}
        """)
        try await settle()
        #expect(backend.focusedNodeID == 2)
        #expect((window.firstResponder as? NSTextView)?.string == "alpha")
        try backend.apply(json: """
        {"generation":3,"ops":[
          {"op":"remove-child","parent":1,"child":2},
          {"op":"drop-node","id":2}
        ]}
        """)
        #expect(backend.focusedNodeID == nil)
        #expect(!backend.requestFocus(nodeID: 2))
        // Replace the focused ID before SwiftUI observes its removal.
        try backend.apply(json: """
        {"generation":4,"ops":[
          {"op":"create-node","id":2,"kind":"input"},
          {"op":"set-prop","id":2,"property":"text","value":"fresh identity"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        #expect(backend.requestFocus(nodeID: 2))
        try await settle()
        #expect(backend.focusedNodeID == 2)
        #expect((window.firstResponder as? NSTextView)?.string == "fresh identity")
    }
}
#endif
