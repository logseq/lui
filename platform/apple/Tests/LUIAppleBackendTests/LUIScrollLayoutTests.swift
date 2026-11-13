import SwiftUI
import Testing
@testable import LUIAppleBackend
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
@Suite("Retained scroll layout", .serialized)
struct LUIScrollLayoutTests {
    @Test("Growing content retains viewport width beside empty containers and respects its cap")
    func cappedGrowingColumn() async throws {
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        for queriesText in [false, true] {
            let backend = LUIAppleBackend()
            backend.frameReportingEnabled = true
            var frames: [Int: CGRect] = [:]
            backend.onFramesReport = { frames = $0 }
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":6,"kind":"column"},
              {"op":"set-prop","id":6,"property":"grow","value":1},
              {"op":"create-node","id":7,"kind":"row"},
              {"op":"set-prop","id":7,"property":"grow","value":1},
              {"op":"set-prop","id":7,"property":"cross","value":"stretch"},
              {"op":"set-prop","id":7,"property":"gap","value":0},
              {"op":"create-node","id":12,"kind":"column"},
              {"op":"set-prop","id":12,"property":"grow","value":0},
              {"op":"create-node","id":13,"kind":"spacer"},
              {"op":"create-node","id":1,"kind":"scroll"},
              {"op":"set-prop","id":1,"property":"grow","value":1},
              {"op":"set-prop","id":1,"property":"min-height","value":0},
              {"op":"set-prop","id":1,"property":"padding-horizontal","value":16},
              {"op":"set-prop","id":1,"property":"padding-vertical","value":32},
              {"op":"create-node","id":2,"kind":"row"},
              {"op":"set-prop","id":2,"property":"main","value":"center"},
              {"op":"set-prop","id":2,"property":"min-width","value":0},
              {"op":"set-prop","id":2,"property":"margin-left","value":16},
              {"op":"create-node","id":3,"kind":"column"},
              {"op":"set-prop","id":3,"property":"grow","value":1},
              {"op":"set-prop","id":3,"property":"min-width","value":0},
              {"op":"set-prop","id":3,"property":"max-width","value":960},
              {"op":"create-node","id":5,"kind":"column"},
              {"op":"set-prop","id":5,"property":"min-width","value":0},
              {"op":"create-node","id":14,"kind":"row"},
              {"op":"set-prop","id":14,"property":"main","value":"space_between"},
              {"op":"create-node","id":15,"kind":"row"},
              {"op":"set-prop","id":15,"property":"grow","value":1},
              {"op":"set-prop","id":15,"property":"cross","value":"start"},
              {"op":"set-prop","id":15,"property":"gap","value":0},
              {"op":"create-node","id":16,"kind":"row"},
              {"op":"create-node","id":17,"kind":"box"},
              {"op":"create-node","id":18,"kind":"box"},
              {"op":"set-prop","id":18,"property":"grow","value":1},
              {"op":"create-node","id":19,"kind":"row"},
              {"op":"create-node","id":20,"kind":"box"},
              {"op":"create-node","id":21,"kind":"text"},
              {"op":"set-prop","id":21,"property":"text","value":"More actions"},
              {"op":"set-prop","id":21,"property":"style-class","value":"single-line"},
              {"op":"create-node","id":4,"kind":"text"},
              {"op":"set-prop","id":4,"property":"text","value":"Nov 13th, 2026"},
              {"op":"insert-child","parent":18,"child":4,"index":0},
              {"op":"insert-child","parent":19,"child":20,"index":0},
              {"op":"insert-child","parent":16,"child":17,"index":0},
              {"op":"insert-child","parent":15,"child":18,"index":0},
              {"op":"insert-child","parent":15,"child":19,"index":1},
              {"op":"insert-child","parent":14,"child":15,"index":0},
              {"op":"insert-child","parent":14,"child":16,"index":1},
              {"op":"insert-child","parent":14,"child":21,"index":2},
              {"op":"insert-child","parent":5,"child":14,"index":0},
              {"op":"insert-child","parent":3,"child":5,"index":0},
              {"op":"insert-child","parent":2,"child":3,"index":0},
              {"op":"insert-child","parent":1,"child":2,"index":0},
              {"op":"insert-child","parent":12,"child":13,"index":0},
              {"op":"insert-child","parent":7,"child":1,"index":0},
              {"op":"insert-child","parent":7,"child":12,"index":1},
              {"op":"insert-child","parent":6,"child":7,"index":0}
            ]}
            """)
            if queriesText { _ = backend.textGeometry(nodeID: 4) }
            let root = LUISwiftUIRoot(backend: backend, rootID: 6)
            #if os(macOS)
            let hosting = NSHostingView(rootView: root)
            hosting.sizingOptions = []
            let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 1600, height: 1200),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil); window.contentView = nil }
            #else
            let hosting = UIHostingController(rootView: root)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1600, height: 1200))
            window.rootViewController = hosting
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            #endif
            for width: CGFloat in [1600, 390] {
                #if os(macOS)
                window.setContentSize(CGSize(width: width, height: 1200))
                hosting.setFrameSize(CGSize(width: width, height: 1200))
                #else
                window.frame.size = CGSize(width: width, height: 1200)
                #endif
                for _ in 0..<30 {
                    #if os(macOS)
                    hosting.layoutSubtreeIfNeeded()
                    window.display()
                    #else
                    window.layoutIfNeeded()
                    hosting.view.layoutIfNeeded()
                    #endif
                    try await Task.sleep(for: .milliseconds(10))
                }
                let viewport = try #require(frames[1])
                let column = try #require(frames[3])
                let title = try #require(frames[18])
                let trailing = try #require(frames[21])
                let text = try #require(frames[4])
                #expect(abs((try #require(frames[6])).width - width) < 1,
                    "Mounted root must resize to \(width): \(frames)")
                #expect(abs(viewport.width - (try #require(frames[6])).width) < 1,
                    "Non-growing empty column must not split the viewport: \(frames)")
                #expect(abs(column.width - min(viewport.width - 48, 960)) < 1,
                    "viewport=\(viewport), column=\(column), queriesText=\(queriesText)")
                #expect(abs(column.midX - viewport.midX - 8) < 1)
                #expect(abs(title.width - column.width + trailing.width) < 1,
                    "Non-growing empty rows must not split title width: \(title), \(column)")
                #expect(trailing.width > 60 && trailing.height < 30)
                #expect(text.height < 40, "text must fit on one line: \(text)")
            }
        }
    }
}
