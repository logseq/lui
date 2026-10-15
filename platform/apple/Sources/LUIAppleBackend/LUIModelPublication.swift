import Observation

struct LUIModelChanges: OptionSet {
    let rawValue: UInt8
    static let properties = Self(rawValue: 1 << 0)
    static let children = Self(rawValue: 1 << 1)
    static let childData = Self(rawValue: 1 << 2)
    static let parent = Self(rawValue: 1 << 3)
    static let derived = Self(rawValue: 1 << 4)
    static let subtreeStamp = Self(rawValue: 1 << 5)
    /// Marked by the stage that actually increments `revision`, so publish
    /// only notifies revision readers on real bumps — `.childData` and
    /// `.subtreeStamp` commits invalidate through their own key paths
    /// without touching the revision gate.
    static let revision = Self(rawValue: 1 << 6)
}

/// Tracks lookup membership per ID, including reads of nodes not yet present.
/// Subscript key paths carry the ID without retaining a token for every lookup.
@Observable
@MainActor
final class LUIModelLookupObservation {
    subscript(id: Int) -> Bool {
        access(keyPath: \.[id])
        return true
    }

    func publish(id: Int) {
        withMutation(keyPath: \.[id]) {}
    }
}
