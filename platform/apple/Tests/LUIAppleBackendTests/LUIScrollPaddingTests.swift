#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("Native scroll padding", .serialized)
struct LUIScrollPaddingTests {
    @Test("Padding belongs to the scrolling document, keeping the whole container as viewport")
    func wholeContainerViewport() async throws {
        _ = NSApplication.shared
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"scroll"},
          {"op":"set-prop","id":1,"property":"orientation","value":"vertical"},
          {"op":"set-prop","id":1,"property":"width","value":400},
          {"op":"set-prop","id":1,"property":"height","value":320},
          {"op":"set-prop","id":1,"property":"padding-horizontal","value":16},
          {"op":"set-prop","id":1,"property":"padding-vertical","value":32},
          {"op":"create-node","id":2,"kind":"box"},
          {"op":"set-prop","id":2,"property":"width","value":320},
          {"op":"set-prop","id":2,"property":"height","value":1000},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        let host = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1))
        let window = NSWindow(contentRect: CGRect(x: -10000, y: 0, width: 400, height: 320),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        var scroll: NSScrollView?
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            scroll = find(host)
            if scroll?.documentView != nil { break }
            try await Task.sleep(for: .milliseconds(15))
        }
        let native = try #require(scroll)
        let frame = native.convert(native.bounds, to: host)
        #expect(abs(frame.height - 320) < 1)
        #expect(abs(frame.width - 400) < 1)
        let scroller = try #require(native.verticalScroller)
        let scrollerFrame = scroller.convert(scroller.bounds, to: host)
        #expect(host.bounds.contains(scrollerFrame), "The entire scrollbar must remain inside the container")
        #expect(abs((native.documentView?.frame.height ?? 0) - 1064) < 1)
    }
}
#endif
