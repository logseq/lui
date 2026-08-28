import SwiftUI

enum LUIDrawerGeometry {
    static func gestureIsEligible(
        enabled: Bool,
        translationX: Double,
        translationY: Double
    ) -> Bool {
        enabled && abs(translationX) > abs(translationY)
    }

    static func dragOffset(
        isPresented: Bool,
        translation: Double,
        width: Double
    ) -> Double {
        if isPresented {
            return min(0.0, max(-width, translation))
        }
        return max(0.0, min(width, translation))
    }

    static func targetIsPresented(
        isPresented: Bool,
        translation: Double,
        predictedTranslation: Double,
        width: Double
    ) -> Bool {
        guard width > 0 else { return false }
        let projected = abs(predictedTranslation) > abs(translation)
            ? predictedTranslation
            : translation
        let visibleWidth = (isPresented ? width : 0.0) + projected
        return visibleWidth >= width * 0.5
    }
}

enum LUIDrawerSafeAreaGeometry {
    static let mainPanelBottomInset: CGFloat = 0
}

enum LUIDrawerInteractionPolicy {
    static func isLocked(isDragging: Bool, isAnimating: Bool) -> Bool {
        isDragging || isAnimating
    }

    static func mainCornerRadius(visibleWidth: CGFloat) -> CGFloat {
        visibleWidth > 0 ? 40.0 : 0.0
    }
}

struct LUIDrawerView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @State private var presented: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimating = false

    init(model: LUINodeModel, backend: LUIAppleBackend) {
        self.model = model
        self.backend = backend
        _presented = State(initialValue: model.isSelected)
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
            let interactionsLocked = LUIDrawerInteractionPolicy.isLocked(
                isDragging: isDragging,
                isAnimating: isAnimating
            )

            ZStack(alignment: .leading) {
                if let panelID = model.children.dropFirst().first {
                    LUIAnyNodeView(nodeID: panelID, backend: backend)
                        .frame(width: width)
                        .frame(maxHeight: CGFloat.infinity, alignment: Alignment.leading)
                        .opacity(Double(progress))
                        .scaleEffect(0.96 + (0.04 * Double(progress)))
                        .offset(x: -20.0 * (1.0 - progress))
                        .scrollDisabled(interactionsLocked)
                        .disabled(interactionsLocked)
                        .allowsHitTesting(presented && !interactionsLocked)
                }

                if let mainID = model.children.first {
                    LUIAnyNodeView(nodeID: mainID, backend: backend)
                        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                        .modifier(LUIDrawerMainSafeAreaModifier(
                            top: geometry.safeAreaInsets.top
                        ))
                        .modifier(LUIDrawerMainSurfaceModifier())
                        .scrollDisabled(interactionsLocked)
                        .disabled(interactionsLocked)
                        .allowsHitTesting(!interactionsLocked)
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
                                .allowsHitTesting(!interactionsLocked)
                            }
                        }
                        .clipShape(RoundedRectangle(
                            cornerRadius: LUIDrawerInteractionPolicy.mainCornerRadius(
                                visibleWidth: visibleWidth
                            )
                        ))
                        .shadow(
                            color: Color.black.opacity(0.18 * Double(progress)),
                            radius: 16,
                            x: -6
                        )
                        .offset(x: visibleWidth)
                }
            }
            #if SKIP
            .simultaneousGesture(drawerGesture(width: width))
            #else
            .simultaneousGesture(
                drawerGesture(width: width),
                isEnabled: model.isEnabled && !isAnimating
            )
            #if os(iOS)
            .sensoryFeedback(.impact(weight: .light), trigger: presented)
            #endif
            #endif
        }
        .modifier(LUIDrawerFullScreenModifier())
        .onChange(of: model.isSelected) { _, selected in
            guard selected != presented || abs(dragOffset) > 0.0 else { return }
            animatePresentation(selected)
        }
        .onChange(of: model.isEnabled) { _, enabled in
            if !enabled { dragOffset = 0 }
        }
    }

    private func drawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard !isAnimating else { return }
                guard LUIDrawerGeometry.gestureIsEligible(
                    enabled: model.isEnabled,
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height)
                ) else { return }
                dragOffset = CGFloat(LUIDrawerGeometry.dragOffset(
                    isPresented: presented,
                    translation: Double(value.translation.width),
                    width: Double(width)
                ))
            }
            .onEnded { value in
                guard !isAnimating else { return }
                guard LUIDrawerGeometry.gestureIsEligible(
                    enabled: model.isEnabled,
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height)
                ) else { return }
                updatePresentation(LUIDrawerGeometry.targetIsPresented(
                    isPresented: presented,
                    translation: Double(value.translation.width),
                    predictedTranslation: Double(value.predictedEndTranslation.width),
                    width: Double(width)
                ))
            }
    }

    private func updatePresentation(_ selected: Bool) {
        guard model.isEnabled else { return }
        animatePresentation(selected)
        guard selected != model.isSelected else { return }
        try? backend.performToggle(node: model.id, checked: selected)
    }

    private func animatePresentation(_ selected: Bool) {
        isAnimating = true
        #if SKIP
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            presented = selected
            dragOffset = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
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
            isAnimating = false
        }
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
