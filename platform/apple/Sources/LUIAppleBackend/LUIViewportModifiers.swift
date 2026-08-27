import SwiftUI

struct LUIContainerRelativeFrameModifier: ViewModifier {
    let axes: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if SKIP
        switch axes {
        case "horizontal":
            content.frame(maxWidth: .infinity, alignment: .topLeading)
        case "vertical":
            content.frame(maxHeight: .infinity, alignment: .topLeading)
        case "both":
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
        default:
            content
        }
        #endif
    }
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
