import SwiftUI
import Testing
@testable import LUIAppleBackend
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
@Suite("Retained absolute positioning", .serialized)
struct LUIAbsolutePositionTests {
    @Test("Absolute children do not enlarge Row or Column flow")
    func absoluteChildrenStayOutOfFlow() async throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        for kind in ["row", "column"] {
            let backend = LUIAppleBackend()
            backend.frameReportingEnabled = true
            var frames: [Int: CGRect] = [:]
            backend.onFramesReport = { frames = $0 }
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"\(kind)"},
              {"op":"set-prop","id":1,"property":"width","value":200},
              {"op":"set-prop","id":1,"property":"cross","value":"start"},
              {"op":"create-node","id":2,"kind":"box"},
              {"op":"set-prop","id":2,"property":"width","value":60},
              {"op":"set-prop","id":2,"property":"height","value":20},
              {"op":"create-node","id":3,"kind":"box"},
              {"op":"set-prop","id":3,"property":"width","value":400},
              {"op":"set-prop","id":3,"property":"height","value":400},
              {"op":"set-prop","id":3,"property":"position","value":"absolute"},
              {"op":"set-prop","id":3,"property":"inset","value":0},
              {"op":"insert-child","parent":1,"child":2,"index":0},
              {"op":"insert-child","parent":1,"child":3,"index":1}
            ]}
            """)
            let root = LUISwiftUIRoot(backend: backend, rootID: 1)
                .fixedSize(horizontal: false, vertical: true).ignoresSafeArea()
            #if os(macOS)
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 200, height: 500),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.orderOut(nil); window.contentView = nil }
            #else
            let host = UIHostingController(rootView: root)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 500))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            #endif
            for _ in 0..<20 {
                #if os(macOS)
                host.layoutSubtreeIfNeeded()
                window.display()
                #else
                window.layoutIfNeeded()
                host.view.layoutIfNeeded()
                #endif
                try await Task.sleep(for: .milliseconds(10))
            }
            let container = try #require(frames[1])
            let overlay = try #require(frames[3])
            #expect(abs(container.height - 20) < 1, "\(kind): \(frames)")
            #expect(abs(overlay.minX - container.minX) < 1)
            #expect(abs(overlay.minY - container.minY) < 1)
        }
    }

    @Test("Absolute stack children honor physical edges and opposing insets when resized")
    func absoluteInsets() async throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let backend = LUIAppleBackend()
            backend.frameReportingEnabled = true
            var frames: [Int: CGRect] = [:]
            backend.onFramesReport = { frames = $0 }
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"stack"},
              {"op":"create-node","id":2,"kind":"button"},
              {"op":"set-prop","id":2,"property":"text","value":"?"},
              {"op":"set-prop","id":2,"property":"width","value":32},
              {"op":"set-prop","id":2,"property":"height","value":32},
              {"op":"set-prop","id":2,"property":"position","value":"absolute"},
              {"op":"set-prop","id":2,"property":"inset-right","value":32.0},
              {"op":"set-prop","id":2,"property":"inset-bottom","value":45.0},
              {"op":"create-node","id":3,"kind":"box"},
              {"op":"set-prop","id":3,"property":"width","value":20},
              {"op":"set-prop","id":3,"property":"height","value":10},
              {"op":"create-node","id":4,"kind":"box"},
              {"op":"set-prop","id":4,"property":"position","value":"absolute"},
              {"op":"set-prop","id":4,"property":"inset","value":8.0},
              {"op":"insert-child","parent":1,"child":3,"index":0},
              {"op":"insert-child","parent":1,"child":4,"index":1},
              {"op":"insert-child","parent":1,"child":2,"index":2}
            ]}
            """)
            let root = LUISwiftUIRoot(backend: backend, rootID: 1)
                .environment(\.layoutDirection, direction)
                .ignoresSafeArea()
            #if os(macOS)
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 500, height: 400),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.orderOut(nil); window.contentView = nil }
            #else
            let host = UIHostingController(rootView: root)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            #endif
            for size in [CGSize(width: 500, height: 400), CGSize(width: 390, height: 250)] {
                #if os(macOS)
                window.setContentSize(size)
                host.setFrameSize(size)
                #else
                window.frame.size = size
                #endif
                for _ in 0..<20 {
                    #if os(macOS)
                    host.layoutSubtreeIfNeeded()
                    window.display()
                    #else
                    window.layoutIfNeeded()
                    host.view.layoutIfNeeded()
                    #endif
                    try await Task.sleep(for: .milliseconds(10))
                }
                let container = try #require(frames[1])
                let button = try #require(frames[2])
                let inset = try #require(frames[4])
                #expect(abs(container.width - size.width) < 1)
                #expect(abs(container.height - size.height) < 1)
                #expect(abs(container.maxX - button.maxX - 32) < 1, "\(direction): \(frames)")
                #expect(abs(container.maxY - button.maxY - 45) < 1)
                #expect(abs(inset.minX - container.minX - 8) < 1)
                #expect(abs(inset.minY - container.minY - 8) < 1)
                #expect(abs(inset.width - container.width + 16) < 1)
                #expect(abs(inset.height - container.height + 16) < 1)
            }
        }
    }
}
