import Foundation
import Observation
import Testing
@testable import LUIAppleBackend

private final class Changes: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@MainActor
@Suite("Host query observation")
struct LUIHostQueryMembershipTests {
    @Test("Activation and retirement invalidate only the requested node")
    func nodeScopedMembership() {
        let queries = LUIHostQueryMembership()
        let activation = Changes()
        withObservationTracking {
            #expect(!queries.contains(1))
        } onChange: { activation.record() }
        queries.insert(2)
        #expect(activation.value == 0, "An unrelated query invalidated node 1")
        queries.insert(1)
        #expect(activation.value == 1 && queries.contains(1), "Activation did not notify its node")

        let removal = Changes()
        withObservationTracking {
            #expect(queries.contains(1))
        } onChange: { removal.record() }
        queries.insert(1)
        queries.remove(2)
        queries.remove(2)
        #expect(removal.value == 0, "Unrelated removal or a no-op invalidated node 1")
        queries.remove(1)
        #expect(removal.value == 1 && !queries.contains(1), "Removal did not notify its node")
    }
}
