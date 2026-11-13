import Foundation
import Observation

@MainActor
@Observable
final class LUIHostFocusState {
    struct Request {
        weak var model: LUINodeModel?
        let token = UUID()
    }

    struct Owner {
        weak var model: LUINodeModel?
        let mount: UUID
    }

    var request: Request?
    var owner: Owner?

    func drop(nodeID: Int) {
        if request?.model?.id == nodeID { request = nil }
        if owner?.model?.id == nodeID { owner = nil }
    }
}

public extension LUIAppleBackend {
    /// Request focus for a standard text input, including one awaiting mount.
    /// True means accepted, not that native focus has completed. The latest
    /// request wins and is consumed once by the original retained node.
    @discardableResult
    func requestFocus(nodeID: Int) -> Bool {
        var accepted = false
        withDeferredEventDelivery {
            // Classify the accepted retained tree, including a newly created
            // input whose observable commit is still waiting to coalesce.
            flushPendingCommit()
            guard let model = model(id: nodeID), isFocusableTextInput(model) else { return }
            hostFocus.request = .init(model: model)
            accepted = true
        }
        return accepted
    }

    /// The focused standard text input, or nil for another native control.
    /// Dropped/replaced node identities are never returned.
    var focusedNodeID: Int? {
        guard let focused = hostFocus.owner?.model, model(id: focused.id) === focused else { return nil }
        return focused.id
    }
}

extension LUIAppleBackend {
    private func isFocusableTextInput(_ model: LUINodeModel) -> Bool {
        guard model.isEnabled else { return false }
        switch model.kind {
        case .textField, .secureField, .input, .searchField, .textarea: return true
        default: return false
        }
    }

    func focusRequestToken(for model: LUINodeModel) -> UUID? {
        guard hostFocus.request?.model === model, self.model(id: model.id) === model else { return nil }
        return hostFocus.request?.token
    }

    func consumeFocusRequest(_ token: UUID, for model: LUINodeModel) -> Bool {
        guard focusRequestToken(for: model) == token else { return false }
        hostFocus.request = nil
        return isFocusableTextInput(model)
    }

    func textInputFocusChanged(model: LUINodeModel, mount: UUID, focused: Bool) {
        if focused {
            guard self.model(id: model.id) === model else { return }
            hostFocus.owner = .init(model: model, mount: mount)
        } else if hostFocus.owner?.mount == mount {
            hostFocus.owner = nil
        }
    }
}
