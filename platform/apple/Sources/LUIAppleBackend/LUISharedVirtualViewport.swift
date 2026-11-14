import Foundation
import SwiftUI
#if os(macOS)
import AppKit
public typealias LUIVirtualNativeView = NSView
#else
import UIKit
public typealias LUIVirtualNativeView = UIView
#endif

/// Evidence required for a cold-key to physical-ownership transfer.
public struct LUIVirtualHandoffRequirements: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let attached = Self(rawValue: 1)
    public static let visible = Self(rawValue: 2)
    public static let focus = Self(rawValue: 4)
}

/// An exact native-control incarnation. Dispose it when the control is reused
/// for another retained node or dismantled. It never keeps the view alive.
@MainActor
public final class LUIVirtualNativeRegistration {
    weak var view: LUIVirtualNativeView?
    weak var model: LUINodeModel?
    weak var extensionModel: LUIExtensionNodeModel?
    var nodeID: Int? { model?.id ?? extensionModel?.id }
    let incarnation: Int
    init(view: LUIVirtualNativeView, model: LUINodeModel, incarnation: Int) {
        self.view = view
        self.model = model
        self.incarnation = incarnation
    }
    init(view: LUIVirtualNativeView, model: LUIExtensionNodeModel, incarnation: Int) {
        self.view = view
        self.extensionModel = model
        self.incarnation = incarnation
    }
}

struct LUIVirtualRetentionRecord: Codable, Equatable {
    let ticket: Int
    let key: String
}

struct LUIVirtualReleaseRecord: Codable, Equatable {
    let ticket: Int
    let receipt: String
}

struct LUIVirtualReceipt: Codable, Equatable {
    struct Row: Codable, Equatable {
        let source: Int
        let generation: Int
        let row: Int
        let incarnation: Int
    }
    var version = 1
    var status: String
    let owner: Int
    let epoch: Int
    let ticket: Int
    let proof: Int
    let rows: [Row]
    let geometry: Int
    let pins: Int
    let requirements: [String]

    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

struct LUISharedSourceBinding: Equatable {
    let owner: Int
    let epoch: Int
    let keys: [String]

    init?(properties: [LUIProperty: LUIWireValue], children: [Int]) throws {
        let fields: [LUIProperty] = [.virtualOwnerNode, .virtualOwnerEpoch, .virtualRowKeys]
        guard fields.contains(where: { properties[$0] != nil }) else { return nil }
        guard let owner = properties[.virtualOwnerNode]?.intValue, owner > 0,
              let epoch = properties[.virtualOwnerEpoch]?.intValue, epoch > 0,
              let keysJSON = properties[.virtualRowKeys]?.stringValue,
              let keysData = keysJSON.data(using: .utf8),
              let keys = try? JSONDecoder().decode([String].self, from: keysData),
              keys.count == children.count, keys.allSatisfy({ !$0.isEmpty }),
              Set(keys).count == keys.count,
              properties[.virtualTotalCount] != nil
        else { throw LUIBackendError.invalidBatch("invalid shared virtual source binding") }
        self.owner = owner
        self.epoch = epoch
        self.keys = keys
    }

    static func retentions(_ properties: [LUIProperty: LUIWireValue]) throws -> [LUIVirtualRetentionRecord] {
        guard let value = properties[.virtualRetentions] else { return [] }
        guard let string = value.stringValue, let data = string.data(using: .utf8) else {
            throw LUIBackendError.invalidBatch("invalid virtual retentions")
        }
        let records: [LUIVirtualRetentionRecord]
        do { records = try JSONDecoder().decode([LUIVirtualRetentionRecord].self, from: data) }
        catch { throw LUIBackendError.invalidBatch("invalid virtual retentions") }
        guard Set(records.map(\.ticket)).count == records.count,
              records.allSatisfy({ $0.ticket > 0 && !$0.key.isEmpty }) else {
            throw LUIBackendError.invalidBatch("invalid virtual retention ticket or key")
        }
        return records
    }

    static func releases(_ properties: [LUIProperty: LUIWireValue]) throws -> [LUIVirtualReleaseRecord] {
        guard let value = properties[.virtualRetentionReleases] else { return [] }
        guard let string = value.stringValue, let data = string.data(using: .utf8),
              let records = try? JSONDecoder().decode([LUIVirtualReleaseRecord].self, from: data),
              Set(records.map(\.ticket)).count == records.count,
              records.allSatisfy({ $0.ticket > 0 && !$0.receipt.isEmpty }) else {
            throw LUIBackendError.invalidBatch("invalid virtual retention releases")
        }
        return records
    }
}

struct LUISharedViewportGeometry: Equatable {
    let offset: CGFloat
    let height: CGFloat
    let documentHeight: CGFloat
    let origin: CGFloat

