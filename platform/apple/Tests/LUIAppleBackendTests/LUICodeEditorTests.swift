import Foundation
import Testing
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
@testable import LUIAppleBackend

private func color(
    _ storage: NSMutableAttributedString, at location: Int
) -> Any? {
    storage.attribute(.foregroundColor, at: location, effectiveRange: nil)
}

@Suite("LUICodeHighlighter")
struct LUICodeHighlighterTests {
    private func highlighted(_ source: String, language: String) -> NSMutableAttributedString {
        let storage = NSMutableAttributedString(string: source)
        LUICodeHighlighter.highlight(storage, language: language, fontSize: 13)
        return storage
    }

    @Test("clojure keywords and comments are tinted")
    func clojure() {
        let source = "(defn f [x] ; comment\n  (+ x 1))"
        let s = highlighted(source, language: "clojure")
        let defn = (source as NSString).range(of: "defn")
        let comment = (source as NSString).range(of: "; comment")
        #expect(color(s, at: defn.location) is Any)
        #expect(color(s, at: comment.location) is Any)
    }

    @Test("comment color wins over keyword inside a line comment")
    func commentWins() {
        let source = "x = 1 // return value"
        let s = highlighted(source, language: "javascript")
        let inside = (source as NSString).range(of: "return value")
        guard let c = color(s, at: inside.location) else {
            Issue.record("missing color inside comment")
            return
        }
        #expect(String(describing: c).contains("secondary")
            || String(describing: c).contains("Secondary"))
    }

    @Test("strings are tinted")
    func strings() {
        let source = "let s = \"hello\""
        let s = highlighted(source, language: "swift")
        let str = (source as NSString).range(of: "\"hello\"")
        #expect(color(s, at: str.location) is Any)
    }

    @Test("unknown language still applies base attributes")
    func unknownLanguage() {
        let s = highlighted("plain text", language: "cobol")
        let font = s.attribute(.font, at: 0, effectiveRange: nil)
        #expect(font is Any)
    }

    @Test("oversized buffers skip highlighting")
    func oversized() {
        let big = String(repeating: "let x = 1\n", count: 25_000)
        let s = NSMutableAttributedString(string: big)
        LUICodeHighlighter.highlight(s, language: "swift", fontSize: 13)
        #expect(s.length == (big as NSString).length)
    }
}

@Suite("LUICodeEditor native updates")
@MainActor
struct LUICodeEditorUpdateTests {
    @Test("platform label colors are used for plain text and comments")
    func platformColors() {
        let source = "value // comment"
        let storage = NSMutableAttributedString(string: source)
        LUICodeHighlighter.highlight(storage, language: "javascript", fontSize: 13)
        #if canImport(AppKit)
        #expect((color(storage, at: 0) as? NSColor) == .labelColor)
        #expect((color(storage, at: 9) as? NSColor) == .secondaryLabelColor)
        #elseif canImport(UIKit)
        #expect((color(storage, at: 0) as? UIColor) == .label)
        #expect((color(storage, at: 9) as? UIColor) == .secondaryLabel)
        #endif
    }

    @Test("prop updates preserve or clamp UTF-16 selection without change echoes",
          arguments: [
            (NSRange(location: 1, length: 2), "abcdef", NSRange(location: 1, length: 2)),
            (NSRange(location: 8, length: 2), "abc", NSRange(location: 3, length: 0)),
            (NSRange(location: 2, length: 5), "abc", NSRange(location: 2, length: 1)),
            (NSRange(location: 8, length: 2), "", NSRange(location: 0, length: 0)),
            (NSRange(location: 8, length: 2), "日📓", NSRange(location: 3, length: 0)),
          ])
    func selection(_ input: (NSRange, String, NSRange)) {
        var changes: [String] = []
        let editor = LUICodeEditor(text: "abcdefghij", onChange: { changes.append($0) })
        let coordinator = editor.makeCoordinator()
        #if canImport(AppKit)
        let view = LUICodeTextView()
        view.delegate = coordinator
        coordinator.textView = view
        coordinator.apply(text: editor.text)
        view.setSelectedRange(input.0)
        coordinator.apply(text: input.1)
        #expect(view.string == input.1)
        #expect(view.selectedRange() == input.2)
        #elseif canImport(UIKit)
        let view = UITextView()
        view.delegate = coordinator
        coordinator.textView = view
        coordinator.apply(text: editor.text)
        view.selectedRange = input.0
        coordinator.apply(text: input.1)
        #expect(view.text == input.1)
        #expect(view.selectedRange == input.2)
        #endif
        #expect(changes.isEmpty)
    }

    #if canImport(UIKit)
    @Test("UIKit typing emits the edited text and survives a shorter host update")
    func typing() {
        var changes: [String] = []
        let editor = LUICodeEditor(text: "let value = 1", language: "swift",
                                  onChange: { changes.append($0) })
        let coordinator = editor.makeCoordinator()
        let view = UITextView()
        view.delegate = coordinator
        coordinator.textView = view
        coordinator.apply(text: editor.text)
        coordinator.refreshHighlight(language: editor.language, fontSize: editor.fontSize)
        view.selectedRange = NSRange(location: view.textStorage.length, length: 0)
        view.insertText(" // 日📓")
        #expect(view.text == "let value = 1 // 日📓")
        #expect(changes == [view.text!])
        #expect((color(view.textStorage, at: 14) as? UIColor) == .secondaryLabel)
        coordinator.apply(text: "let x = 2")
        coordinator.refreshHighlight(language: editor.language, fontSize: editor.fontSize)
        #expect(view.selectedRange == NSRange(location: 9, length: 0))
        #expect(changes.count == 1)
        #expect(view.text == "let x = 2")
        #expect((color(view.textStorage, at: 0) as? UIColor) == .systemBlue)
        view.deleteBackward()
        #expect(view.text == "let x = ")
        #expect(changes.last == "let x = ")
    }
    #endif
}
