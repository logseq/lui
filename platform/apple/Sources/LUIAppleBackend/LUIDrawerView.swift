import SwiftUI

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
    @State private var presented: Bool
    @State private var hasLoadedPanel: Bool
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
        _hasLoadedPanel = State(initialValue: model.isSelected)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(
                CGFloat(model.property(.width)?.intValue ?? 360),
                geometry.size.width * 0.84
            )
            let visibleWidth = min(
                width,
                max(
                    CGFloat(0.0),
                    (presented ? width : CGFloat(0.0)) + dragOffset
                )
            )
            let progress = width > 0.0 ? visibleWidth / width : 0.0
            let isDragging = abs(dragOffset) > 0.0
            let interactionsLocked = LUIDrawerInteractionPolicy.disablesInteraction(
                isDragging: isDragging,
                isAnimating: isAnimating,
                isGestureActive: isGestureActive
            )
            let contentControlsEnabled =
                LUIDrawerInteractionPolicy.contentControlsAreEnabled(
                    isDragging: isDragging,
                    isAnimating: isAnimating,
                    isGestureActive: isGestureActive
                )

            #if SKIP
            ZStack(alignment: .leading) {
                if let mainID = model.children.first {
                    LUIAnyNodeView(nodeID: mainID, backend: backend)
                        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                        .modifier(LUIDrawerMainSurfaceModifier())
                        .scrollDisabled(interactionsLocked)
                        .allowsHitTesting(contentInteractionAllowed)
                        .overlay {
                            if progress > 0 {
                                Button {
                                    updatePresentation(false)
                                } label: {
                                    Color.black.opacity(0.32 * Double(progress))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Close sidebar")
                                .accessibilityIdentifier("button.sidebar.dismiss")
                                .allowsHitTesting(presented && contentInteractionAllowed)
                            }
                        }
                }

                if let panelID = model.children.dropFirst().first {
                    LUIAnyNodeView(nodeID: panelID, backend: backend)
                        .frame(width: width)
                        .frame(maxHeight: CGFloat.infinity, alignment: Alignment.leading)
                        .background(drawerBackground)
                        .offset(x: -width + visibleWidth)
                        .shadow(
                            color: Color.black.opacity(0.18 * Double(progress)),
                            radius: 12,
                            x: 4
                        )
                        .scrollDisabled(interactionsLocked)
                        .allowsHitTesting(presented && contentInteractionAllowed)
                        .accessibilityHidden(
                            LUIDrawerInteractionPolicy.panelIsAccessibilityHidden(
                                isPresented: presented,
                                isEnabled: model.isEnabled
                            )
                        )
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
            .simultaneousGesture(drawerGesture(width: width))
            #else
            ZStack(alignment: .leading) {
                // Retain the panel after its first reveal so closing preserves its state.
                if hasLoadedPanel, let panelID = model.children.dropFirst().first {
                    LUIAnyNodeView(nodeID: panelID, backend: backend)
                        .frame(width: width)
                        .frame(maxHeight: CGFloat.infinity, alignment: Alignment.leading)
                        .background(Color.black.opacity(0.001))
                        .opacity(LUIDrawerInteractionPolicy.sidebarOpacity(progress: progress))
                        .scaleEffect(0.96 + (0.04 * Double(progress)))
                        .offset(x: -20.0 * (1.0 - progress))
                        .scrollDisabled(interactionsLocked)
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
                        .scrollDisabled(interactionsLocked)
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
            .simultaneousGesture(
                drawerGesture(width: width),
                isEnabled: (presented || model.isEnabled) && !isAnimating
            )
            #if os(iOS)
            .sensoryFeedback(.impact(weight: .light), trigger: presented)
            #endif
            #endif
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

    private var drawerBackground: Color {
        semanticColors["background"] ?? (colorScheme == .dark ? .black : .white)
    }

    private func drawerGesture(width: CGFloat) -> some Gesture {
        #if SKIP
        let gesture = DragGesture(minimumDistance: 3)
        #else
        let gesture = DragGesture(minimumDistance: 10, coordinateSpace: .global)
        #endif
        return gesture
            .onChanged { value in
                guard !isAnimating, !rejectedGesture else { return }
                // Once a drag commits to scrolling, never turn it into a drawer swipe.
                if !isGestureActive, abs(value.translation.height) >= 10,
                   abs(value.translation.width) <= abs(value.translation.height) * 2 {
                    rejectedGesture = true
                    return
                }
                let activationAllowed = presented || model.isEnabled
                let gestureIsEligible = LUIDrawerGeometry.gestureIsEligible(
                    enabled: activationAllowed,
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height)
                )
                if isGestureActive || gestureIsEligible {
                    backend.setDrawerInteractionLocked(true, node: model.id)
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        if value.translation.width > 0 { hasLoadedPanel = true }
                        isGestureActive = true
                        dragOffset = CGFloat(LUIDrawerGeometry.dragOffset(
                            isPresented: presented,
                            translation: Double(value.translation.width),
                            width: Double(width)
                        ))
                    }
                } else {
                    dragOffset = 0
                }
            }
            .onEnded { value in
                rejectedGesture = false
                guard !isAnimating else { return }
                guard isGestureActive else {
                    dragOffset = 0
                    return
                }
                updatePresentation(LUIDrawerGeometry.targetIsPresented(
                    isPresented: presented,
                    translation: Double(value.translation.width),
                    predictedTranslation: Double(value.predictedEndTranslation.width),
                    width: Double(width)
                ))
                isGestureActive = false
            }
    }

    private func updatePresentation(_ selected: Bool) {
        guard presented || model.isEnabled else { return }
        animatePresentation(selected)
        guard selected != model.isSelected else { return }
        try? backend.performToggle(node: model.id, checked: selected)
    }

    private func animatePresentation(_ selected: Bool) {
        if selected { hasLoadedPanel = true }
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
        #if SKIP
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            presented = selected
            dragOffset = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(
                LUIDrawerInteractionPolicy.transitionLockMilliseconds
            ))
            guard transitionGeneration == generation, presented == selected else { return }
            isAnimating = false
        }
        #else
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
        #endif
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
        #if !SKIP
        content.ignoresSafeArea(.container)
        #else
        content
        #endif
    }
}

private struct LUIDrawerInteractionShieldModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if !SKIP
        content
            .contentShape(Rectangle())
            .ignoresSafeArea(.container)
            .zIndex(1_000)
        #else
        content.zIndex(1_000)
        #endif
    }
}

private struct LUIDrawerMainSafeAreaModifier: ViewModifier {
    let top: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        #if !SKIP && os(iOS)
        content.safeAreaPadding(.top, top)
            .safeAreaPadding(.bottom, LUIDrawerSafeAreaGeometry.mainPanelBottomInset)
        #else
        content
        #endif
    }
}

private struct LUIDrawerMainSurfaceModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if SKIP
        content.background(Color.primary.opacity(0.04))
        #else
        content.background(.ultraThinMaterial)
        #endif
    }
}
