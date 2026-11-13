import SwiftUI
import Testing
@testable import LUIAppleBackend
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
@Suite("Apple host queries", .serialized)
struct LUIHostQueryTests {
    @Test("Inline newline end carets retain their downstream line", arguments: ["Ptail\n", "Ptail\nQ"])
    func trailingLineGeometry(document: String) throws {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 16)
        #else
        let font = UIFont.systemFont(ofSize: 16)
        #endif
        let layout = LUITextLayout(text: NSAttributedString(string: document,
            attributes: [.font: font]), width: 200, lineLimit: nil)
        let range = NSRange(location: 1, length: 5)
        let bounds = try #require(layout.bounds(for: range))
        let geometry = LUICommittedTextGeometry(nodeID: 1, generation: 1, incarnation: 1,
            text: "tail\n", frame: bounds, identity: UUID(), layout: layout,
            sourceRange: range, sourceOrigin: bounds.origin)
        #expect(geometry.lineRanges == [NSRange(location: 0, length: 5), NSRange(location: 5, length: 0)])
        let endCaret = try #require(geometry.caretRect(atUTF16Offset: 5))
        #expect(geometry.offset(at: CGPoint(x: endCaret.midX, y: endCaret.midY)) == 5)
    }

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

    @Test("Nested text runs share wrapping and keep per-run committed caret geometry")
    func nestedTextGeometry() async throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let backend = LUIAppleBackend()
        backend.frameReportingEnabled = true
        var frames: [Int: CGRect] = [:]
        backend.onFramesReport = { frames = $0 }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"set-prop","id":1,"property":"font-size","value":"var(--editor-size, 14px)"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"display","value":"block"},
          {"op":"set-prop","id":2,"property":"position","value":"relative"},
          {"op":"set-prop","id":2,"property":"z-index","value":1},
          {"op":"set-prop","id":2,"property":"user-select","value":"text"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":3,"property":"text","value":"Apple smoke hello 世界 and a long line that wraps onto another line"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"set-prop","id":4,"property":"text","value":"\u{200B}"},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        _ = backend.textGeometry(nodeID: 3)
        _ = backend.textGeometry(nodeID: 4)
        let root = LUISwiftUIRoot(backend: backend, rootID: 1)
            .luiStyleVariables(["--editor-size": "20px"])
            .environment(\.colorScheme, .light)
        #if os(macOS)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 220, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        func layout() { hosting.layoutSubtreeIfNeeded(); window.display() }
        #else
        let hosting = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 220, height: 240))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func layout() { window.layoutIfNeeded(); hosting.view.layoutIfNeeded() }
        #endif
        for _ in 0..<60 where backend.textGeometry(nodeID: 4) == nil {
            layout()
            try await Task.sleep(for: .milliseconds(10))
        }
        let run = try #require(backend.textGeometry(nodeID: 3))
        let pad = try #require(backend.textGeometry(nodeID: 4))
        #expect(run.text == backend.model(id: 3)?.text)
        #expect(run.lineRanges.count > 1)
        #if os(macOS)
        let nativeText = try #require(backend.hostQueries.textViews[3]?.value)
        let bitmap = try #require(nativeText.bitmapImageRepForCachingDisplay(in: nativeText.bounds))
        nativeText.cacheDisplay(in: nativeText.bounds, to: bitmap)
        let painted = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return pixel.alphaComponent > 0.1
                    && (pixel.redComponent + pixel.greenComponent + pixel.blueComponent) / 3 < 0.8
            }
        }
        #expect(painted)
        #endif
        let caret = try #require(run.caretRect(atUTF16Offset: run.text.utf16.count))
        let padCaret = try #require(pad.caretRect(atUTF16Offset: 0))
        #expect(caret.height >= 20)
        #expect(abs(run.frame.minX + caret.minX - pad.frame.minX - padCaret.minX) < 1)
        #expect(abs(run.frame.minY + caret.minY - pad.frame.minY - padCaret.minY) < 1)
        #expect(!run.selectionRects(in: NSRange(location: 6, length: 5)).isEmpty)
        #expect(backend.isCurrent(run) && backend.isCurrent(pad))
        #expect(frames[3] == run.frame && frames[4] == pad.frame)
        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"set-prop","id":3,"property":"text","value":"Updated 世界"}]}
        """)
        #expect(!backend.isCurrent(run))
        for _ in 0..<60 where backend.textGeometry(nodeID: 3) == nil {
            layout()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(backend.textGeometry(nodeID: 3)?.text == "Updated 世界")
    }

    @Test("Host scroll commands bind to mounted native viewports and expire with node identity")
    func mountedScrolling() async throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let backend = LUIAppleBackend()
        backend.frameReportingEnabled = true
        var reports = 0
        backend.onFramesReport = { _ in reports += 1 }
        let batch = """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"scroll"},
          {"op":"create-node","id":2,"kind":"scroll"},
          {"op":"set-prop","id":2,"property":"height","value":180},
          {"op":"set-prop","id":2,"property":"width","value":220},
          {"op":"create-node","id":3,"kind":"column"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"set-prop","id":4,"property":"text","value":"Head"},
          {"op":"set-prop","id":4,"property":"height","value":900},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"set-prop","id":5,"property":"text","value":"Target"},
          {"op":"set-prop","id":5,"property":"height","value":60},
          {"op":"insert-child","parent":3,"child":4,"index":0},
          {"op":"insert-child","parent":3,"child":5,"index":1},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """
        try backend.apply(json: batch)
        #expect(backend.scrollMetrics(nodeID: 2) == nil)
        #expect(!backend.setScrollTop(nodeID: 2, top: 120))
        #expect(!backend.scrollIntoView(nodeID: 5))
        let root = LUISwiftUIRoot(backend: backend, rootID: 1)
        #if os(macOS)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: 0, width: 220, height: 180),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        func layout() { hosting.layoutSubtreeIfNeeded(); window.display() }
        #else
        let hosting = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 220, height: 180))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func layout() { window.layoutIfNeeded(); hosting.view.layoutIfNeeded() }
        #endif
        for _ in 0..<100 where backend.scrollMetrics(nodeID: 2) == nil {
            layout()
            try await Task.sleep(for: .milliseconds(10))
        }
        let metrics = try #require(backend.scrollMetrics(nodeID: 2))
        #expect(metrics.contentSize.height >= 960)
        #expect(metrics.viewportSize.height > 0 && metrics.viewportSize.height <= 180)
        #expect(backend.setScrollTop(nodeID: 2, top: 120))
        #expect(abs(try #require(backend.scrollMetrics(nodeID: 2)).offset - 120) < 1)
        #expect(backend.setScrollTop(nodeID: 2, top: 0))
        var revealed = backend.scrollIntoView(nodeID: 5)
        for _ in 0..<100 where !revealed {
            layout()
            try await Task.sleep(for: .milliseconds(10))
            revealed = backend.scrollIntoView(nodeID: 5)
        }
        #expect(revealed)
        #expect(try #require(backend.scrollMetrics(nodeID: 2)).offset > 0)
        #expect(!backend.setScrollTop(nodeID: 2, top: .nan))
        #expect(!backend.setScrollTop(nodeID: 4, top: 10))
        #expect(backend.scrollMetrics(nodeID: 4) == nil)
        #expect(!backend.scrollIntoView(nodeID: 999))
        #expect(reports > 0)
        try backend.applySnapshot(json: batch.replacingOccurrences(of: "\"generation\":1", with: "\"generation\":2"))
        #if os(macOS)
        window.contentView = nil
        #else
        window.isHidden = true
        window.rootViewController = nil
        #endif
        #expect(backend.scrollMetrics(nodeID: 2) == nil)
        #expect(!backend.setScrollTop(nodeID: 2, top: 20))
        #expect(!backend.scrollIntoView(nodeID: 5))
    }

    @Test("A zero-width empty-block pad commits a native caret without a draw pass")
    func zeroWidthCaret() async throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"\u{200B}"}
        ]}
        """)
        let model = try #require(backend.model(id: 2))
        let view = LUICommittedTextNativeView()
        view.frame = CGRect(x: 10, y: 10, width: 0, height: 40)
        #if os(macOS)
        _ = NSApplication.shared
        let font = NSFont.systemFont(ofSize: 15)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 200, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView?.addSubview(view)
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        func layout() { view.layoutSubtreeIfNeeded(); window.display() }
        #else
        let font = UIFont.systemFont(ofSize: 15)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func layout() { window.layoutIfNeeded(); view.layoutIfNeeded() }
        #endif
        view.configure(model: model, backend: backend,
            text: NSAttributedString(string: model.text, attributes: [.font: font]), lineLimit: nil)
        for _ in 0..<50 where backend.textGeometry(nodeID: 2) == nil {
            layout()
            try await Task.sleep(for: .milliseconds(10))
        }
        let geometry = try #require(backend.textGeometry(nodeID: 2))
        let caret = try #require(geometry.caretRect(atUTF16Offset: 0))
        #expect(geometry.frame.width == 0)
        #expect(caret.minX.isFinite && caret.minY.isFinite && caret.height > 0)
        #expect(backend.isCurrent(geometry))
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
