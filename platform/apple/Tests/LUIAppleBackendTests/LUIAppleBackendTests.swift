#if !SKIP
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

private final class ObservationFlag: @unchecked Sendable {
    var value = false
}

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
    @Test("events raised during a retained batch wait for the commit boundary")
    func retainedBatchDefersEventsUntilCommitCompletes() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"box"},
          {"op":"set-prop","id":1,"property":"appear-enabled","value":true}
        ]}
        """)
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }

        backend.withDeferredEventDelivery {
            try? backend.performAppear(node: 1)
            #expect(events.isEmpty)
        }

        #expect(events == [.appear(node: 1)])
    }

    @Test("top icon placement uses a vertical label")
    func topIconPlacementUsesAVerticalLabel() {
        #expect(LUIButtonIconPlacementPolicy.usesVerticalLayout("top"))
        #expect(!LUIButtonIconPlacementPolicy.usesVerticalLayout("leading"))
        #expect(!LUIButtonIconPlacementPolicy.usesVerticalLayout("trailing"))
    }

    @Test("plain buttons stay plain and icon buttons use system glyph metrics")
    func plainButtonVisualPolicyMatchesNativeControls() {
        #expect(!LUIButtonVisualPolicy.usesBorderedStyle(variant: "default"))
        #expect(!LUIButtonVisualPolicy.usesBorderedStyle(variant: "ghost"))
        #expect(LUIButtonVisualPolicy.usesBorderedStyle(variant: "outline"))
        #expect(LUIButtonVisualPolicy.iconExtent(buttonSize: "icon") == 24)
        #expect(LUIButtonVisualPolicy.iconExtent(buttonSize: "default") == 18)
        #expect(LUIButtonVisualPolicy.usesIntrinsicHeight(
            variant: "ghost",
            buttonSize: "default",
            hasIcon: false
        ))
        #expect(!LUIButtonVisualPolicy.usesIntrinsicHeight(
            variant: "ghost",
            buttonSize: "icon",
            hasIcon: true
        ))
        #expect(!LUIButtonVisualPolicy.fillsAvailableWidth(grow: nil))
        #expect(!LUIButtonVisualPolicy.fillsAvailableWidth(grow: 0))
        #expect(LUIButtonVisualPolicy.fillsAvailableWidth(grow: 1))
        #expect(LUIButtonVisualPolicy.contentHorizontalPadding(explicit: nil) == 0)
        #expect(LUIButtonVisualPolicy.contentHorizontalPadding(explicit: 30) == 30)
        #expect(LUIButtonVisualPolicy.labelAlignment(textAlignment: "center") == .center)
        #expect(LUIButtonVisualPolicy.labelAlignment(textAlignment: "end") == .trailing)
        #expect(LUIButtonVisualPolicy.labelAlignment(textAlignment: nil) == .leading)
        #expect(LUIButtonVisualPolicy.usesSemiboldLabel(styleClass: "semibold"))
        #expect(LUIButtonVisualPolicy.usesSemiboldLabel(
            styleClass: "flashcard semibold"
        ))
        #expect(!LUIButtonVisualPolicy.usesSemiboldLabel(styleClass: nil))
        #expect(LUIButtonVisualPolicy.usesCaptionLabel(styleClass: "caption"))
        #expect(LUIButtonVisualPolicy.usesCaptionLabel(
            styleClass: "muted caption"
        ))
        #expect(!LUIButtonVisualPolicy.usesCaptionLabel(styleClass: nil))
        #expect(LUIButtonVisualPolicy.resolvedExtent(
            explicit: 24,
            fallback: 40
        ) == 24)
        #expect(LUIButtonVisualPolicy.resolvedExtent(
            explicit: 24,
            fallback: 44
        ) == 24)
        #expect(LUIButtonVisualPolicy.resolvedExtent(
            explicit: nil,
            fallback: 44
        ) == 44)
        #expect(LUIButtonVisualPolicy.defaultWidth(
            buttonSize: "icon",
            usesMinimumTouchTarget: true
        ) == 44)
        #expect(LUIButtonVisualPolicy.defaultWidth(
            buttonSize: "icon",
            usesMinimumTouchTarget: false
        ) == 40)
        #expect(LUIButtonVisualPolicy.defaultWidth(
            buttonSize: "default",
            usesMinimumTouchTarget: true
        ) == nil)
    }

    @Test("intrinsic columns do not append layout-only spacing")
    func intrinsicColumnsDoNotAppendLayoutOnlySpacing() {
        #expect(!LUIColumnLayoutPolicy.showsTrailingSpacer(
            main: nil
        ))
        #expect(!LUIColumnLayoutPolicy.showsTrailingSpacer(
            main: "start"
        ))
        #expect(!LUIColumnLayoutPolicy.showsTrailingSpacer(
            main: nil
        ))
        #expect(LUIColumnLayoutPolicy.showsTrailingSpacer(
            main: "center"
        ))
    }

    @Test("multiline text controls align content to their top edge")
    func multilineTextControlsUseTopLeadingFrameAlignment() {
        #expect(LUISurfaceFramePolicy.usesTopLeadingAlignment(kind: .textarea))
        #expect(!LUISurfaceFramePolicy.usesTopLeadingAlignment(kind: .textField))
        #expect(!LUISurfaceFramePolicy.usesTopLeadingAlignment(kind: .box))
    }

    @Test("disabled custom button surfaces follow native disabled emphasis")
    func disabledCustomButtonSurfacesAreDimmed() {
        #expect(LUISurfaceEmphasisPolicy.opacity(
            kind: .button,
            isEnabled: false,
            hasExplicitBackground: true
        ) == 0.5)
        #expect(LUISurfaceEmphasisPolicy.opacity(
            kind: .button,
            isEnabled: true,
            hasExplicitBackground: true
        ) == 1.0)
        #expect(LUISurfaceEmphasisPolicy.opacity(
            kind: .text,
            isEnabled: false,
            hasExplicitBackground: true
        ) == 1.0)
    }

    @Test("single-line text style matches native summary labels")
    func singleLineTextStyleMatchesNativeSummaryLabels() {
        #expect(LUITextLinePolicy.lineLimit(styleClass: nil) == nil)
        #expect(LUITextLinePolicy.lineLimit(styleClass: "secondary") == nil)
        #expect(LUITextLinePolicy.lineLimit(
            styleClass: "secondary single-line"
        ) == 1)
        #expect(LUITextLinePolicy.layoutPriority(
            styleClass: "secondary single-line"
        ) == 1)
    }

    @Test("semantic muted foreground uses secondary text styling")
    func semanticMutedForegroundUsesSecondaryTextStyling() {
        #expect(LUIThemeColorPolicy.isMutedForeground("muted-foreground"))
        #expect(!LUIThemeColorPolicy.isMutedForeground("foreground"))
        #expect(!LUIThemeColorPolicy.isMutedForeground(nil))
    }

    @Test("menu icons default to primary and preserve explicit semantic colors")
    func menuIconForegroundPolicy() {
        #expect(LUIThemeColorPolicy.menuItemForegroundName(
            explicit: nil,
            destructive: false
        ) == "foreground")
        #expect(LUIThemeColorPolicy.menuItemForegroundName(
            explicit: "task-done",
            destructive: false
        ) == "task-done")
        #expect(LUIThemeColorPolicy.isAccentForeground(
            LUIThemeColorPolicy.menuItemForegroundName(
                explicit: "accent",
                destructive: false
            )
        ))
        #expect(LUIThemeColorPolicy.menuItemForegroundName(
            explicit: "task-done",
            destructive: true
        ) == "red")
        #expect(LUIThemeColorPolicy.menuItemTextForegroundName(
            destructive: false
        ) == "foreground")
        #expect(LUIThemeColorPolicy.menuItemTextForegroundName(
            destructive: true
        ) == "red")
    }

    @Test("dropdown menu items use the native task picker metrics")
    func dropdownMenuLayoutPolicy() {
        #expect(LUIDropdownMenuLayoutPolicy.contentPadding == 12)
        #expect(LUIDropdownMenuLayoutPolicy.itemSpacing == 12)
        #expect(LUIDropdownMenuLayoutPolicy.iconSize == 24)
        #expect(LUIDropdownMenuLayoutPolicy.itemMinimumHeight == 40)
        #expect(LUIDropdownMenuLayoutPolicy.trailingSpacing == 16)
    }

    @Test("native Form buttons keep the system row height")
    func nativeFormButtonHeightPolicy() {
        #expect(LUIButtonVisualPolicy.defaultHeight(isNativeFormRow: true) == nil)
        #expect(LUIButtonVisualPolicy.defaultHeight(isNativeFormRow: false) == 44)
    }

    @Test("empty Form headings split sections without reserving header space")
    func emptyFormHeadingPolicy() {
        #expect(LUINavigationFormSectionPolicy.visibleHeaderID(
            3,
            text: ""
        ) == nil)
        #expect(LUINavigationFormSectionPolicy.visibleHeaderID(
            3,
            text: "Last error"
        ) == 3)
        #expect(LUINavigationFormSectionPolicy.visibleHeaderID(
            nil,
            text: nil
        ) == nil)
    }

    @Test("menu radio groups use the native Picker presentation")
    func menuRadioGroupPolicy() {
        #expect(LUIRadioGroupVisualPolicy.usesMenuStyle("menu"))
        #expect(LUIRadioGroupVisualPolicy.usesMenuStyle("compact menu"))
        #expect(!LUIRadioGroupVisualPolicy.usesMenuStyle(nil))
        #expect(!LUIRadioGroupVisualPolicy.usesMenuStyle("segmented"))
        #expect(LUIRadioGroupVisualPolicy.displayText(
            explicit: "",
            selected: "System"
        ) == "System")
        #expect(LUIRadioGroupVisualPolicy.displayText(
            explicit: "Language",
            selected: "System"
        ) == "Language")
    }

    @Test("semantic headings use the emphasized title weight")
    func semanticHeadingsUseTheEmphasizedTitleWeight() {
        #expect(LUIHeadingTypography.isBold(level: 1))
        #expect(LUIHeadingTypography.isBold(level: 3))
        #expect(!LUIHeadingTypography.isBold(level: 7))
    }

    @Test("identified containers preserve descendant accessibility identifiers")
    func identifiedContainersPreserveDescendantAccessibilityIdentifiers() {
        #expect(LUIAccessibilityPolicy.shouldContainChildren(
            hasChildren: true,
            identifier: "screen.graph-picker"
        ))
        #expect(!LUIAccessibilityPolicy.shouldContainChildren(
            hasChildren: false,
            identifier: "button.refresh"
        ))
        #expect(!LUIAccessibilityPolicy.shouldContainChildren(
            hasChildren: true,
            identifier: nil
        ))
    }

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
    @Test("macOS secondary activation dispatches long press exactly once when enabled")
    func secondaryActivationDispatchesLongPress() {
        let capture = LUISecondaryLongPressView()
        var count = 0
        capture.onLongPress = { count += 1 }

        capture.isLongPressEnabled = false
        capture.handleSecondaryActivation()
        #expect(count == 0)

        capture.isLongPressEnabled = true
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

    @Test("keeps one transparent runtime root while replacing its child")
    func keepsStableRuntimeRoot() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"root"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"Before"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)
        let root = try #require(backend.model(id: 1))

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":3,"property":"text","value":"After"},
          {"op":"remove-child","parent":1,"child":2},
          {"op":"insert-child","parent":1,"child":3,"index":0},
          {"op":"drop-node","id":2}
        ]}
        """)

        #expect(backend.rootIDs == [1])
        #expect(backend.model(id: 1) === root)
        #expect(root.kind == .root)
        #expect(root.children == [3])
        #expect(backend.model(id: 2) == nil)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
    }

    @Test("removes a property without replacing the retained model")
    func removesPropertyInPlace() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"set-prop","id":1,"property":"padding","value":24}
        ]}
        """)
        let model = try #require(backend.model(id: 1))

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"remove-prop","id":1,"property":"padding"}
        ]}
        """)

        #expect(backend.model(id: 1) === model)
        #expect(model.property(.padding) == nil)
    }

    @Test("rejects a runtime root with more than one child")
    func rejectsMultipleRuntimeRootChildren() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"root"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"create-node","id":3,"kind":"text"},
              {"op":"insert-child","parent":1,"child":3,"index":1}
            ]}
            """)
        }
        #expect(backend.generation == 1)
        #expect(backend.model(id: 1)?.children == [2])
        #expect(backend.model(id: 3) == nil)
    }

    @Test("projects direct retained children as Gallery sections")
    func projectsRootSections() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"column"},
          {"op":"create-node","id":3,"kind":"heading"},
          {"op":"set-prop","id":3,"property":"text","value":"Button"},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"create-node","id":4,"kind":"button"},
          {"op":"set-prop","id":4,"property":"text","value":"Default"},
          {"op":"insert-child","parent":2,"child":4,"index":1},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"create-node","id":7,"kind":"column"},
          {"op":"create-node","id":5,"kind":"heading"},
          {"op":"set-prop","id":5,"property":"text","value":"Tabs"},
          {"op":"insert-child","parent":7,"child":5,"index":0},
          {"op":"create-node","id":6,"kind":"tabs"},
          {"op":"insert-child","parent":7,"child":6,"index":1},
          {"op":"insert-child","parent":1,"child":7,"index":1}
        ]}
        """)

        #expect(backend.rootSections(rootID: 1) == [
            LUIRootSection(id: 2, title: "Button"),
            LUIRootSection(id: 7, title: "Tabs"),
        ])
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

    @Test("SwiftUI observes retained properties and child projections")
    func retainedStateIsObservable() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let row = try #require(backend.model(id: 1))
        let button = try #require(backend.model(id: 3))
        let childrenChanged = ObservationFlag()
        let propertiesChanged = ObservationFlag()

        withObservationTracking {
            _ = row.children
        } onChange: {
            childrenChanged.value = true
        }
        withObservationTracking {
            _ = button.isEnabled
        } onChange: {
            propertiesChanged.value = true
        }

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"create-node","id":4,"kind":"paragraph"},
          {"op":"set-prop","id":4,"property":"text","value":"Mounted"},
          {"op":"insert-child","parent":1,"child":4,"index":2},
          {"op":"set-prop","id":3,"property":"enabled","value":false}
        ]}
        """)

        #expect(childrenChanged.value)
        #expect(propertiesChanged.value)
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
          {"op":"set-prop","id":1,"property":"orientation","value":"horizontal"},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Workspace sections"},
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
        #expect(tabs.property(.orientation) == .string("horizontal"))
        #expect(tabs.property(.accessibilityLabel) == .string("Workspace sections"))
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

    @Test("maps BottomTabs to retained native TabView destinations")
    func mapsBottomTabs() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"bottom-tabs"},
          {"op":"create-node","id":2,"kind":"bottom-tab"},
          {"op":"create-node","id":3,"kind":"bottom-tab"},
          {"op":"create-node","id":4,"kind":"paragraph"},
          {"op":"create-node","id":5,"kind":"paragraph"},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Primary destinations"},
          {"op":"set-prop","id":2,"property":"title","value":"Home"},
          {"op":"set-prop","id":2,"property":"icon","value":"folder"},
          {"op":"set-prop","id":2,"property":"selected","value":true},
          {"op":"set-prop","id":2,"property":"press-enabled","value":true},
          {"op":"set-prop","id":3,"property":"title","value":"Search"},
          {"op":"set-prop","id":3,"property":"icon","value":"search"},
          {"op":"set-prop","id":3,"property":"selected","value":false},
          {"op":"set-prop","id":3,"property":"press-enabled","value":true},
          {"op":"set-prop","id":4,"property":"text","value":"Home page"},
          {"op":"set-prop","id":5,"property":"text","value":"Search page"},
          {"op":"insert-child","parent":2,"child":4,"index":0},
          {"op":"insert-child","parent":3,"child":5,"index":0},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        let tabs = try #require(backend.model(id: 1))
        let home = try #require(backend.model(id: 2))
        let search = try #require(backend.model(id: 3))
        let homePage = try #require(backend.model(id: 4))
        let tabsRevision = tabs.revision
        let homePageRevision = homePage.revision
        #expect(tabs.kind.rawValue == "bottom-tabs")
        #expect(home.kind.rawValue == "bottom-tab")
        #expect(tabs.children == [2, 3])
        #expect(home.children == [4])
        #expect(home.property(.title) == .string("Home"))
        #expect(home.property(.icon) == .string("folder"))
        #expect(home.isSelected)
        #expect(!search.isSelected)
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performPress(node: 3)
        #expect(events == [.press(node: 3)])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"selected","value":false},
          {"op":"set-prop","id":3,"property":"selected","value":true}
        ]}
        """)
        #expect(backend.model(id: 1) === tabs)
        #expect(backend.model(id: 2) === home)
        #expect(backend.model(id: 3) === search)
        #expect(backend.model(id: 4) === homePage)
        #expect(tabs.revision == tabsRevision)
        #expect(homePage.revision == homePageRevision)
        #expect(search.isSelected)
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

    @Test("accepts centered button labels")
    func acceptsCenteredButtonLabels() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"button"},
          {"op":"set-prop","id":1,"property":"text","value":"Continue"},
          {"op":"set-prop","id":1,"property":"text-alignment","value":"center"}
        ]}
        """)

        #expect(backend.model(id: 1)?.property(.textAlignment)?.stringValue == "center")
    }

    @Test("navigation list roles do not require tree ancestry")
    func acceptsNavigationListRoles() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"list"},
          {"op":"create-node","id":2,"kind":"list-item"},
          {"op":"create-node","id":3,"kind":"list-item"},
          {"op":"set-prop","id":2,"property":"text","value":"Journals"},
          {"op":"set-prop","id":2,"property":"role","value":"navigation"},
          {"op":"set-prop","id":3,"property":"text","value":"sync 2"},
          {"op":"set-prop","id":3,"property":"role","value":"navigation-heading"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        #expect(backend.model(id: 2)?.role == "navigation")
        #expect(backend.model(id: 3)?.role == "navigation-heading")
    }

    @Test("virtual list retains one flat lazy collection")
    func mapsVirtualList() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"virtual-list"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":1,"property":"gap","value":8},
          {"op":"set-prop","id":1,"property":"selected","value":false},
          {"op":"set-prop","id":1,"property":"style-class","value":"retained-pane"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        let list = try #require(backend.model(id: 1))
        #expect(list.kind == .virtualList)
        #expect(list.children == [2, 3])
        #expect(list.property(.gap) == .int(8))
        #expect(!list.isSelected)
        #expect(list.property(.styleClass) == .string("retained-pane"))
    }

    @Test("virtual list row identity changes only with retained node revision")
    func virtualListRowIdentityTracksRevision() {
        let original = LUIRetainedNodeSnapshot(
            nodeID: 7,
            revision: 2
        )

        #expect(original == LUIRetainedNodeSnapshot(
            nodeID: 7,
            revision: 2
        ))
        #expect(original != LUIRetainedNodeSnapshot(
            nodeID: 7,
            revision: 3
        ))
        #expect(original != LUIRetainedNodeSnapshot(
            nodeID: 8,
            revision: 2
        ))
    }

    @Test("only external resource nodes directly observe retained revision")
    func directRevisionObservationIsResourceScoped() {
        #expect(!LUIDirectRevisionObservationPolicy.requiresRevision(.row))
        #expect(!LUIDirectRevisionObservationPolicy.requiresRevision(.virtualList))
        #expect(!LUIDirectRevisionObservationPolicy.requiresRevision(.text))
        #expect(LUIDirectRevisionObservationPolicy.requiresRevision(.avatar))
        #expect(LUIDirectRevisionObservationPolicy.requiresRevision(.image))
        #expect(LUIDirectRevisionObservationPolicy.requiresRevision(.mediaSurface))
    }

    @Test("Spacer keeps its native flexible layout identity")
    func spacerBypassesSurfaceDecoration() {
        #expect(LUIUnmodifiedNodePolicy.bypassesSurface(kind: .spacer))
        #expect(!LUIUnmodifiedNodePolicy.bypassesSurface(kind: .box))
        #expect(!LUIUnmodifiedNodePolicy.bypassesSurface(kind: .text))
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
          {"op":"set-prop","id":1,"property":"long-press-enabled","value":true},
          {"op":"set-prop","id":3,"property":"checked","value":false}
        ]}
        """)

        try backend.performPress(node: 1)
        try backend.performLongPress(node: 1)
        try backend.performTextChange(node: 2, text: "Draft")
        try backend.performSubmit(node: 2)
        try backend.performToggle(node: 3, checked: true)

        #expect(events == [
            .press(node: 1),
            .longPress(node: 1),
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

    @Test("native drafts preserve Chinese composition while focused")
    func nativeDraftPreservesComposition() {
        var draft = LUITextDraftState(source: "")

        draft.edit("n")
        draft.reconcile(source: "N", focused: true)
        #expect(draft.text == "n")
        draft.edit("ni")
        draft.edit("你")
        draft.edit("你好")
        #expect(draft.text == "你好")

        draft.reconcile(source: "你好", focused: false)
        #expect(draft.text == "你好")
        draft.reconcile(source: "服务器更新", focused: false)
        #expect(draft.text == "服务器更新")
    }

    @Test("focused native drafts accept an authoritative clear")
    func focusedNativeDraftAcceptsClear() {
        var draft = LUITextDraftState(source: "Draft")

        draft.edit("Draft with local composition")
        draft.reconcile(source: "", focused: true)

        #expect(draft.text == "")
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
          {"op":"create-node","id":6,"kind":"menu-item"},
          {"op":"create-node","id":7,"kind":"dropdown-menu"},
          {"op":"create-node","id":8,"kind":"menu-item"},
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
          {"op":"set-prop","id":6,"property":"text","value":"More"},
          {"op":"set-prop","id":7,"property":"anchor","value":"right"},
          {"op":"set-prop","id":8,"property":"text","value":"Archive"},
          {"op":"set-prop","id":8,"property":"press-enabled","value":true},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":4,"index":1},
          {"op":"insert-child","parent":4,"child":5,"index":0},
          {"op":"insert-child","parent":4,"child":6,"index":1},
          {"op":"insert-child","parent":6,"child":7,"index":0},
          {"op":"insert-child","parent":7,"child":8,"index":0}
        ]}
        """)

        let select = try #require(backend.model(id: 2))
        let menu = try #require(backend.model(id: 4))
        #expect(select.kind == .select)
        #expect(backend.model(id: 3)?.kind == .combobox)
        #expect(menu.kind == .dropdownMenu)
        #expect(backend.model(id: 5)?.kind == .menuItem)
        #expect(menu.children == [5, 6])
        #expect(menu.property(.anchor) == .string("below"))
        #expect(menu.property(.anchorAlignment) == .string("stretch"))
        #expect(menu.property(.anchorOffset) == .double(6))
        #expect(backend.model(id: 5)?.isSelected == true)
        #expect(backend.model(id: 6)?.children == [7])
        #expect(backend.model(id: 7)?.children == [8])

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
          {"op":"set-prop","id":2,"property":"long-press-enabled","value":true},
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
        try backend.performLongPress(node: 2)
        try backend.performDoublePress(node: 2)
        try backend.performSubmit(node: 2)
        #expect(events == [
            .press(node: 2),
            .longPress(node: 2),
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

    @Test("custom ListItem content uses a composite interaction container")
    func listItemInteractionStylePreservesInteractiveChildren() {
        #expect(LUIListItemInteractionPolicy.style(hasInteractiveChildren: false) == .button)
        #expect(LUIListItemInteractionPolicy.style(hasInteractiveChildren: true) == .composite)
        #expect(LUIListItemInteractionPolicy.longPressMinimumDuration == 0.35)
    }

    @Test("custom ListItem rows fill the native row width")
    func listItemContentHonorsChildGrow() {
        #expect(LUIListItemLayoutPolicy.stretchesChild(kind: .row, grow: nil))
        #expect(!LUIListItemLayoutPolicy.stretchesChild(kind: .text, grow: nil))
        #expect(!LUIListItemLayoutPolicy.stretchesChild(kind: .text, grow: 0))
        #expect(LUIListItemLayoutPolicy.stretchesChild(kind: .text, grow: 1))
        #expect(LUIListItemLayoutPolicy.showsTrailingSpacer(childGrows: false))
        #expect(!LUIListItemLayoutPolicy.showsTrailingSpacer(childGrows: true))
        #expect(LUIListItemLayoutPolicy.usesInlineTrailingIcon(isNavigationHeading: true))
        #expect(!LUIListItemLayoutPolicy.usesInlineTrailingIcon(isNavigationHeading: false))
        #expect(LUIListItemLayoutPolicy.navigationHeadingSpacing == 8)
        #expect(LUIListItemLayoutPolicy.horizontalPadding(isNavigationRow: true) == 12)
        #expect(LUIListItemLayoutPolicy.horizontalPadding(isNavigationRow: false) == 16)
        #expect(LUIListItemLayoutPolicy.minimumHeight(
            isNativeListRow: true,
            isNavigationRow: false,
            isNavigationHeading: false,
            explicitMinimumHeight: nil
        ) == nil)
        #expect(LUIListItemLayoutPolicy.minimumHeight(
            isNativeListRow: false,
            isNavigationRow: true,
            isNavigationHeading: false,
            explicitMinimumHeight: nil
        ) == nil)
        #expect(LUIListItemLayoutPolicy.minimumHeight(
            isNativeListRow: false,
            isNavigationRow: true,
            isNavigationHeading: true,
            explicitMinimumHeight: nil
        ) == 44)
        #expect(LUIListItemLayoutPolicy.minimumHeight(
            isNativeListRow: true,
            isNavigationRow: false,
            isNavigationHeading: false,
            explicitMinimumHeight: 44
        ) == 44)
    }

    @Test("native form controls defer their row height to SwiftUI")
    func nativeFormControlsUsePlatformRowHeight() {
        #expect(LUIBinaryControlLayoutPolicy.minimumTouchHeight(
            isIOS: true,
            isNativeFormRow: true
        ) == nil)
        #expect(LUIBinaryControlLayoutPolicy.minimumTouchHeight(
            isIOS: true,
            isNativeFormRow: false
        ) == nil)
        #expect(LUIBinaryControlLayoutPolicy.minimumTouchHeight(
            isIOS: false,
            isNativeFormRow: false
        ) == nil)
        #expect(LUIBinaryControlLayoutPolicy.usesAccentTint(isNativeFormRow: false))
        #expect(!LUIBinaryControlLayoutPolicy.usesAccentTint(isNativeFormRow: true))
        #expect(LUIBinaryControlLayoutPolicy.wrapsIdentifiedControlInButton(kind: .toggle))
        #expect(LUIBinaryControlLayoutPolicy.wrapsIdentifiedControlInButton(kind: .switchControl))
        #expect(LUIBinaryControlLayoutPolicy.wrapsIdentifiedControlInButton(kind: .checkbox))
        #expect(!LUIBinaryControlLayoutPolicy.wrapsIdentifiedControlInButton(kind: .button))
    }

    @Test("growing Row children preserve intrinsic trailing controls")
    func growingRowChildrenPreserveTrailingControls() {
        #expect(LUIRowLayoutPolicy.childLayoutPriority(
            grow: nil,
            styleClass: nil
        ) == 0)
        #expect(LUIRowLayoutPolicy.childLayoutPriority(
            grow: 0,
            styleClass: "secondary"
        ) == 0)
        #expect(LUIRowLayoutPolicy.childLayoutPriority(
            grow: 1,
            styleClass: nil
        ) == 0)
        #expect(LUIRowLayoutPolicy.childLayoutPriority(
            grow: nil,
            styleClass: "secondary single-line"
        ) == 1)
        #expect(LUIRowLayoutPolicy.childLayoutPriority(
            grow: 0,
            styleClass: "single-line secondary"
        ) == 1)
        #expect(LUIRowLayoutPolicy.showsTrailingSpacer(
            main: nil,
            hasGrowingChild: false
        ))
        #expect(!LUIRowLayoutPolicy.showsTrailingSpacer(
            main: nil,
            hasGrowingChild: true
        ))
        #expect(LUIRowLayoutPolicy.showsTrailingSpacer(
            main: "center",
            hasGrowingChild: true
        ))
        #expect(LUIRowLayoutPolicy.isFlexibleChild(kind: .spacer, grow: nil))
        #expect(LUIRowLayoutPolicy.isFlexibleChild(kind: .text, grow: 1))
        #expect(!LUIRowLayoutPolicy.isFlexibleChild(kind: .text, grow: nil))
    }

    @Test("growing centered columns fill their allocated width")
    func growingCenteredColumnsFillAllocatedWidth() {
        #expect(LUIColumnLayoutPolicy.fillsAvailableWidth(cross: nil, grow: nil))
        #expect(LUIColumnLayoutPolicy.fillsAvailableWidth(cross: "center", grow: 1))
        #expect(!LUIColumnLayoutPolicy.fillsAvailableWidth(cross: "center", grow: nil))
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

    @Test("Drawer retains two controlled panes and emits toggles")
    func mapsDrawerToControlledRetainedPanes() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"drawer"},
          {"op":"create-node","id":2,"kind":"panel"},
          {"op":"create-node","id":3,"kind":"panel"},
          {"op":"set-prop","id":1,"property":"selected","value":false},
          {"op":"set-prop","id":1,"property":"enabled","value":false},
          {"op":"set-prop","id":1,"property":"toggle-enabled","value":true},
          {"op":"set-prop","id":1,"property":"width","value":320},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        let drawer = try #require(backend.model(id: 1))
        let main = try #require(backend.model(id: 2))
        let panel = try #require(backend.model(id: 3))
        #expect(drawer.kind == .drawer)
        #expect(drawer.children == [2, 3])
        #expect(drawer.property(.selected) == .bool(false))
        #expect(!drawer.isEnabled)
        #expect(drawer.property(.width) == .int(320))

        #expect(throws: LUIBackendError.self) {
            try backend.performToggle(node: 1, checked: true)
        }
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"enabled","value":true}
        ]}
        """)
        try backend.performToggle(node: 1, checked: true)
        #expect(events == [.toggleChanged(node: 1, checked: true)])

        try backend.apply(json: """
        {"generation":3,"ops":[
          {"op":"set-prop","id":1,"property":"selected","value":true}
        ]}
        """)
        #expect(backend.model(id: 1) === drawer)
        #expect(backend.model(id: 2) === main)
        #expect(backend.model(id: 3) === panel)
        #expect(drawer.isSelected)
    }

    @Test("Drawer horizontal gestures resolve to controlled presentation state")
    func resolvesDrawerGestures() {
        #expect(LUIDrawerGeometry.gestureIsEligible(
            enabled: true,
            translationX: 10,
            translationY: 9
        ))
        #expect(!LUIDrawerGeometry.gestureIsEligible(
            enabled: true,
            translationX: 9,
            translationY: 10
        ))
        #expect(!LUIDrawerGeometry.gestureIsEligible(
            enabled: false,
            translationX: 10,
            translationY: 0
        ))
        #expect(LUIDrawerGeometry.dragOffset(
            isPresented: false,
            translation: 400,
            width: 320
        ) == 400)
        #expect(LUIDrawerGeometry.dragOffset(
            isPresented: true,
            translation: -400,
            width: 320
        ) == -400)
        #expect(LUIDrawerGeometry.targetIsPresented(
            isPresented: false,
            translation: 180,
            predictedTranslation: 180,
            width: 320
        ))
        #expect(!LUIDrawerGeometry.targetIsPresented(
            isPresented: false,
            translation: 160,
            predictedTranslation: 160,
            width: 320
        ))
        #expect(!LUIDrawerGeometry.targetIsPresented(
            isPresented: true,
            translation: -180,
            predictedTranslation: -180,
            width: 320
        ))
        #expect(LUIDrawerGeometry.targetIsPresented(
            isPresented: false,
            translation: 20,
            predictedTranslation: 220,
            width: 320
        ))
        #expect(!LUIDrawerGeometry.targetIsPresented(
            isPresented: false,
            translation: 220,
            predictedTranslation: 20,
            width: 320
        ))
        #expect(LUIDrawerGeometry.targetIsPresented(
            isPresented: false,
            translation: 1,
            predictedTranslation: 1,
            width: 0
        ))
    }

    @Test("Drawer motion and appearance match the main application")
    func drawerMotionAndAppearanceMatchMain() {
        #expect(LUIDrawerInteractionPolicy.transitionLockMilliseconds == 350)
        #expect(LUIDrawerInteractionPolicy.usesNativeLogicalCompletion)
        #expect(!LUIDrawerInteractionPolicy.disablesInteraction(
            isDragging: false,
            isAnimating: false
        ))
        #expect(LUIDrawerInteractionPolicy.disablesInteraction(
            isDragging: true,
            isAnimating: false
        ))
        #expect(LUIDrawerInteractionPolicy.disablesInteraction(
            isDragging: false,
            isAnimating: true
        ))
        #expect(LUIDrawerInteractionPolicy.disablesInteraction(
            isDragging: false,
            isAnimating: false,
            isGestureActive: true
        ))
        #expect(LUIDrawerInteractionPolicy.allowsContentInteraction(
            isDragging: false,
            isAnimating: false
        ))
        #expect(!LUIDrawerInteractionPolicy.allowsContentInteraction(
            isDragging: true,
            isAnimating: false
        ))
        #expect(!LUIDrawerInteractionPolicy.allowsContentInteraction(
            isDragging: false,
            isAnimating: true
        ))
        #expect(!LUIDrawerInteractionPolicy.showsInteractionShield(
            isDragging: false,
            isAnimating: false
        ))
        #expect(LUIDrawerInteractionPolicy.showsInteractionShield(
            isDragging: true,
            isAnimating: false
        ))
        #expect(LUIDrawerInteractionPolicy.showsInteractionShield(
            isDragging: false,
            isAnimating: true
        ))
        #expect(LUIDrawerInteractionPolicy.showsInteractionShield(
            isDragging: false,
            isAnimating: false,
            isGestureActive: true
        ))
        #expect(LUIDrawerInteractionPolicy.sidebarOpacity(progress: 0) == 0.35)
        #expect(LUIDrawerInteractionPolicy.sidebarOpacity(progress: 0.5) == 0.675)
        #expect(LUIDrawerInteractionPolicy.sidebarOpacity(progress: 1) == 1)
        #expect(LUIDrawerInteractionPolicy.mainCornerRadius(progress: 0) == 0)
        #expect(LUIDrawerInteractionPolicy.mainCornerRadius(progress: 0.5) == 20)
        #expect(LUIDrawerInteractionPolicy.mainCornerRadius(progress: 1) == 40)
        #expect(LUIDrawerInteractionPolicy.shadowOpacity == 0.18)
        #expect(LUIDrawerInteractionPolicy.panelIsAccessibilityHidden(
            isPresented: false,
            isEnabled: true
        ))
        #expect(LUIDrawerInteractionPolicy.panelIsAccessibilityHidden(
            isPresented: true,
            isEnabled: false
        ))
        #expect(!LUIDrawerInteractionPolicy.panelIsAccessibilityHidden(
            isPresented: true,
            isEnabled: true
        ))
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
        events.removeAll()
        try backend.performTreeTap(node: 2)
        #expect(events == [
            .press(node: 2),
            .toggleChanged(node: 2, checked: false),
        ])

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
          {"op":"set-prop","id":1,"property":"icon-placement","value":"top"},
          {"op":"set-prop","id":1,"property":"selected","value":true},
          {"op":"set-prop","id":1,"property":"autofocus","value":true},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Download report"},
          {"op":"set-prop","id":1,"property":"accessibility-identifier","value":"button.download"},
          {"op":"set-prop","id":1,"property":"long-press-enabled","value":true}
        ]}
        """)

        let button = try #require(backend.model(id: 1))
        let revision = button.revision
        #expect(button.property(.variant) == .string("primary"))
        #expect(button.property(.size) == .string("lg"))
        #expect(button.property(.icon) == .string("download"))
        #expect(button.property(.iconPlacement) == .string("top"))
        #expect(button.property(.selected) == .bool(true))
        #expect(button.property(.autofocus) == .bool(true))
        #expect(button.property(.longPressEnabled) == .bool(true))
        #expect(button.accessibilityLabel(in: backend) == "Download report")
        #expect(button.accessibilityIdentifier(in: backend) == "button.download")
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
          {"op":"set-prop","id":1,"property":"long-press-enabled","value":true}
        ]}
        """)

        let toggle = try #require(backend.model(id: 1))
        let revision = toggle.revision
        #expect(toggle.kind == .toggleButton)
        #expect(toggle.property(.selected) == .bool(false))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.performToggle(node: 1, checked: true)
        try backend.performLongPress(node: 1)
        #expect(events == [
            .toggleChanged(node: 1, checked: true),
            .longPress(node: 1),
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
        let backend = LUIAppleBackend(
            appIcons: [
                "wave-pulse": .systemName("waveform.path"),
                "brand": .assetName("BrandMark"),
            ],
            appIconBundle: .main
        )
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
        #expect(backend.appIconBundle?.bundleURL == Bundle.main.bundleURL)
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

    @Test("accepts minimum container-relative frame semantics")
    func acceptsMinimumContainerRelativeFrame() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"set-prop","id":1,"property":"container-relative-frame","value":"min-vertical"},
          {"op":"set-prop","id":1,"property":"container-relative-frame-inset","value":136}
        ]}
        """)

        #expect(backend.model(id: 1)?.containerRelativeFrame == "min-vertical")
        #expect(backend.model(id: 1)?.containerRelativeFrameInset == 136)
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

    @Test("native dialog policy extracts actions and message from nested content")
    func nativeDialogContentPolicy() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"dialog"},
          {"op":"create-node","id":3,"kind":"column"},
          {"op":"create-node","id":4,"kind":"text"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"create-node","id":6,"kind":"button"},
          {"op":"create-node","id":7,"kind":"button"},
          {"op":"set-prop","id":2,"property":"text","value":"Delete this graph?"},
          {"op":"set-prop","id":4,"property":"text","value":"Delete this graph?"},
          {"op":"set-prop","id":5,"property":"text","value":"This cannot be undone."},
          {"op":"set-prop","id":6,"property":"text","value":"Cancel"},
          {"op":"set-prop","id":7,"property":"text","value":"Confirm"},
          {"op":"set-prop","id":7,"property":"variant","value":"destructive"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":3,"child":4,"index":0},
          {"op":"insert-child","parent":3,"child":5,"index":1},
          {"op":"insert-child","parent":3,"child":6,"index":2},
          {"op":"insert-child","parent":3,"child":7,"index":3}
        ]}
        """)

        let dialog = try #require(backend.model(id: 2))
        #expect(LUIDialogContentPolicy.actionIDs(dialog: dialog, backend: backend) == [6, 7])
        #expect(LUIDialogContentPolicy.nonCancelActionIDs(
            dialog: dialog,
            backend: backend
        ) == [7])
        #expect(LUIDialogContentPolicy.cancelActionID(
            dialog: dialog,
            backend: backend
        ) == 6)
        #expect(
            LUIDialogContentPolicy.message(dialog: dialog, backend: backend)
                == "Delete this graph?\n\nThis cannot be undone."
        )
        #expect(LUIDialogContentPolicy.role(for: try #require(backend.model(id: 6))) == .cancel)
        #expect(LUIDialogContentPolicy.role(for: try #require(backend.model(id: 7))) == .destructive)
    }

    @Test("native dialog policy selects alert presentation declaratively")
    func nativeDialogPresentationPolicy() {
        #expect(LUIDialogContentPolicy.presentationStyle(styleClass: "alert") == .alert)
        #expect(
            LUIDialogContentPolicy.presentationStyle(styleClass: "compact alert destructive")
                == .alert
        )
        #expect(
            LUIDialogContentPolicy.presentationStyle(styleClass: "confirmation-dialog")
                == .confirmationDialog
        )
        #expect(LUIDialogContentPolicy.presentationStyle(styleClass: nil) == .confirmationDialog)
    }

    @Test("native dialogs retain their nearest list presentation anchor")
    func nativeDialogRetainsListAnchor() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"list"},
          {"op":"create-node","id":3,"kind":"dialog"},
          {"op":"set-prop","id":3,"property":"text","value":"Confirm"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}
        """)

        #expect(backend.modalPresentation.item?.anchorID == 2)
    }

    @Test("maps Sheet to one retained native SwiftUI presentation")
    func mapsSheet() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":4,"kind":"sheet"},
          {"op":"create-node","id":5,"kind":"input"},
          {"op":"set-prop","id":4,"property":"text","value":"Share"},
          {"op":"set-prop","id":4,"property":"height","value":320},
          {"op":"set-prop","id":4,"property":"padding","value":20},
          {"op":"insert-child","parent":1,"child":4,"index":0},
          {"op":"insert-child","parent":4,"child":5,"index":0}
        ]}
        """)

        let sheet = try #require(backend.model(id: 4))
        #expect(sheet.kind == .sheet)
        #expect(sheet.children == [5])
        #expect(sheet.property(.height) == .int(320))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":4,"property":"text","value":"Share link"}
        ]}
        """)
        #expect(backend.model(id: 4) === sheet)
        #expect(sheet.property(.text) == .string("Share link"))

        try backend.performDismiss(node: 4)
        #expect(events == [.dismiss(node: 4)])

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":4,"property":"gap","value":8}
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

    @Test("maps Toast and Toolbar to retained native SwiftUI compositions")
    func mapsToastAndToolbar() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-node","id":2,"kind":"toolbar"},
          {"op":"create-node","id":3,"kind":"button"},
          {"op":"create-node","id":4,"kind":"toast"},
          {"op":"create-node","id":5,"kind":"text"},
          {"op":"set-prop","id":2,"property":"orientation","value":"horizontal"},
          {"op":"set-prop","id":2,"property":"accessibility-label","value":"Formatting"},
          {"op":"set-prop","id":2,"property":"gap","value":4},
          {"op":"set-prop","id":3,"property":"text","value":"Bold"},
          {"op":"set-prop","id":4,"property":"duration","value":1200},
          {"op":"set-prop","id":4,"property":"accessibility-label","value":"Saved"},
          {"op":"set-prop","id":5,"property":"text","value":"Draft saved"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":1,"child":4,"index":1},
          {"op":"insert-child","parent":4,"child":5,"index":0}
        ]}
        """)

        let toolbar = try #require(backend.model(id: 2))
        let toast = try #require(backend.model(id: 4))
        #expect(toolbar.children == [3])
        #expect(toolbar.property(.orientation) == .string("horizontal"))
        #expect(toast.children == [5])
        #expect(toast.property(.duration) == .int(1200))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":5,"property":"text","value":"Draft updated"}
        ]}
        """)
        #expect(backend.model(id: 2) === toolbar)
        #expect(backend.model(id: 4) === toast)
        #expect(backend.model(id: 5)?.text == "Draft updated")

        try backend.performDismiss(node: 4)
        #expect(events == [.dismiss(node: 4)])
    }

    @Test("toolbar layout preserves vertical stacks and fixed trailing actions")
    func toolbarLayoutPolicy() {
        #expect(LUIToolbarLayoutPolicy.layout(
            orientation: "vertical",
            styleClass: "scroll-leading",
            childIDs: [1, 2, 3]
        ) == LUIToolbarLayout(
            axis: .vertical,
            scrollingChildIDs: [],
            fixedChildID: nil
        ))
        #expect(LUIToolbarLayoutPolicy.layout(
            orientation: "horizontal",
            styleClass: "compact scroll-leading elevated",
            childIDs: [1, 2, 3]
        ) == LUIToolbarLayout(
            axis: .horizontal,
            scrollingChildIDs: [1, 2],
            fixedChildID: 3
        ))
        #expect(LUIToolbarLayoutPolicy.layout(
            orientation: "horizontal",
            styleClass: "compact scroll",
            childIDs: [1, 2, 3]
        ) == LUIToolbarLayout(
            axis: .horizontal,
            scrollingChildIDs: [1, 2, 3],
            fixedChildID: nil
        ))
        #expect(LUIToolbarLayoutPolicy.layout(
            orientation: nil,
            styleClass: nil,
            childIDs: [1, 2]
        ) == LUIToolbarLayout(
            axis: .horizontal,
            scrollingChildIDs: [],
            fixedChildID: nil
        ))
        #expect(LUIToolbarLayoutPolicy.outerSpacing(hasFixedChild: true, requested: 6) == 0)
        #expect(LUIToolbarLayoutPolicy.outerSpacing(hasFixedChild: false, requested: 6) == 6)
        #expect(LUIToolbarLayoutPolicy.leadingInset("scroll-leading leading-inset-8") == 8)
        #expect(LUIToolbarLayoutPolicy.leadingInset("scroll-leading leading-inset-12") == 12)
        #expect(LUIToolbarLayoutPolicy.leadingInset("scroll-leading") == 0)
        #expect(LUIButtonVisualPolicy.iconExtent(buttonSize: "sm") == 16)
        #expect(LUIButtonVisualPolicy.iconExtent(buttonSize: "default") == 18)
        #expect(LUIButtonVisualPolicy.iconExtent(buttonSize: "icon") == 24)
    }

    @Test("navigation form sheets map content and actions to native placements")
    func navigationFormSheetPolicy() {
        #expect(LUINavigationFormSheetPolicy.isNavigationForm("compact navigation-form"))
        #expect(!LUINavigationFormSheetPolicy.isNavigationForm("compact"))
        #expect(LUINavigationFormSheetPolicy.isNavigationList("compact navigation-list"))
        #expect(!LUINavigationFormSheetPolicy.isNavigationList("navigation-scroll"))
        #expect(LUINavigationFormSheetPolicy.isNavigationContent(
            "compact navigation-content"
        ))
        #expect(!LUINavigationFormSheetPolicy.isNavigationContent(
            "navigation-scroll"
        ))
        #expect(LUINavigationFormSheetPolicy.usesNavigationBackIcon(
            "cancellation-action navigation-back-action"
        ))
        #expect(!LUINavigationFormSheetPolicy.usesNavigationBackIcon(
            "cancellation-action"
        ))
        #expect(!LUINavigationFormSheetPolicy.usesInlineTitle("navigation-form"))
        #expect(LUINavigationFormSheetPolicy.usesInlineTitle(
            "navigation-form navigation-inline-title"
        ))
        #expect(!LUINavigationFormSheetPolicy.usesInlineTitle("compact navigation-scroll"))
        #expect(!LUINavigationFormSheetPolicy.usesInlineTitle("compact"))
        #expect(!LUINavigationFormSheetPolicy.usesInlineTitle(nil))
        #expect(
            LUINavigationFormSheetPolicy.actionPlacement("cancellation-action") == .cancellation
        )
        #expect(
            LUINavigationFormSheetPolicy.actionPlacement("prominent confirmation-action")
                == .confirmation
        )
        #expect(LUINavigationFormSheetPolicy.actionPlacement(nil) == nil)
        #expect(!LUIModalPresentationPolicy.showsDragIndicator(kind: .sheet))
        #expect(!LUIModalPresentationPolicy.showsDragIndicator(kind: .dialog))
        #expect(LUISelectVisualPolicy.indicatorSystemName == "chevron.up.chevron.down")
        #expect(LUISelectVisualPolicy.trailingInset == 12)
        #expect(LUISelectVisualPolicy.verticalInset == 8)
        #expect(LUINavigationFormRowPolicy.usesAutomaticButtonStyle(
            isNativeFormRow: true,
            variant: "default"
        ))
        #expect(!LUINavigationFormRowPolicy.usesAutomaticButtonStyle(
            isNativeFormRow: false,
            variant: ""
        ))
        #expect(!LUINavigationFormRowPolicy.usesAutomaticButtonStyle(
            isNativeFormRow: true,
            variant: "primary"
        ))
        #expect(LUINavigationFormRowPolicy.usesBorderlessButtonStyle(
            isNativeListRow: true,
            variant: "ghost"
        ))
        #expect(!LUINavigationFormRowPolicy.usesBorderlessButtonStyle(
            isNativeListRow: false,
            variant: "ghost"
        ))
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

        let touch = LUITooltipIntent(session: session)
        touch.longPress()
        #expect(touch.isPresented)
        touch.press()
        #expect(!touch.isPresented)
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

    @Test("growing Box surfaces fill the width allocated by a Row")
    func growingBoxSurfacesFillAllocatedRowWidth() {
        #expect(LUIIntrinsicSurfacePolicy.fillsWidth(kind: .box, grow: 1.0))
        #expect(!LUIIntrinsicSurfacePolicy.fillsWidth(kind: .column, grow: 1.0))
        #expect(!LUIIntrinsicSurfacePolicy.fillsWidth(kind: .box, grow: 0.0))
    }

    @Test("zero-width borders do not create shape display work")
    func zeroWidthBordersAvoidShapeDisplayWork() {
        #expect(!LUIBorderRenderingPolicy.drawsBorder(width: 0))
        #expect(!LUIBorderRenderingPolicy.drawsBorder(width: -1))
        #expect(LUIBorderRenderingPolicy.drawsBorder(width: 1))
    }

    @Test("transparent layout containers do not clip descendant effects")
    func transparentLayoutContainersPreserveDescendantEffects() {
        #expect(!LUIClipRenderingPolicy.clipsContent(
            kind: .row,
            background: nil,
            cornerRadius: 0,
            borderWidth: 0
        ))
        #expect(!LUIClipRenderingPolicy.clipsContent(
            kind: .stack,
            background: "transparent",
            cornerRadius: 0,
            borderWidth: 0
        ))
        #expect(LUIClipRenderingPolicy.clipsContent(
            kind: .box,
            background: "background",
            cornerRadius: 0,
            borderWidth: 0
        ))
        #expect(LUIClipRenderingPolicy.clipsContent(
            kind: .column,
            background: nil,
            cornerRadius: 10,
            borderWidth: 0
        ))
        #expect(LUIClipRenderingPolicy.clipsContent(
            kind: .row,
            background: nil,
            cornerRadius: 0,
            borderWidth: 1
        ))
        #expect(LUIClipRenderingPolicy.clipsContent(
            kind: .panel,
            background: nil,
            cornerRadius: 0,
            borderWidth: 0
        ))
        #expect(LUIClipRenderingPolicy.clipsContent(
            kind: .tabs,
            background: nil,
            cornerRadius: 0,
            borderWidth: 0
        ))
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
          {"op":"set-prop","id":3,"property":"icon","value":"trash"},
          {"op":"set-prop","id":3,"property":"foreground","value":"success-foreground"},
          {"op":"set-prop","id":3,"property":"accessibility-identifier","value":"menu.rename"},
          {"op":"set-prop","id":5,"property":"text","value":"Archive"},
          {"op":"set-prop","id":5,"property":"press-enabled","value":true},
          {"op":"set-prop","id":5,"property":"enabled","value":false},
          {"op":"set-prop","id":5,"property":"variant","value":"destructive"},
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

    @Test("groups native list rows under heading sections")
    func groupsNativeListSections() {
        let sections = LUIListSectionPolicy.sections(
            childIDs: [1, 2, 3, 4, 5, 6],
            isHeading: { $0 == 3 || $0 == 5 },
            isFooter: { _ in false }
        )

        #expect(sections == [
            LUIListSection(headerID: nil, childIDs: [1, 2], footerID: nil),
            LUIListSection(headerID: 3, childIDs: [4], footerID: nil),
            LUIListSection(headerID: 5, childIDs: [6], footerID: nil),
        ])

        let sectionsWithFooter = LUIListSectionPolicy.sections(
            childIDs: [1, 2, 3, 4, 5],
            isHeading: { $0 == 1 || $0 == 4 },
            isFooter: { $0 == 3 }
        )
        #expect(sectionsWithFooter == [
            LUIListSection(headerID: 1, childIDs: [2], footerID: 3),
            LUIListSection(headerID: 4, childIDs: [5], footerID: nil),
        ])
    }

    @Test("native lists preserve the platform grouped background")
    func nativeListsPreserveSystemBackground() {
        #expect(LUIListSurfacePolicy.scrollContentBackground == .visible)
        #expect(LUIModalBackgroundPolicy.usesGroupedSystemBackground(
            styleClass: "navigation-list"
        ))
        #expect(!LUIModalBackgroundPolicy.usesGroupedSystemBackground(
            styleClass: "navigation-scroll"
        ))
        #expect(!LUIListSurfacePreferenceKey.defaultValue)
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
          {"op":"set-prop","id":5,"property":"text-alignment","value":"center"},
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
        #expect(backend.model(id: 5)?.property(.textAlignment) == .string("center"))
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

    @Test("registered extensions retain identity and reject invalid batches atomically")
    func registeredExtensionsRetainIdentity() throws {
        let map = LUIAppleExtension(
            identifier: "map",
            fingerprint: "map-v1",
            properties: [
                .init(name: "latitude", kind: .double, isRequired: true),
                .init(name: "longitude", kind: .double, isRequired: true),
            ],
            events: [
                .init(
                    name: "region-change",
                    fields: [
                        .init(name: "latitude", kind: .double, isRequired: true),
                        .init(name: "longitude", kind: .double, isRequired: true),
                    ]
                ),
            ]
        ) { context in
            AnyView(Text("Map \(context.nodeID)"))
        }
        let registry = LUIAppleExtensionRegistry()
        try registry.register(map)
        let backend = try LUIAppleBackend(extensionRegistry: registry)

        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"column"},
          {"op":"create-extension","id":2,"identifier":"map","fingerprint":"map-v1"},
          {"op":"set-extension-prop","id":2,"property":"latitude","value":37.3},
          {"op":"set-extension-prop","id":2,"property":"longitude","value":-122.0},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)

        let model = try #require(backend.extensionModel(id: 2))
        #expect(model.identifier == "map")
        #expect(model.property("latitude") == .double(37.3))
        #expect(backend.rootIDs == [1])
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-extension-prop","id":2,"property":"latitude","value":38.0}
        ]}
        """)
        #expect(backend.extensionModel(id: 2) === model)
        #expect(model.property("latitude") == .double(38.0))

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"create-extension","id":3,"identifier":"map","fingerprint":"wrong"}
            ]}
            """)
        }
        #expect(backend.generation == 2)
        #expect(backend.extensionModel(id: 3) == nil)

        var received: LUIEvent?
        backend.onEvent = { received = $0 }
        try backend.performExtensionEvent(
            node: 2,
            name: "region-change",
            values: ["latitude": .double(38.0), "longitude": .double(-122.0)]
        )
        #expect(received == .extension(
            node: 2,
            identifier: "map",
            name: "region-change",
            values: ["latitude": .double(38.0), "longitude": .double(-122.0)]
        ))
    }

    @Test("standard-child extensions can render any retained direct child")
    func extensionCanRenderASelectedDirectChild() throws {
        var renderedChildIDs: [Int] = []
        let registry = LUIAppleExtensionRegistry()
        try registry.register(
            LUIAppleExtension(
                identifier: "deck",
                fingerprint: "deck-v1",
                acceptsStandardChildren: true
            ) { context in
                renderedChildIDs = context.childIDs
                return context.content(for: context.childIDs[1])
            }
        )
        let backend = try LUIAppleBackend(extensionRegistry: registry)
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-extension","id":1,"identifier":"deck","fingerprint":"deck-v1"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"First"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":3,"property":"text","value":"Second"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        _ = backend.extensionView(nodeID: 1)
        #expect(renderedChildIDs == [2, 3])
    }

    @Test("extension content revision tracks retained direct child updates")
    func extensionContentRevisionTracksDirectChildUpdates() throws {
        var childRevision: Int?
        var unrelatedRevision: Int?
        let registry = LUIAppleExtensionRegistry()
        try registry.register(
            LUIAppleExtension(
                identifier: "deck",
                fingerprint: "deck-v1",
                acceptsStandardChildren: true
            ) { context in
                childRevision = context.contentRevision(for: 2)
                unrelatedRevision = context.contentRevision(for: 3)
                return AnyView(EmptyView())
            }
        )
        let backend = try LUIAppleBackend(extensionRegistry: registry)
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-extension","id":1,"identifier":"deck","fingerprint":"deck-v1"},
          {"op":"create-node","id":2,"kind":"text"},
          {"op":"set-prop","id":2,"property":"text","value":"First"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":3,"property":"text","value":"Unrelated"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)

        _ = backend.extensionView(nodeID: 1)
        #expect(childRevision == 0)
        #expect(unrelatedRevision == nil)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":2,"property":"text","value":"Updated"}
        ]}
        """)
        _ = backend.extensionView(nodeID: 1)

        #expect(childRevision == 1)
        #expect(unrelatedRevision == nil)
    }

    @Test("extension registrations cannot shadow standard nodes or name invalid children")
    func extensionRegistrationNamesAreClosed() throws {
        let registry = LUIAppleExtensionRegistry()

        #expect(throws: LUIBackendError.self) {
            try registry.register(
                LUIAppleExtension(identifier: "button", fingerprint: "shadow") { _ in
                    AnyView(EmptyView())
                }
            )
        }
        #expect(throws: LUIBackendError.self) {
            try registry.register(
                LUIAppleExtension(
                    identifier: "map",
                    fingerprint: "map-v1",
                    childIdentifiers: ["Invalid Child"]
                ) { _ in
                    AnyView(EmptyView())
                }
            )
        }
        #expect(throws: LUIBackendError.self) {
            try registry.register(
                LUIAppleExtension(
                    identifier: "map",
                    fingerprint: "map-v1",
                    childIdentifiers: ["marker", "marker"]
                ) { _ in
                    AnyView(EmptyView())
                }
            )
        }
    }

    @Test("registered platform tweaks wrap exactly one retained child")
    func platformTweaksAreUnaryDecorators() throws {
        let registry = LUIAppleExtensionRegistry()
        try registry.registerTweak(
            LUIAppleTweak(
                identifier: "glass-card",
                fingerprint: "glass-card-v1"
            ) { content, _ in
                AnyView(content.padding(8))
            }
        )
        let backend = try LUIAppleBackend(extensionRegistry: registry)
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-extension","id":1,"identifier":"glass-card","fingerprint":"glass-card-v1"},
          {"op":"create-node","id":2,"kind":"button"},
          {"op":"set-prop","id":2,"property":"text","value":"Save"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"create-node","id":3,"kind":"tabs"},
          {"op":"insert-child","parent":3,"child":1,"index":0}
        ]}
        """)
        #expect(backend.extensionModel(id: 1)?.children == [2])
        #expect(backend.model(id: 3)?.children == [1])

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"create-extension","id":4,"identifier":"glass-card","fingerprint":"glass-card-v1"}
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
#endif
