import Foundation
import Testing
@testable import LUIAppleBackend

@MainActor
struct LUIAnchoredPopoverLifecycleTests {
    @Test("Dismissed and held-rejected declarations cannot replay before retirement")
    func declarationLifetime() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"box"},
          {"op":"create-node","id":2,"kind":"popover"},
          {"op":"set-prop","id":2,"property":"anchor","value":"below"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"create-node","id":3,"kind":"popover"},
          {"op":"set-prop","id":3,"property":"anchor","value":"below"},
          {"op":"create-node","id":4,"kind":"box"},
          {"op":"create-node","id":5,"kind":"popover"},
          {"op":"set-prop","id":5,"property":"anchor","value":"below"}
        ]}
        """)
        let anchor = try #require(backend.model(id: 1))
        let model = try #require(backend.model(id: 2))
        let item = LUIAnchoredPopoverPresentation(
            model: model, anchorID: 1, anchorIdentity: ObjectIdentifier(anchor), anchorRect: nil)
        let retained: Set<ObjectIdentifier> = [item.id]
        let store = LUIAnchoredPopoverStore()
        store.synchronize([1: item], retained: retained, held: false)
        let moved = LUIAnchoredPopoverPresentation(model: model, anchorID: 1,
            anchorIdentity: item.anchorIdentity, anchorRect: CGRect(x: 10, y: 20, width: 30, height: 40))
        store.synchronize([1: moved], retained: retained, held: true)
        #expect(store.presentation(at: 1) == moved)
        // A setter captured before the geometry update still closes its declaration.
        #expect(store.dismiss(item))
        store.synchronize([:], retained: retained, held: false)
        store.synchronize([1: moved], retained: retained, held: false)
        #expect(store.presentation(at: 1) == nil)

        let replacement = LUIAnchoredPopoverPresentation(model: try #require(backend.model(id: 3)),
            anchorID: 1, anchorIdentity: item.anchorIdentity, anchorRect: nil)
        let both: Set<ObjectIdentifier> = [item.id, replacement.id]
        store.synchronize([1: replacement], retained: both, held: false)
        #expect(!store.dismiss(item))
        #expect(store.presentation(at: 1) == replacement)

        let rebound = LUIAnchoredPopoverPresentation(model: replacement.model, anchorID: 4,
            anchorIdentity: ObjectIdentifier(try #require(backend.model(id: 4))), anchorRect: nil)
        store.synchronize([4: rebound], retained: both, held: true)
        #expect(store.presentation(at: 4) == nil)
        store.synchronize([4: rebound], retained: both, held: false)
        #expect(store.presentation(at: 4) == nil)
        #expect(!store.dismiss(replacement))

        store.synchronize([:], retained: [], held: false)
        let fresh = LUIAnchoredPopoverPresentation(model: try #require(backend.model(id: 5)),
            anchorID: 4, anchorIdentity: rebound.anchorIdentity, anchorRect: nil)
        store.synchronize([4: fresh], retained: [fresh.id], held: false)
        #expect(store.presentation(at: 4) == fresh)
    }
}
