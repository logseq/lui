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

struct LUIDrawerView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @Environment(\.colorScheme) private var colorScheme
    @State private var presented: Bool
    @State private var dragOffset: CGFloat = 0

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

            ZStack(alignment: .leading) {
                if let panelID = model.children.dropFirst().first {
                    LUIAnyNodeView(nodeID: panelID, backend: backend)
                        .frame(width: width)
                        .frame(maxHeight: CGFloat.infinity, alignment: Alignment.leading)
                        .background(platformBackground)
                        .opacity(0.35 + (0.65 * Double(progress)))
                        .scaleEffect(0.96 + (0.04 * Double(progress)))
                        .offset(x: -20.0 * (1.0 - progress))
                        .allowsHitTesting(visibleWidth > 0.0 && dragOffset == 0.0)
                }

                if let mainID = model.children.first {
                    LUIAnyNodeView(nodeID: mainID, backend: backend)
                        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
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
                            }
                        }
                        .clipShape(RoundedRectangle(
                            cornerRadius: 40.0 * progress
                        ))
                        .shadow(color: Color.black.opacity(0.18), radius: 16, x: -6)
                        .offset(x: visibleWidth)
                }
            }
            .simultaneousGesture(drawerGesture(width: width))
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: presented)
            .clipped()
        }
        .onChange(of: model.isSelected) { _, selected in
            presented = selected
            dragOffset = 0
        }
        .onChange(of: model.isEnabled) { _, enabled in
            if !enabled { dragOffset = 0 }
        }
    }

    private func drawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
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
        presented = selected
        dragOffset = 0
        guard selected != model.isSelected else { return }
        try? backend.performToggle(node: model.id, checked: selected)
    }

    private var platformBackground: Color {
        #if SKIP
        colorScheme == .dark ? .black : .white
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}
