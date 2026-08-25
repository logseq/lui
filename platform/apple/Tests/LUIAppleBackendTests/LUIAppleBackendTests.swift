import SwiftUI
import Testing
import CoreGraphics
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
    private func image(width: Int = 64, height: Int = 64) throws -> CGImage {
        let bytes = Data(repeating: 0xff, count: width * height * 4)
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        return try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ))
    }

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

    @Test("maps Tabs to a retained native strip with controlled Button triggers")
    func mapsTabs() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"tabs"},
          {"op":"create-node","id":2,"kind":"button"},
          {"op":"create-node","id":3,"kind":"button"},
          {"op":"create-node","id":4,"kind":"toggle-button"},
          {"op":"set-prop","id":1,"property":"gap","value":4},
          {"op":"set-prop","id":2,"property":"text","value":"Overview"},
          {"op":"set-prop","id":2,"property":"selected","value":true},
          {"op":"set-prop","id":3,"property":"text","value":"Activity"},
          {"op":"set-prop","id":3,"property":"selected","value":false},
          {"op":"set-prop","id":4,"property":"text","value":"Pinned"},
          {"op":"set-prop","id":4,"property":"selected","value":false},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":1,"child":4,"index":2}
        ]}
        """)

        let tabs = try #require(backend.model(id: 1))
        let overview = try #require(backend.model(id: 2))
        let activity = try #require(backend.model(id: 3))
        let toggle = try #require(backend.model(id: 4))
        let tabsRevision = tabs.revision
        let overviewRevision = overview.revision
        let toggleRevision = toggle.revision
        #expect(tabs.kind.rawValue == "tabs")
        #expect(tabs.children == [2, 3, 4])
        #expect(tabs.property(.gap) == .int(4))
        #expect(overview.isSelected)
        #expect(!activity.isSelected)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performPress(node: 3)
        try backend.performToggle(node: 4, checked: true)
        #expect(events == [
            .press(node: 3),
            .toggleChanged(node: 4, checked: true),
        ])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"selected","value":false},
          {"op":"set-prop","id":3,"property":"selected","value":true}
        ]}
        """)
        #expect(backend.model(id: 1) === tabs)
        #expect(backend.model(id: 2) === overview)
        #expect(backend.model(id: 3) === activity)
        #expect(backend.model(id: 4) === toggle)
        #expect(tabs.revision == tabsRevision)
        #expect(overview.revision == overviewRevision + 1)
        #expect(toggle.revision == toggleRevision)
        #expect(activity.isSelected)
    }

    @Test("maps ButtonGroup and ToggleGroup without owning child selection")
    func mapsActionGroups() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"button-group"},
          {"op":"create-node","id":3,"kind":"toggle-group"},
          {"op":"create-node","id":4,"kind":"button"},
          {"op":"create-node","id":5,"kind":"toggle-button"},
          {"op":"create-node","id":6,"kind":"toggle-button"},
          {"op":"set-prop","id":2,"property":"gap","value":4},
          {"op":"set-prop","id":3,"property":"gap","value":8},
          {"op":"set-prop","id":4,"property":"text","value":"Save"},
          {"op":"set-prop","id":5,"property":"text","value":"Pin"},
          {"op":"set-prop","id":5,"property":"selected","value":true},
          {"op":"set-prop","id":6,"property":"text","value":"Backend-owned"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":2,"child":4,"index":0},
          {"op":"insert-child","parent":2,"child":5,"index":1},
          {"op":"insert-child","parent":3,"child":6,"index":0}
        ]}
        """)

        let buttonGroup = try #require(backend.model(id: 2))
        let toggleGroup = try #require(backend.model(id: 3))
        let pin = try #require(backend.model(id: 5))
        let backendOwned = try #require(backend.model(id: 6))
        let pinRevision = pin.revision
        #expect(buttonGroup.kind == .buttonGroup)
        #expect(toggleGroup.kind == .toggleGroup)
        #expect(buttonGroup.children == [4, 5])
        #expect(toggleGroup.children == [6])
        #expect(pin.isSelected)
        #expect(backendOwned.property(.selected) == nil)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performPress(node: 4)
        try backend.performToggle(node: 5, checked: false)
        #expect(events == [.press(node: 4), .toggleChanged(node: 5, checked: false)])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":5,"property":"selected","value":false},
          {"op":"remove-child","parent":3,"child":6},
          {"op":"insert-child","parent":2,"child":6,"index":2}
        ]}
        """)
        #expect(backend.model(id: 2) === buttonGroup)
        #expect(backend.model(id: 3) === toggleGroup)
        #expect(backend.model(id: 5) === pin)
        #expect(backend.model(id: 6) === backendOwned)
        #expect(pin.revision == pinRevision + 1)
        #expect(buttonGroup.children == [4, 5, 6])
        #expect(toggleGroup.children.isEmpty)
    }

    @Test("horizontal focus wraps and skips disabled direct controls")
    func horizontalFocusNavigation() {
        let enabled = [true, false, true, true]
        #expect(LUIHorizontalFocus.nextIndex(current: 0, key: .right, enabled: enabled) == 2)
        #expect(LUIHorizontalFocus.nextIndex(current: 2, key: .right, enabled: enabled) == 3)
        #expect(LUIHorizontalFocus.nextIndex(current: 3, key: .right, enabled: enabled) == 0)
        #expect(LUIHorizontalFocus.nextIndex(current: 0, key: .left, enabled: enabled) == 3)
        #expect(LUIHorizontalFocus.nextIndex(current: 3, key: .home, enabled: enabled) == 0)
        #expect(LUIHorizontalFocus.nextIndex(current: 0, key: .end, enabled: enabled) == 3)
        #expect(LUIHorizontalFocus.nextIndex(current: nil, key: .right, enabled: enabled) == 0)
        #expect(LUIHorizontalFocus.nextIndex(current: 0, key: .right, enabled: [false, false]) == nil)
    }

    @Test("maps Breadcrumb and Pagination as retained native compositions")
    func mapsNavigationContainers() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"breadcrumb"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"create-node","id":4,"kind":"icon"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"create-node","id":6,"kind":"pagination"},
          {"op":"create-node","id":7,"kind":"button"},
          {"op":"create-node","id":8,"kind":"button"},
          {"op":"set-prop","id":2,"property":"accessibility-label","value":"Component path"},
          {"op":"set-prop","id":3,"property":"text","value":"Home"},
          {"op":"set-prop","id":3,"property":"press-enabled","value":true},
          {"op":"set-prop","id":4,"property":"name","value":"chevron-right"},
          {"op":"set-prop","id":5,"property":"text","value":"Components"},
          {"op":"set-prop","id":6,"property":"accessibility-label","value":"Gallery pages"},
          {"op":"set-prop","id":7,"property":"text","value":"1"},
          {"op":"set-prop","id":7,"property":"selected","value":true},
          {"op":"set-prop","id":8,"property":"text","value":"2"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":6,"index":1},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"insert-child","parent":2,"child":5,"index":2},
          {"op":"insert-child","parent":6,"child":7,"index":0},
          {"op":"insert-child","parent":6,"child":8,"index":1}
        ]}
        """)

        let breadcrumb = try #require(backend.model(id: 2))
        let home = try #require(backend.model(id: 3))
        let pagination = try #require(backend.model(id: 6))
        let firstPage = try #require(backend.model(id: 7))
        let breadcrumbRevision = breadcrumb.revision
        #expect(breadcrumb.kind == .breadcrumb)
        #expect(pagination.kind == .pagination)
        #expect(breadcrumb.children == [3, 4, 5])
        #expect(pagination.children == [7, 8])
        #expect(home.supportsPress)
        #expect(LUIHorizontalGroupDefaults.gap(for: .breadcrumb) == 4)
        #expect(LUIHorizontalGroupDefaults.gap(for: .pagination) == 2)
        #expect(LUIHorizontalFocus.isEligible(parent: .pagination, child: .button))
        #expect(!LUIHorizontalFocus.isEligible(parent: .breadcrumb, child: .text))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performPress(node: 3)
        try backend.performPress(node: 8)
        #expect(events == [.press(node: 3), .press(node: 8)])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":7,"property":"selected","value":false},
          {"op":"set-prop","id":8,"property":"selected","value":true}
        ]}
        """)
        #expect(backend.model(id: 2) === breadcrumb)
        #expect(backend.model(id: 3) === home)
        #expect(backend.model(id: 6) === pagination)
        #expect(backend.model(id: 7) === firstPage)
        #expect(breadcrumb.revision == breadcrumbRevision)
        #expect(!firstPage.isSelected)
    }

    @Test("rejects text on Tabs instead of silently ignoring it")
    func rejectsTextOnTabs() {
        let backend = LUIAppleBackend()
        #expect(throws: LUIBackendError.invalidBatch("unsupported property value")) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"tabs"},
              {"op":"set-prop","id":1,"property":"text","value":"Overview"}
            ]}
            """)
        }
        #expect(backend.generation == 0)
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

    @Test("maps picker primitives to retained SwiftUI state and typed events")
    func mapsPickerPrimitives() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"stack"},
          {"op":"create-node","id":2,"kind":"select"},
          {"op":"create-node","id":3,"kind":"combobox"},
          {"op":"create-node","id":4,"kind":"dropdown-menu"},
          {"op":"create-node","id":5,"kind":"menu-item"},
          {"op":"set-prop","id":2,"property":"text","value":"Production"},
          {"op":"set-prop","id":2,"property":"press-enabled","value":true},
          {"op":"set-prop","id":3,"property":"placeholder","value":"Search"},
          {"op":"set-prop","id":3,"property":"submit-enabled","value":true},
          {"op":"set-prop","id":4,"property":"anchor","value":"below"},
          {"op":"set-prop","id":4,"property":"anchor-alignment","value":"stretch"},
          {"op":"set-prop","id":4,"property":"anchor-offset","value":6.0},
          {"op":"set-prop","id":5,"property":"text","value":"Production"},
          {"op":"set-prop","id":5,"property":"selected","value":true},
          {"op":"set-prop","id":5,"property":"press-enabled","value":true},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":4,"index":1},
          {"op":"insert-child","parent":4,"child":5,"index":0}
        ]}
        """)

        let select = try #require(backend.model(id: 2))
        let menu = try #require(backend.model(id: 4))
        #expect(select.kind == .select)
        #expect(backend.model(id: 3)?.kind == .combobox)
        #expect(menu.kind == .dropdownMenu)
        #expect(backend.model(id: 5)?.kind == .menuItem)
        #expect(menu.children == [5])
        #expect(menu.property(.anchor) == .string("below"))
        #expect(menu.property(.anchorAlignment) == .string("stretch"))
        #expect(menu.property(.anchorOffset) == .double(6))
        #expect(backend.model(id: 5)?.isSelected == true)

        try backend.performAction(node: 2)
        try backend.performTextChange(node: 3, text: "sol")
        try backend.performSubmit(node: 3)
        try backend.performAction(node: 5)
        try backend.performDismiss(node: 4)
        #expect(events == [
            .press(node: 2),
            .textChanged(node: 3, text: "sol"),
            .submit(node: 3),
            .press(node: 5),
            .dismiss(node: 4),
        ])
    }

    @Test("maps ListItem text and custom content to one retained native row")
    func mapsListItem() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"list"},
          {"op":"create-node","id":2,"kind":"list-item"},
          {"op":"create-node","id":3,"kind":"list-item"},
          {"op":"create-node","id":4,"kind":"row"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"Quarterly report.md"},
          {"op":"set-prop","id":2,"property":"icon","value":"file-text"},
          {"op":"set-prop","id":2,"property":"selected","value":true},
          {"op":"set-prop","id":2,"property":"press-enabled","value":true},
          {"op":"set-prop","id":2,"property":"double-press-enabled","value":true},
          {"op":"set-prop","id":2,"property":"submit-enabled","value":true},
          {"op":"set-prop","id":5,"property":"text","value":"Custom child row"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":3,"child":4,"index":0},
          {"op":"insert-child","parent":4,"child":5,"index":0}
        ]}
        """)

        let item = try #require(backend.model(id: 2))
        let revision = item.revision
        #expect(item.kind == .listItem)
        #expect(item.property(.icon) == .string("file-text"))
        #expect(item.isSelected)
        #expect(backend.model(id: 3)?.children == [4])

        try backend.performPress(node: 2)
        try backend.performDoublePress(node: 2)
        try backend.performSubmit(node: 2)
        #expect(events == [
            .press(node: 2),
            .doublePress(node: 2),
            .submit(node: 2),
        ])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"selected","value":false}
        ]}
        """)
        #expect(backend.model(id: 2) === item)
        #expect(item.revision == revision + 1)
    }

    @Test("maps Table structure and patches only the retained row and cell")
    func mapsTable() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"table"},
          {"op":"create-node","id":2,"kind":"table-row"},
          {"op":"create-node","id":3,"kind":"table-row"},
          {"op":"create-node","id":4,"kind":"table-cell"},
          {"op":"create-node","id":5,"kind":"table-cell"},
          {"op":"create-node","id":6,"kind":"table-cell"},
          {"op":"create-node","id":7,"kind":"table-cell"},
          {"op":"set-prop","id":2,"property":"gap","value":4},
          {"op":"set-prop","id":3,"property":"selected","value":false},
          {"op":"set-prop","id":4,"property":"text","value":"Invoice"},
          {"op":"set-prop","id":4,"property":"size","value":"sm"},
          {"op":"set-prop","id":5,"property":"text","value":"Amount"},
          {"op":"set-prop","id":5,"property":"text-alignment","value":"end"},
          {"op":"set-prop","id":6,"property":"text","value":"INV-002"},
          {"op":"set-prop","id":6,"property":"press-enabled","value":true},
          {"op":"set-prop","id":7,"property":"text","value":"$150.00"},
          {"op":"set-prop","id":7,"property":"text-alignment","value":"end"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":2,"child":4,"index":0},
          {"op":"insert-child","parent":2,"child":5,"index":1},
          {"op":"insert-child","parent":3,"child":6,"index":0},
          {"op":"insert-child","parent":3,"child":7,"index":1}
        ]}
        """)

        let table = try #require(backend.model(id: 1))
        let row = try #require(backend.model(id: 3))
        let cell = try #require(backend.model(id: 7))
        let tableRevision = table.revision
        let rowRevision = row.revision
        let cellRevision = cell.revision
        #expect(table.kind == .table)
        #expect(backend.model(id: 2)?.kind == .tableRow)
        #expect(cell.kind == .tableCell)
        #expect(table.children == [2, 3])
        #expect(row.children == [6, 7])
        #expect(cell.property(.textAlignment) == .string("end"))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performPress(node: 6)
        #expect(events == [.press(node: 6)])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":3,"property":"selected","value":true},
          {"op":"set-prop","id":7,"property":"text","value":"$175.00"}
        ]}
        """)
        #expect(backend.model(id: 1) === table)
        #expect(backend.model(id: 3) === row)
        #expect(backend.model(id: 7) === cell)
        #expect(table.revision == tableRevision)
        #expect(row.revision == rowRevision + 1)
        #expect(cell.revision == cellRevision + 1)
        #expect(row.isSelected)
        #expect(cell.text == "$175.00")
    }

    @Test("rejects malformed Table nesting without committing a partial batch")
    func rejectsMalformedTableNesting() throws {
        let backend = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"table"},
              {"op":"create-node","id":2,"kind":"text"},
              {"op":"set-prop","id":2,"property":"text","value":"Invalid"},
              {"op":"insert-child","parent":1,"child":2,"index":0}
            ]}
            """)
        }
        #expect(backend.generation == 0)
        #expect(backend.rootIDs.isEmpty)
        #expect(backend.model(id: 1) == nil)
    }

    @Test("Resizable preserves dragged width until its source width changes")
    func mapsResizable() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"resizable"},
          {"op":"create-node","id":2,"kind":"panel"},
          {"op":"set-prop","id":1,"property":"width","value":240},
          {"op":"set-prop","id":1,"property":"min-width","value":180},
          {"op":"set-prop","id":1,"property":"max-width","value":480},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Resizable sidebar"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)

        let resizable = try #require(backend.model(id: 1))
        let child = try #require(backend.model(id: 2))
        let childRevision = child.revision
        #expect(resizable.kind == .resizable)
        #expect(resizable.surfaceWidth == 240)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        var width = LUIResizableWidthState(
            sourceWidth: 240,
            minimumWidth: 180,
            maximumWidth: 480
        )
        width.drag(by: 80, fallbackWidth: 240)
        #expect(width.width == 320)
        width.reconcile(sourceWidth: 240, minimumWidth: 180, maximumWidth: 480)
        #expect(width.width == 320)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"background","value":"secondary"}
        ]}
        """)
        #expect(backend.model(id: 1) === resizable)
        #expect(backend.model(id: 2) === child)
        #expect(child.revision == childRevision)
        width.reconcile(sourceWidth: 240, minimumWidth: 180, maximumWidth: 480)
        #expect(width.width == 320)

        try backend.apply(json: """
        {"generation":3,"ops":[
          {"op":"set-prop","id":1,"property":"width","value":260}
        ]}
        """)
        width.reconcile(sourceWidth: 260, minimumWidth: 180, maximumWidth: 480)
        #expect(width.width == 260)
        width.drag(by: -200, fallbackWidth: 260)
        #expect(width.width == 180)
    }

    @Test("rejects flow properties on Resizable atomically")
    func rejectsMalformedResizable() throws {
        let backend = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"resizable"},
              {"op":"set-prop","id":1,"property":"gap","value":8}
            ]}
            """)
        }
        #expect(backend.generation == 0)
        #expect(backend.rootIDs.isEmpty)
    }

    @Test("Split retains two panes and reconciles one controlled fraction")
    func mapsSplit() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"split"},
          {"op":"create-node","id":2,"kind":"panel"},
          {"op":"create-node","id":3,"kind":"panel"},
          {"op":"set-prop","id":1,"property":"value","value":0.35},
          {"op":"set-prop","id":1,"property":"gap","value":8},
          {"op":"set-prop","id":1,"property":"resize-duration","value":180},
          {"op":"set-prop","id":1,"property":"resize-easing","value":"standard"},
          {"op":"set-prop","id":1,"property":"resize-origin","value":0.1},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Workspace panes"},
          {"op":"set-prop","id":2,"property":"min-width","value":180},
          {"op":"set-prop","id":3,"property":"min-width","value":320},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        let split = try #require(backend.model(id: 1))
        let first = try #require(backend.model(id: 2))
        let second = try #require(backend.model(id: 3))
        #expect(split.kind == .split)
        #expect(split.children == [2, 3])
        #expect(split.property(.resizeDuration) == .int(180))
        #expect(split.property(.resizeEasing) == .string("standard"))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        #expect(LUISplitGeometry.effectiveFraction(
            value: 0,
            available: 792,
            firstMinimum: 180,
            secondMinimum: 320
        ) == 0.5)
        #expect(LUISplitGeometry.effectiveFraction(
            value: 0.9,
            available: 792,
            firstMinimum: 180,
            secondMinimum: 320
        ) == 1 - (320.0 / 792.0))
        #expect(LUISplitGeometry.effectiveFraction(
            value: 0.2,
            available: 800,
            firstMinimum: 500,
            secondMinimum: 500
        ) == 0.5)

        var state = LUISplitFractionState(sourceFraction: 0.35)
        state.applyUserFraction(0.42)
        state.reconcile(sourceFraction: 0.35)
        #expect(state.fraction == 0.42)
        state.reconcile(sourceFraction: 0.42)
        #expect(state.fraction == 0.42)
        state.reconcile(sourceFraction: 0.55)
        #expect(state.fraction == 0.55)

        try backend.performValueChange(node: 1, value: 0.42)
        #expect(events == [.valueChanged(node: 1, value: 0.42)])
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"value","value":0.42}
        ]}
        """)
        #expect(backend.model(id: 1) === split)
        #expect(backend.model(id: 2) === first)
        #expect(backend.model(id: 3) === second)
    }

    @Test("Split rejects malformed child counts and inert animation options")
    func rejectsMalformedSplit() throws {
        for operations in [
            """
            {"op":"create-node","id":1,"kind":"split"},
            {"op":"create-node","id":2,"kind":"panel"},
            {"op":"insert-child","parent":1,"child":2,"index":0}
            """,
            """
            {"op":"create-node","id":1,"kind":"split"},
            {"op":"create-node","id":2,"kind":"panel"},
            {"op":"create-node","id":3,"kind":"panel"},
            {"op":"create-node","id":4,"kind":"panel"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":3,"index":1},
            {"op":"insert-child","parent":1,"child":4,"index":2}
            """,
            """
            {"op":"create-node","id":1,"kind":"split"},
            {"op":"create-node","id":2,"kind":"panel"},
            {"op":"create-node","id":3,"kind":"panel"},
            {"op":"set-prop","id":1,"property":"resize-easing","value":"spring"},
            {"op":"insert-child","parent":1,"child":2,"index":0},
            {"op":"insert-child","parent":1,"child":3,"index":1}
            """,
        ] {
            let backend = LUIAppleBackend()
            #expect(throws: LUIBackendError.self) {
                try backend.apply(json: """
                {"generation":1,"ops":[\(operations)]}
                """)
            }
            #expect(backend.generation == 0)
            #expect(backend.rootIDs.isEmpty)
        }
    }

    @Test("maps Tree rows to one retained native focus set")
    func mapsTree() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"tree"},
          {"op":"create-node","id":2,"kind":"list-item"},
          {"op":"create-node","id":3,"kind":"list-item"},
          {"op":"create-node","id":4,"kind":"panel"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"set-prop","id":1,"property":"gap","value":2},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Project files"},
          {"op":"set-prop","id":2,"property":"text","value":"src"},
          {"op":"set-prop","id":2,"property":"role","value":"treeitem"},
          {"op":"set-prop","id":2,"property":"tree-level","value":1},
          {"op":"set-prop","id":2,"property":"expanded","value":true},
          {"op":"set-prop","id":2,"property":"selected","value":true},
          {"op":"set-prop","id":2,"property":"press-enabled","value":true},
          {"op":"set-prop","id":2,"property":"change-enabled","value":true},
          {"op":"set-prop","id":2,"property":"toggle-enabled","value":true},
          {"op":"set-prop","id":3,"property":"text","value":"main.cljc"},
          {"op":"set-prop","id":3,"property":"role","value":"treeitem"},
          {"op":"set-prop","id":3,"property":"tree-level","value":2},
          {"op":"set-prop","id":3,"property":"press-enabled","value":true},
          {"op":"set-prop","id":3,"property":"change-enabled","value":true},
          {"op":"set-prop","id":4,"property":"role","value":"treeitem"},
          {"op":"set-prop","id":4,"property":"tree-level","value":1},
          {"op":"set-prop","id":4,"property":"change-enabled","value":true},
          {"op":"set-prop","id":5,"property":"text","value":"README"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":1,"child":4,"index":2},
          {"op":"insert-child","parent":4,"child":5,"index":0}
        ]}
        """)

        let tree = try #require(backend.model(id: 1))
        let folder = try #require(backend.model(id: 2))
        let file = try #require(backend.model(id: 3))
        let treeRevision = tree.revision
        let folderRevision = folder.revision
        #expect(tree.kind == .tree)
        #expect(folder.property(.role) == .string("treeitem"))
        #expect(folder.property(.treeLevel) == .int(1))
        #expect(folder.property(.expanded) == .bool(true))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        #expect(try backend.performTreeKey(tree: 1, node: 2, key: .down) == 3)
        #expect(events == [.change(node: 3)])
        events.removeAll()
        #expect(try backend.performTreeKey(tree: 1, node: 3, key: .left) == 2)
        #expect(events == [.change(node: 2)])
        events.removeAll()
        #expect(try backend.performTreeKey(tree: 1, node: 2, key: .left) == 2)
        #expect(events == [.toggleChanged(node: 2, checked: false)])
        events.removeAll()
        #expect(try backend.performTreeKey(tree: 1, node: 3, key: .activate) == 3)
        #expect(events == [.press(node: 3)])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"expanded","value":false},
          {"op":"set-prop","id":2,"property":"selected","value":false},
          {"op":"set-prop","id":3,"property":"selected","value":true}
        ]}
        """)
        #expect(backend.model(id: 1) === tree)
        #expect(backend.model(id: 2) === folder)
        #expect(backend.model(id: 3) === file)
        #expect(tree.revision == treeRevision)
        #expect(folder.revision == folderRevision + 1)
        #expect(file.isSelected)
    }

    @Test("rejects orphaned or malformed Tree metadata atomically")
    func rejectsMalformedTreeMetadata() throws {
        for operations in [
            """
            {"op":"create-node","id":1,"kind":"column"},
            {"op":"create-node","id":2,"kind":"list-item"},
            {"op":"set-prop","id":2,"property":"role","value":"treeitem"},
            {"op":"insert-child","parent":1,"child":2,"index":0}
            """,
            """
            {"op":"create-node","id":1,"kind":"tree"},
            {"op":"create-node","id":2,"kind":"list-item"},
            {"op":"set-prop","id":2,"property":"expanded","value":true},
            {"op":"insert-child","parent":1,"child":2,"index":0}
            """,
            """
            {"op":"create-node","id":1,"kind":"tree"},
            {"op":"create-node","id":2,"kind":"list-item"},
            {"op":"set-prop","id":2,"property":"role","value":"treeitem"},
            {"op":"set-prop","id":2,"property":"tree-level","value":0},
            {"op":"insert-child","parent":1,"child":2,"index":0}
            """,
        ] {
            let backend = LUIAppleBackend()
            #expect(throws: LUIBackendError.self) {
                try backend.apply(json: """
                {"generation":1,"ops":[\(operations)]}
                """)
            }
            #expect(backend.generation == 0)
            #expect(backend.rootIDs.isEmpty)
        }
    }

    @Test("registering an image invalidates only Avatars that reference its ImageId")
    func mapsRegisteredAvatarImage() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"row"},
          {"op":"create-node","id":2,"kind":"avatar"},
          {"op":"create-node","id":3,"kind":"avatar"},
          {"op":"set-prop","id":2,"property":"text","value":"ZN"},
          {"op":"set-prop","id":2,"property":"image","value":7},
          {"op":"set-prop","id":2,"property":"source-x","value":8.0},
          {"op":"set-prop","id":2,"property":"source-y","value":4.0},
          {"op":"set-prop","id":2,"property":"source-width","value":32.0},
          {"op":"set-prop","id":2,"property":"source-height","value":24.0},
          {"op":"set-prop","id":2,"property":"accessibility-label","value":"Profile picture"},
          {"op":"set-prop","id":3,"property":"text","value":"CT"},
          {"op":"set-prop","id":3,"property":"image","value":8},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        let first = try #require(backend.model(id: 2))
        let second = try #require(backend.model(id: 3))
        let firstRevision = first.revision
        let secondRevision = second.revision
        #expect(first.registeredImage(in: backend) == nil)
        #expect(first.avatarSourceRect == CGRect(x: 8, y: 4, width: 32, height: 24))

        let registered = try image()
        try backend.registerImage(id: 7, image: registered)
        #expect(first.registeredImage(in: backend) === registered)
        #expect(first.revision == firstRevision + 1)
        #expect(second.revision == secondRevision)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        backend.unregisterImage(id: 7)
        #expect(first.registeredImage(in: backend) == nil)
        #expect(first.revision == firstRevision + 2)
        #expect(second.revision == secondRevision)

        backend.unregisterImage(id: 7)
        #expect(first.revision == firstRevision + 2)
        #expect(throws: LUIBackendError.self) {
            try backend.registerImage(id: 0, image: registered)
        }
    }

    @Test("Image and MediaSurface keep stable resource ids and invalidate only dependents")
    func mapsRetainedMediaResources() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"row"},
          {"op":"create-node","id":2,"kind":"image"},
          {"op":"create-node","id":3,"kind":"image"},
          {"op":"create-node","id":4,"kind":"media-surface"},
          {"op":"create-node","id":5,"kind":"media-surface"},
          {"op":"set-prop","id":2,"property":"image","value":7},
          {"op":"set-prop","id":2,"property":"source-x","value":8.0},
          {"op":"set-prop","id":2,"property":"source-y","value":4.0},
          {"op":"set-prop","id":2,"property":"source-width","value":40.0},
          {"op":"set-prop","id":2,"property":"source-height","value":24.0},
          {"op":"set-prop","id":3,"property":"image","value":8},
          {"op":"set-prop","id":4,"property":"surface","value":11},
          {"op":"set-prop","id":5,"property":"surface","value":12},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1},
          {"op":"insert-child","parent":1,"child":4,"index":2},
          {"op":"insert-child","parent":1,"child":5,"index":3}
        ]}
        """)

        let imageNode = try #require(backend.model(id: 2))
        let otherImage = try #require(backend.model(id: 3))
        let surfaceNode = try #require(backend.model(id: 4))
        let otherSurface = try #require(backend.model(id: 5))
        let revisions = (
            imageNode.revision,
            otherImage.revision,
            surfaceNode.revision,
            otherSurface.revision
        )
        let frame = try image()
        #expect(surfaceNode.mediaSurfacePlaceholderComponents == [87, 115, 81])

        try backend.registerImage(id: 7, image: frame)
        #expect(imageNode.registeredImage(in: backend) === frame)
        #expect(imageNode.imageSourceRect == CGRect(x: 8, y: 4, width: 40, height: 24))
        #expect(imageNode.revision == revisions.0 + 1)
        #expect(otherImage.revision == revisions.1)

        try backend.presentMediaSurfaceFrame(id: 11, image: frame)
        #expect(surfaceNode.mediaSurfaceFrame(in: backend) === frame)
        #expect(surfaceNode.revision == revisions.2 + 1)
        #expect(otherSurface.revision == revisions.3)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        backend.unregisterMediaSurface(id: 11)
        #expect(surfaceNode.mediaSurfaceFrame(in: backend) == nil)
        #expect(surfaceNode.revision == revisions.2 + 2)
        #expect(otherSurface.revision == revisions.3)
        #expect(throws: LUIBackendError.self) {
            try backend.presentMediaSurfaceFrame(id: 0, image: frame)
        }
    }

    @Test("Image and MediaSurface reject missing ids and partial crops atomically")
    func rejectsInvalidMediaLeaves() throws {
        for kind in ["image", "media-surface"] {
            let backend = LUIAppleBackend()
            #expect(throws: LUIBackendError.self) {
                try backend.apply(json: """
                {"generation":1,"ops":[
                  {"op":"create-node","id":1,"kind":"\(kind)"}
                ]}
                """)
            }
            #expect(backend.generation == 0)
        }

        let partial = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try partial.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"image"},
              {"op":"set-prop","id":1,"property":"image","value":7},
              {"op":"set-prop","id":1,"property":"source-x","value":0.0}
            ]}
            """)
        }
        #expect(partial.generation == 0)
    }

    @Test("rejects partial and invalid Avatar source crops atomically")
    func rejectsInvalidAvatarCrop() throws {
        let backend = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"avatar"},
              {"op":"set-prop","id":1,"property":"text","value":"ZN"},
              {"op":"set-prop","id":1,"property":"image","value":7},
              {"op":"set-prop","id":1,"property":"source-x","value":0.0}
            ]}
            """)
        }
        #expect(backend.generation == 0)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"avatar"},
              {"op":"set-prop","id":1,"property":"text","value":"ZN"},
              {"op":"set-prop","id":1,"property":"image","value":7},
              {"op":"set-prop","id":1,"property":"source-x","value":0.0},
              {"op":"set-prop","id":1,"property":"source-y","value":0.0},
              {"op":"set-prop","id":1,"property":"source-width","value":-1.0},
              {"op":"set-prop","id":1,"property":"source-height","value":24.0}
            ]}
            """)
        }
        #expect(backend.generation == 0)

        let expanded = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try expanded.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"avatar"},
              {"op":"set-prop","id":1,"property":"text","value":"ZN"},
              {"op":"set-prop","id":1,"property":"width","value":40}
            ]}
            """)
        }
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

    @Test("maps Dialog to a retained native SwiftUI modal")
    func mapsDialog() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"dialog"},
          {"op":"create-node","id":3,"kind":"input"},
          {"op":"set-prop","id":2,"property":"text","value":"Rename note"},
          {"op":"set-prop","id":2,"property":"width","value":380},
          {"op":"set-prop","id":2,"property":"height","value":240},
          {"op":"set-prop","id":2,"property":"padding","value":24},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}
        """)

        let dialog = try #require(backend.model(id: 2))
        #expect(dialog.kind == .dialog)
        #expect(dialog.children == [3])
        #expect(dialog.property(.text) == .string("Rename note"))
        #expect(dialog.property(.width) == .int(380))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performDismiss(node: 2)
        #expect(events == [.dismiss(node: 2)])
        #expect(throws: LUIBackendError.self) {
            try backend.performDismiss(node: 1)
        }
    }

    @Test("maps Drawer and Sheet to retained adaptive SwiftUI presentations")
    func mapsDrawerAndSheet() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"drawer"},
          {"op":"create-node","id":3,"kind":"input"},
          {"op":"create-node","id":4,"kind":"sheet"},
          {"op":"create-node","id":5,"kind":"input"},
          {"op":"set-prop","id":2,"property":"text","value":"Filters"},
          {"op":"set-prop","id":2,"property":"height","value":260},
          {"op":"set-prop","id":2,"property":"padding","value":24},
          {"op":"set-prop","id":4,"property":"text","value":"Share"},
          {"op":"set-prop","id":4,"property":"width","value":320},
          {"op":"set-prop","id":4,"property":"padding","value":20},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":1,"child":4,"index":1},
          {"op":"insert-child","parent":4,"child":5,"index":0}
        ]}
        """)

        let drawer = try #require(backend.model(id: 2))
        let sheet = try #require(backend.model(id: 4))
        #expect(drawer.kind == .drawer)
        #expect(drawer.children == [3])
        #expect(drawer.property(.text) == .string("Filters"))
        #expect(drawer.property(.height) == .int(260))
        #expect(sheet.kind == .sheet)
        #expect(sheet.children == [5])
        #expect(sheet.property(.width) == .int(320))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"height","value":300},
          {"op":"set-prop","id":4,"property":"text","value":"Share link"}
        ]}
        """)
        #expect(backend.model(id: 2) === drawer)
        #expect(backend.model(id: 4) === sheet)
        #expect(drawer.property(.height) == .int(300))
        #expect(sheet.property(.text) == .string("Share link"))

        try backend.performDismiss(node: 2)
        try backend.performDismiss(node: 4)
        #expect(events == [.dismiss(node: 2), .dismiss(node: 4)])

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":2,"property":"gap","value":8}
            ]}
            """)
        }
        #expect(backend.generation == 2)
    }

    @Test("maps static and anchored Tooltip to one retained SwiftUI leaf")
    func mapsTooltip() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"stack"},
          {"op":"create-node","id":3,"kind":"button"},
          {"op":"create-node","id":4,"kind":"tooltip"},
          {"op":"create-node","id":5,"kind":"tooltip"},
          {"op":"set-prop","id":3,"property":"text","value":"Bold"},
          {"op":"set-prop","id":4,"property":"text","value":"Bold the selection"},
          {"op":"set-prop","id":4,"property":"anchor","value":"above"},
          {"op":"set-prop","id":4,"property":"anchor-alignment","value":"end"},
          {"op":"set-prop","id":4,"property":"anchor-offset","value":8.0},
          {"op":"set-prop","id":4,"property":"tooltip-delay","value":250},
          {"op":"set-prop","id":5,"property":"text","value":"Copied!"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"insert-child","parent":1,"child":5,"index":1}
        ]}
        """)

        let button = try #require(backend.model(id: 3))
        let tooltip = try #require(backend.model(id: 4))
        #expect(tooltip.kind == .tooltip)
        #expect(tooltip.text == "Bold the selection")
        #expect(tooltip.property(.anchor) == .string("above"))
        #expect(tooltip.property(.anchorAlignment) == .string("end"))
        #expect(tooltip.property(.anchorOffset) == .double(8))
        #expect(tooltip.property(.tooltipDelay) == .int(250))
        #expect(backend.model(id: 5)?.kind == .tooltip)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":4,"property":"text","value":"Toggle bold"},
          {"op":"set-prop","id":4,"property":"tooltip-delay","value":0}
        ]}
        """)
        #expect(backend.model(id: 3) === button)
        #expect(backend.model(id: 4) === tooltip)
        #expect(tooltip.text == "Toggle bold")
        #expect(tooltip.property(.tooltipDelay) == .int(0))

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":5,"property":"tooltip-delay","value":20}
            ]}
            """)
        }
        #expect(backend.generation == 2)
    }

    @Test("Tooltip hover intent delays, warms only on pointer leave, and resets on press")
    func tooltipIntentLifecycle() {
        let session = LUITooltipSession()
        let first = LUITooltipIntent(session: session)
        let second = LUITooltipIntent(session: session)

        first.pointerEntered(at: 0, delay: 0.6)
        #expect(!first.isPresented)
        first.advance(to: 0.599)
        #expect(!first.isPresented)
        first.advance(to: 0.6)
        #expect(first.isPresented)

        first.pointerLeft(at: 0.7)
        #expect(!first.isPresented)
        second.pointerEntered(at: 0.8, delay: 0.6)
        #expect(second.isPresented)

        second.focusLeft()
        second.focusEntered()
        #expect(second.isPresented)
        second.focusLeft()
        #expect(!second.isPresented)

        second.press()
        let cold = LUITooltipIntent(session: session)
        cold.pointerEntered(at: 0.9, delay: 0.6)
        #expect(!cold.isPresented)
        cold.advance(to: 1.49)
        #expect(!cold.isPresented)
        cold.advance(to: 1.5)
        #expect(cold.isPresented)
        cold.escape()
        #expect(!cold.isPresented)
    }

    @Test("maps Stepper and Timeline to stable native semantic compositions")
    func mapsStepperAndTimeline() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"stepper"},
          {"op":"set-prop","id":2,"property":"active","value":1},
          {"op":"set-prop","id":2,"property":"accessibility-label","value":"Release progress"},
          {"op":"create-node","id":3,"kind":"step"},
          {"op":"set-prop","id":3,"property":"text","value":"Draft"},
          {"op":"create-node","id":4,"kind":"step"},
          {"op":"set-prop","id":4,"property":"text","value":"Review"},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"create-node","id":5,"kind":"timeline"},
          {"op":"set-prop","id":5,"property":"gap","value":6},
          {"op":"set-prop","id":5,"property":"accessibility-label","value":"Release activity"},
          {"op":"create-node","id":6,"kind":"timeline-item"},
          {"op":"set-prop","id":6,"property":"title","value":"Validated"},
          {"op":"set-prop","id":6,"property":"description","value":"Checks completed"},
          {"op":"set-prop","id":6,"property":"meta","value":"CI · 2m"},
          {"op":"set-prop","id":6,"property":"indicator","value":"2"},
          {"op":"set-prop","id":6,"property":"variant","value":"primary"},
          {"op":"set-prop","id":6,"property":"connector","value":true},
          {"op":"set-prop","id":6,"property":"selected","value":false},
          {"op":"set-prop","id":6,"property":"press-enabled","value":true},
          {"op":"insert-child","parent":5,"child":6,"index":0},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":5,"index":1}
        ]}
        """)

        let stepper = try #require(backend.model(id: 2))
        let review = try #require(backend.model(id: 4))
        let timeline = try #require(backend.model(id: 5))
        let item = try #require(backend.model(id: 6))
        #expect(stepper.kind == .stepper)
        #expect(stepper.property(.active) == .int(1))
        #expect(stepper.children == [3, 4])
        #expect(review.kind == .step)
        #expect(timeline.kind == .timeline)
        #expect(timeline.children == [6])
        #expect(item.kind == .timelineItem)
        #expect(item.property(.title) == .string("Validated"))
        #expect(item.property(.connector) == .bool(true))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performPress(node: 6)
        #expect(events == [.press(node: 6)])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"active","value":2},
          {"op":"set-prop","id":4,"property":"text","value":"Approve"},
          {"op":"set-prop","id":6,"property":"title","value":"Deployed"},
          {"op":"set-prop","id":6,"property":"connector","value":false},
          {"op":"set-prop","id":6,"property":"selected","value":true}
        ]}
        """)
        #expect(backend.model(id: 2) === stepper)
        #expect(backend.model(id: 4) === review)
        #expect(backend.model(id: 5) === timeline)
        #expect(backend.model(id: 6) === item)
        #expect(stepper.property(.active) == .int(2))
        #expect(review.text == "Approve")
        #expect(item.property(.title) == .string("Deployed"))
        #expect(item.property(.connector) == .bool(false))
        #expect(item.isSelected)
    }

    @Test("rejects invalid Stepper and Timeline structure atomically")
    func rejectsInvalidStepperAndTimeline() {
        let backend = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"stepper"}
            ]}
            """)
        }
        #expect(backend.generation == 0)
        #expect(backend.model(id: 1) == nil)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"timeline-item"}
            ]}
            """)
        }
        #expect(backend.generation == 0)
        #expect(backend.model(id: 1) == nil)
    }

    @Test("maps InputGroup to one stable native composer field")
    func mapsInputGroup() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"input-group"},
          {"op":"set-prop","id":2,"property":"accessibility-label","value":"Message composer"},
          {"op":"set-prop","id":2,"property":"width","value":320},
          {"op":"set-prop","id":2,"property":"height","value":120},
          {"op":"set-prop","id":2,"property":"min-width","value":240},
          {"op":"set-prop","id":2,"property":"grow","value":1.0},
          {"op":"create-node","id":3,"kind":"textarea"},
          {"op":"set-prop","id":3,"property":"text","value":"Draft"},
          {"op":"set-prop","id":3,"property":"placeholder","value":"Message the team"},
          {"op":"create-node","id":4,"kind":"input-group-actions"},
          {"op":"set-prop","id":4,"property":"gap","value":8},
          {"op":"create-node","id":5,"kind":"button"},
          {"op":"set-prop","id":5,"property":"text","value":"Attach"},
          {"op":"create-node","id":6,"kind":"spacer"},
          {"op":"set-prop","id":6,"property":"grow","value":1.0},
          {"op":"create-node","id":7,"kind":"button"},
          {"op":"set-prop","id":7,"property":"text","value":"Send"},
          {"op":"insert-child","parent":4,"child":5,"index":0},
          {"op":"insert-child","parent":4,"child":6,"index":1},
          {"op":"insert-child","parent":4,"child":7,"index":2},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)

        let group = try #require(backend.model(id: 2))
        let textarea = try #require(backend.model(id: 3))
        let actions = try #require(backend.model(id: 4))
        #expect(group.kind == .inputGroup)
        #expect(group.children == [3, 4])
        #expect(group.property(.width) == .int(320))
        #expect(group.property(.height) == .int(120))
        #expect(group.property(.minWidth) == .int(240))
        #expect(textarea.kind == .textarea)
        #expect(actions.kind == .inputGroupActions)
        #expect(actions.children == [5, 6, 7])
        #expect(actions.property(.gap) == .int(8))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":3,"property":"text","value":"Updated"}
        ]}
        """)
        #expect(backend.model(id: 2) === group)
        #expect(backend.model(id: 3) === textarea)
        #expect(backend.model(id: 4) === actions)
        #expect(textarea.text == "Updated")
    }

    @Test("rejects malformed InputGroup structure atomically")
    func rejectsMalformedInputGroup() {
        let backend = LUIAppleBackend()
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"input-group"},
              {"op":"create-node","id":2,"kind":"input-group-actions"},
              {"op":"insert-child","parent":1,"child":2,"index":0}
            ]}
            """)
        }
        #expect(backend.generation == 0)
        #expect(backend.model(id: 1) == nil)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":1,"ops":[
              {"op":"create-node","id":1,"kind":"input-group-actions"}
            ]}
            """)
        }
        #expect(backend.generation == 0)
        #expect(backend.model(id: 1) == nil)
    }

    @Test("maps Accordion to a controlled retained SwiftUI disclosure")
    func mapsAccordion() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"accordion"},
          {"op":"create-node","id":2,"kind":"column"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":1,"property":"text","value":"Details"},
          {"op":"set-prop","id":1,"property":"selected","value":false},
          {"op":"set-prop","id":1,"property":"toggle-enabled","value":true},
          {"op":"set-prop","id":1,"property":"height","value":180},
          {"op":"set-prop","id":3,"property":"text","value":"Retained content"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}
        """)

        let accordion = try #require(backend.model(id: 1))
        let content = try #require(backend.model(id: 2))
        #expect(accordion.kind == .accordion)
        #expect(accordion.text == "Details")
        #expect(accordion.property(.selected) == .bool(false))
        #expect(accordion.property(.height) == .int(180))
        #expect(accordion.children == [2])
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performToggle(node: 1, checked: true)
        #expect(events == [.toggleChanged(node: 1, checked: true)])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"text","value":"Advanced details"},
          {"op":"set-prop","id":1,"property":"selected","value":true}
        ]}
        """)
        #expect(backend.model(id: 1) === accordion)
        #expect(backend.model(id: 2) === content)
        #expect(accordion.text == "Advanced details")
        #expect(accordion.isSelected)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"padding","value":8}
            ]}
            """)
        }
        #expect(backend.generation == 2)
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

    @Test("maps ContextMenu metadata to native SwiftUI actions")
    func mapsContextMenu() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"button"},
          {"op":"create-node","id":2,"kind":"context-menu"},
          {"op":"create-node","id":3,"kind":"menu-item"},
          {"op":"create-node","id":4,"kind":"divider"},
          {"op":"create-node","id":5,"kind":"menu-item"},
          {"op":"set-prop","id":1,"property":"text","value":"Document"},
          {"op":"set-prop","id":3,"property":"text","value":"Rename"},
          {"op":"set-prop","id":3,"property":"press-enabled","value":true},
          {"op":"set-prop","id":5,"property":"text","value":"Archive"},
          {"op":"set-prop","id":5,"property":"press-enabled","value":true},
          {"op":"set-prop","id":5,"property":"enabled","value":false},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"insert-child","parent":2,"child":5,"index":2}
        ]}
        """)

        let host = try #require(backend.model(id: 1))
        let menu = try #require(backend.model(id: 2))
        #expect(host.kind == .button)
        #expect(menu.kind == .contextMenu)
        #expect(host.children == [2])
        #expect(menu.children == [3, 4, 5])
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
        try backend.performPress(node: 3)
        #expect(events == [.press(node: 3)])
        #expect(throws: LUIBackendError.self) {
            try backend.performPress(node: 5)
        }
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"create-node","id":6,"kind":"context-menu"},
              {"op":"create-node","id":7,"kind":"menu-item"},
              {"op":"set-prop","id":7,"property":"text","value":"Nested"},
              {"op":"set-prop","id":7,"property":"press-enabled","value":true},
              {"op":"insert-child","parent":3,"child":6,"index":0},
              {"op":"insert-child","parent":6,"child":7,"index":0}
            ]}
            """)
        }
        #expect(backend.generation == 1)
    }

    @Test("maps message and status surfaces as retained native compositions")
    func mapsMessageSurfaces() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"alert"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"create-node","id":4,"kind":"bubble"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"create-node","id":6,"kind":"status-bar"},
          {"op":"set-prop","id":2,"property":"text","value":"Sync paused"},
          {"op":"set-prop","id":3,"property":"text","value":"Reconnect to continue"},
          {"op":"set-prop","id":4,"property":"variant","value":"primary"},
          {"op":"set-prop","id":4,"property":"text","value":"2 reactions"},
          {"op":"set-prop","id":4,"property":"text-alignment","value":"start"},
          {"op":"set-prop","id":5,"property":"text","value":"Shipped"},
          {"op":"set-prop","id":6,"property":"text","value":"3 items"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":1,"child":4,"index":1},
          {"op":"insert-child","parent":4,"child":5,"index":0},
          {"op":"insert-child","parent":1,"child":6,"index":2}
        ]}
        """)

        #expect(backend.model(id: 2) != nil)
        #expect(backend.model(id: 4)?.children == [5])
        #expect(backend.model(id: 4)?.property(.text) == .string("2 reactions"))
        #expect(backend.model(id: 6)?.property(.text) == .string("3 items"))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"set-prop","id":4,"property":"gap","value":8}
            ]}
            """)
        }
        #expect(backend.generation == 1)
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
