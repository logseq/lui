import AppKit
import Darwin
import Foundation
import LUIAppleBackend

private typealias PatchCallback = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias StartFunction = @convention(c) (PatchCallback?) -> Int32
private typealias PressFunction = @convention(c) (Int64) -> Int32
private typealias TextChangedFunction =
    @convention(c) (Int64, UnsafePointer<CChar>?) -> Int32

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
    private let pressFunction: PressFunction
    private let textChangedFunction: TextChangedFunction

    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw RuntimeError(String(cString: dlerror()))
        }
        self.handle = handle
        startFunction = try Self.load("lui_ocaml_start", from: handle)
        pressFunction = try Self.load("lui_ocaml_press", from: handle)
        textChangedFunction = try Self.load("lui_ocaml_text_changed", from: handle)
    }

    func start() throws {
        guard startFunction(receivePatch) == 1 else {
            throw RuntimeError("LG Todos initialization failed")
        }
    }

    func press(node: Int) {
        _ = pressFunction(Int64(node))
    }

    func textChanged(node: Int, text: String) {
        text.withCString { source in
            _ = textChangedFunction(Int64(node), source)
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
private final class TodosHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let backend = LUIAppleBackend()
    private let content = NSView()
    private var runtime: NativeTodosRuntime?
    private var window: NSWindow?

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
                case let .textChanged(node, text):
                    self?.runtime?.textChanged(node: node, text: text)
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
        guard let root = backend.rootViews.first else { return }
        guard root.superview !== content else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])
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
