import Observation
import SwiftUI
#if os(macOS)
import AppKit
typealias LUIMenuAttachmentView = NSView
typealias LUIMenuAttachmentWindow = NSWindow
#else
import UIKit
typealias LUIMenuAttachmentView = UIView
typealias LUIMenuAttachmentWindow = UIWindow
#endif

enum LUIAnchoredMenuMode {
    case popover, dialog
}

struct LUIAnchoredMenuCandidate: Equatable {
    let host: LUINodeModel
    let menu: LUINodeModel
    let mode: LUIAnchoredMenuMode

    func isSameDeclaration(as other: Self) -> Bool {
        host === other.host && menu === other.menu
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isSameDeclaration(as: rhs) && lhs.mode == rhs.mode
    }
}

@MainActor
final class LUIAnchoredMenuAttachment {
    let host: LUINodeModel
    private weak var view: LUIMenuAttachmentView?
    private weak var parent: LUIMenuAttachmentView?
    private weak var window: LUIMenuAttachmentWindow?
    private var revoked = false

    init(host: LUINodeModel, view: LUIMenuAttachmentView) {
        self.host = host
        self.view = view
        parent = view.superview
        window = view.window
    }

    var isLive: Bool {
        guard !revoked, let view, let parent, let window else { return false }
        return view.superview === parent && view.window === window
    }

    func revoke() { revoked = true }
}

struct LUIAnchoredMenuLease: Identifiable {
    let id = UUID()
    let candidate: LUIAnchoredMenuCandidate
    let attachment: LUIAnchoredMenuAttachment
    var host: LUINodeModel { candidate.host }
    var menu: LUINodeModel { candidate.menu }
}

@MainActor
@Observable
final class LUIAnchoredMenuAdmission {
    @ObservationIgnored private var candidates: [Int: LUIAnchoredMenuCandidate] = [:]
    @ObservationIgnored private var attachments: [Int: LUIAnchoredMenuAttachment] = [:]
    private var leases: [Int: LUIAnchoredMenuLease] = [:]
    @ObservationIgnored private var dismissed: [ObjectIdentifier: LUINodeModel] = [:]
    @ObservationIgnored private var pendingCloses: [UUID: LUIAnchoredMenuLease] = [:]

    static var physicalHeld: Bool {
        #if os(macOS)
        NSEvent.pressedMouseButtons != 0
        #else
        false
        #endif
    }

    func synchronize(_ next: [Int: LUIAnchoredMenuCandidate],
                     retained: Set<ObjectIdentifier>, held: Bool,
                     isHostRetained: (LUINodeModel) -> Bool) {
        dismissed = dismissed.filter { retained.contains($0.key) }
        // Sample logical arrival even when no native attachment exists yet.
        if held {
            for (id, item) in next where candidates[id]?.isSameDeclaration(as: item) != true {
                dismissed[ObjectIdentifier(item.menu)] = item.menu
            }
        }
        if candidates != next { candidates = next }
        for (id, source) in attachments where !isHostRetained(source.host) || !source.isLive {
            source.revoke()
            attachments[id] = nil
        }
        for id in Set(leases.keys).union(next.keys) { reconcile(id, held: held) }
        invalidatePendingCloses()
    }

    func retire(droppedNodeIDs: Set<Int>) {
        guard !droppedNodeIDs.isEmpty else { return }
        // Accepted destruction retires authority before observable models catch up.
        // Recreating the same numeric IDs cannot restore these candidates/leases.
        candidates = candidates.filter { _, item in
            !droppedNodeIDs.contains(item.host.id) && !droppedNodeIDs.contains(item.menu.id)
        }
        for (id, source) in attachments where droppedNodeIDs.contains(source.host.id) {
            source.revoke()
            attachments[id] = nil
        }
        invalidatePendingCloses()
        // Invalidate every affected context before publishing lease removal.
        for id in leases.keys where candidates[id] == nil { revokeLease(at: id) }
    }

    func attach(_ source: LUIAnchoredMenuAttachment, held: Bool) {
        guard source.isLive else { return }
        let id = source.host.id
        if attachments[id] !== source {
            attachments[id]?.revoke()
            attachments[id] = source
        }
        reconcile(id, held: held)
        invalidatePendingCloses()
    }

    func detach(_ source: LUIAnchoredMenuAttachment) {
        source.revoke()
        let id = source.host.id
        guard attachments[id] === source else { return }
        attachments[id] = nil
        revokeLease(at: id)
        invalidatePendingCloses()
    }

