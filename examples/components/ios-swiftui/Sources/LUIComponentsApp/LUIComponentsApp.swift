import LUIAppleBackend
import Foundation
import Observation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

private typealias PatchCallback = @convention(c) (UnsafePointer<CChar>?) -> Void

@_silgen_name("lui_ocaml_start")
private func luiOCamlStart(
    _ callback: PatchCallback?,
    _ platform: Int32,
    _ host: Int32
) -> Int32
@_silgen_name("lui_ocaml_stop")
private func luiOCamlStop() -> Int32
@_silgen_name("lui_ocaml_press")
private func luiOCamlPress(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_long_press")
private func luiOCamlLongPress(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_text_changed")
private func luiOCamlTextChanged(_ node: Int64, _ text: UnsafePointer<CChar>?) -> Int32
@_silgen_name("lui_ocaml_submit")
private func luiOCamlSubmit(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_dismiss")
private func luiOCamlDismiss(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_picked")
private func luiOCamlPicked(_ node: Int64, _ payload: UnsafePointer<CChar>) -> Int32
@_silgen_name("lui_ocaml_double_press")
private func luiOCamlDoublePress(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_toggle_changed")
private func luiOCamlToggleChanged(_ node: Int64, _ checked: Int32) -> Int32
@_silgen_name("lui_ocaml_radio_changed")
private func luiOCamlRadioChanged(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_slider_changed")
private func luiOCamlSliderChanged(_ node: Int64, _ value: Double) -> Int32
@_silgen_name("lui_ocaml_appear")
private func luiOCamlAppear(_ node: Int64) -> Int32

nonisolated(unsafe) private var activeHost: GalleryHost?

nonisolated(unsafe) private let receivePatch: PatchCallback = { source in
    guard let source else { return }
    let json = String(cString: source)
    MainActor.assumeIsolated {
        activeHost?.apply(json: json)
    }
}

@Observable
@MainActor
private final class GalleryHost {
    let backend: LUIAppleBackend
    private(set) var rootID: Int?
    private(set) var sections: [LUIRootSection] = []
    private var started = false
    private let composerImports = GalleryComposerImports()
    private var composerPickers: Set<Int> = []
    private var pickerRequests: [Int: Int] = [:]
    private var attachmentPaths: [Int: String] = [:]
    private var composerPatchRevision = 0
    private var composerChildren: [Int: Set<Int>] = [:]
    private var composerParents: [Int: Int] = [:]
    private var composerEpoch = 0

    init() {
        do {
            backend = try LUIAppleBackend(
                extensionRegistry: galleryExtensionRegistry()
            )
        } catch {
            fatalError("Invalid Gallery extension registry: \(error)")
        }
        backend.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case let .press(node): _ = luiOCamlPress(Int64(node))
            case let .longPress(node): _ = luiOCamlLongPress(Int64(node))
            case let .textChanged(node, text):
                text.withCString { _ = luiOCamlTextChanged(Int64(node), $0) }
            case let .submit(node): _ = luiOCamlSubmit(Int64(node))
            case let .dismiss(node): _ = luiOCamlDismiss(Int64(node))
            case let .picked(node, payload):
                if self.composerPickers.contains(node) {
                    Task { await self.importComposerSelection(node: node, payload: payload) }
                } else {
                    payload.withCString { _ = luiOCamlPicked(Int64(node), $0) }
                }
            case let .doublePress(node): _ = luiOCamlDoublePress(Int64(node))
            case let .toggleChanged(node, checked):
                _ = luiOCamlToggleChanged(Int64(node), checked ? 1 : 0)
            case let .change(node): _ = luiOCamlRadioChanged(Int64(node))
            case let .valueChanged(node, value):
                _ = luiOCamlSliderChanged(Int64(node), value)
            case let .appear(node): _ = luiOCamlAppear(Int64(node))
            case .extension:
                assertionFailure("Gallery extensions do not declare LG events")
            case .scrollCompleted, .visibleRange, .pressDetail, .pointerDown,
                 .pointerUp, .pointerEnter, .pointerLeave, .contextMenuPress:
                break
            }
        }
    }

    func start() {
        guard !started else { return }
        activeHost = self
        guard luiOCamlStart(receivePatch, 2, 2) == 1 else {
            fatalError("LG Gallery initialization failed")
        }
        started = true
    }

    func apply(json: String) {
        do {
            try backend.apply(json: json)
            trackComposerPatch(json)
            rootID = backend.rootIDs.first
            sections = rootID.map(backend.rootSections(rootID:)) ?? []
        } catch {
            assertionFailure("Invalid LUI patch: \(error)")
        }
    }

    private func trackComposerPatch(_ json: String) {
        guard let data = json.data(using: .utf8),
              let batch = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ops = batch["ops"] as? [[String: Any]] else { return }
        for op in ops {
            let operation = op["op"] as? String
            if operation == "insert-child", let parent = op["parent"] as? Int,
               let child = op["child"] as? Int {
                if let previous = composerParents[child] { composerChildren[previous]?.remove(child) }
                composerChildren[parent, default: []].insert(child)
                composerParents[child] = parent
                continue
            }
            if operation == "remove-child", let parent = op["parent"] as? Int,
               let child = op["child"] as? Int {
                composerChildren[parent]?.remove(child)
                composerParents.removeValue(forKey: child)
                continue
            }
            guard let id = op["id"] as? Int else { continue }
            if operation == "drop-node" || operation == "detach-subtree" {
                forgetComposerSubtree(id)
            } else if operation == "remove-prop" {
                if op["property"] as? String == "request" { pickerRequests.removeValue(forKey: id) }
                if op["property"] as? String == "accessibility-identifier" {
                    composerPickers.remove(id)
                    attachmentPaths.removeValue(forKey: id)
                }
            } else if operation == "set-prop" {
                if op["property"] as? String == "request", let request = op["value"] as? Int {
                    pickerRequests[id] = request
                }
                if op["property"] as? String == "accessibility-identifier", let value = op["value"] as? String {
                    composerPickers.remove(id)
                    attachmentPaths.removeValue(forKey: id)
                    if value == "picker.composer" { composerPickers.insert(id) }
                    let prefix = "composer-attachment:"
                    if value.hasPrefix(prefix) { attachmentPaths[id] = String(value.dropFirst(prefix.count)) }
                }
            }
        }
        let paths = Set(attachmentPaths.values)
        composerPatchRevision += 1
        let revision = composerPatchRevision
        Task { await composerImports.retain(paths, revision: revision) }
    }

    private func forgetComposerSubtree(_ root: Int) {
        var remaining = [root]
        while let id = remaining.popLast() {
            remaining.append(contentsOf: composerChildren.removeValue(forKey: id) ?? [])
            if let parent = composerParents.removeValue(forKey: id) { composerChildren[parent]?.remove(id) }
            composerPickers.remove(id)
            pickerRequests.removeValue(forKey: id)
            attachmentPaths.removeValue(forKey: id)
        }
    }

    private func importComposerSelection(node: Int, payload: String) async {
        let request = pickerRequests[node]
        let epoch = composerEpoch
        let result = await composerImports.stage(payload)
        guard started, composerEpoch == epoch, composerPickers.contains(node), pickerRequests[node] == request else {
            await composerImports.retain(Set(attachmentPaths.values), revision: composerPatchRevision,
                finishing: result?.created ?? [])
            return
        }
        guard let batch = result else { _ = luiOCamlDismiss(Int64(node)); return }
        batch.payload.withCString { _ = luiOCamlPicked(Int64(node), $0) }
        await composerImports.retain(Set(attachmentPaths.values), revision: composerPatchRevision,
            finishing: batch.created)
    }

    func stop() {
        guard started else { return }
        _ = luiOCamlStop()
        started = false
        composerEpoch += 1
        composerPickers.removeAll()
        pickerRequests.removeAll()
        attachmentPaths.removeAll()
        composerChildren.removeAll()
        composerParents.removeAll()
        activeHost = nil
        Task { await composerImports.clear() }
    }
}

private struct GalleryRootView: View {
    @State private var host = GalleryHost()

    var body: some View {
        splitView
            .modifier(ModalHostModifier(host: host))
            .task {
                host.start()
            }
    }

    /// Dialogs/sheets anchor to the traversal root, but each detail page is a
    /// separate `LUISwiftUIRoot` keyed by section — so the app hosts modals at
    /// the split-view level instead.
    private struct ModalHostModifier: ViewModifier {
        let host: GalleryHost

        func body(content: Content) -> some View {
            if let rootID = host.rootID {
                content.modifier(
                    LUIModalHostModifier(rootID: rootID, backend: host.backend)
                )
            } else {
                content
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(host.sections) { section in
                        sectionRow(section)
                    }
                }
                .modifier(LUIGalleryScrollBehavior())
            }
            .navigationTitle("Components")
            .navigationDestination(for: Int.self) { sectionID in
                detailView(sectionID: sectionID)
            }
        } detail: {
            if host.rootID == nil {
                ProgressView("Starting LG Gallery")
            } else {
                ContentUnavailableView(
                    "Select a component",
                    systemImage: "square.grid.2x2"
                )
            }
        }
    }

    private struct LUIGalleryScrollBehavior: ViewModifier {
        func body(content: Content) -> some View {
            #if os(iOS)
            content.background(LUIScrollDecelerationLimiter())
            #else
            content
            #endif
        }
    }

    #if os(iOS)
    private struct LUIScrollDecelerationLimiter: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            return view
        }

        func updateUIView(_ uiView: UIView, context: Context) {
            DispatchQueue.main.async {
                var superview = uiView.superview
                while let candidate = superview {
                    if let scrollView = candidate as? UIScrollView {
                        scrollView.decelerationRate = UIScrollView.DecelerationRate(rawValue: 0.5)
                        NSLog("LUI scroll limiter: set decelerationRate on %@", String(describing: type(of: scrollView)))
                        return
                    }
                    superview = candidate.superview
                }
                NSLog("LUI scroll limiter: no UIScrollView ancestor")
            }
        }
    }
    #endif

    private func sectionRow(_ section: LUIRootSection) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: section.id) {
                HStack {
                    Text(section.title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("component-row-\(section.title)")
            Divider().padding(.leading, 20)
        }
    }

    private func detailView(sectionID: Int) -> some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LUISwiftUIRoot(backend: host.backend, rootID: sectionID)
                    .environment(\.luiInsideScroll, true)
            }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(galleryBackground)
        // The section's own heading is the page title; repeating it as the
        // nav-bar title renders the same text twice.
        .navigationTitle("")
    }

    private var galleryBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

@main
private struct AppMain: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppMainDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppMainDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            GalleryRootView()
        }
    }
}

#if os(iOS)
@MainActor
private final class AppMainDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        activeHost?.stop()
    }
}
#else
@MainActor
private final class AppMainDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        activeHost?.stop()
    }
}
#endif