    var localOffset: CGFloat { offset - origin }
    func target(_ local: CGFloat) -> CGFloat {
        min(max(0, origin + local), max(0, documentHeight - height))
    }
}

@MainActor
extension LUIAppleBackend {
    /// Bind a concrete control to its exact retained-node incarnation. A view
    /// cannot represent two live nodes. This is not a focus or visibility claim.
    public func registerVirtualNativeView(nodeID: Int, view: LUIVirtualNativeView) throws
        -> LUIVirtualNativeRegistration {
        try sharedVirtualViewport.register(nodeID: nodeID, view: view)
    }

    public func unregisterVirtualNativeView(_ registration: LUIVirtualNativeRegistration) {
        sharedVirtualViewport.unregister(registration)
    }

    /// True means native evidence was verified and a receipt emitted. The app
    /// must match its intent/epoch/arm and request release through Lui_virtual;
    /// this method never releases a cold-key ticket or delivers editor input.
    @discardableResult
    public func acknowledgeVirtualRetention(ownerNode: Int, ticket: Int,
        view: LUIVirtualNativeView, requirements: LUIVirtualHandoffRequirements) throws -> Bool {
        try sharedVirtualViewport.acknowledge(ownerNode: ownerNode, ticket: ticket,
            view: view, requirements: requirements)
    }
}

@MainActor
final class LUISharedVirtualViewport {
    final class Source {
        weak var state: LUISparseVirtualState?
        weak var model: LUINodeModel?
        weak var anchor: LUIVirtualNativeView?
        var binding: LUISharedSourceBinding
        var geometry: LUISharedViewportGeometry?
        var rowAnchors: [Int: LUIWeakSharedRowAnchor] = [:]
        init(state: LUISparseVirtualState, model: LUINodeModel, binding: LUISharedSourceBinding) {
            self.state = state
            self.model = model
            self.binding = binding
        }
    }

    final class Owner {
        weak var model: LUINodeModel?
        weak var scroll: LUIHostNativeScroll?
        let epoch: Int
        var geometry = 1
        var pins = 1
        var signature: LUISharedViewportGeometry?
        var pinSet = Set<Int>()
        var attempted = Set<String>()
        var visibleAnchor: VisibleAnchor?
        var observedOffset: CGFloat?
        // One issued envelope per live ticket survives physical proof retirement.
        // Only exact SDK-issued bytes may produce a refusal after cache eviction.
        var issuedReceipts: [Int: (receipt: LUIVirtualReceipt, envelope: String)] = [:]
        init(model: LUINodeModel, scroll: LUIHostNativeScroll, epoch: Int) {
            self.model = model
            self.scroll = scroll
            self.epoch = epoch
        }
    }

    @MainActor final class VisibleAnchor {
        weak var source: Source?
        weak var marker: LUISharedRowMarker?
        weak var rowModel: AnyObject?
        let owner: Int
        let epoch: Int
        let key: String
        let position: CGFloat
        init(source: Source, marker: LUISharedRowMarker,
            rowModel: AnyObject, key: String, position: CGFloat) {
            self.source = source
            self.marker = marker
            self.rowModel = rowModel
            owner = source.binding.owner
            epoch = source.binding.epoch
            self.key = key
            self.position = position
        }
    }

    final class Proof {
        let receipt: LUIVirtualReceipt
        let envelope: String
        weak var registration: LUIVirtualNativeRegistration?
        let requirements: LUIVirtualHandoffRequirements
        var released = false
        init(receipt: LUIVirtualReceipt, envelope: String,
            registration: LUIVirtualNativeRegistration, requirements: LUIVirtualHandoffRequirements) {
            self.receipt = receipt
            self.envelope = envelope
            self.registration = registration
            self.requirements = requirements
        }
    }

    private weak var backend: LUIAppleBackend?
    private(set) var sources: [Int: Source] = [:]
    private var owners: [Int: Owner] = [:]
    private var registrations: [ObjectIdentifier: LUIVirtualNativeRegistration] = [:]
    private var proofs: [Int: Proof] = [:]
    private var rowIncarnations: [ObjectIdentifier: Int] = [:]
    private var nextIdentity = 1
    private var pressed: Set<ObjectIdentifier> = []
    private var menus: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
    private weak var composition: LUIVirtualNativeRegistration?
    private var task: Task<Void, Never>?
    private var refreshing = false

    init(backend: LUIAppleBackend) { self.backend = backend }

    private func identity() -> Int {
        precondition(nextIdentity < Int.max >> 1, "virtual ownership identity exhausted")
        defer { nextIdentity += 1 }
        return nextIdentity
    }

