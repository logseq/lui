import SwiftUI

// Applies the LUI `tooltip` prop as a platform help tooltip; absent or empty
// text leaves the content untouched.
struct LUITooltipModifier: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(Text(text))
        } else {
            content
        }
    }
}
