import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Apple registrations for Lui.Navigation.navigation_stack. Business routes
/// stay in OCaml; only process-local entry IDs and revisions cross the bridge.
@MainActor
public enum LUINavigation {
    static let stackFingerprint = "lui-extension-v1|16:navigation-stack|profiles:ios/swiftui,macos/swiftui|standard-children:0|children:15:navigation-page|properties:4:path:string:required:none,8:revision:int:required:none|events:12:path-changed[6:length:int:required,8:revision:int:required],7:settled[6:length:int:required,8:revision:int:required]"
    static let pageFingerprint = "lui-extension-v1|15:navigation-page|profiles:ios/swiftui,macos/swiftui|standard-children:1|children:|properties:8:entry-id:string:required:none|events:"

    public static func register(in registry: LUIAppleExtensionRegistry) throws {
        let fields = [
            LUIExtensionEventField(name: "revision", kind: .int, isRequired: true),
            LUIExtensionEventField(name: "length", kind: .int, isRequired: true),
        ]
        try registry.register(LUIAppleExtension(
            identifier: "navigation-stack", fingerprint: stackFingerprint,
            childIdentifiers: ["navigation-page"],
            properties: [
                LUIExtensionProperty(name: "path", kind: .string, isRequired: true),
                LUIExtensionProperty(name: "revision", kind: .int, isRequired: true),
            ],
            events: [
                LUIExtensionEvent(name: "path-changed", fields: fields),
                LUIExtensionEvent(name: "settled", fields: fields),
            ],
            viewFactory: { AnyView(LUINavigationStackView(context: $0)) }
        ))
        try registry.register(LUIAppleExtension(
            identifier: "navigation-page", fingerprint: pageFingerprint,
            acceptsStandardChildren: true,
            properties: [LUIExtensionProperty(name: "entry-id", kind: .string, isRequired: true)],
            viewFactory: { $0.content }
        ))
    }
}

/// One controlled path proposal may be in flight. Token/revision checks make
/// a cancelled or superseded UIKit transition harmless, including synchronous
/// OCaml writes made inside event delivery.
@MainActor
@Observable
final class LUINavigationState {
    private(set) var path: [String] = []
    private(set) var revision = 0
    private var authoritative: [String] = []
    private var sequence = 0
    private var pending: (token: Int, revision: Int, length: Int)?

    func apply(path: [String], revision: Int) {
        guard revision != self.revision else { return }
        pending = nil
        self.revision = revision
        authoritative = path
        self.path = path
    }

    func propose(_ path: [String]) -> Int? {
        guard pending == nil, path.count < authoritative.count,
              Array(authoritative.prefix(path.count)) == path else { return nil }
        sequence += 1
        pending = (sequence, revision, path.count)
        self.path = path
        return sequence
    }

    @discardableResult
    func complete(_ token: Int, cancelled: Bool, emit: (Int, Int) -> Void) -> Bool {
        guard let proposal = pending, proposal.token == token,
              proposal.revision == revision else { return false }
        pending = nil
        if cancelled {
            path = authoritative
        } else {
            // Clear pending before calling out; the owner may apply a new
            // authoritative revision from inside this synchronous callback.
            emit(proposal.revision, proposal.length)
        }
        return true
    }
}

private struct LUINavigationSnapshot: Equatable {
    var path: [String]
    var revision: Int
    @MainActor init(_ context: LUIAppleExtensionViewContext) {
        path = (context.property("path")?.wireValue.stringValue ?? "")
            .split(separator: ",").map(String.init)
        revision = context.property("revision")?.wireValue.intValue ?? 0
    }
}

@MainActor
private struct LUINavigationStackView: View {
    let context: LUIAppleExtensionViewContext
    @State private var state: LUINavigationState
    @State private var settledRevision: Int?
    #if canImport(UIKit)
    @State private var transitions = LUINavigationTransitions()
    #endif

    init(context: LUIAppleExtensionViewContext) {
        self.context = context
        let snapshot = LUINavigationSnapshot(context)
        let initial = LUINavigationState()
        initial.apply(path: snapshot.path, revision: snapshot.revision)
        _state = State(initialValue: initial)
    }

    private var snapshot: LUINavigationSnapshot { LUINavigationSnapshot(context) }
    private var pages: [String: Int] {
        Dictionary(uniqueKeysWithValues: context.childIDs.compactMap { child in
            context.childProperty(node: child, "entry-id")?.wireValue.stringValue.map { ($0, child) }
        })
    }

    var body: some View {
        NavigationStack(path: Binding(get: { state.path }, set: { propose($0) })) {
            page("root")
                .navigationDestination(for: String.self) { id in page(id) }
        }
        .onChange(of: snapshot) { _, next in
            #if canImport(UIKit)
            state.apply(path: next.path, revision: next.revision)
            #else
            withAnimation(.default, completionCriteria: .removed) {
                state.apply(path: next.path, revision: next.revision)
            } completion: {
                settle(page: next.path.last ?? "root", revision: next.revision)
            }
            #endif
        }
    }

