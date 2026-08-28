import Testing
import SwiftUI
#if os(macOS)
import AppKit
#endif
@testable import LUIAppleBackend

@MainActor
@Suite("LUI shared backend parity")
struct LUIBackendParityTests {
    @Test("lists use lazy vertical containers on both SwiftUI hosts")
    func listContainersAreLazy() {
        #expect(LUIVerticalContainerPolicy.isLazy(kind: LUINodeKind.list))
        #expect(!LUIVerticalContainerPolicy.isLazy(kind: LUINodeKind.column))
        #expect(LUIVerticalContainerPolicy.stretchesCrossAxis(nil))
        #expect(LUIVerticalContainerPolicy.stretchesCrossAxis("stretch"))
        #expect(!LUIVerticalContainerPolicy.stretchesCrossAxis("start"))
    }

    @Test("drawer width sizes its panel without constraining the root surface")
    func drawerWidthOnlySizesPanel() {
        #expect(LUIExplicitFramePolicy.width(kind: LUINodeKind.drawer, requested: 320) == nil)
        #expect(LUIExplicitFramePolicy.width(kind: LUINodeKind.card, requested: 320) == 320)
        #expect(
            LUIExplicitFramePolicy.width(kind: LUINodeKind.resizable, requested: 320) == nil
        )
    }

    @Test("retains viewport-relative layout and appearance lifecycle semantics")
    func retainsViewportAndAppearanceSemantics() throws {
        let backend = LUIAppleBackend()

        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"box"},
          {"op":"set-prop","id":1,"property":"container-relative-frame","value":"vertical"},
          {"op":"set-prop","id":1,"property":"appear-enabled","value":true}
        ]}
        """)

        #expect(backend.model(id: 1) != nil)
    }

    #if os(macOS)
    @Test("a vertical container-relative frame fills its scroll viewport")
    func verticalContainerRelativeFrameFillsViewport() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"scroll"},
          {"op":"create-node","id":2,"kind":"box"},
          {"op":"set-prop","id":2,"property":"container-relative-frame","value":"vertical"},
          {"op":"set-prop","id":2,"property":"width","value":60},
          {"op":"set-prop","id":2,"property":"background","value":"red"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)

        let host = NSHostingView(
            rootView: LUIAnyNodeView(nodeID: 1, backend: backend)
        )
        host.frame = NSRect(x: 0, y: 0, width: 60, height: 100)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let viewportBottom = try #require(bitmap.colorAt(x: 30, y: 90))

        #expect(viewportBottom.redComponent > 0.8)
        #expect(viewportBottom.redComponent > viewportBottom.blueComponent + 0.5)
    }

    @Test("an appear-enabled node emits once when SwiftUI presents it")
    func appearEnabledNodeEmitsWhenPresented() throws {
        let backend = LUIAppleBackend()
        var events: [String] = []
        backend.onEvent = { events.append(String(describing: $0)) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"box"},
          {"op":"set-prop","id":1,"property":"width","value":1},
          {"op":"set-prop","id":1,"property":"height","value":1},
          {"op":"set-prop","id":1,"property":"appear-enabled","value":true}
        ]}
        """)

        let host = NSHostingView(
            rootView: LUIAnyNodeView(nodeID: 1, backend: backend)
        )
        host.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        #expect(events == ["appear(node: 1)"])
    }

    @Test("vertical scroll lays out multiple children sequentially")
    func verticalScrollChildrenDoNotOverlap() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"scroll"},
          {"op":"create-node","id":2,"kind":"box"},
          {"op":"create-node","id":3,"kind":"box"},
          {"op":"set-prop","id":2,"property":"width","value":60},
          {"op":"set-prop","id":2,"property":"height","value":40},
          {"op":"set-prop","id":2,"property":"background","value":"red"},
          {"op":"set-prop","id":3,"property":"width","value":60},
          {"op":"set-prop","id":3,"property":"height","value":40},
          {"op":"set-prop","id":3,"property":"background","value":"blue"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        let renderer = ImageRenderer(
            content: LUIVerticalScrollContent(
                model: try #require(backend.model(id: 1)),
                backend: backend
            )
                .frame(width: 60, height: 80)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let firstChild = try #require(bitmap.colorAt(x: 30, y: 20))
        let secondChild = try #require(bitmap.colorAt(x: 30, y: 60))

        #expect(firstChild.redComponent > 0.8)
        #expect(firstChild.redComponent > firstChild.blueComponent + 0.5)
        #expect(secondChild.blueComponent > 0.8)
        #expect(secondChild.blueComponent > secondChild.redComponent + 0.5)
    }

    @Test("explicit ListItem padding replaces the native row inset")
    func explicitListItemPaddingReplacesDefaultInset() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"list-item"},
          {"op":"create-node","id":2,"kind":"box"},
          {"op":"set-prop","id":1,"property":"padding","value":0},
          {"op":"set-prop","id":2,"property":"width","value":40},
          {"op":"set-prop","id":2,"property":"height","value":40},
          {"op":"set-prop","id":2,"property":"background","value":"red"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """)

        let renderer = ImageRenderer(
            content: LUIAnyNodeView(nodeID: 1, backend: backend)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)

        #expect(image.width <= 56)
    }

    @Test("an open drawer pushes undimmed main content beside the sidebar")
    func openDrawerPushesMainContent() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"drawer"},
          {"op":"create-node","id":2,"kind":"row"},
          {"op":"create-node","id":3,"kind":"panel"},
          {"op":"create-node","id":4,"kind":"panel"},
          {"op":"create-node","id":5,"kind":"panel"},
          {"op":"set-prop","id":1,"property":"selected","value":true},
          {"op":"set-prop","id":1,"property":"width","value":200},
          {"op":"set-prop","id":2,"property":"gap","value":0},
          {"op":"set-prop","id":3,"property":"width","value":20},
          {"op":"set-prop","id":3,"property":"height","value":200},
          {"op":"set-prop","id":3,"property":"background","value":"green"},
          {"op":"set-prop","id":3,"property":"border-width","value":0},
          {"op":"set-prop","id":3,"property":"corner-radius","value":0},
          {"op":"set-prop","id":4,"property":"width","value":380},
          {"op":"set-prop","id":4,"property":"height","value":200},
          {"op":"set-prop","id":4,"property":"background","value":"red"},
          {"op":"set-prop","id":4,"property":"border-width","value":0},
          {"op":"set-prop","id":4,"property":"corner-radius","value":0},
          {"op":"set-prop","id":5,"property":"width","value":200},
          {"op":"set-prop","id":5,"property":"height","value":200},
          {"op":"set-prop","id":5,"property":"background","value":"blue"},
          {"op":"set-prop","id":5,"property":"border-width","value":0},
          {"op":"set-prop","id":5,"property":"corner-radius","value":0},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":5,"index":1},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":2,"child":4,"index":1}
        ]}
        """)

        let renderer = ImageRenderer(
            content: LUIDrawerView(
                model: try #require(backend.model(id: 1)),
                backend: backend
            )
            .frame(width: 400, height: 200)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)

        let pushedMainLeadingColor = try #require(bitmap.colorAt(x: 205, y: 100))
        #expect(pushedMainLeadingColor.greenComponent > 0.65)
        #expect(pushedMainLeadingColor.redComponent < 0.2)

        let undimmedMainColor = try #require(bitmap.colorAt(x: 300, y: 100))
        #expect(undimmedMainColor.redComponent > 0.8)
        #expect(undimmedMainColor.greenComponent < 0.3)
    }

    @Test("a closed drawer does not bleed through transparent main content")
    func closedDrawerDoesNotBleedThroughMainContent() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"drawer"},
          {"op":"create-node","id":2,"kind":"stack"},
          {"op":"create-node","id":3,"kind":"panel"},
          {"op":"set-prop","id":1,"property":"selected","value":false},
          {"op":"set-prop","id":1,"property":"width","value":200},
          {"op":"set-prop","id":3,"property":"width","value":200},
          {"op":"set-prop","id":3,"property":"height","value":200},
          {"op":"set-prop","id":3,"property":"background","value":"red"},
          {"op":"set-prop","id":3,"property":"border-width","value":0},
          {"op":"set-prop","id":3,"property":"corner-radius","value":0},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        let drawer = try #require(backend.model(id: 1))
        let renderer = ImageRenderer(
            content: ZStack {
                Color.green
                LUIDrawerView(
                    model: drawer,
                    backend: backend
                )
            }
            .frame(width: 400, height: 200)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let closedDrawerColor = try #require(bitmap.colorAt(x: 100, y: 100))

        #expect(closedDrawerColor.greenComponent > 0.75)
        #expect(closedDrawerColor.redComponent < 0.25)
    }

    @Test("semantic surface colors are supplied without changing the wire protocol")
    func semanticSurfaceColorsUseEnvironmentOverrides() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"list-item"},
          {"op":"set-prop","id":1,"property":"text","value":"Graph"},
          {"op":"set-prop","id":1,"property":"width","value":100},
          {"op":"set-prop","id":1,"property":"height","value":50},
          {"op":"set-prop","id":1,"property":"background","value":"surface"},
          {"op":"set-prop","id":1,"property":"corner-radius","value":0}
        ]}
        """)

        let renderer = ImageRenderer(
            content: ZStack {
                Color.green
                LUIAnyNodeView(nodeID: 1, backend: backend)
                    .luiSemanticColors(["surface": .red])
            }
            .frame(width: 100, height: 50)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let surfaceColor = try #require(bitmap.colorAt(x: 90, y: 25))

        #expect(surfaceColor.redComponent > 0.8)
        #expect(surfaceColor.greenComponent < 0.3)
    }

    @Test("modal navigation surfaces use the semantic app background")
    func modalNavigationSurfacesUseSemanticBackground() throws {
        #if os(macOS)
        let renderer = ImageRenderer(
            content: Rectangle().fill(
                LUIModalBackgroundPolicy.color(
                    semanticColors: ["background": .red],
                    systemBackground: .green
                )
            )
            .frame(width: 20, height: 20)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = try #require(bitmap.colorAt(x: 10, y: 10))

        #expect(color.redComponent > 0.8)
        #expect(color.greenComponent < 0.3)
        #endif
    }

    @Test("drawer preserves its host background outside its content")
    func drawerPreservesHostBackground() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"drawer"},
          {"op":"create-node","id":2,"kind":"stack"},
          {"op":"create-node","id":3,"kind":"stack"},
          {"op":"set-prop","id":2,"property":"width","value":20},
          {"op":"set-prop","id":2,"property":"height","value":20},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)
        let drawer = try #require(backend.model(id: 1))

        let renderer = ImageRenderer(
            content: ZStack {
                Color.green
                LUIDrawerView(
                    model: drawer,
                    backend: backend
                )
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: 20)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 20)
                }
            }
            .frame(width: 100, height: 100)
        )
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        let referenceRenderer = ImageRenderer(
            content: Color.green.frame(width: 100, height: 100)
        )
        referenceRenderer.scale = 1
        let referenceImage = try #require(referenceRenderer.cgImage)
        let referenceBitmap = NSBitmapImageRep(cgImage: referenceImage)
        let referenceColor = try #require(referenceBitmap.colorAt(x: 50, y: 50))
        let topColor = try #require(bitmap.colorAt(x: 50, y: 90))
        let middleColor = try #require(bitmap.colorAt(x: 50, y: 50))
        let bottomColor = try #require(bitmap.colorAt(x: 50, y: 10))

        for color in [topColor, middleColor, bottomColor] {
            #expect(abs(color.redComponent - referenceColor.redComponent) < 0.01)
            #expect(abs(color.greenComponent - referenceColor.greenComponent) < 0.01)
            #expect(abs(color.blueComponent - referenceColor.blueComponent) < 0.01)
        }
    }

    #endif

    @Test("alerts keep their content height inside flexible columns")
    func alertsUseIntrinsicContentHeight() {
        #expect(LUIVerticalContainerPolicy.usesIntrinsicHeight(kind: LUINodeKind.alert))
        #expect(!LUIVerticalContainerPolicy.usesIntrinsicHeight(kind: LUINodeKind.column))
    }

    @Test("semantic surfaces pass their foreground color to plain children")
    func semanticForegroundInheritance() {
        #expect(LUIThemeColorPolicy.usesDefaultForeground(kind: LUINodeKind.alert))
        #expect(LUIThemeColorPolicy.usesDefaultForeground(kind: LUINodeKind.card))
        #expect(!LUIThemeColorPolicy.usesDefaultForeground(kind: LUINodeKind.column))
        #expect(!LUIThemeColorPolicy.usesDefaultForeground(kind: LUINodeKind.text))
    }

    @Test("retains nodes and patches properties")
    func retainsNodesAndPatchesProperties() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"root"},
          {"op":"create-node","id":2,"kind":"row"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":2,"property":"gap","value":12},
          {"op":"set-prop","id":3,"property":"text","value":"Before"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0}
        ]}
        """)

        let root = try #require(backend.model(id: 1))
        let row = try #require(backend.model(id: 2))
        let text = try #require(backend.model(id: 3))
        #expect(root.children == [2])
        #expect(row.children == [3])
        #expect(row.property(LUIProperty.gap) == LUIWireValue.int(12))
        #expect(text.property(LUIProperty.text) == LUIWireValue.string("Before"))

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":3,"property":"text","value":"After"}
        ]}
        """)

        #expect(backend.model(id: 1) === root)
        #expect(backend.model(id: 2) === row)
        #expect(backend.model(id: 3) === text)
        #expect(text.property(LUIProperty.text) == LUIWireValue.string("After"))
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
    }

    @Test("dispatches text, press, and toggle events")
    func dispatchesControlEvents() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"text-field"},
          {"op":"create-node","id":2,"kind":"button"},
          {"op":"create-node","id":3,"kind":"toggle"},
          {"op":"set-prop","id":1,"property":"text","value":""},
          {"op":"set-prop","id":2,"property":"text","value":"Save"},
          {"op":"set-prop","id":3,"property":"text","value":"Pinned"},
          {"op":"set-prop","id":3,"property":"checked","value":false}
        ]}
        """)

        try backend.performTextChange(node: 1, text: "Draft")
        try backend.performPress(node: 2)
        try backend.performToggle(node: 3, checked: true)

        #expect(events == [
            LUIEvent.textChanged(node: 1, text: "Draft"),
            LUIEvent.press(node: 2),
            LUIEvent.toggleChanged(node: 3, checked: true),
        ])
    }

    @Test("secure fields retain text input behavior without exposing plain text controls")
    func secureFieldDispatchesTextEvents() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"secure-field"},
          {"op":"set-prop","id":1,"property":"text","value":""},
          {"op":"set-prop","id":1,"property":"placeholder","value":"Password"}
        ]}
        """)

        #expect(backend.model(id: 1)?.kind.rawValue == "secure-field")
        try backend.performTextChange(node: 1, text: "secret")
        #expect(events == [.textChanged(node: 1, text: "secret")])
        _ = LUISwiftUIRoot(backend: backend, rootID: 1)
    }
}
