import LUIAppleBackend
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
@_silgen_name("lui_ocaml_double_press")
private func luiOCamlDoublePress(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_toggle_changed")
private func luiOCamlToggleChanged(_ node: Int64, _ checked: Int32) -> Int32
@_silgen_name("lui_ocaml_radio_changed")
private func luiOCamlRadioChanged(_ node: Int64) -> Int32
@_silgen_name("lui_ocaml_slider_changed")
private func luiOCamlSliderChanged(_ node: Int64, _ value: Double) -> Int32

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

    init() {
        do {
            backend = try LUIAppleBackend(
                extensionRegistry: galleryExtensionRegistry()
            )
        } catch {
            fatalError("Invalid Gallery extension registry: \(error)")
        }
        backend.onEvent = { event in
            switch event {
            case let .press(node): _ = luiOCamlPress(Int64(node))
            case let .longPress(node): _ = luiOCamlLongPress(Int64(node))
            case let .textChanged(node, text):
                text.withCString { _ = luiOCamlTextChanged(Int64(node), $0) }
            case let .submit(node): _ = luiOCamlSubmit(Int64(node))
            case let .dismiss(node): _ = luiOCamlDismiss(Int64(node))
            case let .doublePress(node): _ = luiOCamlDoublePress(Int64(node))
            case let .toggleChanged(node, checked):
                _ = luiOCamlToggleChanged(Int64(node), checked ? 1 : 0)
            case let .change(node): _ = luiOCamlRadioChanged(Int64(node))
            case let .valueChanged(node, value):
                _ = luiOCamlSliderChanged(Int64(node), value)
            case .extension:
                assertionFailure("Gallery extensions do not declare LG events")
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
            rootID = backend.rootIDs.first
            sections = rootID.map(backend.rootSections(rootID:)) ?? []
        } catch {
            assertionFailure("Invalid LUI patch: \(error)")
        }
    }

    func stop() {
        guard started else { return }
        _ = luiOCamlStop()
        started = false
        activeHost = nil
    }
}

private struct GalleryRootView: View {
    @State private var host = GalleryHost()
    @State private var selectedSectionID: Int?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationSplitView {
            List(host.sections, selection: $selectedSectionID) { section in
                NavigationLink(value: section.id) {
                    Text(section.title)
                }
                .accessibilityIdentifier("component-row-\(section.title)")
            }
            .navigationTitle("Components")
        } detail: {
            if let section = selectedSection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        LUISwiftUIRoot(backend: host.backend, rootID: section.id)
                    }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .background(galleryBackground)
                .navigationTitle(section.title)
            } else if host.rootID == nil {
                ProgressView("Starting LG Gallery")
            } else {
                ContentUnavailableView(
                    "Select a component",
                    systemImage: "square.grid.2x2"
                )
            }
        }
        .task {
            host.start()
            selectDefaultForRegularWidth()
        }
        .onChange(of: host.sections) {
            selectDefaultForRegularWidth()
        }
        .onChange(of: horizontalSizeClass) {
            selectDefaultForRegularWidth()
        }
    }

    private var selectedSection: LUIRootSection? {
        host.sections.first { $0.id == selectedSectionID }
    }

    private var galleryBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private func selectDefaultForRegularWidth() {
        guard selectedSectionID == nil, horizontalSizeClass != .compact else { return }
        selectedSectionID = host.sections.first?.id
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
