import Foundation
import Observation
import SwiftUI

public enum LUIExtensionValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
}

public enum LUIExtensionValueKind: Sendable {
    case string
    case bool
    case int
    case double

    func accepts(_ value: LUIWireValue) -> Bool {
        switch self {
        case .string:
            if case .string = value { return true }
        case .bool:
            if case .bool = value { return true }
        case .int:
            if case .int = value { return true }
        case .double:
            switch value {
            case .double(let number): return number.isFinite
            case .int: return true
            default: break
            }
        }
        return false
    }

    func normalize(_ value: LUIWireValue) -> LUIWireValue {
        switch self {
        case .double:
            if case .int(let number) = value {
                return .double(Double(number))
            }
        default:
            break
        }
        return value
    }
}

public struct LUIExtensionProperty: Sendable {
    public let name: String
    public let kind: LUIExtensionValueKind
    public let isRequired: Bool
    public let defaultValue: LUIExtensionValue?

    public init(
        name: String,
        kind: LUIExtensionValueKind,
        isRequired: Bool = false,
        defaultValue: LUIExtensionValue? = nil
    ) {
        self.name = name
        self.kind = kind
        self.isRequired = isRequired
        self.defaultValue = defaultValue
    }
}

public struct LUIExtensionEventField: Sendable {
    public let name: String
    public let kind: LUIExtensionValueKind
    public let isRequired: Bool

    public init(name: String, kind: LUIExtensionValueKind, isRequired: Bool = false) {
        self.name = name
        self.kind = kind
        self.isRequired = isRequired
    }
}

public struct LUIExtensionEvent: Sendable {
    public let name: String
    public let fields: [LUIExtensionEventField]

    public init(name: String, fields: [LUIExtensionEventField] = []) {
        self.name = name
        self.fields = fields
    }
}

@MainActor
public struct LUIAppleExtension {
    public typealias ViewFactory = @MainActor (LUIAppleExtensionViewContext) -> AnyView

    public let identifier: String
    public let fingerprint: String
    public let acceptsStandardChildren: Bool
    public let childIdentifiers: [String]
    public let properties: [LUIExtensionProperty]
    public let events: [LUIExtensionEvent]
    let isTweak: Bool
    let viewFactory: ViewFactory

    public init(
        identifier: String,
        fingerprint: String,
        acceptsStandardChildren: Bool = false,
        childIdentifiers: [String] = [],
        properties: [LUIExtensionProperty] = [],
        events: [LUIExtensionEvent] = [],
        viewFactory: @escaping ViewFactory
    ) {
        self.identifier = identifier
        self.fingerprint = fingerprint
        self.acceptsStandardChildren = acceptsStandardChildren
        self.childIdentifiers = childIdentifiers
        self.properties = properties
        self.events = events
        isTweak = false
        self.viewFactory = viewFactory
    }

    init(
        identifier: String,
        fingerprint: String,
        properties: [LUIExtensionProperty],
        isTweak: Bool,
        viewFactory: @escaping ViewFactory
    ) {
        self.identifier = identifier
        self.fingerprint = fingerprint
        acceptsStandardChildren = true
        childIdentifiers = []
        self.properties = properties
        events = []
        self.isTweak = isTweak
        self.viewFactory = viewFactory
    }
}

@MainActor
public struct LUIAppleTweak {
    public typealias Modifier = @MainActor (AnyView, LUIAppleExtensionViewContext) -> AnyView

    public let identifier: String
    public let fingerprint: String
    public let properties: [LUIExtensionProperty]
    let modifier: Modifier

    public init(
        identifier: String,
        fingerprint: String,
        properties: [LUIExtensionProperty] = [],
        modifier: @escaping Modifier
    ) {
        self.identifier = identifier
        self.fingerprint = fingerprint
        self.properties = properties
        self.modifier = modifier
    }
}

@MainActor
public final class LUIAppleExtensionRegistry {
    private(set) var registrations: [String: LUIAppleExtension] = [:]
    private var isFrozen = false

    public init() {}

    public func register(_ registration: LUIAppleExtension) throws {
        guard !isFrozen else { throw invalid("extension registry is frozen") }
        guard Self.isValidName(registration.identifier) else {
            throw invalid("invalid extension identifier")
        }
        guard LUINodeKind(rawValue: registration.identifier) == nil else {
            throw invalid("extension identifier shadows a standard node")
        }
        guard registrations[registration.identifier] == nil else {
            throw invalid("extension identifier is already registered")
        }
        guard registration.childIdentifiers.allSatisfy({ Self.isValidName($0) }) else {
            throw invalid("invalid extension child identifier")
        }
        try Self.validateUniqueNames(
            registration.childIdentifiers,
            label: "child identifier"
        )
        try Self.validateUniqueNames(registration.properties.map({ $0.name }), label: "property")
        try Self.validateUniqueNames(registration.events.map({ $0.name }), label: "event")
        for property in registration.properties {
            guard Self.isValidName(property.name) else {
                throw invalid("invalid extension property name")
            }
            if let value = property.defaultValue {
                guard property.kind.accepts(value.wireValue) else {
                    throw invalid("invalid extension property default")
                }
            }
        }
        for event in registration.events {
            guard Self.isValidName(event.name) else {
                throw invalid("invalid extension event name")
            }
            try Self.validateUniqueNames(event.fields.map({ $0.name }), label: "event field")
            guard event.fields.allSatisfy({ Self.isValidName($0.name) }) else {
                throw invalid("invalid extension event field name")
            }
        }
        registrations[registration.identifier] = registration
    }

