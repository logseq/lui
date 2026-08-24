import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class LUINodeModel: Identifiable {
    let id: Int
    let kind: LUINodeKind

    @ObservationIgnored private(set) var properties: [LUIProperty: LUIWireValue]
    @ObservationIgnored private(set) var children: [Int]
    private(set) var revision = 0

    init(id: Int, state: LUINodeState) {
        self.id = id
        kind = state.kind
        properties = state.properties
        children = state.children
    }

    func property(_ property: LUIProperty) -> LUIWireValue? {
        properties[property]
    }

    func apply(state: LUINodeState) {
        guard properties != state.properties || children != state.children else {
            return
        }
        properties = state.properties
        children = state.children
        revision += 1
    }

    var text: String {
        properties[.text]?.stringValue ?? ""
    }

    var isEnabled: Bool {
        properties[.enabled]?.boolValue ?? true
    }

    var isReadOnly: Bool {
        properties[.readOnly]?.boolValue ?? false
    }

    var isChecked: Bool {
        properties[.checked]?.boolValue ?? false
    }

    var isIndeterminate: Bool {
        properties[.indeterminate]?.boolValue ?? false
    }

    var isInvalid: Bool {
        properties[.invalid]?.boolValue ?? false
    }

    var surfaceWidth: Int? { properties[.width]?.intValue }
    var surfaceHeight: Int? { properties[.height]?.intValue }
    var surfaceMinWidth: Int? { properties[.minWidth]?.intValue }
    var surfaceMaxWidth: Int? { properties[.maxWidth]?.intValue }
    var surfaceMinHeight: Int? { properties[.minHeight]?.intValue }
    var surfaceMaxHeight: Int? { properties[.maxHeight]?.intValue }

    var progressFraction: Double {
        let minimum = properties[.minValue]?.intValue ?? 0
        let maximum = properties[.maxValue]?.intValue ?? 100
        let value = properties[.progressValue]?.intValue ?? minimum
        let clamped = min(max(value, minimum), maximum)
        return Double(clamped - minimum) / Double(maximum - minimum)
    }

    func accessibilityLabel(in backend: LUIAppleBackend) -> String? {
        if let explicit = properties[.accessibilityLabel]?.stringValue {
            return explicit
        }
        guard let label = properties[.labelledBy]?.intValue else { return nil }
        return backend.model(id: label)?.text
    }

    func accessibilityHint(in backend: LUIAppleBackend) -> String? {
        let description = properties[.describedBy]?.intValue
            .flatMap { backend.model(id: $0)?.text }
        let error = isInvalid
            ? properties[.errorMessageBy]?.intValue
                .flatMap { backend.model(id: $0)?.text }
            : nil
        let combined = [description, error].compactMap { $0 }.joined(separator: " ")
        return combined.isEmpty ? nil : combined
    }
}

@MainActor
public final class LUIAppleBackend {
    public private(set) var generation = 0
    public var onEvent: ((LUIEvent) -> Void)?

    private var tree = LUIRetainedTree()
    private var models: [Int: LUINodeModel] = [:]
    private let decoder = JSONDecoder()

    public init() {}

    public var rootIDs: [Int] {
        tree.rootIDs.sorted()
    }

    func model(id: Int) -> LUINodeModel? {
        models[id]
    }

    public func apply(json: String) throws {
        guard let data = json.data(using: .utf8) else {
            throw invalid("patch batch is not UTF-8")
        }
        let batch: LUIPatchBatch
        do {
            batch = try decoder.decode(LUIPatchBatch.self, from: data)
        } catch let error as LUIBackendError {
            throw error
        } catch {
            throw invalid(error.localizedDescription)
        }

        let expectedGeneration = generation + 1
        guard batch.generation == expectedGeneration else {
            throw invalid(
                "expected patch generation \(expectedGeneration), received \(batch.generation)"
            )
        }

        let nextTree = try tree.applying(batch.ops)
        withTransaction(Transaction(animation: nil)) {
            commit(nextTree)
        }
        tree = nextTree
        generation = batch.generation
    }

    func performPress(node: Int) throws {
        guard let model = models[node], model.kind == .button, model.isEnabled else {
            throw invalid("node \(node) is not an enabled button")
        }
        onEvent?(.press(node: node))
    }

    func performTextChange(node: Int, text: String) throws {
        guard let model = models[node],
              model.kind == .textInput || model.kind == .textArea,
              model.isEnabled, !model.isReadOnly else {
            throw invalid("node \(node) is not an editable text control")
        }
        onEvent?(.textChanged(node: node, text: text))
    }

    func performToggle(node: Int, checked: Bool) throws {
        guard let model = models[node],
              model.kind == .checkbox || model.kind == .switchControl,
              model.isEnabled else {
            throw invalid("node \(node) is not an enabled toggle")
        }
        onEvent?(.toggleChanged(node: node, checked: checked))
    }

    func performAction(node: Int) throws {
        guard let model = models[node] else { throw invalid("unknown node") }
        switch model.kind {
        case .button:
            try performPress(node: node)
        case .checkbox, .switchControl:
            try performToggle(node: node, checked: model.isIndeterminate || !model.isChecked)
        default:
            throw invalid("node \(node) has no action")
        }
    }

    private func commit(_ nextTree: LUIRetainedTree) {
        for id in Array(models.keys) where nextTree.nodes[id] == nil {
            models[id] = nil
        }
        for (id, state) in nextTree.nodes {
            if let model = models[id] {
                model.apply(state: state)
            } else {
                models[id] = LUINodeModel(id: id, state: state)
            }
        }
    }

    private func invalid(_ message: String) -> LUIBackendError {
        .invalidBatch(message)
    }
}
