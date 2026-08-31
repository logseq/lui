import SwiftUI

enum LUIContainerRelativeFramePolicy {
    static func skipFillsHorizontal(_ axes: String?) -> Bool {
        axes == "horizontal" || axes == "both"
    }

    static func skipFillsVertical(_ axes: String?) -> Bool {
        axes == "vertical" || axes == "both"
    }
}

struct LUIContainerRelativeFrameModifier: ViewModifier {
    let axes: String?
    let inset: CGFloat
    @State private var minimumContainerSize = CGSize.zero

    @ViewBuilder
    func body(content: Content) -> some View {
        #if SKIP
        if LUIContainerRelativeFramePolicy.skipFillsHorizontal(axes),
           LUIContainerRelativeFramePolicy.skipFillsVertical(axes) {
            content.frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        } else if LUIContainerRelativeFramePolicy.skipFillsHorizontal(axes) {
            content.frame(maxWidth: .infinity, alignment: .topLeading)
        } else if LUIContainerRelativeFramePolicy.skipFillsVertical(axes) {
            content.frame(maxHeight: .infinity, alignment: .topLeading)
        } else {
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
