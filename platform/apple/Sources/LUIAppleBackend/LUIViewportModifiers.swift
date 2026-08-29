import SwiftUI

struct LUIContainerRelativeFrameModifier: ViewModifier {
    let axes: String?
    let inset: CGFloat
    @State private var minimumContainerSize = CGSize.zero

    @ViewBuilder
    func body(content: Content) -> some View {
        #if SKIP
        switch axes {
        case "horizontal", "min-horizontal":
            content.frame(maxWidth: .infinity, alignment: .topLeading)
        case "vertical", "min-vertical":
            content.frame(maxHeight: .infinity, alignment: .topLeading)
        case "both", "min-both":
            content.frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        default:
            content
        }
        #else
        switch axes {
        case "horizontal":
            content.containerRelativeFrame(.horizontal, alignment: .topLeading)
        case "vertical":
            content.containerRelativeFrame(.vertical, alignment: .topLeading)
        case "both":
            content.containerRelativeFrame(
                [.horizontal, .vertical],
                alignment: .topLeading
            )
        case "min-horizontal":
            content
                .frame(
                    minWidth: max(0, minimumContainerSize.width - inset),
                    alignment: .topLeading
                )
                .background {
                    minimumContainerMeasurement(.horizontal)
                }
        case "min-vertical":
            content
                .frame(
                    minHeight: max(0, minimumContainerSize.height - inset),
                    alignment: .topLeading
                )
                .background {
                    minimumContainerMeasurement(.vertical)
                }
        case "min-both":
            content
                .fixedSize(horizontal: true, vertical: true)
                .frame(
                    minWidth: max(0, minimumContainerSize.width - inset),
                    minHeight: max(0, minimumContainerSize.height - inset),
                    alignment: .topLeading
                )
                .background {
                    minimumContainerMeasurement([.horizontal, .vertical])
                }
        default:
            content
        }
        #endif
    }

    #if !SKIP
    private func minimumContainerMeasurement(_ axes: Axis.Set) -> some View {
        Color.clear
            .containerRelativeFrame(axes, alignment: .topLeading)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                guard minimumContainerSize != size else { return }
                minimumContainerSize = size
            }
    }
    #endif
}

struct LUIAppearModifier: ViewModifier {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    @ViewBuilder
    func body(content: Content) -> some View {
        if model.supportsAppear {
            content.onAppear {
                try? backend.performAppear(node: model.id)
            }
        } else {
            content
        }
    }
}
