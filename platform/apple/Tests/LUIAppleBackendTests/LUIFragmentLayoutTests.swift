#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("Transparent fragment layout", .serialized)
struct LUIFragmentLayoutTests {
    @Test("Virtual sources retain fragment row identities")
    func virtualRowIdentity() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: #"{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"virtual-list"},{"op":"create-node","id":2,"kind":"box"},{"op":"set-prop","id":2,"property":"display","value":"contents"},{"op":"create-node","id":3,"kind":"box"},{"op":"insert-child","parent":2,"child":3,"index":0},{"op":"insert-child","parent":1,"child":2,"index":0}]}"#)
        #expect(try #require(backend.model(id: 1)).visibleChildren == [2])
    }

    @Test("Plain bounded containers match decorated container sizing")
    func boundedContainerSizing() async throws {
        _ = NSApplication.shared
        for kind in ["row", "column", "box"] {
            for decorated in [false, true] {
                let backend = LUIAppleBackend()
                backend.frameReportingEnabled = true
                var frames: [Int: CGRect] = [:]
                backend.onFramesReport = { frames = $0 }
                let decoration = decorated ? #",{"op":"set-prop","id":1,"property":"background","value":"transparent"}"# : ""
                try backend.apply(json: """
                {"generation":1,"ops":[
                  {"op":"create-node","id":1,"kind":"\(kind)"},
                  {"op":"set-prop","id":1,"property":"min-width","value":80},
                  {"op":"set-prop","id":1,"property":"max-width","value":100},
                  {"op":"set-prop","id":1,"property":"min-height","value":40},
                  {"op":"set-prop","id":1,"property":"max-height","value":60},
                  {"op":"create-node","id":2,"kind":"box"},
                  {"op":"set-prop","id":2,"property":"width","value":120},
                  {"op":"set-prop","id":2,"property":"height","value":80},
                  {"op":"insert-child","parent":1,"child":2,"index":0}\(decoration)
                ]}
                """)
                let host = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1).fixedSize())
                host.sizingOptions = []
                let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 200, height: 100),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.orderFrontRegardless()
                defer { window.orderOut(nil); window.contentView = nil }
                for _ in 0..<20 {
                    host.layoutSubtreeIfNeeded()
                    window.display()
                    try await Task.sleep(for: .milliseconds(10))
                }
                let frame = try #require(frames[1])
                #expect(abs(frame.width - 100) < 1, "\(kind), decorated=\(decorated)")
                #expect(abs(frame.height - 60) < 1, "\(kind), decorated=\(decorated)")
            }
        }
    }

    @Test("Empty and populated fragments occupy their children's flow slots", arguments: [false, true])
    func fragmentFlow(_ populated: Bool) async throws {
        _ = NSApplication.shared
        let backend = LUIAppleBackend()
        backend.frameReportingEnabled = true
        var frames: [Int: CGRect] = [:]
        backend.onFramesReport = { frames = $0 }
        var ops: [[String: Any]] = [
            ["op": "create-node", "id": 1, "kind": "row"],
            ["op": "set-prop", "id": 1, "property": "gap", "value": 4],
            ["op": "set-prop", "id": 1, "property": "cross", "value": "start"],
            ["op": "create-node", "id": 3, "kind": "box"],
            ["op": "set-prop", "id": 3, "property": "display", "value": "contents"]
        ]
        for id in [2, 4] + (populated ? [5, 6] : []) {
            ops += [
                ["op": "create-node", "id": id, "kind": "box"],
                ["op": "set-prop", "id": id, "property": "width", "value": 10],
                ["op": "set-prop", "id": id, "property": "height", "value": 10]
            ]
        }
        for (index, id) in [2, 3, 4].enumerated() {
            ops.append(["op": "insert-child", "parent": 1, "child": id, "index": index])
        }
        if populated {
            for (index, id) in [5, 6].enumerated() {
                ops.append(["op": "insert-child", "parent": 3, "child": id, "index": index])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["generation": 1, "ops": ops])
        try backend.apply(json: String(decoding: data, as: UTF8.self))
        let host = NSHostingView(rootView: LUISwiftUIRoot(backend: backend, rootID: 1).fixedSize())
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            window.display()
            try await Task.sleep(for: .milliseconds(10))
        }
        let first = try #require(frames[2])
        let last = try #require(frames[4])
        #expect(abs(last.minX - first.minX - (populated ? 42 : 14)) < 1)
        #expect(abs(last.minY - first.minY) < 1)
        if populated {
            #expect(abs(try #require(frames[5]).minX - first.minX - 14) < 1)
            #expect(abs(try #require(frames[6]).minX - first.minX - 28) < 1)
        }
        // Changing only the fragment's children must refresh its native parent.
        var changes: [[String: Any]] = []
        if populated {
            for id in [5, 6] {
                changes.append(["op": "detach-subtree", "id": id])
            }
        } else {
            for (index, id) in [5, 6].enumerated() {
                changes += [
                    ["op": "create-node", "id": id, "kind": "box"],
                    ["op": "set-prop", "id": id, "property": "width", "value": 10],
                    ["op": "set-prop", "id": id, "property": "height", "value": 10],
                    ["op": "insert-child", "parent": 3, "child": id, "index": index]
                ]
            }
        }
        let update = try JSONSerialization.data(withJSONObject: ["generation": 2, "ops": changes])
        try backend.apply(json: String(decoding: update, as: UTF8.self))
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            window.display()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(abs(try #require(frames[4]).minX - #require(frames[2]).minX - (populated ? 14 : 42)) < 1)

    }
}
#endif
