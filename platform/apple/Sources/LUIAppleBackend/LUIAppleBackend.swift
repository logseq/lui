import Foundation
import Observation
import SwiftUI

public enum LUIAppleIconSource: Equatable, Sendable {
    case systemName(String)
    case assetName(String)
}

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

    var isChecked: Bool {
        properties[.checked]?.boolValue ?? false
    }

    var isSelected: Bool { properties[.selected]?.boolValue ?? false }
    var requestsAutofocus: Bool { properties[.autofocus]?.boolValue ?? false }
    var supportsHold: Bool { properties[.holdEnabled]?.boolValue ?? false }
    var supportsChange: Bool { properties[.changeEnabled]?.boolValue ?? false }
    var supportsToggle: Bool { properties[.toggleEnabled]?.boolValue ?? false }
    var supportsPress: Bool { properties[.pressEnabled]?.boolValue ?? false }
    var supportsSubmit: Bool { properties[.submitEnabled]?.boolValue ?? false }
    var sliderValue: Double { properties[.progressValue]?.doubleValue ?? 0 }
    var buttonVariant: String { properties[.variant]?.stringValue ?? "default" }
    var buttonSize: String { properties[.size]?.stringValue ?? "default" }
    var buttonIconName: String { properties[.icon]?.stringValue ?? "" }
    var buttonIconPlacement: String {
        properties[.iconPlacement]?.stringValue ?? "leading"
    }

    var surfaceWidth: Int? { properties[.width]?.intValue }
    var surfaceHeight: Int? { properties[.height]?.intValue }
    var surfaceMinWidth: Int? { properties[.minWidth]?.intValue }
    var surfaceMaxWidth: Int? { properties[.maxWidth]?.intValue }
    var surfaceMinHeight: Int? { properties[.minHeight]?.intValue }
    var surfaceMaxHeight: Int? { properties[.maxHeight]?.intValue }

    var spinnerExtent: Int {
        switch properties[.size]?.stringValue ?? "default" {
        case "sm": 16
        case "lg": 24
        default: 20
        }
    }

    var spinnerWidth: Int { surfaceWidth ?? spinnerExtent }
    var spinnerHeight: Int { surfaceHeight ?? spinnerExtent }

    var spinnerControlSize: ControlSize {
        switch properties[.size]?.stringValue ?? "default" {
        case "sm": .small
        case "lg": .large
        default: .regular
        }
    }

    var iconExtent: Int {
        switch properties[.size]?.stringValue ?? "default" {
        case "sm": 16
        case "lg": 24
        default: 18
        }
    }

    var iconWidth: Int { surfaceWidth ?? iconExtent }
    var iconHeight: Int { surfaceHeight ?? iconExtent }

    var iconName: String { properties[.name]?.stringValue ?? "" }

    var iconSystemName: String {
        Self.systemIconName(for: iconName)
    }

    static func systemIconName(for name: String) -> String {
        switch name {
        case "alert": "exclamationmark.triangle"
        case "archive": "archivebox"
        case "arrow-down": "arrow.down"
        case "arrow-right": "arrow.right"
        case "arrow-up": "arrow.up"
        case "check": "checkmark"
        case "check-circle": "checkmark.circle"
        case "chevron-down": "chevron.down"
        case "chevron-left": "chevron.left"
        case "chevron-right": "chevron.right"
        case "chevron-up": "chevron.up"
        case "circle-dot": "circle.circle"
        case "clock": "clock"
        case "copy": "doc.on.doc"
        case "download": "arrow.down.to.line"
        case "edit": "pencil"
        case "ellipsis": "ellipsis"
        case "external-link": "arrow.up.right.square"
        case "eye": "eye"
        case "file-text": "doc.text"
        case "folder": "folder"
        case "folder-open": "folder.fill"
        case "git-branch": "arrow.triangle.branch"
        case "git-merge": "arrow.triangle.merge"
        case "git-pull-request": "arrow.triangle.pull"
        case "info": "info.circle"
        case "menu": "line.3.horizontal"
        case "mic": "mic"
        case "moon": "moon"
        case "music": "music.note"
        case "panel-left": "sidebar.left"
        case "panel-right": "sidebar.right"
        case "pause": "pause"
        case "play": "play"
        case "plus": "plus"
        case "refresh-cw": "arrow.clockwise"
        case "repeat": "repeat"
        case "save": "square.and.arrow.down"
        case "search": "magnifyingglass"
        case "send": "paperplane"
        case "settings": "gearshape"
        case "shuffle": "shuffle"
        case "skip-back": "backward.end"
        case "skip-forward": "forward.end"
        case "sun": "sun.max"
        case "terminal": "terminal"
        case "trash": "trash"
        case "volume": "speaker.wave.2"
        case "wrench": "wrench"
        case "x": "xmark"
        case "x-circle": "xmark.circle"
        default: "questionmark.square.dashed"
        }
    }

    var progressFraction: Double {
        min(max(properties[.progressValue]?.doubleValue ?? 0, 0), 1)
    }

    func accessibilityLabel(in backend: LUIAppleBackend) -> String? {
        properties[.accessibilityLabel]?.stringValue
    }

    func accessibilityHint(in backend: LUIAppleBackend) -> String? { nil }
}

