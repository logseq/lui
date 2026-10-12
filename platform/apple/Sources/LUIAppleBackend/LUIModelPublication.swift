import Observation

struct LUIModelChanges: OptionSet {
    let rawValue: UInt8
    static let properties = Self(rawValue: 1 << 0)
    static let children = Self(rawValue: 1 << 1)
    static let visibleChildren = Self(rawValue: 1 << 2)
    static let parent = Self(rawValue: 1 << 3)
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
