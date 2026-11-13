import SwiftUI
import Testing
@testable import LUIAppleBackend
#if os(macOS)
import AppKit
#endif

@MainActor
@Suite("Apple host queries", .serialized)
struct LUIHostQueryTests {
    @Test("SVG replacement is atomic and image dimensions precede cropping")
    func resources() throws {
        let backend = LUIAppleBackend()
        let original = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"10\"><rect width=\"20\" height=\"10\" fill=\"red\"/></svg>".utf8)
        try backend.registerIcon(name: "app:test-icon", svg: original)
        #expect(backend.iconSource(for: "app:test-icon") == .svg(original))
        let invalid: [(String, Data)] = [
            ("check", original), ("app:bad--name", original),
            ("app:test-icon", Data("not an SVG".utf8)),
            ("app:test-icon", Data("<svg width=\"0\" height=\"10\"/>".utf8)),
        ]
        for (name, data) in invalid {
            #expect(throws: LUIBackendError.self) { try backend.registerIcon(name: name, svg: data) }
            #expect(backend.iconSource(for: "app:test-icon") == .svg(original))
        }
        let replacement = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 32 16\"><path d=\"M0 0h32v16H0z\" fill=\"blue\"/></svg>".utf8)
        try backend.registerIcon(name: "app:test-icon", svg: replacement)
        #expect(backend.iconSource(for: "app:test-icon") == .svg(replacement))
        backend.unregisterIcon(name: "app:test-icon")
        #expect(backend.iconSource(for: "app:test-icon") == .systemName("questionmark.square.dashed"))
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"image"},
          {"op":"set-prop","id":1,"property":"image","value":7},
          {"op":"set-prop","id":1,"property":"source-x","value":0.0},
          {"op":"set-prop","id":1,"property":"source-y","value":0.0},
          {"op":"set-prop","id":1,"property":"source-width","value":5.0},
          {"op":"set-prop","id":1,"property":"source-height","value":5.0}
        ]}
        """)
        #expect(backend.naturalImageSize(nodeID: 1) == nil)
        let context = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        try backend.registerImage(id: 7, image: #require(context.makeImage()))
        #expect(backend.naturalImageSize(nodeID: 1) == CGSize(width: 40, height: 20))
        backend.unregisterImage(id: 7)
        #expect(backend.naturalImageSize(nodeID: 1) == nil)
        #expect(backend.naturalImageSize(nodeID: 999) == nil)
    }

    #if os(macOS)
    @Test("Mounted native text exposes immutable UTF-16 metrics with expiring identity")
    func committedText() async throws {
        _ = NSApplication.shared
        let backend = LUIAppleBackend()
        backend.frameReportingEnabled = true
        var reports = 0
        backend.onFramesReport = { _ in reports += 1 }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"A😀 ffi é\\nאבג xyz"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        #expect(backend.textGeometry(nodeID: 2) == nil)
        let hosting = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: 0, width: 220, height: 180),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        for _ in 0..<100 where backend.textGeometry(nodeID: 2) == nil {
            hosting.layoutSubtreeIfNeeded()
            window.display()
            try await Task.sleep(for: .milliseconds(10))
        }
        let geometry = try #require(backend.textGeometry(nodeID: 2))
        #expect(geometry.text == "A😀 ffi é\nאבג xyz")
        #expect(geometry.generation == 1)
        #expect(geometry.frame.width > 0 && geometry.frame.height > 0)
        #expect(geometry.lineRanges.count >= 2)
        #expect(backend.isCurrent(geometry))
        let caret = try #require(geometry.caretRect(atUTF16Offset: 1))
        #expect(caret.height > 0)
        #expect(geometry.offset(at: CGPoint(x: caret.minX, y: caret.midY)) == 1)
        #expect(geometry.caretRect(atUTF16Offset: -1) == nil)
        #expect(geometry.caretRect(atUTF16Offset: geometry.text.utf16.count + 1) == nil)
        #expect(!geometry.selectionRects(in: NSRange(location: 0, length: 3)).isEmpty)
        #expect(geometry.selectionRects(in: NSRange(location: Int.max, length: 10)).isEmpty)
        #expect(reports > 0)
        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"set-prop","id":2,"property":"text","value":"Replacement"}]}
        """)
        #expect(!backend.isCurrent(geometry))
        #expect(backend.textGeometry(nodeID: 2) == nil)
        for _ in 0..<100 where backend.textGeometry(nodeID: 2) == nil {
            hosting.layoutSubtreeIfNeeded(); window.display()
            try await Task.sleep(for: .milliseconds(10))
        }
        let replacement = try #require(backend.textGeometry(nodeID: 2))
        #expect(replacement.text == "Replacement")
        #expect(geometry.text == "A😀 ffi é\nאבג xyz")
        #expect(geometry.caretRect(atUTF16Offset: 1) == caret)
        try backend.applySnapshot(json: """
        {"generation":3,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"Reused id"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        #expect(!backend.isCurrent(replacement))
        for _ in 0..<100 where backend.textGeometry(nodeID: 2) == nil {
            hosting.layoutSubtreeIfNeeded(); window.display()
            try await Task.sleep(for: .milliseconds(10))
        }
        let reused = try #require(backend.textGeometry(nodeID: 2))
        #expect(reused.incarnation != replacement.incarnation)
        window.contentView = nil
        #expect(backend.textGeometry(nodeID: 2) == nil)
    }
    #endif
}