    public func registerTweak(_ tweak: LUIAppleTweak) throws {
        let registration = LUIAppleExtension(
            identifier: tweak.identifier,
            fingerprint: tweak.fingerprint,
            properties: tweak.properties,
            isTweak: true
        ) { context in
            tweak.modifier(context.content, context)
        }
        try register(registration)
    }

    static func frozenEmpty() -> LUIAppleExtensionRegistry {
        let registry = LUIAppleExtensionRegistry()
        registry.isFrozen = true
        return registry
    }

    func freeze() throws {
        guard !isFrozen else { return }
        for registration in registrations.values {
            for child in registration.childIdentifiers where registrations[child] == nil {
                throw invalid("unknown extension child schema")
            }
        }
        isFrozen = true
    }

    func registration(_ identifier: String) -> LUIAppleExtension? {
        registrations[identifier]
    }

    private static func validateUniqueNames(_ names: [String], label: String) throws {
        guard Set(names).count == names.count else {
            throw LUIBackendError.invalidBatch("duplicate extension \(label)")
        }
    }

    private static func isValidName(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.split(separator: "-", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { byte in
                let value = Int(byte)
                return (value >= 97 && value <= 122) ||
                    (value >= 48 && value <= 57)
            }
        }
    }

    private func invalid(_ message: String) -> LUIBackendError {
        .invalidBatch(message)
    }
}

@MainActor
public struct LUIAppleExtensionViewContext {
    public let nodeID: Int
    let backend: LUIAppleBackend

    /// Check at action delivery time, including actions that began before a drawer drag.
    /// This does not suppress state updates sent through `emit`.
    public var isUserInteractionEnabled: Bool {
        backend.allowsControlInteraction(node: nodeID)
    }

    public func property(_ name: String) -> LUIExtensionValue? {
        backend.extensionModel(id: nodeID)?.property(name)
    }

    public var childIDs: [Int] {
        backend.extensionModel(id: nodeID)?.children ?? []
    }

    public var content: AnyView {
        guard childIDs.count == 1 else { return AnyView(EmptyView()) }
        return content(for: childIDs[0])
    }

    public func content(for childID: Int) -> AnyView {
        guard childIDs.contains(childID) else { return AnyView(EmptyView()) }
        return backend.anyNodeView(nodeID: childID)
    }

    public func contentRevision(for childID: Int) -> Int? {
        guard childIDs.contains(childID) else { return nil }
        return backend.model(id: childID)?.revision
            ?? backend.extensionModel(id: childID)?.revision
    }

    public func childProperty(node childID: Int, _ name: String) -> LUIExtensionValue? {
        backend.extensionModel(id: childID)?.property(name)
    }

    public func emit(name: String, values: [String: LUIExtensionValue] = [:]) throws {
        try backend.performExtensionEvent(node: nodeID, name: name, values: values)
    }
}

struct LUIExtensionNodeState {
    let identifier: String
    let fingerprint: String
    var parent: Int?
    var children: [Int]
    var properties: [String: LUIWireValue]
}

@Observable
@MainActor
final class LUIExtensionNodeModel: Identifiable {
    let id: Int
    let identifier: String
    let fingerprint: String
    private(set) var parent: Int?
    private(set) var children: [Int]
    private(set) var properties: [String: LUIExtensionValue]
    private(set) var revision = 0

    init(id: Int, state: LUIExtensionNodeState) {
        self.id = id
        identifier = state.identifier
        fingerprint = state.fingerprint
        parent = state.parent
        children = state.children
        properties = state.properties.mapValues({ $0.extensionValue })
    }

    func property(_ name: String) -> LUIExtensionValue? {
        properties[name]
    }

    func apply(state: LUIExtensionNodeState) {
        let nextProperties = state.properties.mapValues({ $0.extensionValue })
        guard parent != state.parent || children != state.children ||
            properties != nextProperties else { return }
        parent = state.parent
        children = state.children
        properties = nextProperties
        revision += 1
    }
}

extension LUIExtensionValue {
    var wireValue: LUIWireValue {
        switch self {
        case let .string(value): .string(value)
        case let .bool(value): .bool(value)
        case let .int(value): .int(value)
        case let .double(value): .double(value)
        }
    }
}

extension LUIWireValue {
    var extensionValue: LUIExtensionValue {
        switch self {
        case let .string(value): .string(value)
        case let .bool(value): .bool(value)
        case let .int(value): .int(value)
        case let .double(value): .double(value)
        }
    }
}
