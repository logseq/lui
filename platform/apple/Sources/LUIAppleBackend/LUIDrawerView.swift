import SwiftUI
#if os(iOS)
import UIKit
#endif

enum LUIDrawerGeometry {
    static func gestureIsEligible(
        enabled: Bool,
        translationX: Double,
        translationY: Double
    ) -> Bool {
        enabled && abs(translationX) >= 18 && abs(translationX) > abs(translationY) * 2
    }

    static func dragOffset(
        isPresented: Bool,
        translation: Double,
        width: Double
    ) -> Double {
        _ = width
        if isPresented {
            return min(0.0, translation)
        }
        return max(0.0, translation)
    }

    static func targetIsPresented(
        isPresented: Bool,
        translation: Double,
        predictedTranslation: Double,
        width: Double
    ) -> Bool {
        _ = translation
        let visibleWidth = (isPresented ? width : 0.0) + predictedTranslation
        return visibleWidth > width * 0.5
    }
}

struct LUIPinnedDrawerChromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var luiPinnedDrawerChrome: Bool {
        get { self[LUIPinnedDrawerChromeKey.self] }
        set { self[LUIPinnedDrawerChromeKey.self] = newValue }
    }
}

/// Buttons tagged `drawer-toggle` in `style_class` opt into being suppressed
/// while the system supplies the drawer affordance (pinned split-view chrome).
enum LUIDrawerToggleMarker {
    static func isDrawerToggle(styleClass: String?) -> Bool {
        styleClass?.split(separator: " ").contains("drawer-toggle") == true
    }
}

enum LUIDrawerSafeAreaGeometry {
    static let mainPanelBottomInset: CGFloat = 0
}

enum LUIDrawerInteractionPolicy {
    static let shadowOpacity = 0.18
    static let transitionLockMilliseconds = 350
    static let usesNativeLogicalCompletion = true

    static func panelIsAccessibilityHidden(
        isPresented: Bool,
        isEnabled: Bool
    ) -> Bool {
        !isPresented || !isEnabled
    }

    static func disablesInteraction(
        isDragging: Bool,
        isAnimating: Bool,
        isGestureActive: Bool = false
    ) -> Bool {
        isDragging || isAnimating || isGestureActive
    }

    static func showsInteractionShield(
        isDragging: Bool,
        isAnimating: Bool,
        isGestureActive: Bool = false
    ) -> Bool {
        disablesInteraction(
            isDragging: isDragging,
            isAnimating: isAnimating,
            isGestureActive: isGestureActive
        )
    }

    static func contentControlsAreEnabled(
        isDragging: Bool,
        isAnimating: Bool,
        isGestureActive: Bool = false
    ) -> Bool {
        !disablesInteraction(
            isDragging: isDragging,
            isAnimating: isAnimating,
            isGestureActive: isGestureActive
        )
    }

    static func sidebarOpacity(progress: CGFloat) -> Double {
        0.35 + (0.65 * Double(progress))
    }

    static func mainCornerRadius(progress: CGFloat) -> CGFloat {
        40.0 * progress
    }
}

