#if canImport(AppKit)
import AppKit
import Darwin
import Foundation
import LUIAppleBackend
import SwiftUI

private typealias PatchCallback = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias StartFunction = @convention(c) (PatchCallback?, Int32, Int32) -> Int32
private typealias StopFunction = @convention(c) () -> Int32
private typealias AppearFunction = @convention(c) (Int64) -> Int32
private typealias PressFunction = @convention(c) (Int64) -> Int32
private typealias LongPressFunction = @convention(c) (Int64) -> Int32
private typealias TextChangedFunction =
    @convention(c) (Int64, UnsafePointer<CChar>?, Int32) -> Int32
private typealias SubmitFunction = @convention(c) (Int64) -> Int32
private typealias DismissFunction = @convention(c) (Int64) -> Int32
private typealias PickedFunction =
    @convention(c) (Int64, UnsafePointer<CChar>?, Int32) -> Int32
private typealias DoublePressFunction = @convention(c) (Int64) -> Int32
private typealias ToggleChangedFunction = @convention(c) (Int64, Int32) -> Int32
private typealias RadioChangedFunction = @convention(c) (Int64) -> Int32
private typealias SliderChangedFunction = @convention(c) (Int64, Double) -> Int32
private typealias ExtensionEventFunction =
    @convention(c) (
        Int64, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> Int32

nonisolated(unsafe) private var activeHost: SplitDemoHost?

nonisolated(unsafe) private let receivePatch: PatchCallback = { source in
    guard let source else { return }
    let json = String(cString: source)
    MainActor.assumeIsolated {
        activeHost?.apply(json: json)
    }
}

// Host-side flat encoding matching Lui_json.parse_values on the OCaml side.
private func luiExtensionValuesJSON(_ values: [String: LUIExtensionValue]) -> String {
    func escape(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
    let fields = values
        .sorted { $0.key < $1.key }
        .map { name, value -> String in
            switch value {
            case let .string(text):
                return "\"\(escape(name))\":\"\(escape(text))\""
            case let .bool(flag):
                return "\"\(escape(name))\":\(flag ? "true" : "false")"
            case let .int(number):
                return "\"\(escape(name))\":\(number)"
            case let .double(number):
                return "\"\(escape(name))\":\(number)"
            }
        }
    return "{\(fields.joined(separator: ","))}"
}

@MainActor
private final class NativeSplitRuntime {
    private let handle: UnsafeMutableRawPointer
    private let startFunction: StartFunction
    private let stopFunction: StopFunction
    private let appearFunction: AppearFunction
    private let pressFunction: PressFunction
    private let longPressFunction: LongPressFunction
    private let textChangedFunction: TextChangedFunction
    private let submitFunction: SubmitFunction
    private let dismissFunction: DismissFunction
    private let pickedFunction: PickedFunction
    private let doublePressFunction: DoublePressFunction
    private let toggleChangedFunction: ToggleChangedFunction
    private let radioChangedFunction: RadioChangedFunction
    private let sliderChangedFunction: SliderChangedFunction
    private let extensionEventFunction: ExtensionEventFunction

    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw RuntimeError(String(cString: dlerror()))
        }
        self.handle = handle
        startFunction = try Self.load("lui_ocaml_start", from: handle)
        stopFunction = try Self.load("lui_ocaml_stop", from: handle)
        appearFunction = try Self.load("lui_ocaml_appear", from: handle)
        pressFunction = try Self.load("lui_ocaml_press", from: handle)
        longPressFunction = try Self.load("lui_ocaml_long_press", from: handle)
        textChangedFunction = try Self.load("lui_ocaml_text_changed_utf8", from: handle)
        submitFunction = try Self.load("lui_ocaml_submit", from: handle)
        dismissFunction = try Self.load("lui_ocaml_dismiss", from: handle)
        pickedFunction = try Self.load("lui_ocaml_picked_utf8", from: handle)
        doublePressFunction = try Self.load("lui_ocaml_double_press", from: handle)
        toggleChangedFunction = try Self.load("lui_ocaml_toggle_changed", from: handle)
        radioChangedFunction = try Self.load("lui_ocaml_radio_changed", from: handle)
        sliderChangedFunction = try Self.load("lui_ocaml_slider_changed", from: handle)
        extensionEventFunction = try Self.load("lui_ocaml_extension_event", from: handle)
    }

    func start() throws {
        guard startFunction(receivePatch, 1, 2) == 1 else {
            throw RuntimeError("LUI Split initialization failed")
        }
    }

    func stop() {
        _ = stopFunction()
    }

    func appear(node: Int) { _ = appearFunction(Int64(node)) }

    func press(node: Int) { _ = pressFunction(Int64(node)) }

    func longPress(node: Int) { _ = longPressFunction(Int64(node)) }

    func textChanged(node: Int, text: String) {
        text.withCString { source in
            _ = textChangedFunction(Int64(node), source, Int32(text.utf8.count))
        }
    }

    func submit(node: Int) { _ = submitFunction(Int64(node)) }

    func dismiss(node: Int) { _ = dismissFunction(Int64(node)) }

    func picked(node: Int, payload: String) {
        payload.withCString { source in
            _ = pickedFunction(Int64(node), source, Int32(payload.utf8.count))
        }
    }

    func doublePress(node: Int) { _ = doublePressFunction(Int64(node)) }

    func toggleChanged(node: Int, checked: Bool) {
        _ = toggleChangedFunction(Int64(node), checked ? 1 : 0)
    }

    func radioChanged(node: Int) { _ = radioChangedFunction(Int64(node)) }

    func sliderChanged(node: Int, value: Double) {
        _ = sliderChangedFunction(Int64(node), value)
    }

    func extensionEvent(
        node: Int, identifier: String, name: String,
        values: [String: LUIExtensionValue]
    ) {
        let json = luiExtensionValuesJSON(values)
        identifier.withCString { identifierSource in
            name.withCString { nameSource in
                json.withCString { jsonSource in
                    _ = extensionEventFunction(
                        Int64(node), identifierSource, nameSource, jsonSource)
                }
            }
        }
    }

    private static func load<Function>(
        _ name: String,
        from handle: UnsafeMutableRawPointer
    ) throws -> Function {
        guard let symbol = dlsym(handle, name) else {
            throw RuntimeError("Missing native symbol: \(name)")
        }
        return unsafeBitCast(symbol, to: Function.self)
    }
}