    func register(nodeID: Int, view: LUIVirtualNativeView) throws -> LUIVirtualNativeRegistration {
        let registration: LUIVirtualNativeRegistration
        if let model = backend?.model(id: nodeID) {
            if let old = registrations[ObjectIdentifier(view)], old.model === model { return old }
            registration = LUIVirtualNativeRegistration(view: view, model: model, incarnation: identity())
        } else if let model = backend?.extensionModel(id: nodeID) {
            if let old = registrations[ObjectIdentifier(view)], old.extensionModel === model { return old }
            registration = LUIVirtualNativeRegistration(view: view, model: model, incarnation: identity())
        } else {
            throw LUIBackendError.invalidBatch("native virtual control has no live retained node")
        }
        registrations[ObjectIdentifier(view)] = registration
        schedule()
        return registration
    }

    func unregister(_ registration: LUIVirtualNativeRegistration) {
        if let view = registration.view, registrations[ObjectIdentifier(view)] === registration {
            registrations[ObjectIdentifier(view)] = nil
        }
        registration.model = nil
        registration.extensionModel = nil
        registration.view = nil
        schedule()
    }

    func source(state: LUISparseVirtualState, model: LUINodeModel, binding: LUISharedSourceBinding) {
        if let old = sources[model.id], old.model === model, old.state === state {
            guard old.binding != binding else { return }
            old.binding = binding
            schedule()
            return
        }
        sources[model.id] = Source(state: state, model: model, binding: binding)
        schedule()
    }

    func sourceAnchor(state: LUISparseVirtualState, view: LUIVirtualNativeView?) {
        guard let source = sources.values.first(where: { $0.state === state }) else { return }
        source.anchor = view
        schedule()
    }

    func rowAnchor(state: LUISparseVirtualState, row: Int, view: LUISharedRowMarker, attached: Bool) {
        guard let source = sources.values.first(where: { $0.state === state }) else { return }
        if attached { source.rowAnchors[row] = LUIWeakSharedRowAnchor(view) }
        else if source.rowAnchors[row]?.value === view { source.rowAnchors[row] = nil }
        schedule()
    }

    func removeSource(_ state: LUISparseVirtualState) {
        sources = sources.filter { $0.value.state !== state }
        schedule()
    }

    func owner(model: LUINodeModel, scroll: LUIHostNativeScroll) {
        guard let epoch = model.property(.virtualViewportEpoch)?.intValue, epoch > 0 else { return }
        if let old = owners[model.id], old.model === model, old.epoch == epoch {
            if old.scroll !== scroll {
                old.scroll = scroll
                old.visibleAnchor = nil
                old.observedOffset = nil
                proofs = proofs.filter { $0.value.receipt.owner != model.id }
            }
            schedule()
            return
        }
        owners[model.id] = Owner(model: model, scroll: scroll, epoch: epoch)
        proofs = proofs.filter { $0.value.receipt.owner != model.id }
        schedule()
    }

    func removeOwner(model: LUINodeModel, scroll: LUIHostNativeScroll?) {
        guard let old = owners[model.id], old.model === model, old.scroll === scroll else { return }
        // Native detachment retires physical evidence, not the semantic lease's
        // ability to refuse its last issued receipt while the ticket is live.
        old.scroll = nil
        old.visibleAnchor = nil
        old.observedOffset = nil
        proofs = proofs.filter { $0.value.receipt.owner != model.id }
        schedule()
    }