struct LUIDrawerView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @Environment(\.luiSemanticColors) private var semanticColors
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var presented: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var isGestureActive = false
    @State private var rejectedGesture = false
    @State private var isAnimating = false
    @State private var transitionGeneration = 0
    #if DEBUG
    @State private var transitionStartedAt = 0.0
    #endif

    init(model: LUINodeModel, backend: LUIAppleBackend) {
        self.model = model
        self.backend = backend
        _presented = State(initialValue: model.isSelected)
    }

    /// On regular-width windows (iPad, the iPhone Duo inner display) the panel
    /// pins beside the main content through `NavigationSplitView`, giving the
    /// system's own collapse control, gestures and column memory; compact
    /// widths keep the edge-swipe overlay drawer. Once the iOS 27.1 SDK is the
    /// build floor the fold-aware layout should map to `ArrangementView`.
    private var pinsSidebar: Bool {
        horizontalSizeClass == .regular
    }

    private var splitColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { presented ? .all : .detailOnly },
            set: { visibility in
                updatePresentation(visibility != .detailOnly)
            }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(
                CGFloat(model.property(.width)?.intValue ?? 360),
                geometry.size.width * 0.84
            )
            if pinsSidebar {
                pinnedBody(width: width, geometry: geometry)
            } else {
                overlayBody(width: width, geometry: geometry)
            }
        }
        .modifier(LUIDrawerFullScreenModifier())
        .onDisappear {
            backend.setDrawerInteractionLocked(false, node: model.id)
        }
        .onChange(of: model.isSelected) { _, selected in
            guard selected != presented || abs(dragOffset) > 0.0 else { return }
            animatePresentation(selected)
        }
        .onChange(of: model.isEnabled) { _, enabled in
            if !enabled {
                dragOffset = 0
                isGestureActive = false
                rejectedGesture = false
                if !isAnimating {
                    backend.setDrawerInteractionLocked(false, node: model.id)
                }
            }
        }
    }

    @ViewBuilder
    private func pinnedBody(width: CGFloat, geometry: GeometryProxy) -> some View {
        NavigationSplitView(columnVisibility: splitColumnVisibility) {
            if let panelID = model.children.dropFirst().first {
                LUIAnyNodeView(nodeID: panelID, backend: backend)
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .navigationSplitViewColumnWidth(
                        min: width * 0.8,
                        ideal: width,
                        max: width * 1.25
                    )
                    .accessibilityHidden(
                        LUIDrawerInteractionPolicy.panelIsAccessibilityHidden(
                            isPresented: presented,
                            isEnabled: model.isEnabled
                        )
                    )
            }
        } detail: {
            if let mainID = model.children.first {
                LUIAnyNodeView(nodeID: mainID, backend: backend)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(LUIDrawerMainSafeAreaModifier(
                        top: geometry.safeAreaInsets.top
                    ))
                    .modifier(LUIDrawerMainSurfaceModifier())
                    // The split view's own collapse control replaces any
                    // in-content `drawer-toggle` button; compact widths leave
                    // the flag unset so the overlay keeps its toggle.
                    .environment(\.luiPinnedDrawerChrome, true)
            }
        }
    }

    @ViewBuilder
    private func overlayBody(width: CGFloat, geometry: GeometryProxy) -> some View {
        let visibleWidth = min(
                width,
                max(
                    CGFloat(0.0),
                    (presented ? width : CGFloat(0.0)) + dragOffset
                )
            )
            let progress = width > 0.0 ? visibleWidth / width : 0.0
            let isDragging = abs(dragOffset) > 0.0
            let contentControlsEnabled =
                LUIDrawerInteractionPolicy.contentControlsAreEnabled(
                    isDragging: isDragging,
                    isAnimating: isAnimating,
                    isGestureActive: isGestureActive
                )

            // Native scroll locking preserves the descendant SwiftUI environment,
            // so drawer transitions do not invalidate a long content tree.
            ZStack(alignment: .leading) {
                // Retain the panel after its first reveal so closing preserves its state.
                if let panelID = model.children.dropFirst().first {
                    LUIAnyNodeView(nodeID: panelID, backend: backend)
                        .frame(width: width)
                        .frame(maxHeight: CGFloat.infinity, alignment: Alignment.leading)
                        .background(Color.black.opacity(0.001))
                        .opacity(LUIDrawerInteractionPolicy.sidebarOpacity(progress: progress))
                        .scaleEffect(0.96 + (0.04 * Double(progress)))
                        .offset(x: -20.0 * (1.0 - progress))
                        .allowsHitTesting(presented && contentControlsEnabled)
                        .accessibilityHidden(
                            LUIDrawerInteractionPolicy.panelIsAccessibilityHidden(
                                isPresented: presented,
                                isEnabled: model.isEnabled
                            )
                        )
                }

                if let mainID = model.children.first {
                    LUIAnyNodeView(nodeID: mainID, backend: backend)
                        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                        .modifier(LUIDrawerMainSafeAreaModifier(
                            top: geometry.safeAreaInsets.top
                        ))
                        .modifier(LUIDrawerMainSurfaceModifier())
                        .allowsHitTesting(contentControlsEnabled)
                        .overlay {
                            if presented {
                                Button {
                                    updatePresentation(false)
                                } label: {
                                    Color.black.opacity(0.001)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Close sidebar")
                                .accessibilityIdentifier("button.sidebar.dismiss")
                                .allowsHitTesting(contentControlsEnabled)
                            }
                        }
                        .clipShape(RoundedRectangle(
                            cornerRadius: LUIDrawerInteractionPolicy.mainCornerRadius(
                                progress: progress
                            )
                        ))
                        .shadow(
                            color: Color.black.opacity(
                                LUIDrawerInteractionPolicy.shadowOpacity
                            ),
                            radius: 16,
                            x: -6
                        )
                        .offset(x: visibleWidth)
                }

                if LUIDrawerInteractionPolicy.showsInteractionShield(
                    isDragging: isDragging,
                    isAnimating: isAnimating,
                    isGestureActive: isGestureActive
                ) {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                        .allowsHitTesting(true)
                        .accessibilityHidden(true)
                        .modifier(LUIDrawerInteractionShieldModifier())
                }
            }
            #if os(iOS)
            .background(LUIDrawerNativeInteraction(
                isEnabled: (presented || model.isEnabled) && !isAnimating,
                isPresented: presented,
                isLocked: !contentControlsEnabled,
                onChanged: { updateDrag(translation: $0) },
                onEnded: { translation, predicted in
                    finishDrag(translation: translation, predicted: predicted, width: width)
                },
                onCancelled: {
                    animatePresentation(presented)
                    isGestureActive = false
                }
            ))
            .sensoryFeedback(.impact(weight: .light), trigger: presented)
            #else
            .simultaneousGesture(
                drawerGesture(width: width),
                isEnabled: (presented || model.isEnabled) && !isAnimating
            )
            #endif
    }

    private func updateDrag(translation: CGSize) {
        guard !isAnimating, !rejectedGesture else { return }
        if !isGestureActive, abs(translation.height) >= 10,
           abs(translation.width) <= abs(translation.height) * 2 {
            rejectedGesture = true
            return
        }
        let gestureIsEligible = LUIDrawerGeometry.gestureIsEligible(
            enabled: presented || model.isEnabled,
            translationX: Double(translation.width),
            translationY: Double(translation.height)
        )
        if isGestureActive || gestureIsEligible {
            backend.setDrawerInteractionLocked(true, node: model.id)
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                isGestureActive = true
                dragOffset = CGFloat(LUIDrawerGeometry.dragOffset(
                    isPresented: presented,
                    translation: Double(translation.width),
                    width: 0
                ))
            }
        } else {
            dragOffset = 0
        }
    }

    private func finishDrag(translation: CGSize, predicted: CGSize, width: CGFloat) {
        rejectedGesture = false
        guard !isAnimating else { return }
        guard isGestureActive else {
            dragOffset = 0
            return
        }
        updatePresentation(LUIDrawerGeometry.targetIsPresented(
            isPresented: presented,
            translation: Double(translation.width),
            predictedTranslation: Double(predicted.width),
            width: Double(width)
        ))
        isGestureActive = false
    }

    private func drawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { updateDrag(translation: $0.translation) }
            .onEnded {
                finishDrag(translation: $0.translation,
                    predicted: $0.predictedEndTranslation, width: width)
            }
    }

    private func updatePresentation(_ selected: Bool) {
        guard presented || model.isEnabled else { return }
        if selected != model.isSelected,
           (try? backend.performToggle(node: model.id, checked: selected)) == nil {
            // The toggle was rejected (e.g. the node went disabled) — keep the
            // presented state in sync with the model instead of animating.
            return
        }
        animatePresentation(selected)
    }

    private func animatePresentation(_ selected: Bool) {
        transitionGeneration += 1
        let generation = transitionGeneration
        isAnimating = true
        backend.setDrawerInteractionLocked(true, node: model.id)
        #if DEBUG
        transitionStartedAt = ProcessInfo.processInfo.systemUptime
        print(
            "LUI_DRAWER transition=begin generation=\(generation) selected=\(selected)"
        )
        #endif
        withAnimation(
            .spring(response: 0.28, dampingFraction: 0.9),
            completionCriteria: .logicallyComplete
        ) {
            presented = selected
            dragOffset = 0
        } completion: {
            finishAnimation(generation: generation, selected: selected)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(
                LUIDrawerInteractionPolicy.transitionLockMilliseconds
            ))
            finishAnimation(generation: generation, selected: selected)
        }
    }

    private func finishAnimation(generation: Int, selected: Bool) {
        guard isAnimating,
              transitionGeneration == generation,
              presented == selected else { return }
        isAnimating = false
        backend.setDrawerInteractionLocked(false, node: model.id)
        #if DEBUG
        let elapsedMilliseconds =
            (ProcessInfo.processInfo.systemUptime - transitionStartedAt) * 1_000
        print(
            String(
                format: "LUI_DRAWER transition=end generation=%d selected=%@ duration_ms=%.3f",
                generation,
                selected.description,
                elapsedMilliseconds
            )
        )
        #endif
    }
}

private struct LUIDrawerFullScreenModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.ignoresSafeArea(.container)
    }
}

private struct LUIDrawerInteractionShieldModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .ignoresSafeArea(.container)
            .zIndex(1_000)
    }
}

private struct LUIDrawerMainSafeAreaModifier: ViewModifier {
    let top: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        content.safeAreaPadding(.top, top)
            .safeAreaPadding(.bottom, LUIDrawerSafeAreaGeometry.mainPanelBottomInset)
    }
}

private struct LUIDrawerMainSurfaceModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content.background(.ultraThinMaterial)
    }
}

#if os(iOS)
/// Arbitrate drawer pans before descendant scroll views begin, without changing
/// SwiftUI's scroll environment and reevaluating every mounted row.
private struct LUIDrawerNativeInteraction: UIViewRepresentable {
    let isEnabled: Bool
    let isPresented: Bool
    let isLocked: Bool
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize, CGSize) -> Void
    let onCancelled: () -> Void

    func makeUIView(context: Context) -> DrawerInteractionView {
        DrawerInteractionView(configuration: self)
    }

    func updateUIView(_ view: DrawerInteractionView, context: Context) {
        view.configuration = self
        view.updateInteraction()
        // Descendant ScrollViews commit their UIKit configuration in this update.
        DispatchQueue.main.async { [weak view] in view?.updateInteraction() }
    }

    static func dismantleUIView(_ view: DrawerInteractionView, coordinator: ()) {
        view.detach()
    }

    final class DrawerInteractionView: UIView, UIGestureRecognizerDelegate {
        var configuration: LUIDrawerNativeInteraction
        private weak var gestureRoot: UIView?
        private var registeredScrollViews = NSHashTable<UIScrollView>.weakObjects()
        private struct ScrollState {
            let scroll: UIScrollView
            let enabled: Bool
            let verticalIndicator: Bool
            let horizontalIndicator: Bool
            let offset: CGPoint
        }
        private var suspended: [ObjectIdentifier: ScrollState] = [:]
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged))

        init(configuration: LUIDrawerNativeInteraction) {
            self.configuration = configuration
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            pan.delegate = self
            pan.name = "lui.drawer"
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { updateInteraction() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateInteraction()
        }

        func updateInteraction() {
            guard window != nil else { return }
            if gestureRoot == nil {
                var responder: UIResponder? = self
                while let current = responder {
                    if let controller = current as? UIViewController {
                        gestureRoot = controller.view
                        controller.view.addGestureRecognizer(pan)
                        break
                    }
                    responder = current.next
                }
            }
            guard let root = gestureRoot else { return }
            let dragging = pan.state == .began || pan.state == .changed
            let locked = configuration.isLocked || dragging
            var pending = [root]
            while let view = pending.popLast() {
                pending.append(contentsOf: view.subviews)
                guard let scroll = view as? UIScrollView else { continue }
                if !registeredScrollViews.contains(scroll) {
                    scroll.panGestureRecognizer.require(toFail: pan)
                    registeredScrollViews.add(scroll)
                }
                if locked {
                    let id = ObjectIdentifier(scroll)
                    let state = suspended[id] ?? ScrollState(scroll: scroll,
                        enabled: scroll.isScrollEnabled,
                        verticalIndicator: scroll.showsVerticalScrollIndicator,
                        horizontalIndicator: scroll.showsHorizontalScrollIndicator,
                        offset: scroll.contentOffset)
                    suspended[id] = state
                    scroll.setContentOffset(state.offset, animated: false)
                    scroll.showsVerticalScrollIndicator = false
                    scroll.showsHorizontalScrollIndicator = false
                    scroll.isScrollEnabled = false
                    scroll.contentOffset = state.offset
                }
            }
            if !locked { restoreScrolling() }
        }

        private func restoreScrolling() {
            for state in suspended.values {
                state.scroll.isScrollEnabled = state.enabled
                state.scroll.showsVerticalScrollIndicator = state.verticalIndicator
                state.scroll.showsHorizontalScrollIndicator = state.horizontalIndicator
                state.scroll.contentOffset = state.offset
            }
            suspended.removeAll()
        }

        func detach() {
            restoreScrolling()
            gestureRoot?.removeGestureRecognizer(pan)
            gestureRoot = nil
            registeredScrollViews.removeAllObjects()
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard configuration.isEnabled, !configuration.isLocked else { return false }
            let velocity = pan.velocity(in: gestureRoot)
            guard abs(velocity.x) > abs(velocity.y) * 2 else { return false }
            return configuration.isPresented ? velocity.x < 0 : velocity.x > 0
        }

        @objc private func dragged() {
            let translation = pan.translation(in: gestureRoot)
            let size = CGSize(width: translation.x, height: translation.y)
            switch pan.state {
            case .began, .changed:
                updateInteraction()
                configuration.onChanged(size)
            case .ended:
                let velocity = pan.velocity(in: gestureRoot)
                configuration.onEnded(size, CGSize(width: translation.x + velocity.x * 0.2,
                    height: translation.y + velocity.y * 0.2))
                updateInteraction()
            case .cancelled, .failed:
                configuration.onCancelled()
                updateInteraction()
            default: break
            }
        }
    }
}
#endif
