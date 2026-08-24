import SwiftUI
import Testing
#if os(macOS)
import AppKit
#endif
@testable import LUIAppleBackend

private struct CapturedAppleEvent: Equatable, Sendable {
    let kind: Int32
    let node: Int32
    let text: String
}

nonisolated(unsafe) private var capturedAppleEvent: CapturedAppleEvent?

private let captureAppleEvent: LUIAppleEventCallback = { kind, node, text in
    capturedAppleEvent = CapturedAppleEvent(
        kind: kind,
        node: node,
        text: text.map(String.init(cString:)) ?? ""
    )
}

@MainActor
@Suite("LUI SwiftUI backend", .serialized)
struct LUISwiftUIBackendTests {
#if os(macOS)
    @Test("macOS secondary activation dispatches hold exactly once when enabled")
    func secondaryActivationDispatchesHold() {
        let capture = LUISecondaryHoldView()
        var count = 0
        capture.onHold = { count += 1 }

        capture.isHoldEnabled = false
        capture.handleSecondaryActivation()
        #expect(count == 0)

        capture.isHoldEnabled = true
        capture.handleSecondaryActivation()
        #expect(count == 1)
    }
#endif

    @Test("builds one retained observable tree for SwiftUI")
    func buildsRetainedTree() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)

        let row = try #require(backend.model(id: 1))
        let label = try #require(backend.model(id: 2))
        let button = try #require(backend.model(id: 3))

        #expect(backend.rootIDs == [1])
        #expect(row.kind == .row)
        #expect(row.children == [2, 3])
        #expect(row.property(.gap) == .int(12))
        #expect(label.property(.text) == .string("Hello from LG"))
        #expect(button.property(.text) == .string("Continue"))
        #expect(button.property(.enabled) == .bool(true))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
    }

    @Test("a property patch invalidates only its retained SwiftUI node")
    func propertyPatchIsLocal() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let row = try #require(backend.model(id: 1))
        let label = try #require(backend.model(id: 2))
        let button = try #require(backend.model(id: 3))
        let rowRevision = row.revision
        let labelRevision = label.revision
        let buttonRevision = button.revision

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"text","value":"Updated"}
        ]}
        """)

        #expect(backend.model(id: 1) === row)
        #expect(backend.model(id: 2) === label)
        #expect(backend.model(id: 3) === button)
        #expect(row.revision == rowRevision)
        #expect(label.revision == labelRevision + 1)
        #expect(button.revision == buttonRevision)
        #expect(label.property(.text) == .string("Updated"))
    }

    @Test("a keyed move changes only the parent child projection")
    func keyedMoveIsLocal() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let row = try #require(backend.model(id: 1))
        let label = try #require(backend.model(id: 2))
        let button = try #require(backend.model(id: 3))
        let rowRevision = row.revision
        let labelRevision = label.revision
        let buttonRevision = button.revision

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"move-child","parent":1,"child":3,"index":0}
        ]}
        """)

        #expect(row.children == [3, 2])
        #expect(row.revision == rowRevision + 1)
        #expect(label.revision == labelRevision)
        #expect(button.revision == buttonRevision)
        #expect(backend.model(id: 2) === label)
        #expect(backend.model(id: 3) === button)
    }

    @Test("rejects invalid batches before observable models change")
    func rejectsInvalidBatchAtomically() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let row = try #require(backend.model(id: 1))
        let children = row.children
        let revision = row.revision

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"create-node","id":4,"kind":"text"},
              {"op":"insert-child","parent":99,"child":4,"index":0}
            ]}
            """)
        }

        #expect(backend.generation == 1)
        #expect(backend.model(id: 4) == nil)
        #expect(row.children == children)
        #expect(row.revision == revision)
    }

    @Test("SwiftUI controls return typed events without owning app state")
    func returnsSemanticEvents() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"button"},
          {"op":"create-node","id":2,"kind":"text-field"},
          {"op":"create-node","id":3,"kind":"switch"},
          {"op":"set-prop","id":1,"property":"text","value":"Continue"},
          {"op":"set-prop","id":1,"property":"enabled","value":true},
          {"op":"set-prop","id":1,"property":"hold-enabled","value":true},
          {"op":"set-prop","id":3,"property":"checked","value":false}
        ]}
        """)

        try backend.performPress(node: 1)
        try backend.performHold(node: 1)
        try backend.performTextChange(node: 2, text: "Draft")
        try backend.performSubmit(node: 2)
        try backend.performToggle(node: 3, checked: true)

        #expect(events == [
            .press(node: 1),
            .hold(node: 1),
            .textChanged(node: 2, text: "Draft"),
            .submit(node: 2),
            .toggleChanged(node: 3, checked: true),
        ])
        #expect(backend.model(id: 2)?.property(.text) == nil)
        #expect(backend.model(id: 3)?.property(.checked) == .bool(false))
    }

    @Test("maps every direct text-entry kind to retained native state")
    func mapsDirectTextEntryKinds() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"text-field"},
          {"op":"create-node","id":3,"kind":"input"},
          {"op":"create-node","id":4,"kind":"search-field"},
          {"op":"create-node","id":5,"kind":"textarea"},
          {"op":"set-prop","id":2,"property":"text","value":"Draft"},
          {"op":"set-prop","id":3,"property":"placeholder","value":"Email"},
          {"op":"set-prop","id":4,"property":"autofocus","value":true},
          {"op":"set-prop","id":5,"property":"submit-on-enter","value":true},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":1,"child":4,"index":2},
          {"op":"insert-child","parent":1,"child":5,"index":3}
        ]}
        """)

        let textField = try #require(backend.model(id: 2))
        #expect(textField.kind == .textField)
        #expect(backend.model(id: 3)?.kind == .input)
        #expect(backend.model(id: 4)?.kind == .searchField)
        #expect(backend.model(id: 5)?.kind == .textarea)
        #expect(textField.text == "Draft")
        #expect(backend.model(id: 4)?.property(.autofocus) == .bool(true))
        #expect(backend.model(id: 5)?.property(.submitOnEnter) == .bool(true))

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"text","value":"Updated"}
        ]}
        """)
        #expect(backend.model(id: 2) === textField)
        #expect(textField.text == "Updated")
    }

    @Test("maps the complete Vercel Native Button contract to one retained model")
    func mapsVercelNativeButton() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"button"},
          {"op":"set-prop","id":1,"property":"text","value":"Download"},
          {"op":"set-prop","id":1,"property":"variant","value":"primary"},
          {"op":"set-prop","id":1,"property":"size","value":"lg"},
          {"op":"set-prop","id":1,"property":"icon","value":"download"},
          {"op":"set-prop","id":1,"property":"icon-placement","value":"trailing"},
          {"op":"set-prop","id":1,"property":"selected","value":true},
          {"op":"set-prop","id":1,"property":"autofocus","value":true},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Download report"},
          {"op":"set-prop","id":1,"property":"hold-enabled","value":true}
        ]}
        """)

        let button = try #require(backend.model(id: 1))
        let revision = button.revision
        #expect(button.property(.variant) == .string("primary"))
        #expect(button.property(.size) == .string("lg"))
        #expect(button.property(.icon) == .string("download"))
        #expect(button.property(.iconPlacement) == .string("trailing"))
        #expect(button.property(.selected) == .bool(true))
        #expect(button.property(.autofocus) == .bool(true))
        #expect(button.property(.holdEnabled) == .bool(true))
        #expect(button.accessibilityLabel(in: backend) == "Download report")
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"text","value":"Export"},
          {"op":"set-prop","id":1,"property":"autofocus","value":false}
        ]}
        """)
        #expect(backend.model(id: 1) === button)
        #expect(button.revision == revision + 1)
        #expect(button.text == "Export")

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"variant","value":"link"}
            ]}
            """)
        }
        #expect(backend.generation == 2)
    }

    @Test("rejects an unnamed icon-only Button")
    func rejectsUnnamedIconButton() {
        let backend = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"button"},
              {"op":"set-prop","id":1,"property":"size","value":"icon"},
              {"op":"set-prop","id":1,"property":"icon","value":"plus"}
            ]}
            """)
        }
        #expect(backend.generation == 0)
    }

    @Test("maps ToggleButton as a distinct retained native control")
    func mapsToggleButton() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"toggle-button"},
          {"op":"set-prop","id":1,"property":"text","value":"Bold"},
          {"op":"set-prop","id":1,"property":"variant","value":"outline"},
          {"op":"set-prop","id":1,"property":"size","value":"sm"},
          {"op":"set-prop","id":1,"property":"icon","value":"edit"},
          {"op":"set-prop","id":1,"property":"selected","value":false},
          {"op":"set-prop","id":1,"property":"hold-enabled","value":true}
        ]}
        """)

        let toggle = try #require(backend.model(id: 1))
        let revision = toggle.revision
        #expect(toggle.kind == .toggleButton)
        #expect(toggle.property(.selected) == .bool(false))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performToggle(node: 1, checked: true)
        try backend.performHold(node: 1)
        #expect(events == [
            .toggleChanged(node: 1, checked: true),
            .hold(node: 1),
        ])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"selected","value":true}
        ]}
        """)
        #expect(backend.model(id: 1) === toggle)
        #expect(toggle.revision == revision + 1)
        #expect(toggle.isSelected)
    }

    @Test("maps direct text-bearing checkbox and switch without replacing models")
    func mapsDirectToggleControls() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"checkbox"},
          {"op":"create-node","id":2,"kind":"switch"},
          {"op":"set-prop","id":1,"property":"text","value":"Select all"},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Select every item"},
          {"op":"set-prop","id":1,"property":"checked","value":false},
          {"op":"set-prop","id":2,"property":"text","value":"Notifications"},
          {"op":"set-prop","id":2,"property":"checked","value":false}
        ]}
        """)

        let checkbox = try #require(backend.model(id: 1))
        let toggle = try #require(backend.model(id: 2))
        let checkboxRevision = checkbox.revision
        let toggleRevision = toggle.revision
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
        _ = LUISwiftUIRoot(backend: backend, rootID: 2)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"text","value":"All items"},
          {"op":"set-prop","id":2,"property":"checked","value":true}
        ]}
        """)

        #expect(backend.model(id: 1) === checkbox)
        #expect(backend.model(id: 2) === toggle)
        #expect(checkbox.property(.text) == .string("All items"))
        #expect(toggle.property(.checked) == .bool(true))
        #expect(checkbox.revision == checkboxRevision + 1)
        #expect(toggle.revision == toggleRevision + 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"indeterminate","value":true}
            ]}
            """)
        }
        #expect(backend.generation == 2)
    }

    @Test("maps Progress to a clamped retained SwiftUI value")
    func mapsProgress() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"progress"},
          {"op":"set-prop","id":1,"property":"value","value":0.3}
        ]}
        """)

        let progress = try #require(backend.model(id: 1))
        let progressRevision = progress.revision
        #expect(progress.progressFraction == 0.3)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"value","value":1.2}
        ]}
        """)
        #expect(backend.model(id: 1) === progress)
        #expect(progress.progressFraction == 1)
        #expect(progress.revision == progressRevision + 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"value","value":1}
            ]}
            """)
        }
        #expect(backend.generation == 2)
        #expect(progress.progressFraction == 1)
    }

    @Test("maps Spinner size rungs to an indeterminate SwiftUI ProgressView")
    func mapsSpinner() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"spinner"},
          {"op":"set-prop","id":1,"property":"size","value":"sm"},
          {"op":"set-prop","id":1,"property":"foreground","value":"primary"}
        ]}
        """)

        let spinner = try #require(backend.model(id: 1))
        let revision = spinner.revision
        #expect(spinner.kind == .spinner)
        #expect(spinner.spinnerExtent == 16)
        #expect(spinner.property(.foreground) == .string("primary"))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"size","value":"lg"}
        ]}
        """)
        #expect(backend.model(id: 1) === spinner)
        #expect(spinner.spinnerExtent == 24)
        #expect(spinner.revision == revision + 1)

        try backend.apply(json: """
        {"generation":3,"ops":[
          {"op":"set-prop","id":1,"property":"width","value":32},
          {"op":"set-prop","id":1,"property":"height","value":28}
        ]}
        """)
        #expect(spinner.spinnerWidth == 32)
        #expect(spinner.spinnerHeight == 28)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":4,"ops":[
              {"op":"set-prop","id":1,"property":"size","value":"heading"}
            ]}
            """)
        }
        #expect(backend.generation == 3)
        #expect(spinner.spinnerExtent == 24)
    }

    @Test("maps Icon names to SF Symbols without replacing its model")
    func mapsIcon() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"icon"},
          {"op":"set-prop","id":1,"property":"name","value":"search"},
          {"op":"set-prop","id":1,"property":"size","value":"sm"},
          {"op":"set-prop","id":1,"property":"foreground","value":"primary"}
        ]}
        """)

        let icon = try #require(backend.model(id: 1))
        let revision = icon.revision
        #expect(icon.kind == .icon)
        #expect(icon.iconSystemName == "magnifyingglass")
        #expect(icon.iconExtent == 16)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"name","value":"trash"}
        ]}
        """)
        #expect(backend.model(id: 1) === icon)
        #expect(icon.iconSystemName == "trash")
        #expect(icon.revision == revision + 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"name","value":"unknown"}
            ]}
            """)
        }
        #expect(backend.generation == 2)
        #expect(icon.iconSystemName == "trash")
    }

    @Test("resolves application icons through the immutable SwiftUI registry")
    func mapsApplicationIcon() throws {
        let backend = LUIAppleBackend(appIcons: [
            "wave-pulse": .systemName("waveform.path"),
            "brand": .assetName("BrandMark"),
        ])
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"icon"},
          {"op":"set-prop","id":1,"property":"name","value":"app:wave-pulse"}
        ]}
        """)

        #expect(backend.iconSource(for: "app:wave-pulse") == .systemName("waveform.path"))
        #expect(backend.iconSource(for: "app:brand") == .assetName("BrandMark"))
        #expect(
            backend.iconSource(for: "app:missing") ==
                .systemName("questionmark.square.dashed")
        )
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
    }

    @Test("maps Separator orientation without replacing its SwiftUI model")
    func mapsSeparatorOrientation() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"divider"},
          {"op":"set-prop","id":1,"property":"orientation","value":"horizontal"}
        ]}
        """)

        let separator = try #require(backend.model(id: 1))
        let revision = separator.revision
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"orientation","value":"vertical"}
        ]}
        """)
        #expect(backend.model(id: 1) === separator)
        #expect(separator.revision == revision + 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"orientation","value":"diagonal"}
            ]}
            """)
        }
        #expect(backend.generation == 2)
        #expect(separator.revision == revision + 1)
    }

    @Test("maps typed Surface size constraints without replacing its SwiftUI model")
    func mapsSurfaceSizeConstraints() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"box"},
          {"op":"set-prop","id":1,"property":"width","value":120},
          {"op":"set-prop","id":1,"property":"height","value":24},
          {"op":"set-prop","id":1,"property":"min-width","value":80},
          {"op":"set-prop","id":1,"property":"max-width","value":160},
          {"op":"set-prop","id":1,"property":"min-height","value":16},
          {"op":"set-prop","id":1,"property":"max-height","value":32}
        ]}
        """)

        let box = try #require(backend.model(id: 1))
        let revision = box.revision
        #expect(box.surfaceWidth == 120)
        #expect(box.surfaceHeight == 24)
        #expect(box.surfaceMinWidth == 80)
        #expect(box.surfaceMaxWidth == 160)
        #expect(box.surfaceMinHeight == 16)
        #expect(box.surfaceMaxHeight == 32)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"width","value":140}
        ]}
        """)
        #expect(backend.model(id: 1) === box)
        #expect(box.surfaceWidth == 140)
        #expect(box.revision == revision + 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"min-width","value":170},
              {"op":"set-prop","id":1,"property":"max-width","value":160}
            ]}
            """)
        }
        #expect(backend.generation == 2)
        #expect(box.surfaceMinWidth == 80)
        #expect(box.revision == revision + 1)
    }

    @Test("maps the Vercel Native layout vocabulary to SwiftUI primitives")
    func mapsVercelLayoutPrimitives() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"row"},
          {"op":"create-node","id":3,"kind":"grid"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"set-prop","id":1,"property":"main","value":"center"},
          {"op":"set-prop","id":1,"property":"cross","value":"stretch"},
          {"op":"set-prop","id":2,"property":"main","value":"space_between"},
          {"op":"set-prop","id":2,"property":"cross","value":"end"},
          {"op":"set-prop","id":3,"property":"columns","value":2},
          {"op":"set-prop","id":3,"property":"gap","value":6},
          {"op":"set-prop","id":4,"property":"grow","value":1.0},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":2,"child":4,"index":0}
        ]}
        """)

        let column = try #require(backend.model(id: 1))
        let row = try #require(backend.model(id: 2))
        let grid = try #require(backend.model(id: 3))
        let text = try #require(backend.model(id: 4))
        #expect(column.property(.main) == .string("center"))
        #expect(column.property(.cross) == .string("stretch"))
        #expect(row.property(.main) == .string("space_between"))
        #expect(row.property(.cross) == .string("end"))
        #expect(grid.property(.columns) == .int(2))
        #expect(text.property(.grow) == .double(1.0))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"set-prop","id":2,"property":"main","value":"between"}
            ]}
            """)
        }
        #expect(backend.generation == 1)
    }

    @Test("maps Vercel Native overlay surfaces to retained SwiftUI nodes")
    func mapsOverlaySurfaces() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"stack"},
          {"op":"create-node","id":2,"kind":"panel"},
          {"op":"create-node","id":3,"kind":"card"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":3,"child":4,"index":0}
        ]}
        """)

        #expect(backend.model(id: 1)?.kind == .stack)
        #expect(backend.model(id: 2)?.kind == .panel)
        #expect(backend.model(id: 3)?.kind == .card)
        #expect(backend.model(id: 1)?.children == [2, 3])
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"set-prop","id":3,"property":"gap","value":8}
            ]}
            """)
        }
        #expect(backend.generation == 1)
        #expect(backend.model(id: 3)?.property(.gap) == nil)
    }

    @Test("maps List flow and multi-child Scroll to retained SwiftUI containers")
    func mapsListAndScrollContainers() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"row"},
          {"op":"create-node","id":2,"kind":"list"},
          {"op":"create-node","id":3,"kind":"scroll"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"create-node","id":6,"kind":"text"},
          {"op":"set-prop","id":2,"property":"gap","value":8},
          {"op":"set-prop","id":2,"property":"main","value":"end"},
          {"op":"set-prop","id":2,"property":"cross","value":"stretch"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":2,"child":4,"index":0},
          {"op":"insert-child","parent":3,"child":5,"index":0},
          {"op":"insert-child","parent":3,"child":6,"index":1}
        ]}
        """)

        #expect(backend.model(id: 2)?.kind == .list)
        #expect(backend.model(id: 2)?.property(.gap) == .int(8))
        #expect(backend.model(id: 2)?.property(.main) == .string("end"))
        #expect(backend.model(id: 3)?.children == [5, 6])
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
    }

    @Test("maps the daily value-control batch to retained SwiftUI controls")
    func mapsDailyValueControls() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"toggle"},
          {"op":"create-node","id":3,"kind":"radio-group"},
          {"op":"create-node","id":4,"kind":"radio"},
          {"op":"create-node","id":5,"kind":"slider"},
          {"op":"set-prop","id":2,"property":"text","value":"Bold"},
          {"op":"set-prop","id":2,"property":"checked","value":false},
          {"op":"set-prop","id":3,"property":"accessibility-label","value":"Density"},
          {"op":"set-prop","id":4,"property":"text","value":"Comfortable"},
          {"op":"set-prop","id":4,"property":"checked","value":false},
          {"op":"set-prop","id":4,"property":"change-enabled","value":true},
          {"op":"set-prop","id":5,"property":"value","value":0.25},
          {"op":"set-prop","id":5,"property":"accessibility-label","value":"Volume"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":3,"child":4,"index":0},
          {"op":"insert-child","parent":1,"child":5,"index":2}
        ]}
        """)

        let toggle = try #require(backend.model(id: 2))
        let radio = try #require(backend.model(id: 4))
        let slider = try #require(backend.model(id: 5))
        #expect(toggle.kind == .toggle)
        #expect(radio.kind == .radio)
        #expect(slider.kind == .slider)
        #expect(slider.property(.progressValue) == .double(0.25))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performToggle(node: 2, checked: true)
        try backend.performChange(node: 4)
        try backend.performValueChange(node: 5, value: 0.75)
        #expect(events == [
            .toggleChanged(node: 2, checked: true),
            .change(node: 4),
            .valueChanged(node: 5, value: 0.75),
        ])

        let sliderRevision = slider.revision
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"checked","value":true},
          {"op":"set-prop","id":4,"property":"checked","value":true},
          {"op":"set-prop","id":5,"property":"value","value":0.75}
        ]}
        """)
        #expect(backend.model(id: 2) === toggle)
        #expect(backend.model(id: 4) === radio)
        #expect(backend.model(id: 5) === slider)
        #expect(slider.revision == sliderRevision + 1)
        try backend.performChange(node: 4)
        #expect(events.count == 3)

        let ungrouped = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try ungrouped.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"radio"},
              {"op":"set-prop","id":1,"property":"text","value":"Orphan"}
            ]}
            """)
        }
    }

    @Test("C ABI forwards SwiftUI backend events")
    func cABIForwardsEvent() {
        capturedAppleEvent = nil
        luiAppleReset()
        luiAppleSetEventCallback(captureAppleEvent)
        defer {
            luiAppleSetEventCallback(nil)
            luiAppleReset()
        }

        let accepted = """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"button"},
          {"op":"set-prop","id":1,"property":"text","value":"Continue"},
          {"op":"set-prop","id":1,"property":"enabled","value":true}
        ]}
        """.withCString(luiAppleApply)

        #expect(accepted == 1)
        #expect(luiApplePerformAction(1) == 1)
        #expect(capturedAppleEvent == CapturedAppleEvent(kind: 0, node: 1, text: ""))
    }

    private static let initialBatch = """
    {"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"row"},
      {"op":"create-node","id":2,"kind":"text"},
      {"op":"create-node","id":3,"kind":"button"},
      {"op":"set-prop","id":1,"property":"gap","value":12},
      {"op":"set-prop","id":2,"property":"text","value":"Hello from LG"},
      {"op":"set-prop","id":3,"property":"text","value":"Continue"},
      {"op":"set-prop","id":3,"property":"enabled","value":true},
      {"op":"insert-child","parent":1,"child":2,"index":0},
      {"op":"insert-child","parent":1,"child":3,"index":1}
    ]}
    """
}
