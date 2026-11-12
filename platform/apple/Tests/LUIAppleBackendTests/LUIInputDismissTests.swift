import SwiftUI
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif
@testable import LUIAppleBackend

@MainActor
@Suite("Retained input cancellation", .serialized)
struct LUIInputDismissTests {
    private func input(kind: String = "input", dismiss: Bool = true,
                       blur: Bool = true) throws -> LUIAppleBackend {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"\(kind)"},
          {"op":"set-prop","id":1,"property":"dismiss-enabled","value":\(dismiss)},
          {"op":"set-prop","id":1,"property":"submit-on-blur","value":\(blur)}
        ]}
        """)
        return backend
    }

    @Test("all five text kinds admit only enabled opt-in Dismiss")
    func textKindAdmission() throws {
        for kind in ["text-field", "secure-field", "input", "search-field", "textarea"] {
            let backend = try input(kind: kind)
            var events: [LUIEvent] = []
            backend.onEvent = { events.append($0) }
            try backend.performDismiss(node: 1)
            try backend.apply(json: """
            {"generation":2,"ops":[{"op":"remove-prop","id":1,"property":"dismiss-enabled"}]}
            """)
            #expect(throws: LUIBackendError.self) { try backend.performDismiss(node: 1) }
            try backend.apply(json: """
            {"generation":3,"ops":[
              {"op":"set-prop","id":1,"property":"dismiss-enabled","value":true},
              {"op":"set-prop","id":1,"property":"enabled","value":false}
            ]}
            """)
            #expect(throws: LUIBackendError.self) { try backend.performDismiss(node: 1) }
            #expect(events == [.dismiss(node: 1)])
        }
    }

    @Test("dismiss-enabled rejects non-Boolean values and non-text owners")
    func wireAdmission() throws {
        for (kind, value) in [("input", "\"true\""), ("button", "true")] {
            let backend = LUIAppleBackend()
            #expect(throws: LUIBackendError.self) {
                try backend.apply(json: """
                {"generation":1,"ops":[
                  {"op":"create-node","id":1,"kind":"\(kind)"},
                  {"op":"set-prop","id":1,"property":"dismiss-enabled","value":\(value)}
                ]}
                """)
            }
            #expect(backend.model(id: 1) == nil)
        }
    }

    @Test("Dismiss suppresses even synchronous blur before its handler returns")
    func synchronousBlur() throws {
        let backend = try input()
        let session = LUIInputDismissSession()
        session.configure(model: try #require(backend.model(id: 1)), backend: backend)
        session.focusBegan()
        var events: [LUIEvent] = []
        backend.onEvent = { event in
            events.append(event)
            if event == .dismiss(node: 1) { session.focusEnded() }
        }
        #expect(session.cancel(composing: false))
        #expect(!session.cancel(composing: false))
        #expect(events == [.dismiss(node: 1)])
        session.focusBegan()
        session.focusEnded()
        #expect(events == [.dismiss(node: 1), .submit(node: 1)])
    }

    @Test("IME, default false, removed handler and retired owner never consume cancellation")
    func cancellationAdmission() throws {
        let backend = try input(dismiss: false)
        let session = LUIInputDismissSession()
        session.configure(model: try #require(backend.model(id: 1)), backend: backend)
        session.focusBegan()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        #expect(!session.cancel(composing: false))
        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"set-prop","id":1,"property":"dismiss-enabled","value":true}]}
        """)
        #expect(!session.cancel(composing: true))
        session.focusEnded()
        #expect(events == [.submit(node: 1)])
        try backend.apply(json: """
        {"generation":3,"ops":[{"op":"remove-prop","id":1,"property":"dismiss-enabled"}]}
        """)
        #expect(!session.cancel(composing: false))
        try backend.apply(json: """
        {"generation":4,"ops":[
          {"op":"drop-node","id":1},
          {"op":"create-node","id":1,"kind":"input"},
          {"op":"set-prop","id":1,"property":"dismiss-enabled","value":true}
        ]}
        """)
        #expect(!session.cancel(composing: false))
        #expect(events == [.submit(node: 1)])
    }

    @Test("Enter plus blur submits once; editing or refocusing starts a new submission interval")
    func explicitSubmitAndBlur() throws {
        let backend = try input()
        let session = LUIInputDismissSession()
        session.configure(model: try #require(backend.model(id: 1)), backend: backend)
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        session.focusBegan()
        session.submit()
        session.focusEnded()
        #expect(events == [.submit(node: 1)])
        session.focusBegan()
        session.submit()
        session.textEdited()
        session.focusEnded()
        #expect(events == [.submit(node: 1), .submit(node: 1), .submit(node: 1)])
        session.focusBegan()
        #expect(session.cancel(composing: false))
        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"remove-prop","id":1,"property":"dismiss-enabled"}]}
        """)
        session.focusEnded()
        #expect(events.last == .dismiss(node: 1))
    }

    @Test("the absent blur-submit default emits no Submit")
    func defaultBlur() throws {
        let backend = try input(blur: false)
        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"remove-prop","id":1,"property":"submit-on-blur"}]}
        """)
        let session = LUIInputDismissSession()
        session.configure(model: try #require(backend.model(id: 1)), backend: backend)
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        session.focusBegan()
        session.focusEnded()
        #expect(events.isEmpty)
    }

    @Test("composing blur does not save and a new edit permits another cancellation")
    func compositionAndNewEdit() throws {
        let backend = try input()
        let session = LUIInputDismissSession()
        session.configure(model: try #require(backend.model(id: 1)), backend: backend)
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        session.focusBegan()
        session.focusEnded(composing: true)
        #expect(events.isEmpty)
        session.focusBegan()
        session.submit()
        #expect(session.cancel(composing: false))
        session.submit()
        #expect(!session.cancel(composing: false))
        session.textEdited()
        #expect(session.cancel(composing: false))
        session.focusEnded()
        #expect(events == [.submit(node: 1), .dismiss(node: 1), .dismiss(node: 1)])
    }

    #if os(macOS)
    @Test("native Escape belongs only to the focused retained editor and ignores marked text")
    func nativeEditorOwnership() throws {
        let backend = try input()
        let session = LUIInputDismissSession()
        session.configure(model: try #require(backend.model(id: 1)), backend: backend)
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: 0, width: 400, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        let group = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        let other = NSTextField(frame: NSRect(x: 0, y: 100, width: 180, height: 24))
        let probe = LUIInputDismissProbeView()
        probe.session = session
        group.addSubview(field)
        group.addSubview(probe)
        root.addSubview(group)
        root.addSubview(other)
        window.contentView = root
        // Exercise the owned field editor without taking the user's key window.
        window.orderBack(nil)
        #expect(!window.isKeyWindow)
        defer { probe.disconnect(); window.orderOut(nil); window.contentView = nil }
        #expect(window.makeFirstResponder(field))
        probe.refresh()
        #expect(probe.monitorsEscape)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setMarkedText("候", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!probe.handle(event))
        #expect(events.isEmpty)
        editor.unmarkText()
        let repeated = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: true, keyCode: 53))
        #expect(!probe.handle(repeated))
        #expect(probe.handle(event))
        #expect(!probe.handle(event))
        #expect(events == [.dismiss(node: 1)])
        #expect(window.makeFirstResponder(other))
        #expect(!probe.monitorsEscape)
        #expect(!probe.handle(event))
        #expect(events == [.dismiss(node: 1)])
        #expect(window.makeFirstResponder(field))
        probe.refresh()
        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"remove-prop","id":1,"property":"dismiss-enabled"}]}
        """)
        probe.refresh()
        #expect(!probe.monitorsEscape)
        #expect(field.currentEditor() === editor)
        #expect(!probe.handle(event))
    }
    #else
    @Test("iOS retained field, multiline editor and native search probes require exact focus")
    func nativeUIKitEditorOwnership() throws {
        for kind in ["input", "textarea", "search-field"] {
            let backend = try input(kind: kind)
            let session = LUIInputDismissSession()
            session.configure(model: try #require(backend.model(id: 1)), backend: backend)
            var events: [LUIEvent] = []
            backend.onEvent = { events.append($0) }
            let controller = UIViewController()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
            window.rootViewController = controller
            let search = UISearchController(searchResultsController: nil)
            let editor: UIView
            if kind == "search-field" {
                controller.navigationItem.searchController = search
                search.searchBar.frame = CGRect(x: 0, y: 0, width: 300, height: 44)
                controller.view.addSubview(search.searchBar)
                editor = search.searchBar.searchTextField
            } else {
                editor = kind == "textarea" ? UITextView() : UITextField()
                editor.frame = CGRect(x: 0, y: 0, width: 300, height: 60)
                controller.view.addSubview(editor)
            }
            let probe = LUIInputDismissProbeView()
            probe.session = session
            probe.nativeSearch = kind == "search-field"
            controller.view.addSubview(probe)
            window.makeKeyAndVisible()
            defer { probe.disconnect(); window.isHidden = true; window.rootViewController = nil }
            controller.view.layoutIfNeeded()
            probe.refresh()
            #expect(!probe.cancelFocusedInput())
            #expect(editor.becomeFirstResponder())
            let input = try #require(editor as? any UITextInput)
            input.setMarkedText("候", selectedRange: NSRange(location: 1, length: 0))
            #expect(!probe.cancelFocusedInput())
            #expect(events.isEmpty)
            input.unmarkText()
            #expect(probe.cancelFocusedInput())
            #expect(events == [.dismiss(node: 1)])
            #expect(editor.resignFirstResponder())
            #expect(events == [.dismiss(node: 1)])
            #expect(!probe.cancelFocusedInput())
            try backend.apply(json: """
            {"generation":2,"ops":[{"op":"remove-prop","id":1,"property":"dismiss-enabled"}]}
            """)
            probe.refresh()
            #expect(editor.becomeFirstResponder())
            #expect(!probe.cancelFocusedInput())
            if kind == "search-field" { #expect(search.searchBar.searchTextField === editor) }
        }
    }
    #endif
}