    func presentation(at hostID: Int) -> LUIAnchoredMenuLease? {
        guard let lease = leases[hostID], let current = candidates[hostID],
              current == lease.candidate, attachments[hostID] === lease.attachment,
              lease.attachment.isLive, lease.attachment.host === current.host,
              dismissed[ObjectIdentifier(current.menu)] == nil else { return nil }
        return lease
    }

    func take(_ lease: LUIAnchoredMenuLease) -> Bool {
        guard presentation(at: lease.host.id)?.id == lease.id else { return false }
        // Take before invoking application code; reentrant replacement is independent.
        dismissed[ObjectIdentifier(lease.menu)] = lease.menu
        revokeLease(at: lease.host.id)
        pendingCloses[lease.id] = lease
        return true
    }

    func consumeClose(_ lease: LUIAnchoredMenuLease) -> Bool {
        guard pendingCloses.removeValue(forKey: lease.id) != nil else { return false }
        return matchesTakenContext(lease)
    }

    private func matchesTakenContext(_ lease: LUIAnchoredMenuLease) -> Bool {
        candidates[lease.host.id] == lease.candidate
            && attachments[lease.host.id] === lease.attachment
            && lease.attachment.isLive
            && dismissed[ObjectIdentifier(lease.menu)] === lease.menu
    }

    private func invalidatePendingCloses() {
        pendingCloses = pendingCloses.filter { matchesTakenContext($0.value) }
    }

    private func reconcile(_ id: Int, held: Bool) {
        guard let candidate = candidates[id], let source = attachments[id],
              source.isLive, source.host === candidate.host,
              dismissed[ObjectIdentifier(candidate.menu)] == nil else {
            revokeLease(at: id)
            return
        }
        let previous = leases[id]
        if previous?.candidate == candidate, previous?.attachment === source { return }
        // A native-mode migration preserves admission, but gets a new close lease.
        let admitted = previous?.candidate.isSameDeclaration(as: candidate) == true
            && previous?.attachment === source
        revokeLease(at: id)
        if held && !admitted {
            dismissed[ObjectIdentifier(candidate.menu)] = candidate.menu
        } else {
            leases[id] = LUIAnchoredMenuLease(candidate: candidate, attachment: source)
        }
    }

    private func revokeLease(at hostID: Int) {
        if leases[hostID] != nil { leases[hostID] = nil }
    }
}

@MainActor
final class LUIMenuAttachmentProbeView: LUIMenuAttachmentView {
    private weak var backend: LUIAppleBackend?
    private var host: LUINodeModel?
    private var source: LUIAnchoredMenuAttachment?

    func configure(host: LUINodeModel, backend: LUIAppleBackend) {
        if self.host !== host || self.backend !== backend {
            disconnect()
            self.host = host
            self.backend = backend
        }
        connect()
    }

    func disconnect() {
        if let source {
            source.revoke()
            self.source = nil
            backend?.anchoredMenus.detach(source)
        }
    }

    func invalidate() {
        disconnect()
        host = nil
        backend = nil
    }

    private func connect() {
        guard let host, let backend, backend.model(id: host.id) === host else {
            disconnect()
            return
        }
        guard source?.isLive != true else { return }
        disconnect()
        guard superview != nil, window != nil else { return }
        source = LUIAnchoredMenuAttachment(host: host, view: self)
        if let source {
            backend.anchoredMenus.attach(source, held: LUIAnchoredMenuAdmission.physicalHeld)
        }
    }

    #if os(macOS)
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        connect()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        connect()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    #else
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        connect()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        connect()
    }
    #endif
}

#if os(macOS)
struct LUIAnchoredMenuAttachmentProbe: NSViewRepresentable {
    let host: LUINodeModel
    let backend: LUIAppleBackend

    func makeNSView(context: Context) -> LUIMenuAttachmentProbeView {
        let view = LUIMenuAttachmentProbeView(frame: .zero)
        view.configure(host: host, backend: backend)
        return view
    }

    func updateNSView(_ view: LUIMenuAttachmentProbeView, context: Context) {
        view.configure(host: host, backend: backend)
    }

    static func dismantleNSView(_ view: LUIMenuAttachmentProbeView, coordinator: ()) {
        view.invalidate()
    }
}
#else
struct LUIAnchoredMenuAttachmentProbe: UIViewRepresentable {
    let host: LUINodeModel
    let backend: LUIAppleBackend

    func makeUIView(context: Context) -> LUIMenuAttachmentProbeView {
        let view = LUIMenuAttachmentProbeView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.configure(host: host, backend: backend)
        return view
    }

    func updateUIView(_ view: LUIMenuAttachmentProbeView, context: Context) {
        view.configure(host: host, backend: backend)
    }

    static func dismantleUIView(_ view: LUIMenuAttachmentProbeView, coordinator: ()) {
        view.invalidate()
    }
}
#endif
