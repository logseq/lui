import SwiftUI

enum LUIDrawerGeometry {
    static func gestureIsEligible(isPresented: Bool, startX: Double) -> Bool {
        isPresented || startX <= 24.0
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
        width: Double
    ) -> Bool {
        guard width > 0 else { return false }
        if isPresented {
            return translation > -(width * 0.5)
        }
        return translation >= width * 0.5
    }
}

struct LUIDrawerView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

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
                CGFloat(model.property(.width)?.intValue ?? 320),
                geometry.size.width * 0.9
            )
            let visibleWidth = min(
                width,
                max(
                    CGFloat(0.0),
                    (presented ? width : CGFloat(0.0)) + dragOffset
                )
            )

            ZStack(alignment: .leading) {
                if let mainID = model.children.first {
                    LUIAnyNodeView(nodeID: mainID, backend: backend)
                        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                }

                if visibleWidth > 0 {
                    Color.black
                        .opacity(0.32 * Double(visibleWidth / width))
                        .ignoresSafeArea()
                        .onTapGesture { updatePresentation(false) }
                }

                if let panelID = model.children.dropFirst().first {
                    LUIAnyNodeView(nodeID: panelID, backend: backend)
                        .frame(width: width)
                        .frame(maxHeight: CGFloat.infinity, alignment: Alignment.leading)
                        .offset(x: -width + visibleWidth)
                        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 4)
                }
            }
            .simultaneousGesture(drawerGesture(width: width))
            .clipped()
        }
        .onChange(of: model.isSelected) { _, selected in
            presented = selected
            dragOffset = 0
        }
    }

    private func drawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard LUIDrawerGeometry.gestureIsEligible(
                    isPresented: presented,
                    startX: Double(value.startLocation.x)
                ) else { return }
                dragOffset = CGFloat(LUIDrawerGeometry.dragOffset(
                    isPresented: presented,
                    translation: Double(value.translation.width),
                    width: Double(width)
                ))
            }
            .onEnded { value in
                guard LUIDrawerGeometry.gestureIsEligible(
                    isPresented: presented,
                    startX: Double(value.startLocation.x)
                ) else { return }
                updatePresentation(LUIDrawerGeometry.targetIsPresented(
                    isPresented: presented,
                    translation: Double(value.translation.width),
                    width: Double(width)
                ))
            }
    }

    private func updatePresentation(_ selected: Bool) {
        presented = selected
        dragOffset = 0
        guard selected != model.isSelected else { return }
        try? backend.performToggle(node: model.id, checked: selected)
    }
}
