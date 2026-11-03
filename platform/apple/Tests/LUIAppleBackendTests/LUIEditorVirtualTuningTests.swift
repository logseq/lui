import SwiftUI
import Testing
#if os(macOS)
import AppKit
#endif
@testable import LUIAppleBackend

#if os(macOS)
@MainActor
private final class ExtentMarkerLifetime {
    weak var view: NSView?
}

private struct ExtentMarker: NSViewRepresentable {
    let lifetime: ExtentMarkerLifetime
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        lifetime.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
#endif

@MainActor
@Suite("Editor and virtual tuning migration", .serialized)
struct LUIEditorVirtualTuningTests {
    @Test("typed virtual tuning is accepted and invalid changes are atomic")
    func typedVirtualProperties() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: #"{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"virtual-list"},{"op":"set-prop","id":1,"property":"overscan","value":0},{"op":"set-prop","id":1,"property":"item-extent","value":24.5}]}"#)
        for (index, operation) in [
            #"{"op":"set-prop","id":1,"property":"overscan","value":-1}"#,
            #"{"op":"set-prop","id":1,"property":"overscan","value":1.5}"#,
            #"{"op":"set-prop","id":1,"property":"item-extent","value":0}"#,
        ].enumerated() {
            #expect(throws: (any Error).self) { try backend.apply(json: "{\"generation\":\(index + 2),\"ops\":[\(operation)]}") }
            #expect(backend.model(id: 1)?.property(.itemExtent)?.doubleValue == 24.5)
        }
    }

    #if os(macOS)
    @Test("typed extent overrides legacy window geometry and removal restores fallback")
    func virtualWindowGeometry() async throws {
        let marker = ExtentMarkerLifetime()
        let registry = LUIAppleExtensionRegistry()
        try registry.register(LUIAppleExtension(identifier: "extent-marker", fingerprint: "v1") { _ in
            AnyView(ExtentMarker(lifetime: marker).frame(height: 16))
        })
        let backend = try LUIAppleBackend(extensionRegistry: registry)
        try backend.apply(json: #"{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"virtual-list"},{"op":"set-prop","id":1,"property":"height","value":200},{"op":"set-prop","id":1,"property":"item-extent","value":24.5},{"op":"set-prop","id":1,"property":"data-attrs","value":"data-item-extent\u001f55"},{"op":"create-node","id":2,"kind":"column"},{"op":"set-prop","id":2,"property":"data-attrs","value":"data-virtual-count\u001f100\u001edata-virtual-start\u001f2\u001edata-virtual-length\u001f1\u001edata-item-extent\u001f40"},{"op":"create-extension","id":3,"identifier":"extent-marker","fingerprint":"v1"},{"op":"insert-child","parent":2,"child":3,"index":0},{"op":"insert-child","parent":1,"child":2,"index":0}]}"#)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: 0, width: 400, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        func scroll(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for child in view.subviews { if let found = scroll(in: child) { return found } }
            return nil
        }
        for _ in 0..<20 { hosting.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        let native = try #require(scroll(in: hosting))
        let markerView = try #require(marker.view)
        let document = try #require(native.documentView)
        #expect(abs(markerView.convert(markerView.bounds, to: document).minY - 49) < 2)
        try backend.apply(json: #"{"generation":2,"ops":[{"op":"remove-prop","id":1,"property":"item-extent"}]}"#)
        for _ in 0..<20 { hosting.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        #expect(abs(markerView.convert(markerView.bounds, to: document).minY - 110) < 2)
        try backend.apply(json: #"{"generation":3,"ops":[{"op":"remove-prop","id":1,"property":"data-attrs"}]}"#)
        for _ in 0..<20 { hosting.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        #expect(abs(markerView.convert(markerView.bounds, to: document).minY - 80) < 2)
    }

    @Test("readonly preserves selectable native fields and identity on removal", arguments:
        ["text-field", "secure-field", "input", "search-field", "textarea", "combobox"])
    func readonlyNativeField(_ kind: String) async throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"\(kind)"},
          {"op":"set-prop","id":1,"property":"text","value":"preserved"},
          {"op":"set-prop","id":1,"property":"read-only","value":true},
          {"op":"set-prop","id":1,"property":"change-enabled","value":true},
          {"op":"set-prop","id":1,"property":"submit-enabled","value":true}
        ]}
        """)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: 0, width: 400, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.stringValue == "preserved" { return field }
            for child in view.subviews { if let result = field(in: child) { return result } }
            return nil
        }
        for _ in 0..<50 where field(in: hosting) == nil {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let native = try #require(field(in: hosting))
        #expect(!native.isEditable)
        #expect(native.isSelectable)
        #expect(native.isEnabled)
        native.selectText(nil)
        let responder = window.firstResponder
        #expect(responder != nil)
        try backend.apply(json: #"{"generation":2,"ops":[{"op":"remove-prop","id":1,"property":"read-only"}]}"#)
        for _ in 0..<20 where !native.isEditable {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(field(in: hosting) === native)
        #expect(native.isEditable)
        #expect(window.firstResponder === responder)
    }
    #endif
}
