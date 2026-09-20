#if !SKIP
import SwiftUI
import Observation

public struct LUIScrollTitlePreferenceKey: PreferenceKey {
    public static var defaultValue: String? { nil }
    public static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

struct LUIScrollTitleCoordinateSpace: Hashable {
    let nodeID: Int
}

struct LUIScrollSectionFrameModifier: ViewModifier {
    let index: Int
    let title: String?
    let coordinateSpace: LUIScrollTitleCoordinateSpace
    let onVisibilityChange: (Int, String?) -> Void
    @State private var isBelowTop = true

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.frame(in: .named(coordinateSpace)).maxY > 0
            } action: { belowTop in
                isBelowTop = belowTop
                onVisibilityChange(index, belowTop ? title : nil)
            }
            .onAppear { onVisibilityChange(index, isBelowTop ? title : nil) }
            .onChange(of: title) { _, title in
                onVisibilityChange(index, isBelowTop ? title : nil)
            }
            .onDisappear { onVisibilityChange(index, nil) }
    }
}

@MainActor
@Observable
final class LUIScrollSectionTitleTracker {
    private(set) var title: String?
    // Row visibility must not invalidate LazyVStack while it is calculating layout.
    // Only the separate title emitter observes the derived title.
    @ObservationIgnored private var visibleSections: [Int: String] = [:]

    func update(index: Int, title: String?) {
        guard visibleSections[index] != title else { return }
        visibleSections[index] = title
        let next = visibleSections.min(by: { $0.key < $1.key })?.value
        if self.title != next { self.title = next }
    }
}

struct LUIScrollSectionTitleEmitter: View {
    let tracker: LUIScrollSectionTitleTracker
    let isActive: Bool

    var body: some View {
        Color.clear.preference(key: LUIScrollTitlePreferenceKey.self,
                               value: isActive ? tracker.title : nil)
    }
}
#endif