    @ViewBuilder private func page(_ id: String) -> some View {
        let pageRevision = snapshot.revision
        if let node = pages[id] {
            context.content(for: node)
                .id(id)
                #if canImport(UIKit)
                .background(LUINavigationTransitionProbe(
                    transitions: transitions, pageID: id,
                    didSettle: { settle(page: id, revision: pageRevision) }
                ).frame(width: 0, height: 0))
                #endif
        }
    }

    private func propose(_ path: [String]) {
        guard context.isUserInteractionEnabled else { return }
        #if canImport(UIKit)
        guard let token = state.propose(path) else { return }
        transitions.afterTransition(to: path.last ?? "root") { cancelled in
            complete(token, cancelled: cancelled, candidate: path)
        }
        #else
        // macOS has no interactive edge swipe. Associate the path mutation
        // with SwiftUI's animation transaction and its removal completion.
        var token: Int?
        withAnimation(.default, completionCriteria: .removed) {
            token = state.propose(path)
        } completion: {
            if let token { complete(token, cancelled: false, candidate: path) }
        }
        #endif
    }

    private func complete(_ token: Int, cancelled: Bool, candidate: [String]) {
        let completed = state.complete(token, cancelled: cancelled) { revision, length in
            do {
                try context.emit(name: "path-changed", values: [
                    "revision": .int(revision), "length": .int(length),
                ])
                // The native bridge can synchronously flush an OCaml reply.
                // Apply the latest reply, never a captured authoritative path.
                let latest = snapshot
                state.apply(path: latest.path, revision: latest.revision)
            } catch {
                // Owner teardown may race a native animation completion.
            }
        }
        guard completed, !cancelled else { return }
        let latest = snapshot
        // A synchronous owner replacement may start another transition. Only
        // the actually revealed page can confirm this completed transition.
        settle(page: candidate.last ?? "root", revision: latest.revision)
    }

    private func settle(page: String, revision: Int) {
        let latest = snapshot
        guard settledRevision != revision, latest.revision == revision, state.revision == revision,
              state.path == latest.path, page == (latest.path.last ?? "root") else { return }
        settledRevision = revision
        do {
            try context.emit(name: "settled", values: [
                "revision": .int(revision), "length": .int(latest.path.count),
            ])
        } catch {
            // Owner teardown may race a native animation completion.
        }
    }
}

#if canImport(UIKit)
/// Observe the enclosing native transition without replacing SwiftUI's
/// UINavigationController delegate. onDisappear never owns LUI disposal.
@MainActor
private final class LUINavigationTransitions {
    weak var controller: LUINavigationTransitionProbe.ProbeController?
    private var awaitingAppearance: (page: String, complete: (Bool) -> Void)?

    func afterTransition(to page: String, _ completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let coordinator = self.controller?.transitionCoordinator {
                if coordinator.animate(alongsideTransition: nil, completion: {
                    completion($0.isCancelled)
                }) { return }
            }
            // Binding writes can precede UIKit installing its coordinator.
            // A real appearance, rather than a timer, completes that case.
            if let controller = self.controller,
               controller.hasAppeared, controller.pageID == page {
                // SwiftUI may write its Binding after UIKit has completed.
                completion(false)
            } else {
                self.awaitingAppearance = (page, completion)
            }
        }
    }

    func appeared(page: String) {
        let pending = awaitingAppearance
        awaitingAppearance = nil
        if let pending { pending.complete(page != pending.page) }
    }
}

@MainActor
private struct LUINavigationTransitionProbe: UIViewControllerRepresentable {
    let transitions: LUINavigationTransitions
    let pageID: String
    let didSettle: () -> Void

    func makeUIViewController(context: Context) -> ProbeController {
        let controller = ProbeController()
        controller.transitions = transitions
        controller.pageID = pageID
        controller.didSettle = didSettle
        return controller
    }
    func updateUIViewController(_ controller: ProbeController, context: Context) {
        controller.didSettle = didSettle
        controller.pageID = pageID
        if controller.hasAppeared { transitions.controller = controller }
        if controller.hasAppeared {
            let completion = controller.didSettle
            if let coordinator = controller.transitionCoordinator {
                _ = coordinator.animate(alongsideTransition: nil) { result in
                    if !result.isCancelled { completion?() }
                }
            } else {
                DispatchQueue.main.async {
                    guard controller.hasAppeared, controller.transitionCoordinator == nil else { return }
                    completion?()
                }
            }
        }
    }
    final class ProbeController: UIViewController {
        weak var transitions: LUINavigationTransitions?
        var didSettle: (() -> Void)?
        var hasAppeared = false
        var pageID = "root"
        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            transitions?.controller = self
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hasAppeared = true
            transitions?.controller = self
            transitions?.appeared(page: pageID)
            didSettle?()
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            hasAppeared = false
        }
    }
}
#endif
