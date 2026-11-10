#if os(iOS)
import SwiftUI

public extension View {
    /// The standalone iOS input surface used by LUI fields and native extensions.
    func luiInputSurface(isFocused: Bool = false) -> some View {
        modifier(LUIInputSurface(isFocused: isFocused))
    }
}

private struct LUIInputSurface: ViewModifier {
    let isFocused: Bool
    @Environment(\.luiSemanticColors) private var colors
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        let fill = colors["input"] ?? colors["surface"] ?? colors["muted"] ?? Color(uiColor: .tertiarySystemFill)
        let tint = colors["input-focus"] ?? colors["primary"] ?? Color.accentColor
        let focused = isFocused && isEnabled

        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(fill, in: shape)
            .overlay {
                if focused || contrast == .increased {
                    shape.strokeBorder(focused ? tint : Color.secondary, lineWidth: contrast == .increased ? 2 : 1.5)
                        .allowsHitTesting(false)
                }
            }
    }
}
#endif