    func schedule() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            task = nil
            refresh()
        }
    }

    private func live(_ registration: LUIVirtualNativeRegistration) -> Bool {
        guard let view = registration.view, retained(registration),
              registrations[ObjectIdentifier(view)] === registration, view.window != nil else { return false }
        #if os(macOS)
        return !view.isHiddenOrHasHiddenAncestor
        #else
        var current: UIView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
        #endif
    }

    private func retained(_ registration: LUIVirtualNativeRegistration) -> Bool {
        if let model = registration.model { return backend?.model(id: model.id) === model }
        if let model = registration.extensionModel { return backend?.extensionModel(id: model.id) === model }
        return false
    }

    private func focused(_ view: LUIVirtualNativeView) -> Bool {
        #if os(macOS)
        var responder = view.window?.firstResponder as? NSView
        if let text = responder as? NSTextView, text.isFieldEditor,
           let control = text.delegate as? NSView { responder = control }
        return responder.map { $0 === view || $0.isDescendant(of: view) } ?? false
        #else
        if view.isFirstResponder { return true }
        return view.subviews.contains { focused($0) }
        #endif
    }

    private func marked(_ view: LUIVirtualNativeView) -> Bool {
        #if os(macOS)
        if let text = view as? NSTextView { return text.hasMarkedText() }
        if let text = view.window?.firstResponder as? NSTextView, text.isFieldEditor,
           let control = text.delegate as? NSView, control === view || control.isDescendant(of: view) {
            return text.hasMarkedText()
        }
        return false
        #else
        if let input = view as? any UITextInput, input.markedTextRange != nil { return true }
        return view.subviews.contains { marked($0) }
        #endif
    }

    private func source(for owner: Owner) -> Source? {
        guard let ownerID = owner.model?.id else { return nil }
        let owned = sources.values.filter { $0.binding.owner == ownerID && $0.binding.epoch == owner.epoch }
        return owned.count == 1 ? owned.first : nil
    }

    private func row(nodeID: Int, source: Source) -> LUIVirtualReceipt.Row? {
        guard let backend, let model = source.model, let state = source.state,
              backend.model(id: model.id) === model else { return nil }
        var current: Int? = nodeID
        var visited = Set<Int>()
        while let node = current, visited.insert(node).inserted {
            let standard = backend.model(id: node)
            let custom = backend.extensionModel(id: node)
            let parentID = standard?.parent ?? custom?.parent
            if parentID == model.id {
                guard state.contains(node), let object = retainedIdentity(nodeID: node) else { return nil }
                let incarnation: Int
                if let existing = rowIncarnations[object] { incarnation = existing }
                else { incarnation = identity(); rowIncarnations[object] = incarnation }
                return .init(source: model.id, generation: state.generation, row: node, incarnation: incarnation)
            }
            current = parentID
        }
        return nil
    }

    private func retainedIdentity(nodeID: Int) -> ObjectIdentifier? {
        if let model = backend?.model(id: nodeID) { return ObjectIdentifier(model) }
        if let model = backend?.extensionModel(id: nodeID) { return ObjectIdentifier(model) }
        return nil
    }

    private func metrics(_ owner: Owner) -> (CGFloat, CGFloat, CGFloat)? {
        guard let scroll = owner.scroll, scroll.window != nil else { return nil }
        #if os(macOS)
        guard let document = scroll.documentView else { return nil }
        let clip = document.convert(scroll.contentView.bounds, from: scroll.contentView)
        let offset = document.isFlipped ? clip.minY - document.bounds.minY : document.bounds.maxY - clip.maxY
        let values = (offset, clip.height, document.bounds.height)
        #else
        let inset = scroll.adjustedContentInset
        let values = (scroll.contentOffset.y + inset.top,
            scroll.bounds.height - inset.top - inset.bottom, scroll.contentSize.height)
        #endif
        guard values.0.isFinite, values.1.isFinite, values.1 > 0, values.2.isFinite else { return nil }
        return values
    }

    private func geometry(_ source: Source, owner: Owner) -> LUISharedViewportGeometry? {
        guard let anchor = source.anchor, anchor.window != nil,
              let scroll = owner.scroll, let (offset, height, total) = metrics(owner) else { return nil }
        #if os(macOS)
        guard let document = scroll.documentView, anchor.isDescendant(of: document) else { return nil }
        let frame = anchor.convert(anchor.bounds, to: document)
        let origin = document.isFlipped ? frame.minY - document.bounds.minY : document.bounds.maxY - frame.maxY
        #else
        guard anchor.isDescendant(of: scroll) else { return nil }
        let frame = anchor.convert(anchor.bounds, to: scroll)
        let origin = frame.minY + scroll.adjustedContentInset.top
        #endif
        // A shared source is part of this exact outer document. Intervening
        // native scrollers, rotation, scale and skew are outside v1 coordinates.
        var ancestor = anchor.superview
        while let current = ancestor {
            if let candidate = current as? LUIHostNativeScroll {
                guard candidate === scroll else { return nil }
                break
            }
            ancestor = current.superview
        }
        #if os(macOS)
        let basis = anchor.convert(CGPoint.zero, to: document)
        let xAxis = anchor.convert(CGPoint(x: 1, y: 0), to: document)
        let yAxis = anchor.convert(CGPoint(x: 0, y: 1), to: document)
        let expectedY: CGFloat = anchor.isFlipped == document.isFlipped ? 1 : -1
        #else
        let basis = anchor.convert(CGPoint.zero, to: scroll)
        let xAxis = anchor.convert(CGPoint(x: 1, y: 0), to: scroll)
        let yAxis = anchor.convert(CGPoint(x: 0, y: 1), to: scroll)
        let expectedY: CGFloat = 1
        #endif
        let roundoff: CGFloat = 0.000001
        guard abs(xAxis.y - basis.y) < roundoff, abs(yAxis.x - basis.x) < roundoff,
              abs(xAxis.x - basis.x - 1) < roundoff,
              abs(yAxis.y - basis.y - expectedY) < roundoff else { return nil }
        guard origin.isFinite else { return nil }
        return .init(offset: offset, height: height, documentHeight: total, origin: origin)
    }

    private func anchorFrame(_ marker: LUISharedRowMarker, source: Source) -> CGRect? {
        guard let model = source.model, let anchor = source.anchor, let geometry = source.geometry,
              backend?.model(id: model.id) === model,
              model.children.contains(marker.row.id), source.state?.contains(marker.row.id) == true,
              source.rowAnchors[marker.row.id]?.value === marker,
              marker.window != nil, marker.window === anchor.window,
              marker.isDescendant(of: anchor) else { return nil }
        let frame = marker.convert(marker.bounds, to: anchor)
        #if os(macOS)
        let top = anchor.isFlipped ? frame.minY - anchor.bounds.minY : anchor.bounds.maxY - frame.maxY
        #else
        let top = frame.minY - anchor.bounds.minY
        #endif
        let position = geometry.origin + top
        guard position.isFinite, frame.height.isFinite, frame.height > 0 else { return nil }
        return CGRect(x: 0, y: position, width: 1, height: frame.height)
    }

    private func anchorKeys(_ source: Source) -> [Int: String]? {
        // Retained children update before the source configures. Resolve the key
        // from that same current metadata, while preserving the owner lease.
        guard let model = source.model,
              let binding = try? LUISharedSourceBinding(properties: model.properties, children: model.children),
              binding.owner == source.binding.owner, binding.epoch == source.binding.epoch else { return nil }
        return Dictionary(uniqueKeysWithValues: zip(model.children, binding.keys))
    }

    private func anchorModel(_ node: Int) -> AnyObject? {
        if let model = backend?.model(id: node) { return model }
        return backend?.extensionModel(id: node)
    }

    // Candidate rows must really intersect the native viewport and every
    // clipping ancestor. A saved row may move vertically outside the viewport
    // before compensation, so its identity check only requires horizontal visibility.
    private func anchorVisibility(_ marker: LUISharedRowMarker, owner: Owner,
        verticalClip: Bool) -> CGRect? {
        guard let scroll = owner.scroll, let window = marker.window, window === scroll.window else { return nil }
        #if os(macOS)
        guard window.isVisible, window.alphaValue > 0, let document = scroll.documentView else { return nil }
        let coordinates = document
        var viewport = document.convert(scroll.contentView.bounds, from: scroll.contentView)
        #else
        let coordinates = scroll
        var viewport = scroll.bounds.inset(by: scroll.adjustedContentInset)
        #endif
        var frame = marker.convert(marker.bounds, to: coordinates)
        var ancestor: LUIHostNativeView? = marker
        var foundScroll = false
        while let view = ancestor {
            #if os(macOS)
            guard !view.isHidden, view.alphaValue > 0 else { return nil }
            #else
            guard !view.isHidden, view.alpha > 0 else { return nil }
            #endif
            if view === scroll { foundScroll = true }
            if view.clipsToBounds {
                var clip = view.convert(view.bounds, to: coordinates)
                if !verticalClip {
                    clip.origin.y = frame.minY
                    clip.size.height = frame.height
                }
                frame = frame.intersection(clip)
            }
            ancestor = view.superview
        }
        guard foundScroll else { return nil }
        if !verticalClip {
            viewport.origin.y = frame.minY
            viewport.size.height = frame.height
        }
        frame = frame.intersection(viewport)
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0 else { return nil }
        #if os(macOS)
        let top = document.isFlipped ? frame.minY - document.bounds.minY : document.bounds.maxY - frame.maxY
        #else
        let top = frame.minY + scroll.adjustedContentInset.top
        #endif
        return CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height)
    }

    // One flat source's leading native row is the owner's sole measurement anchor.
    private func preserveVisibleAnchor(_ owner: Owner, source: Source?) {
        guard let source, let scroll = owner.scroll, let (offset, height, total) = metrics(owner) else {
            owner.visibleAnchor = nil
            owner.observedOffset = nil
            return
        }
        var currentOffset = offset
        let keys = anchorKeys(source)
        // Reading anchors survive generation updates only for the same semantic
        // key, native marker and retained model. Receipt attestation stays generation-bound.
        if let previousOffset = owner.observedOffset, abs(previousOffset - offset) <= 0.1,
           let saved = owner.visibleAnchor, saved.source === source,
           saved.owner == source.binding.owner, saved.epoch == source.binding.epoch,
           let marker = saved.marker,
           let rowModel = saved.rowModel, anchorModel(marker.row.id) === rowModel,
           keys?[marker.row.id] == saved.key,
           anchorVisibility(marker, owner: owner, verticalClip: false) != nil,
           let frame = anchorFrame(marker, source: source) {
            let delta = frame.minY - saved.position
            let target = min(max(0, offset + delta), max(0, total - height))
            if abs(target - offset) > 0.1,
               backend?.setNativeScrollTop(scroll, top: target, documentHeight: total, viewportHeight: height) == true {
                currentOffset = metrics(owner)?.0 ?? offset
            }
        }
        owner.observedOffset = currentOffset
        var candidates: [(anchor: VisibleAnchor, visible: CGRect)] = []
        for weakMarker in source.rowAnchors.values {
            guard let marker = weakMarker.value, let frame = anchorFrame(marker, source: source),
                  let visible = anchorVisibility(marker, owner: owner, verticalClip: true),
                  let rowModel = anchorModel(marker.row.id), let key = keys?[marker.row.id]
            else { continue }
            candidates.append((VisibleAnchor(source: source, marker: marker,
                rowModel: rowModel, key: key, position: frame.minY), visible))
        }
        owner.visibleAnchor = candidates.min { left, right in
            let leftCrosses = left.visible.minY <= currentOffset && left.visible.maxY > currentOffset
            let rightCrosses = right.visible.minY <= currentOffset && right.visible.maxY > currentOffset
            if leftCrosses != rightCrosses { return leftCrosses }
            if left.visible.minY != right.visible.minY { return left.visible.minY < right.visible.minY }
            return left.anchor.key < right.anchor.key
        }?.anchor
    }

    // Public intents resolve their exact native scroll before invalidating it;
    // internal measurement writes deliberately do not pass through this hook.
    func explicitScroll(_ scroll: LUIHostNativeScroll) {
        for owner in owners.values where owner.scroll === scroll {
            owner.visibleAnchor = nil
            owner.observedOffset = nil
            schedule()
        }
    }

    private func visible(_ view: LUIVirtualNativeView, in owner: Owner) -> Bool {
        // Attachment can outlive native presentation; only visible proofs need
        // a presented window and nontransparent view hierarchy.
        guard let scroll = owner.scroll else { return false }
        #if os(macOS)
        guard let window = view.window, window.isVisible, window.alphaValue > 0 else { return false }
        var current: NSView? = view
        while let candidate = current {
            guard !candidate.isHidden, candidate.alphaValue > 0 else { return false }
            current = candidate.superview
        }
        let frame = view.convert(view.visibleRect, to: scroll.contentView)
        let clip = scroll.contentView.bounds
        #else
        guard let window = view.window, !window.isHidden, window.alpha > 0 else { return false }
        var current: UIView? = view
        while let candidate = current {
            guard !candidate.isHidden, candidate.alpha > 0 else { return false }
            current = candidate.superview
        }
        var frame = view.convert(view.bounds, to: scroll)
        var ancestor = view.superview
        while let candidate = ancestor, candidate !== scroll {
            if candidate.clipsToBounds { frame = frame.intersection(candidate.convert(candidate.bounds, to: scroll)) }
            ancestor = candidate.superview
        }
        let clip = scroll.bounds.inset(by: scroll.adjustedContentInset)
        #endif
        return frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0 && frame.intersects(clip)
    }

    private func satisfies(_ registration: LUIVirtualNativeRegistration,
        owner: Owner, requirements: LUIVirtualHandoffRequirements) -> Bool {
        guard live(registration), let view = registration.view, metrics(owner) != nil,
              requirements.rawValue > 0, requirements.rawValue & ~7 == 0 else { return false }
        guard let scroll = owner.scroll, view.window === scroll.window else { return false }
        #if os(macOS)
        guard let document = scroll.documentView, view.isDescendant(of: document) else { return false }
        #else
        guard view.isDescendant(of: scroll) else { return false }
        #endif
        let frame = view.bounds
        guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return false }
        if requirements.contains(.visible), !visible(view, in: owner) { return false }
        if requirements.contains(.focus), !focused(view) { return false }
        return true
    }

    private func proofIsCurrent(_ proof: Proof, owner: Owner) -> Bool {
        guard let registration = proof.registration, let node = registration.nodeID, let model = owner.model,
              backend?.model(id: model.id) === model,
              model.property(.virtualViewportEpoch)?.intValue == owner.epoch,
              owner.model?.id == proof.receipt.owner, owner.epoch == proof.receipt.epoch,
              owner.geometry == proof.receipt.geometry,
              let source = source(for: owner), let row = row(nodeID: node, source: source),
              proof.receipt.rows == [row],
              satisfies(registration, owner: owner, requirements: proof.requirements) else { return false }
        guard let sourceModel = source.model,
              backend?.model(id: row.source) === sourceModel,
              sourceModel.property(.virtualGeneration)?.intValue == row.generation,
              source.binding.epoch == owner.epoch, source.geometry != nil,
              let current = try? LUISharedSourceBinding(properties: sourceModel.properties, children: sourceModel.children)
        else { return false }
        return current == source.binding && rowGeometry(row, source: source, registration: registration)
    }

    private func rowGeometry(_ row: LUIVirtualReceipt.Row, source: Source,
        registration: LUIVirtualNativeRegistration) -> Bool {
        guard let marker = source.rowAnchors[row.row]?.value, let anchor = source.anchor,
              let state = source.state, let native = registration.view,
              marker.window != nil, marker.window === anchor.window, native.window === marker.window,
              marker.generation == row.generation, marker.row.id == row.row,
              let expected = state.sharedRowGeometry(row.row), marker.row.index == expected.index else { return false }
        let measured = marker.convert(marker.bounds, to: anchor)
        let nativeRect = native.convert(native.bounds, to: marker)
        return measured.minY.isFinite && measured.height.isFinite && measured.width > 0
            && abs(measured.minY - expected.origin) <= 1 && abs(measured.height - expected.height) <= 1
            && nativeRect.intersection(marker.bounds).width > 0 && nativeRect.intersection(marker.bounds).height > 0
    }

    private func ticket(_ number: Int, owner: Owner) -> LUIVirtualRetentionRecord? {
        guard let model = owner.model else { return nil }
        return (try? LUISharedSourceBinding.retentions(model.properties))?.first { $0.ticket == number }
    }

    func acknowledge(ownerNode: Int, ticket number: Int, view: LUIVirtualNativeView,
        requirements: LUIVirtualHandoffRequirements) throws -> Bool {
        refresh()
        guard let owner = owners[ownerNode], let retainedTicket = ticket(number, owner: owner),
              let registration = registrations[ObjectIdentifier(view)], let node = registration.nodeID,
              satisfies(registration, owner: owner, requirements: requirements) else { return false }
        guard let source = source(for: owner), let row = row(nodeID: node, source: source),
              let position = source.model?.children.firstIndex(of: row.row),
              source.binding.keys.indices.contains(position), source.binding.keys[position] == retainedTicket.key,
              source.geometry != nil, rowGeometry(row, source: source, registration: registration) else { return false }
        let names = ["attached"] + (requirements.contains(.visible) ? ["visible"] : [])
            + (requirements.contains(.focus) ? ["focus"] : [])
        if owner.pinSet.insert(row.row).inserted {
            owner.pins = identity()
        }
        let receipt = LUIVirtualReceipt(status: requirements.contains(.focus) ? "focused" : "pinned",
            owner: ownerNode, epoch: owner.epoch, ticket: number, proof: identity(), rows: [row],
            geometry: owner.geometry, pins: owner.pins, requirements: names)
        let envelope = try receipt.encoded()
        proofs = proofs.filter { $0.value.receipt.owner != ownerNode || $0.value.receipt.ticket != number }
        proofs[receipt.proof] = Proof(receipt: receipt, envelope: envelope,
            registration: registration, requirements: requirements)
        refresh()
        source.state?.flushOwnership()
        guard owners[ownerNode] === owner, let installed = proofs[receipt.proof], ticket(number, owner: owner) != nil,
              proofIsCurrent(installed, owner: owner) else {
            proofs[receipt.proof] = nil
            return false
        }
        owner.issuedReceipts[number] = (receipt, envelope)
        backend?.performVirtualRetention(owner: ownerNode, ticket: number, receipt: envelope)
        return true
    }

    func refresh() {
        guard !refreshing, let backend else { return }
        refreshing = true
        defer { refreshing = false }
        registrations = registrations.filter { _, registration in
            guard let view = registration.view else { return false }
            return retained(registration) && registrations[ObjectIdentifier(view)] === registration
        }
        owners = owners.filter { _, owner in
            guard let model = owner.model else { return false }
            return backend.model(id: model.id) === model
                && model.property(.virtualViewportEpoch)?.intValue == owner.epoch
        }
        sources = sources.filter { _, source in
            guard let model = source.model else { return false }
            return source.state?.sharedBinding == source.binding && backend.model(id: model.id) === model
        }
        let liveRowObjects = Set(sources.values.flatMap { source in
            (source.model?.children ?? []).compactMap { node -> ObjectIdentifier? in
                if let model = backend.model(id: node) { return ObjectIdentifier(model) }
                if let model = backend.extensionModel(id: node) { return ObjectIdentifier(model) }
                return nil
            }
        })
        rowIncarnations = rowIncarnations.filter { liveRowObjects.contains($0.key) }
        for (ownerID, owner) in Array(owners) {
            let source = source(for: owner)
            if let source { source.geometry = geometry(source, owner: owner) }
            preserveVisibleAnchor(owner, source: source)
            if let source { source.geometry = geometry(source, owner: owner) }
            let signature = source?.geometry
            if signature != owner.signature { owner.signature = signature; owner.geometry = identity() }
            var pins = Set<Int>()
            for registration in registrations.values where live(registration) {
                guard let view = registration.view, let node = registration.nodeID else { continue }
                let id = ObjectIdentifier(view)
                let hasFocus = focused(view)
                if hasFocus && marked(view) { composition = registration }
                let ownsComposition = composition === registration && marked(view)
                if hasFocus || ownsComposition || pressed.contains(id) || menus.values.contains(where: { $0.contains(id) }) {
                    if let source, let row = row(nodeID: node, source: source) { pins.insert(row.row) }
                }
            }
            pins.formUnion(source?.state?.sharedInteractionRows ?? [])
            for proof in proofs.values where proof.receipt.owner == ownerID {
                guard let registration = proof.registration, let view = registration.view,
                      live(registration), ticket(proof.receipt.ticket, owner: owner) != nil || proof.released else { continue }
                if !proof.released || focused(view) || marked(view) || visible(view, in: owner) {
                    if let row = proof.receipt.rows.first { pins.insert(row.row) }
                }
            }
            if pins != owner.pinSet { owner.pinSet = pins; owner.pins = identity() }
            if let source {
                let direct = Set(source.model?.children ?? []).intersection(pins)
                source.state?.sharedViewport(source.geometry, pins: direct)
            }
            guard let model = owner.model,
                  let retentions = try? LUISharedSourceBinding.retentions(model.properties),
                  let releases = try? LUISharedSourceBinding.releases(model.properties) else { continue }
            let tickets = Set(retentions.map(\.ticket))
            owner.issuedReceipts = owner.issuedReceipts.filter { tickets.contains($0.key) }
            owner.attempted.formIntersection(Set(owner.issuedReceipts.values.map(\.envelope)))
            owner.attempted.formIntersection(Set(releases.map(\.receipt)))
            for release in releases {
                guard owners[ownerID] === owner, backend.model(id: ownerID) === model,
                      model.property(.virtualViewportEpoch)?.intValue == owner.epoch,
                      let issued = owner.issuedReceipts[release.ticket],
                      issued.receipt.owner == ownerID, issued.receipt.epoch == owner.epoch,
                      issued.receipt.ticket == release.ticket, tickets.contains(release.ticket),
                      issued.envelope.utf8.elementsEqual(release.receipt.utf8),
                      owner.attempted.insert(issued.envelope).inserted else { continue }
                let receipt = issued.receipt
                var response = receipt
                response.status = "stale"
                if let proof = proofs[receipt.proof], proof.envelope.utf8.elementsEqual(issued.envelope.utf8),
                   proofIsCurrent(proof, owner: owner) {
                    // Feedback adopts the full physical pin set before shared
                    // OCaml may remove its cold-key retention.
                    source?.state?.flushOwnership()
                    if owners[ownerID] === owner, proofs[receipt.proof] === proof,
                       proofIsCurrent(proof, owner: owner) {
                        proof.released = true
                        response.status = "released"
                    }
                }
                guard owners[ownerID] === owner, backend.model(id: ownerID) === model,
                      model.property(.virtualViewportEpoch)?.intValue == owner.epoch,
                      ticket(release.ticket, owner: owner) != nil else { continue }
                if let envelope = try? response.encoded() {
                    backend.performVirtualRetention(owner: ownerID, ticket: release.ticket, receipt: envelope)
                }
            }
        }
        proofs = proofs.filter { _, proof in
            guard let owner = owners[proof.receipt.owner], proof.registration?.view != nil else { return false }
            return ticket(proof.receipt.ticket, owner: owner) != nil
        }
    }

    func setOffset(_ local: CGFloat, state: LUISparseVirtualState, animated: Bool) {
        guard let source = sources.values.first(where: { $0.state === state }),
              let geometry = source.geometry, let owner = owners[source.binding.owner],
              let scroll = owner.scroll,
              let backend else { return }
        _ = animated // Explicit shared-owner intents use current measured geometry.
        owner.visibleAnchor = nil
        owner.observedOffset = nil
        _ = backend.setNativeScrollTop(scroll, top: geometry.target(local),
            documentHeight: geometry.documentHeight, viewportHeight: geometry.height)
        // The owner probe uses the same existing document and owns notifications.
        if owner.scroll != nil { schedule() }
    }

    func pointer(view: LUIVirtualNativeView?, down: Bool) {
        if down {
            pressed.removeAll()
            var candidate = view
            while let current = candidate {
                if registrations[ObjectIdentifier(current)] != nil { pressed.insert(ObjectIdentifier(current)); break }
                candidate = current.superview
            }
            refresh()
            for source in Array(sources.values) { source.state?.flushOwnership() }
        } else {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.pressed.removeAll()
                self?.schedule()
            }
        }
    }

    #if os(macOS)
    func menu(_ menu: NSMenu, opened: Bool) {
        let identity = ObjectIdentifier(menu)
        if !opened { menus[identity] = nil; schedule(); return }
        var owners = pressed
        for registration in registrations.values {
            guard let view = registration.view, let attached = view.menu else { continue }
            var candidate: NSMenu? = menu
            while let current = candidate {
                if current === attached { owners.insert(ObjectIdentifier(view)); break }
                candidate = current.supermenu
            }
        }
        menus[identity] = owners
        refresh()
        for source in Array(sources.values) { source.state?.flushOwnership() }
    }
    #endif
}