@MainActor
public final class LUIAppleBackend {
    public private(set) var generation = 0
    public var onEvent: ((LUIEvent) -> Void)?

    private var tree = LUIRetainedTree()
    private var models: [Int: LUINodeModel] = [:]
    private let decoder = JSONDecoder()
    private let appIcons: [String: LUIAppleIconSource]

    public init(appIcons: [String: LUIAppleIconSource] = [:]) {
        self.appIcons = appIcons
    }

    func iconSource(for name: String) -> LUIAppleIconSource {
        if name.hasPrefix("app:") {
            return appIcons[String(name.dropFirst(4))]
                ?? .systemName("questionmark.square.dashed")
        }
        return .systemName(LUINodeModel.systemIconName(for: name))
    }

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
        guard let model = models[node],
              model.kind == .button || model.kind == .select ||
                model.kind == .combobox || model.kind == .menuItem,
              model.isEnabled else {
            throw invalid("node \(node) is not an enabled pressable control")
        }
        onEvent?(.press(node: node))
    }

    func performHold(node: Int) throws {
        guard let model = models[node],
              model.kind == .button || model.kind == .toggleButton,
              model.isEnabled, model.supportsHold else {
            throw invalid("node \(node) is not an enabled holdable button")
        }
        onEvent?(.hold(node: node))
    }

    func performTextChange(node: Int, text: String) throws {
        guard let model = models[node],
              Self.isTextEntry(model.kind), model.isEnabled else {
            throw invalid("node \(node) is not an editable text control")
        }
        onEvent?(.textChanged(node: node, text: text))
    }

    func performSubmit(node: Int) throws {
        guard let model = models[node], Self.isTextEntry(model.kind), model.isEnabled else {
            throw invalid("node \(node) is not an enabled text control")
        }
        onEvent?(.submit(node: node))
    }

    func performToggle(node: Int, checked: Bool) throws {
        guard let model = models[node],
              model.kind == .toggleButton || model.kind == .checkbox ||
                model.kind == .switchControl || model.kind == .toggle,
              model.isEnabled else {
            throw invalid("node \(node) is not an enabled toggle")
        }
        onEvent?(.toggleChanged(node: node, checked: checked))
    }

    func performChange(node: Int) throws {
        guard let model = models[node], model.kind == .radio, model.isEnabled else {
            throw invalid("node \(node) is not an enabled radio")
        }
        if model.supportsChange {
            if !model.isChecked { onEvent?(.change(node: node)) }
        } else if model.supportsToggle {
            onEvent?(.toggleChanged(node: node, checked: true))
        } else if model.supportsPress {
            onEvent?(.press(node: node))
        }
    }

    func performValueChange(node: Int, value: Double) throws {
        guard let model = models[node], model.kind == .slider, model.isEnabled,
              value.isFinite else {
            throw invalid("node \(node) is not an enabled slider")
        }
        onEvent?(.valueChanged(node: node, value: min(max(value, 0), 1)))
    }

    func performDismiss(node: Int) throws {
        guard let model = models[node],
              model.kind == .select || model.kind == .combobox ||
                model.kind == .dropdownMenu else {
            throw invalid("node \(node) is not dismissible")
        }
        onEvent?(.dismiss(node: node))
    }

    func performAction(node: Int) throws {
        guard let model = models[node] else { throw invalid("unknown node") }
        switch model.kind {
        case .button, .select, .combobox, .menuItem:
            try performPress(node: node)
        case .toggleButton:
            try performToggle(node: node, checked: !model.isSelected)
        case .checkbox, .switchControl, .toggle:
            try performToggle(node: node, checked: !model.isChecked)
        case .radio:
            try performChange(node: node)
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

    private static func isTextEntry(_ kind: LUINodeKind) -> Bool {
        kind == .textField || kind == .input || kind == .searchField || kind == .textarea ||
            kind == .combobox
    }
}