private struct RuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

@MainActor
private func splitExtensionRegistry() -> LUIAppleExtensionRegistry {
    let registry = LUIAppleExtensionRegistry()
    do {
        try LUISplit.register(in: registry)
    } catch {
        assertionFailure("split extension registry failed: \(error)")
    }
    return registry
}

@MainActor
private final class SplitDemoHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let backend: LUIAppleBackend
    private let content = NSView()
    private var runtime: NativeSplitRuntime?
    private var window: NSWindow?
    private var hostedRootID: Int?

    override init() {
        do {
            backend = try LUIAppleBackend(
                extensionRegistry: splitExtensionRegistry())
        } catch {
            assertionFailure("split backend failed: \(error)")
            backend = LUIAppleBackend()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let path = try libraryPath()
            let runtime = try NativeSplitRuntime(path: path)
            self.runtime = runtime
            activeHost = self
            backend.onEvent = { [weak self] event in
                switch event {
                case let .appear(node):
                    self?.runtime?.appear(node: node)
                case let .press(node):
                    self?.runtime?.press(node: node)
                case let .longPress(node):
                    self?.runtime?.longPress(node: node)
                case let .textChanged(node, text):
                    self?.runtime?.textChanged(node: node, text: text)
                case let .submit(node):
                    self?.runtime?.submit(node: node)
                case let .toggleChanged(node, checked):
                    self?.runtime?.toggleChanged(node: node, checked: checked)
                case let .change(node):
                    self?.runtime?.radioChanged(node: node)
                case let .valueChanged(node, value):
                    self?.runtime?.sliderChanged(node: node, value: value)
                case let .dismiss(node):
                    self?.runtime?.dismiss(node: node)
                case let .picked(node, payload):
                    self?.runtime?.picked(node: node, payload: payload)
                case let .doublePress(node):
                    self?.runtime?.doublePress(node: node)
                case let .`extension`(node, identifier, name, values):
                    self?.runtime?.extensionEvent(
                        node: node, identifier: identifier, name: name,
                        values: values)
                case .scrollCompleted, .visibleRange:
                    // The C bridge exports no scroll/visible-range entry points.
                    break
                }
            }
            makeWindow()
            try runtime.start()
            window?.makeKeyAndOrderFront(nil)
            if #available(macOS 14.0, *) {
                NSApplication.shared.activate()
            } else {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } catch {
            present(error: error)
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime?.stop()
        runtime = nil
        activeHost = nil
    }

    func apply(json: String) {
        do {
            try backend.apply(json: json)
            refreshRoot()
        } catch {
            present(error: error)
        }
    }

    private func makeWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LUI · Split"
        window.center()
        window.contentView = content
        window.delegate = self
        self.window = window
    }

    private func refreshRoot() {
        guard let rootID = backend.rootIDs.first else {
            content.subviews.forEach { $0.removeFromSuperview() }
            hostedRootID = nil
            return
        }
        guard hostedRootID != rootID else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        let root = NSHostingView(
            rootView: LUISwiftUIRoot(backend: backend, rootID: rootID)
                .padding(8)
        )
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        hostedRootID = rootID
    }

    private func libraryPath() throws -> String {
        if let path = ProcessInfo.processInfo.environment["LUI_SPLIT_LIBRARY"],
           !path.isEmpty {
            return path
        }
        let executable = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        return executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Frameworks/liblui_split.dylib")
            .path
    }

    private func present(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "LUI Split could not start"
        alert.informativeText = String(describing: error)
        alert.runModal()
    }
}

private let application = NSApplication.shared
private let delegate = SplitDemoHost()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
#endif
