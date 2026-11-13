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
    /// Request focus for a focusable control, including one awaiting mount.
    /// Text inputs are focusable on both platforms; `searchField` focus and
    /// ownership require iOS 18 or later on iOS. On macOS `button` and
    /// `menuItem` also qualify. True means accepted, not that native focus
    /// has completed. The latest request wins and is consumed once by the
    /// original retained node.
    @discardableResult
    func requestFocus(nodeID: Int) -> Bool {
        var accepted = false
        withDeferredEventDelivery {
            // Classify the accepted retained tree, including a newly created
            // input whose observable commit is still waiting to coalesce.
            flushPendingCommit()
            guard let model = model(id: nodeID), isFocusTarget(model) else { return }
            hostFocus.request = .init(model: model)
            accepted = true
        }
        return accepted
    }

    /// The currently focused control — a text input, or on macOS a
    /// `button`/`menuItem` — or nil when another native control holds focus.
    /// Search-field ownership on iOS requires iOS 18 or later.
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
        case .textField, .secureField, .input, .textarea: return true
        case .searchField:
            #if os(iOS)
            // Search activation on iOS 17 does not identify keyboard focus.
            if #unavailable(iOS 18.0) { return false }
            #endif
            return true
        default: return false
        }
    }

    #if os(macOS)
    private func isFocusableGenericControl(_ model: LUINodeModel) -> Bool {
        guard model.isEnabled else { return false }
        switch model.kind {
        case .button, .menuItem: return true
        default: return false
        }
    }
    #endif

    func isFocusTarget(_ model: LUINodeModel) -> Bool {
        if isFocusableTextInput(model) { return true }
        #if os(macOS)
        if isFocusableGenericControl(model) { return true }
        #endif
        return false
    }

    func focusRequestToken(for model: LUINodeModel) -> UUID? {
        guard hostFocus.request?.model === model, self.model(id: model.id) === model else { return nil }
        return hostFocus.request?.token
    }

    func consumeFocusRequest(_ token: UUID, for model: LUINodeModel) -> Bool {
        guard focusRequestToken(for: model) == token else { return false }
        hostFocus.request = nil
        return isFocusTarget(model)
    }

    func controlFocusChanged(model: LUINodeModel, mount: UUID, focused: Bool) {
        if focused {
            guard isFocusTarget(model), self.model(id: model.id) === model else { return }
            hostFocus.owner = .init(model: model, mount: mount)
        } else if hostFocus.owner?.mount == mount {
            hostFocus.owner = nil
        }
    }
}
