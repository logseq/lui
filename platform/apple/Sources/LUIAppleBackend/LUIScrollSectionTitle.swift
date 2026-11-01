import SwiftUI
import Observation

public struct LUIScrollTitlePreferenceKey: PreferenceKey {
    public static var defaultValue: String? { nil }
    public static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

struct LUIScrollTitleCoordinateSpace: Hashable, Sendable {
    let nodeID: Int
}

struct LUIScrollSectionFrameModifier: ViewModifier {
    let index: Int
    let title: String?
    let coordinateSpace: LUIScrollTitleCoordinateSpace
    let onVisibilityChange: (Int, String?, UUID) -> Void
    @State private var registration = UUID()
    @State private var isBelowTop = true

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.frame(in: .named(coordinateSpace)).maxY > 0
            } action: { belowTop in
                isBelowTop = belowTop
                onVisibilityChange(index, belowTop ? title : nil, registration)
            }
            .onAppear { onVisibilityChange(index, isBelowTop ? title : nil, registration) }
            .onChange(of: title) { _, title in
                onVisibilityChange(index, isBelowTop ? title : nil, registration)
            }
            .onDisappear { onVisibilityChange(index, nil, registration) }
    }
}

@MainActor
@Observable
final class LUIScrollSectionTitleTracker {
    private(set) var title: String?
    // Row visibility must not invalidate LazyVStack while it is calculating layout.
    // Only the separate title emitter observes the derived title.
    @ObservationIgnored private var visibleSections: [Int: (title: String, startsSection: Bool, registration: UUID)] = [:]
    @ObservationIgnored private var headingStates: [String: Bool] = [:]

    func updateHeading(title: String, isPastTop: Bool) {
        guard headingStates[title] != isPastTop else { return }
        headingStates[title] = isPastTop
        deriveTitle()
    }

    func update(index: Int, title: String?, startsSection: Bool = false, registration: UUID) {
        if let title {
            if let previous = visibleSections[index], previous.title == title,
               previous.startsSection == startsSection, previous.registration == registration { return }
            visibleSections[index] = (title, startsSection, registration)
        } else {
            // A replaced row may disappear after its replacement has registered.
            guard visibleSections[index]?.registration == registration else { return }
            visibleSections.removeValue(forKey: index)
        }
        deriveTitle()
    }

    private func deriveTitle() {
        let candidate = visibleSections.min(by: { $0.key < $1.key })?.value
        let next = candidate.flatMap { candidate in
            let past = !candidate.startsSection || headingStates[candidate.title] == true
            return past ? candidate.title : nil
        }
        if title != next { title = next }
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

struct LUIScrollHeadingContext: Sendable {
    let coordinateSpace: LUIScrollTitleCoordinateSpace
    let tracker: LUIScrollSectionTitleTracker
}

private struct LUIScrollHeadingContextKey: EnvironmentKey {
    static let defaultValue: LUIScrollHeadingContext? = nil
}

extension EnvironmentValues {
    var luiScrollHeadingContext: LUIScrollHeadingContext? {
        get { self[LUIScrollHeadingContextKey.self] }
        set { self[LUIScrollHeadingContextKey.self] = newValue }
    }
}

struct LUIScrollHeadingModifier: ViewModifier {
    let title: String
    let enabled: Bool
    @Environment(\.luiScrollHeadingContext) private var context

    @ViewBuilder func body(content: Content) -> some View {
        if enabled, let context {
            content.onGeometryChange(for: Bool.self) { geometry in
                geometry.frame(in: .named(context.coordinateSpace)).maxY <= 0
            } action: { past in
                context.tracker.updateHeading(title: title, isPastTop: past)
            }
        } else { content }
    }
}
