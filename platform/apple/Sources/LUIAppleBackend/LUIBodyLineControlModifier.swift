import SwiftUI

// A one-line body text strut keeps icons centered on the first line at every
// Dynamic Type size, without letting multiline content move their center.
struct LUIBodyLineControlModifier: ViewModifier {
    let enabled: Bool
    let width: CGFloat?
    let minimumHeight: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            Text(" ")
                .font(.body)
                .hidden()
                .frame(width: width)
                .frame(minHeight: minimumHeight)
                .overlay { content }
        } else {
            content
        }
    }
}
