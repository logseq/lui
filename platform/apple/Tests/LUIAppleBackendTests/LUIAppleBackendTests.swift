import AppKit
import Testing
@testable import LUIAppleBackend

private struct CapturedAppleEvent: Equatable, Sendable {
    let kind: Int32
    let node: Int32
    let text: String
}

nonisolated(unsafe) private var capturedAppleEvent: CapturedAppleEvent?

private let captureAppleEvent: LUIAppleEventCallback = { kind, node, text in
    capturedAppleEvent = CapturedAppleEvent(
        kind: kind,
        node: node,
        text: text.map(String.init(cString:)) ?? ""
    )
}

@MainActor
@Suite("LUI AppKit backend", .serialized)
struct LUIAppleBackendTests {
    @Test("applies one LG patch batch to real AppKit views")
    func appliesPatchBatch() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)

        let row = try #require(backend.view(id: 1) as? NSStackView)
        let label = try #require(backend.view(id: 2) as? NSTextField)
        let button = try #require(backend.view(id: 3) as? NSButton)

        #expect(row.orientation == .horizontal)
        #expect(row.spacing == 12)
        #expect(label.stringValue == "Hello from LG")
        #expect(button.title == "Continue")
        #expect(button.isEnabled == true)
        #expect(row.arrangedSubviews.map(backend.id(of:)) == [2, 3])
    }

    @Test("moves existing native views without recreating them")
    func preservesIdentityOnMove() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)
        let originalButton = try #require(backend.view(id: 3))

        try backend.apply(json: """
        {"generation":2,"ops":[{"op":"move-child","parent":1,"child":3,"index":0}]}
        """)

        let row = try #require(backend.view(id: 1) as? NSStackView)
        #expect(backend.view(id: 3) === originalButton)
        #expect(row.arrangedSubviews.map(backend.id(of:)) == [3, 2])
    }

    @Test("rejects an invalid batch atomically")
    func rejectsInvalidBatchAtomically() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[
              {"op":"create-node","id":4,"kind":"text"},
              {"op":"insert-child","parent":99,"child":4,"index":0}
            ]}
            """)
        }

        #expect(backend.view(id: 4) == nil)
        #expect(backend.generation == 1)
    }

    @Test("rejects duplicate or skipped generations atomically")
    func rejectsOutOfOrderGeneration() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: Self.initialBatch)

        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":3,"ops":[{"op":"create-node","id":4,"kind":"text"}]}
            """)
        }

        #expect(backend.view(id: 4) == nil)
        #expect(backend.generation == 1)
    }

    @Test("native control action returns a semantic event")
    func returnsButtonEvent() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: Self.initialBatch)

        let button = try #require(backend.view(id: 3) as? NSButton)
        button.performClick(nil)

        #expect(events == [.press(node: 3)])
    }

    @Test("native text editing returns each semantic change")
    func returnsTextChangedEvent() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"text-input"},
          {"op":"set-prop","id":1,"property":"text","value":""},
          {"op":"set-prop","id":1,"property":"enabled","value":true}
        ]}
        """)

        let field = try #require(backend.view(id: 1) as? NSTextField)
        field.stringValue = "Write Apple Todos"
        NotificationCenter.default.post(
            name: NSControl.textDidChangeNotification,
            object: field
        )

        #expect(events == [.textChanged(node: 1, text: "Write Apple Todos")])
    }

    @Test("maps semantic text-input properties to native AppKit behavior")
    func mapsTextInputSemantics() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"text-input"},
          {"op":"set-prop","id":1,"property":"placeholder","value":"Search"},
          {"op":"set-prop","id":1,"property":"read-only","value":true},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Search todos"}
        ]}
        """)

        let field = try #require(backend.view(id: 1) as? NSTextField)
        #expect(field.placeholderString == "Search")
        #expect(field.isEditable == false)
        #expect(field.accessibilityLabel() == "Search todos")
    }

    @Test("maps semantic content primitives to native AppKit views")
    func mapsSemanticContentPrimitives() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"box"},
          {"op":"create-node","id":2,"kind":"heading"},
          {"op":"create-node","id":3,"kind":"paragraph"},
          {"op":"set-prop","id":2,"property":"heading-level","value":3},
          {"op":"set-prop","id":2,"property":"text","value":"Account"},
          {"op":"set-prop","id":3,"property":"text","value":"Manage your profile."},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)

        let box = try #require(backend.view(id: 1) as? NSStackView)
        let heading = try #require(backend.view(id: 2) as? NSTextField)
        let paragraph = try #require(backend.view(id: 3) as? NSTextField)

        #expect(box.orientation == .vertical)
        #expect(box.arrangedSubviews.map(backend.id(of:)) == [2, 3])
        #expect(heading.stringValue == "Account")
        if #available(macOS 26.0, *) {
            #expect(heading.accessibilityRole() == .headingRole)
        } else {
            #expect(heading.accessibilityRole() == .staticText)
        }
        #expect(paragraph.stringValue == "Manage your profile.")
    }

    @Test("retains form labels, descriptions, errors, and input type")
    func retainsFormRelationships() throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"label"},
          {"op":"create-node","id":2,"kind":"text-input"},
          {"op":"create-node","id":3,"kind":"paragraph"},
          {"op":"create-node","id":4,"kind":"paragraph"},
          {"op":"set-prop","id":1,"property":"text","value":"Password"},
          {"op":"set-prop","id":3,"property":"text","value":"Use at least 12 characters."},
          {"op":"set-prop","id":4,"property":"text","value":"Password is too short."},
          {"op":"set-prop","id":2,"property":"labelled-by","value":1},
          {"op":"set-prop","id":2,"property":"described-by","value":3},
          {"op":"set-prop","id":2,"property":"error-message-by","value":4},
          {"op":"set-prop","id":2,"property":"input-type","value":"password"},
          {"op":"set-prop","id":2,"property":"invalid","value":true}
        ]}
        """)

        let label = try #require(backend.view(id: 1) as? NSTextField)
        let input = try #require(backend.view(id: 2) as? NSTextField)
        let titleElement = input.accessibilityTitleUIElement() as? NSView
        #expect(titleElement === label)
        #expect(input.accessibilityHelp() == "Use at least 12 characters. Password is too short.")
        #expect(input.cell is NSSecureTextFieldCell)
        #expect(input.layer?.borderWidth == 1)

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":3,"property":"text","value":"Twelve or more characters."},
          {"op":"set-prop","id":2,"property":"invalid","value":false}
        ]}
        """)
        #expect(input.accessibilityHelp() == "Twelve or more characters.")
        #expect(input.layer?.borderWidth == 0)

        try backend.apply(json: """
        {"generation":3,"ops":[
          {"op":"drop-node","id":1},
          {"op":"drop-node","id":3}
        ]}
        """)
        #expect(input.accessibilityTitleUIElement() == nil)
        #expect(input.accessibilityHelp() == nil)
    }

    @Test("maps checkbox and switch to retained native controls")
    func mapsToggleControls() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"checkbox"},
          {"op":"create-node","id":2,"kind":"switch"},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Select all"},
          {"op":"set-prop","id":1,"property":"checked","value":true},
          {"op":"set-prop","id":1,"property":"indeterminate","value":true},
          {"op":"set-prop","id":2,"property":"accessibility-label","value":"Notifications"},
          {"op":"set-prop","id":2,"property":"checked","value":true}
        ]}
        """)

        let checkbox = try #require(backend.view(id: 1) as? NSButton)
        let toggle = try #require(backend.view(id: 2) as? NSSwitch)
        #expect(checkbox.allowsMixedState)
        #expect(checkbox.state == .mixed)
        #expect(checkbox.accessibilityLabel() == "Select all")
        #expect(toggle.state == .on)
        #expect(toggle.accessibilityLabel() == "Notifications")

        checkbox.performClick(nil)
        #expect(events == [.toggleChanged(node: 1, checked: true)])
        events.removeAll()

        let originalCheckbox = checkbox
        let originalToggle = toggle
        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"indeterminate","value":false},
          {"op":"set-prop","id":1,"property":"checked","value":false},
          {"op":"set-prop","id":2,"property":"checked","value":false}
        ]}
        """)
        #expect(backend.view(id: 1) === originalCheckbox)
        #expect(backend.view(id: 2) === originalToggle)
        #expect(checkbox.state == .off)
        #expect(toggle.state == .off)

        checkbox.performClick(nil)
        toggle.performClick(nil)
        #expect(events == [
            .toggleChanged(node: 1, checked: true),
            .toggleChanged(node: 2, checked: true),
        ])
    }

    @Test("maps text-area to a retained native multiline editor")
    func mapsTextAreaSemantics() throws {
        let backend = LUIAppleBackend()
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"text-area"},
          {"op":"set-prop","id":1,"property":"text","value":"First line"},
          {"op":"set-prop","id":1,"property":"placeholder","value":"Notes"},
          {"op":"set-prop","id":1,"property":"read-only","value":false},
          {"op":"set-prop","id":1,"property":"min-lines","value":3},
          {"op":"set-prop","id":1,"property":"max-lines","value":6},
          {"op":"set-prop","id":1,"property":"accessibility-label","value":"Todo notes"}
        ]}
        """)

        let area = try #require(backend.view(id: 1) as? LUIAppKitTextArea)
        let originalArea = area
        #expect(area.textView.string == "First line")
        #expect(area.placeholder == "Notes")
        #expect(area.textView.isEditable == true)
        #expect(area.minLines == 3)
        #expect(area.maxLines == 6)
        #expect(area.accessibilityLabel() == "Todo notes")

        area.textView.string = "First line\nSecond line"
        area.textDidChange(Notification(name: NSText.didChangeNotification, object: area.textView))
        #expect(events == [.textChanged(node: 1, text: "First line\nSecond line")])

        try backend.apply(json: """
        {"generation":2,"ops":[
          {"op":"set-prop","id":1,"property":"text","value":"Patched"},
          {"op":"set-prop","id":1,"property":"read-only","value":true}
        ]}
        """)
        #expect(backend.view(id: 1) === originalArea)
        #expect(area.textView.string == "Patched")
        #expect(area.textView.isEditable == false)
    }

    @Test("C ABI accepts the LG wire batch")
    func cABIReceivesWireBatch() {
        luiAppleReset()
        let accepted = Self.initialBatch.withCString(luiAppleApply)
        #expect(accepted == 1)
        luiAppleReset()
    }

    @Test("C ABI forwards toggle events with the next checked value")
    func cABIForwardsToggleEvent() {
        capturedAppleEvent = nil
        luiAppleReset()
        luiAppleSetEventCallback(captureAppleEvent)
        defer {
            luiAppleSetEventCallback(nil)
            luiAppleReset()
        }

        let accepted = """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"checkbox"},
          {"op":"set-prop","id":1,"property":"checked","value":false}
        ]}
        """.withCString(luiAppleApply)

        #expect(accepted == 1)
        #expect(luiApplePerformAction(1) == 1)
        #expect(capturedAppleEvent == CapturedAppleEvent(kind: 2, node: 1, text: "true"))
    }

    private static let initialBatch = """
    {"generation":1,"ops":[
      {"op":"create-node","id":1,"kind":"row"},
      {"op":"create-node","id":2,"kind":"text"},
      {"op":"create-node","id":3,"kind":"button"},
      {"op":"set-prop","id":1,"property":"gap","value":12},
      {"op":"set-prop","id":2,"property":"text","value":"Hello from LG"},
      {"op":"set-prop","id":3,"property":"text","value":"Continue"},
      {"op":"set-prop","id":3,"property":"enabled","value":true},
      {"op":"insert-child","parent":1,"child":2,"index":0},
      {"op":"insert-child","parent":1,"child":3,"index":1}
    ]}
    """
}
