import Foundation

/// Geometry belongs to both a retained model incarnation and a mounted producer.
/// Keep the model alive while callbacks retain the owner, so object identifiers
/// cannot be recycled underneath a delayed callback.
enum LUIFrameModel: Equatable, Sendable {
    case node(LUINodeModel)
    case extensionNode(LUIExtensionNodeModel)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.node(left), .node(right)): left === right
        case let (.extensionNode(left), .extensionNode(right)): left === right
        default: false
        }
    }
}

struct LUIFrameOwner: Equatable, Sendable {
    let nodeID: Int
    let model: LUIFrameModel
    let source: UUID
}

struct LUIFrameSample: Equatable, Sendable {
    let owner: LUIFrameOwner
    let rect: CGRect
}

/// Non-observable storage avoids a SwiftUI update for each geometry sample.
/// Geometry and appearance callbacks can arrive in either order; publish only
/// after the producer mounts, and never reactivate it from a geometry callback.
@MainActor
final class LUIFrameReporter {
    let source = UUID()
    private weak var backend: LUIAppleBackend?
    private var owner: LUIFrameOwner?
    private var representedOwner: LUIFrameOwner?
    private var sample: LUIFrameSample?

    func represent(_ owner: LUIFrameOwner?) {
        representedOwner = owner
    }

    func activate(_ next: LUIFrameOwner?, backend: LUIAppleBackend) {
        guard representedOwner == next else { return }
        guard let next else {
            if let owner { deactivate(owner) }
            return
        }
        guard backend.isCurrentFrameOwner(next) else { return }
        if owner == next, self.backend === backend { return }
        if let owner { deactivate(owner) }
        self.backend = backend
        owner = next
        backend.registerNodeFrame(next)
        if let sample, sample.owner == next {
            backend.reportNodeFrame(sample.owner.nodeID, sample.rect, owner: next)
        }
    }

    func observe(_ sample: LUIFrameSample?) {
        guard let sample, representedOwner == sample.owner else { return }
        self.sample = sample
        guard owner == sample.owner else { return }
        backend?.reportNodeFrame(sample.owner.nodeID, sample.rect, owner: sample.owner)
    }

    func deactivate(_ previous: LUIFrameOwner?) {
        guard let previous, owner == previous else { return }
        backend?.removeNodeFrame(previous.nodeID, owner: previous)
        owner = nil
        if sample?.owner == previous { sample = nil }
        backend = nil
    }
}
