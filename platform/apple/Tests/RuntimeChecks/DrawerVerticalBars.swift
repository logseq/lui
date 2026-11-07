import SwiftUI
import UIKit
@testable import LUIAppleBackend

@MainActor private final class DrawerStabilityState {
    var mainInstances = Set<UUID>()
    var toolbarFrame = CGRect.zero
    var toolbarIsVertical = false
}

@available(iOS 27.1, *)
private struct DrawerMainProbe: View {
    let state: DrawerStabilityState
    @State private var identity = UUID()
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(0..<100) { index in
                        Text("Retained journal row \(index)")
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    }
                }
            }
            .navigationTitle("Drawer stability")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: {
                        Image(systemName: "calendar")
                            .frame(width: 44, height: 44)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                state.toolbarFrame = $0
                            }
                    }
                }
                .axisBehavior(.verticalPreferred)
            }
        }
        .onAppear { state.mainInstances.insert(identity) }
        .onChange(of: verticalEdge, initial: true) { _, edge in
            state.toolbarIsVertical = edge != nil
        }
    }
}

@main struct DrawerVerticalBarsCheck {
    @MainActor static func main() async throws {
        guard #available(iOS 27.1, *) else {
            throw failure("This check needs iOS 27.1 or later")
        }
        let state = DrawerStabilityState()
        let registry = LUIAppleExtensionRegistry()
        try registry.register(LUIAppleExtension(identifier: "drawer-main-probe", fingerprint: "probe-v1") { _ in
            AnyView(DrawerMainProbe(state: state))
        })
        let backend = try LUIAppleBackend(extensionRegistry: registry)
        try backend.apply(json: #"""
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"drawer"},
          {"op":"set-prop","id":1,"property":"selected","value":false},
          {"op":"create-extension","id":2,"identifier":"drawer-main-probe","fingerprint":"probe-v1"},
          {"op":"create-node","id":3,"kind":"text"},
          {"op":"set-prop","id":3,"property":"text","value":"Sidebar overlay"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """#)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            throw failure("No window scene")
        }
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: LUISwiftUIRoot(backend: backend, rootID: 1)
            .environment(\.horizontalSizeClass, .compact))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
        var scroll: UIScrollView?
        for _ in 0..<100 {
            scroll = views(window).compactMap { $0 as? UIScrollView }.first {
                $0.bounds.width > 150 && $0.bounds.height > 200 && $0.contentSize.height > $0.bounds.height * 2
            }
            if scroll != nil && !state.toolbarFrame.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let scroll, !state.toolbarFrame.isEmpty else { throw failure("The native journal and toolbar must mount") }
        try await Task.sleep(for: .milliseconds(300))
        let vertical = window.traitCollection.verticalBarEdge != .unspecified
        if ProcessInfo.processInfo.environment["LUI_DRAWER_REQUIRE_VERTICAL_BAR"] == "1", !vertical {
            throw failure("Run this check on iPhone Duo's outer display")
        }
        guard state.toolbarIsVertical == vertical else { throw failure("Toolbar must follow the scene's preferred axis") }
        scroll.setContentOffset(CGPoint(x: 0, y: 700), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        let initialScroll = scroll.contentOffset
        let initialFrame = scroll.convert(scroll.bounds, to: window)
        let initialToolbar = state.toolbarFrame
        var generation = 1
        var maximumShift: CGFloat = 0
        for _ in 0..<3 {
            for open in [true, false] {
                generation += 1
                try backend.apply(json: """
                {"generation":\(generation),"ops":[{"op":"set-prop","id":1,"property":"selected","value":\(open)}]}
                """)
                for _ in 0..<24 {
                    try await Task.sleep(for: .milliseconds(20))
                    let frame = scroll.convert(scroll.bounds, to: window)
                    maximumShift = max(maximumShift, abs(frame.minX - initialFrame.minX))
                    guard state.mainInstances.count == 1,
                          abs(scroll.contentOffset.y - initialScroll.y) < 1,
                          abs(frame.width - initialFrame.width) < 1,
                          abs(frame.height - initialFrame.height) < 1 else {
                        throw failure("Sidebar transitions must retain the journal, viewport size and scroll position")
                    }
                    if vertical {
                        guard abs(frame.minX - initialFrame.minX) < 1,
                              abs(frame.minY - initialFrame.minY) < 1,
                              state.toolbarIsVertical,
                              abs(state.toolbarFrame.midX - initialToolbar.midX) < 1,
                              abs(state.toolbarFrame.midY - initialToolbar.midY) < 1 else {
                            throw failure("Opening the sidebar must not relocate a vertical toolbar or journal: page=\(frame) toolbar=\(state.toolbarFrame)")
                        }
                    }
                }
            }
        }
        guard vertical || maximumShift > initialFrame.width * 0.5 else {
            throw failure("Ordinary compact-width iPhones must retain the existing push transition")
        }
        print("PASS: repeated sidebar transitions preserve journal identity and scroll; vertical=\(vertical) maximumShift=\(maximumShift)")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "DrawerVerticalBars", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
