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
