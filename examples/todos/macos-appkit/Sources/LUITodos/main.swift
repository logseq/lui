#if canImport(AppKit)
import AppKit
import Darwin
import Foundation
import LUIAppleBackend
import SwiftUI

private typealias PatchCallback = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias StartFunction = @convention(c) (PatchCallback?, Int32) -> Int32
private typealias StopFunction = @convention(c) () -> Int32
private typealias PressFunction = @convention(c) (Int64) -> Int32
private typealias HoldFunction = @convention(c) (Int64) -> Int32
private typealias TextChangedFunction =
    @convention(c) (Int64, UnsafePointer<CChar>?) -> Int32
private typealias SubmitFunction = @convention(c) (Int64) -> Int32
private typealias DismissFunction = @convention(c) (Int64) -> Int32
private typealias ToggleChangedFunction = @convention(c) (Int64, Int32) -> Int32
private typealias RadioChangedFunction = @convention(c) (Int64) -> Int32
private typealias SliderChangedFunction = @convention(c) (Int64, Double) -> Int32

nonisolated(unsafe) private var activeHost: TodosHost?

nonisolated(unsafe) private let receivePatch: PatchCallback = { source in
    guard let source else { return }
    let json = String(cString: source)
    MainActor.assumeIsolated {
        activeHost?.apply(json: json)
    }
}

@MainActor
private final class NativeTodosRuntime {
    private let handle: UnsafeMutableRawPointer
    private let startFunction: StartFunction
    private let stopFunction: StopFunction
    private let pressFunction: PressFunction
    private let holdFunction: HoldFunction
    private let textChangedFunction: TextChangedFunction
    private let submitFunction: SubmitFunction
    private let dismissFunction: DismissFunction
    private let toggleChangedFunction: ToggleChangedFunction
    private let radioChangedFunction: RadioChangedFunction
    private let sliderChangedFunction: SliderChangedFunction

    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw RuntimeError(String(cString: dlerror()))
        }
        self.handle = handle
        startFunction = try Self.load("lui_ocaml_start", from: handle)
        stopFunction = try Self.load("lui_ocaml_stop", from: handle)
        pressFunction = try Self.load("lui_ocaml_press", from: handle)
        holdFunction = try Self.load("lui_ocaml_hold", from: handle)
        textChangedFunction = try Self.load("lui_ocaml_text_changed", from: handle)
        submitFunction = try Self.load("lui_ocaml_submit", from: handle)
        dismissFunction = try Self.load("lui_ocaml_dismiss", from: handle)
        toggleChangedFunction = try Self.load("lui_ocaml_toggle_changed", from: handle)
        radioChangedFunction = try Self.load("lui_ocaml_radio_changed", from: handle)
        sliderChangedFunction = try Self.load("lui_ocaml_slider_changed", from: handle)
    }

    func start() throws {
        guard startFunction(receivePatch, 1) == 1 else {
            throw RuntimeError("LG Todos initialization failed")
        }
    }

    func stop() {
        _ = stopFunction()
    }

    func press(node: Int) {
        _ = pressFunction(Int64(node))
    }

    func hold(node: Int) {
        _ = holdFunction(Int64(node))
    }

    func textChanged(node: Int, text: String) {
        text.withCString { source in
            _ = textChangedFunction(Int64(node), source)
        }
    }

    func submit(node: Int) {
        _ = submitFunction(Int64(node))
    }

    func dismiss(node: Int) {
        _ = dismissFunction(Int64(node))
    }

    func toggleChanged(node: Int, checked: Bool) {
        _ = toggleChangedFunction(Int64(node), checked ? 1 : 0)
    }

    func radioChanged(node: Int) {
        _ = radioChangedFunction(Int64(node))
    }

    func sliderChanged(node: Int, value: Double) {
        _ = sliderChangedFunction(Int64(node), value)
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
private final class TodosHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let backend = LUIAppleBackend()
    private let content = NSView()
    private var runtime: NativeTodosRuntime?
    private var window: NSWindow?
    private var hostedRootID: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let path = try libraryPath()
            let runtime = try NativeTodosRuntime(path: path)
            self.runtime = runtime
            activeHost = self
            backend.onEvent = { [weak self] event in
                switch event {
                case let .press(node):
                    self?.runtime?.press(node: node)
                case let .hold(node):
                    self?.runtime?.hold(node: node)
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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LUI · LG Todos"
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
                .padding(24)
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
        if let path = ProcessInfo.processInfo.environment["LUI_TODOS_LIBRARY"],
           !path.isEmpty {
            return path
        }
        let executable = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        return executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Frameworks/liblui_todos.dylib")
            .path
    }

    private func present(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "LUI Todos could not start"
        alert.informativeText = String(describing: error)
        alert.runModal()
    }
}

private let application = NSApplication.shared
private let delegate = TodosHost()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
#endif
