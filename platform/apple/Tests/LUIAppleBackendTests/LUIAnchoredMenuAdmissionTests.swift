#if os(macOS)
import AppKit
import Testing
@testable import LUIAppleBackend

@MainActor
struct LUIAnchoredMenuAdmissionTests {
    @Test("Only the current native lease can close a retained hosted declaration")
    func declarationLifetime() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"stack"},
          {"op":"create-node","id":2,"kind":"dropdown-menu"},
          {"op":"create-node","id":3,"kind":"dropdown-menu"},
          {"op":"create-node","id":5,"kind":"dropdown-menu"}
        ]}
        """)
        let host = try #require(backend.model(id: 1))
        let rejected = try #require(backend.model(id: 2))
        let menu = try #require(backend.model(id: 3))
        let fresh = try #require(backend.model(id: 5))
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = NSView(frame: .zero)
        window.contentView!.addSubview(view)
        let attachment = LUIAnchoredMenuAttachment(host: host, view: view)
        let store = LUIAnchoredMenuAdmission()
        let hostIsRetained: (LUINodeModel) -> Bool = { backend.model(id: $0.id) === $0 }
        let retained: Set<ObjectIdentifier> = [rejected, menu, fresh].reduce(into: []) {
            $0.insert(ObjectIdentifier($1))
        }
        let first = LUIAnchoredMenuCandidate(host: host, menu: rejected, mode: .popover)
        // Logical admission must sample held before a native host exists.
        store.synchronize([host.id: first], retained: retained, held: true,
                          isHostRetained: hostIsRetained)
        store.attach(attachment, held: false)
        #expect(store.presentation(at: host.id) == nil)
        store.synchronize([:], retained: retained, held: false, isHostRetained: hostIsRetained)
        store.synchronize([host.id: first], retained: retained, held: false,
                          isHostRetained: hostIsRetained)
        #expect(store.presentation(at: host.id) == nil)

        // Retirement permits a genuinely different declaration, not a revision replay.
        let current = LUIAnchoredMenuCandidate(host: host, menu: menu, mode: .popover)
        let surviving: Set<ObjectIdentifier> = [ObjectIdentifier(menu), ObjectIdentifier(fresh)]
        store.synchronize([host.id: current], retained: surviving, held: false,
                          isHostRetained: hostIsRetained)
        let before = try #require(store.presentation(at: host.id))
        store.synchronize([host.id: current], retained: surviving, held: true,
                          isHostRetained: hostIsRetained)
        #expect(store.presentation(at: host.id)?.id == before.id)

        // Mode migration replaces the lease without rejecting an admitted declaration.
        let dialog = LUIAnchoredMenuCandidate(host: host, menu: menu, mode: .dialog)
        store.synchronize([host.id: dialog], retained: surviving, held: true,
                          isHostRetained: hostIsRetained)
        let migrated = try #require(store.presentation(at: host.id))
        #expect(migrated.id != before.id)
        #expect(!store.take(before))
        #expect(store.presentation(at: host.id)?.id == migrated.id)

        // A real reattachment is a new admission and samples physical held again.
        store.detach(attachment)
        #expect(!store.take(migrated))
        let rebound = LUIAnchoredMenuAttachment(host: host, view: view)
        store.attach(rebound, held: true)
        #expect(store.presentation(at: host.id) == nil)
        store.attach(rebound, held: false)
        #expect(store.presentation(at: host.id) == nil)

        let next = LUIAnchoredMenuCandidate(host: host, menu: fresh, mode: .popover)
        store.synchronize([host.id: next], retained: [ObjectIdentifier(fresh)], held: false,
                          isHostRetained: hostIsRetained)
        let oldLease = try #require(store.presentation(at: host.id))
        let replacementView = NSView(frame: .zero)
        window.contentView!.addSubview(replacementView)
        let replacement = LUIAnchoredMenuAttachment(host: host, view: replacementView)
        store.attach(replacement, held: false)
        let lease = try #require(store.presentation(at: host.id))
        store.detach(rebound)
        #expect(!store.take(oldLease))
        #expect(store.presentation(at: host.id)?.id == lease.id)
        #expect(store.take(lease))
        #expect(!store.take(lease))
        store.synchronize([:], retained: [ObjectIdentifier(fresh)], held: false,
                          isHostRetained: hostIsRetained)
        store.synchronize([host.id: next], retained: [ObjectIdentifier(fresh)], held: false,
                          isHostRetained: hostIsRetained)
        #expect(store.presentation(at: host.id) == nil)
        store.detach(replacement)
    }

    @Test("Queued close cannot target a replacement model with the same node ID")
    func deferredCloseOwnership() throws {
        let backend = LUIAppleBackend()
        let initial = """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"stack"},
          {"op":"create-node","id":2,"kind":"dropdown-menu"},
          {"op":"set-prop","id":2,"property":"anchor","value":"below"},
          {"op":"insert-child","parent":1,"child":2,"index":0}
        ]}
        """
        try backend.apply(json: initial)
        let host = try #require(backend.model(id: 1))
        let menu = try #require(backend.model(id: 2))
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = NSView(frame: .zero)
        window.contentView!.addSubview(view)
        backend.anchoredMenus.attach(LUIAnchoredMenuAttachment(host: host, view: view), held: false)
        let lease = try #require(backend.anchoredMenuPresentation(host: host))
        var dismissed: [Int] = []
        backend.onEvent = { if case .dismiss(let node) = $0 { dismissed.append(node) } }
        var replacementError: Error?
        backend.withDeferredEventDelivery {
            backend.dismissAnchoredMenu(lease)
            do { try backend.applySnapshot(json: initial) }
            catch { replacementError = error }
        }
        if let replacementError { throw replacementError }
        #expect(backend.model(id: 2) !== menu)
        #expect(dismissed.isEmpty)

        let nextHost = try #require(backend.model(id: 1))
        backend.anchoredMenus.attach(LUIAnchoredMenuAttachment(host: nextHost, view: view), held: false)
        let current = try #require(backend.anchoredMenuPresentation(host: nextHost))
        backend.dismissAnchoredMenu(current)
        #expect(dismissed == [2])
    }
}
#endif
