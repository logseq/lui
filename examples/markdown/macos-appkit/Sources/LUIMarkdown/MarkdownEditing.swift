#if canImport(AppKit)
import AppKit
import LUIAppleBackend
import UniformTypeIdentifiers

// Editing behaviors on top of the plain NSTextView: list/quote continuation,
// auto-paired delimiters, skip-over closers, empty-pair deletion, selection
// wrapping, per-line block transforms and file-open/save hooks. Everything
// edits through `applyEdit` so the storage delegate (highlighter) and the
// undo manager see one coherent mutation.

final class MarkdownTextView: NSTextView, NSTextViewDelegate {

    /// Set by the representable; pushes extension events to the OCaml model.
    var emitEvent: ((String, [String: LUIExtensionValue]) -> Void)?
    var highlighter: MarkdownHighlighter?

    /// The host menu routes Open/Save to whichever editor is mounted.
    static weak var active: MarkdownTextView?

    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }
    private var placeholderColor = NSColor.placeholderTextColor

    /// Tracks a just-inserted empty pair ("*|*"): typing the closing char
    /// skips over it instead of doubling it.
    private var pendingPairCloser: (char: Character, location: Int)?

    private let symmetricPairs: [Character: Character] = [
        "*": "*", "_": "_", "`": "`", "~": "~", "=": "=",
        "$": "$", "\"": "\"", "'": "'",
    ]
    private let asymmetricPairs: [Character: Character] = ["[": "]", "(": ")"]
    /// Pairs only when the caret sits at a word boundary (snake_case, =~,
    /// path/name shouldn't explode into pairs).
    private let boundaryPairs: Set<Character> = ["_", "~", "=", "\"", "'"]

    private var nsString: NSString { string as NSString }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        delegate = self
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
        configure()
    }

    private func configure() {
        isRichText = true
        importsGraphics = true
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainerInset = NSSize(width: 24, height: 28)
        usesAdaptiveColorMappingForDarkAppearance = true

        // smart substitutions corrupt markdown source
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false

        registerForDraggedTypes([.fileURL])
        Self.active = self
    }

    // MARK: - model sync

    private func emitTextChanged() {
        emitEvent?("text-changed", [
            "text": .string(string),
            "caret": .int(selectedRange().location),
        ])
    }

    func textDidChange(_ notification: Notification) {
        emitTextChanged()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard nsString.length > 0 else { return }
        // Reveal markers only when the caret crosses into another paragraph —
        // same-line moves don't change what is shown.
        if let highlighter {
            // paragraphRange reads the character at range.location — clamp to
            // the last char since a caret at the end of the string is out of bounds.
            let sel = selectedRange()
            let last = nsString.length - 1
            let start = min(sel.location, last)
            var paragraph = nsString.paragraphRange(for: NSRange(
                location: start, length: 0))
            let end = min(NSMaxRange(sel), last)
            if end > start {
                paragraph = NSUnionRange(paragraph, nsString.paragraphRange(
                    for: NSRange(location: start, length: end - start)))
            }
            let previous = nsString.paragraphRange(for: NSRange(
                location: min(highlighter.activeCharacterRange.location, last),
                length: 0))
            if paragraph != previous
                || highlighter.activeCharacterRange.length != selectedRange().length {
                highlighter.activeCharacterRange = selectedRange()
                highlighter.restyle()
            }
        }
        emitEvent?("cursor", ["caret": .int(selectedRange().location)])
    }

    // MARK: - text entry

    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString replacement: String?
    ) -> Bool {
        guard isEditable, let replacement else { return isEditable }

        // newline: continue or exit block structure
        if replacement == "\n" {
            return !handleReturn(affectedCharRange)
        }
        // tab: indent/outdent
        if replacement == "\t" {
            return !indentSelection(outdent: false)
        }
        // paste drops straight through
        guard replacement.count == 1, let typed = replacement.first else {
            return true
        }
        // skip-over a pending closer (typing `]` over `]` inside `[]|]`)
        if let pending = pendingPairCloser,
           affectedCharRange.length == 0,
           pending.char == typed, pending.location == affectedCharRange.location {
            pendingPairCloser = nil
            setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
            return false
        }
        pendingPairCloser = nil
        // symmetric closers: skip over when the next char is the same
        // delimiter and we did not just open a fresh pair here.
        if affectedCharRange.length == 0,
           symmetricPairs.keys.contains(typed),
           affectedCharRange.location < nsString.length,
           charAt(affectedCharRange.location) == typed {
            setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
            return false
        }
        // backspace: an empty pair collapses to nothing
        if replacement.isEmpty, affectedCharRange.length == 1,
           deleteEmptyPair(at: affectedCharRange.location) {
            return false
        }
        // openers: wrap a selection, or insert the pair at a word boundary
        if let closer = matchingCloser(for: typed) {
            if affectedCharRange.length > 0 {
                wrapSelection(with: String(typed), closer: String(closer), range: affectedCharRange)
                return false
            }
            if shouldAutoPair(typed, at: affectedCharRange.location) {
                insertPair(typed, closer, at: affectedCharRange.location)
                return false
            }
        }
        return true
    }

    private func matchingCloser(for typed: Character) -> Character? {
        symmetricPairs[typed] ?? asymmetricPairs[typed]
    }

    private func shouldAutoPair(_ char: Character, at location: Int) -> Bool {
        if !boundaryPairs.contains(char) { return true }
        guard let previous = charAt(location - 1) else { return true }
        return previous.isWhitespace || previous.isNewline
            || "([{\"'`~=_-—…,.;:!?".contains(previous)
    }

    private func charAt(_ location: Int) -> Character? {
        guard location >= 0, location < nsString.length else { return nil }
        return nsString.substring(with: NSRange(location: location, length: 1)).first
    }

    private func isMember(_ code: unichar, of set: CharacterSet) -> Bool {
        Unicode.Scalar(code).map(set.contains) == true
    }

    private func insertPair(_ open: Character, _ close: Character, at location: Int) {
        let inserted = String([open, close])
        applyEdit(range: NSRange(location: location, length: 0), replacement: inserted)
        setSelectedRange(NSRange(location: location + 1, length: 0))
        pendingPairCloser = (close, location + 1)
    }

    private func deleteEmptyPair(at location: Int) -> Bool {
        // location is the char about to be deleted (range location)
        guard location > 0, location < nsString.length else { return false }
        guard let b = charAt(location - 1), let a = charAt(location) else { return false }
        guard symmetricPairs[b] == a || asymmetricPairs[b] == a else { return false }
        applyEdit(range: NSRange(location: location - 1, length: 2), replacement: "")
        setSelectedRange(NSRange(location: location - 1, length: 0))
        return true
    }

    // MARK: - return / list continuation

    /// Returns true when the newline was handled here (caller swallows it).
    private func handleReturn(_ range: NSRange) -> Bool {
        let text = nsString
        let caret = range.location
        let line = text.lineRange(for: NSRange(location: min(caret, text.length), length: 0))
        var content = line
        while content.length > 0,
              isMember(text.character(at: NSMaxRange(content) - 1), of: .newlines) {
            content.length -= 1
        }
        let lineText = (content.length > 0 ? text.substring(with: content) : "") as NSString

        // inside a fenced block: keep it dumb — raw newline, no continuation
        if isInsideCodeFence(at: caret) {
            return false
        }

        let task = Regexes.task.firstMatch(in: lineText as String, range: NSRange(location: 0, length: lineText.length))
        let bullet = Regexes.bullet.firstMatch(in: lineText as String, range: NSRange(location: 0, length: lineText.length))
        let ordered = Regexes.ordered.firstMatch(in: lineText as String, range: NSRange(location: 0, length: lineText.length))
        let quote = Regexes.quote.firstMatch(in: lineText as String, range: NSRange(location: 0, length: lineText.length))

        if let match = task ?? bullet {
            return continueList(
                range: range, line: line, match: match.range, ordered: false, number: 0)
        }
        if let match = ordered {
            let number = Int(lineText.substring(with: match.range(at: 2))) ?? 1
            return continueList(
                range: range, line: line, match: match.range, ordered: true, number: number)
        }
        if let match = quote {
            let prefix = lineText.substring(with: match.range(at: 1))
            let rest = lineText.substring(from: NSMaxRange(match.range(at: 1)))
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                // empty quote line → drop the marker, stay on the line
                applyEdit(range: NSRange(location: content.location + match.range(at: 1).location,
                                         length: match.range(at: 1).length),
                          replacement: "")
                setSelectedRange(NSRange(location: content.location, length: 0))
            } else {
                applyEdit(range: range, replacement: "\n" + String(repeating: "> ", count: prefix.filter { $0 == ">" }.count))
            }
            return true
        }
        // Heading / hr lines end the structure: a plain newline.
        return false
    }

    private func continueList(
        range: NSRange, line: NSRange, match: NSRange, ordered: Bool, number: Int
    ) -> Bool {
        let text = nsString
        let prefix = text.substring(with: NSRange(location: line.location + match.location,
                                                  length: match.length))
        // line content after the marker, excluding the trailing newline
        var tailEnd = NSMaxRange(line)
        while tailEnd > line.location + NSMaxRange(match),
              isMember(text.character(at: tailEnd - 1), of: .newlines) {
            tailEnd -= 1
        }
        let rest = text.substring(with: NSRange(
            location: line.location + NSMaxRange(match),
            length: max(0, tailEnd - (line.location + NSMaxRange(match)))))
        let restOnLine = rest.trimmingCharacters(in: .whitespaces)
        if restOnLine.isEmpty {
            // lone marker → convert the line back to a paragraph
            applyEdit(range: NSRange(location: line.location + match.location,
                                     length: match.length),
                      replacement: "")
            setSelectedRange(NSRange(location: line.location, length: 0))
            return true
        }
        let continued: String
        if ordered {
            let digits = "\(number + 1)"
            var next = prefix
            if let digitsRange = next.range(of: "\\d+", options: .regularExpression) {
                next.replaceSubrange(digitsRange, with: digits)
            }
            continued = "\n" + next
        } else if prefix.contains("[x]") || prefix.contains("[X]") {
            continued = "\n" + prefix.replacingOccurrences(of: "[x]", with: "[ ]")
                .replacingOccurrences(of: "[X]", with: "[ ]")
        } else {
            continued = "\n" + prefix
        }
        applyEdit(range: range, replacement: continued)
        return true
    }

    private func isInsideCodeFence(at location: Int) -> Bool {
        // count fence markers above the caret; odd → inside
        let text = nsString
        var depth = 0
        var position = 0
        let pattern = Regexes.fence
        while position < min(location, text.length) {
            let line = text.lineRange(for: NSRange(location: position, length: 0))
            if pattern.firstMatch(in: text as String, range: line) != nil {
                depth += 1
            }
            position = NSMaxRange(line)
        }
        return depth % 2 == 1
    }

    // MARK: - indentation

    @discardableResult
    private func indentSelection(outdent: Bool) -> Bool {
        let selection = selectedRange()
        let lineCount = selectedLineRanges().count
        let lines = nsString.lineRange(for: selection)
        var edited = false
        var cursor = lines.location
        var shift = 0
        for _ in 0..<lineCount where cursor <= nsString.length {
            if outdent {
                var remove = 0
                while remove < 2,
                      cursor + remove < nsString.length,
                      nsString.character(at: cursor + remove) == 0x20 {
                    remove += 1
                }
                if remove > 0 {
                    applyEdit(range: NSRange(location: cursor, length: remove), replacement: "")
                    shift -= remove
                    edited = true
                }
            } else {
                applyEdit(range: NSRange(location: cursor, length: 0), replacement: "  ")
                shift += 2
                edited = true
            }
            cursor = NSMaxRange(
                nsString.lineRange(for: NSRange(location: cursor, length: 0)))
        }
        if edited {
            setSelectedRange(NSRange(
                location: max(lines.location, selection.location + shift), length: 0))
        }
        return edited
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertBacktab(_:)) {
            if indentSelection(outdent: true) { return }
        }
        super.doCommand(by: selector)
    }

    // MARK: - key equivalents

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers,
              let key = chars.first else { return super.performKeyEquivalent(with: event) }
        let shift = event.modifierFlags.contains(.shift)
        switch (key, shift) {
        case ("b", false): toggleWrap("**")
        case ("i", false): toggleWrap("*")
        case ("e", false): toggleWrap("`")
        case ("k", false): insertLink()
        case ("x", true): toggleWrap("~~")
        case ("h", true): toggleWrap("==")
        case ("m", true): toggleWrap("$")
        case ("0", false): setHeadingLevel(0)
        case ("1", false): setHeadingLevel(1)
        case ("2", false): setHeadingLevel(2)
        case ("3", false): setHeadingLevel(3)
        case ("4", false): setHeadingLevel(4)
        case ("5", false): setHeadingLevel(5)
        case ("6", false): setHeadingLevel(6)
        case ("c", true): toggleCodeBlock()
        case ("q", true): toggleLinePrefix("> ")
        case ("u", true): toggleLinePrefix("- ")
        case ("o", true): toggleOrderedList()
        case ("t", true): toggleLinePrefix("- [ ] ")
        case ("=", false), ("+", false): adjustFontSize(1)
        case ("-", false): adjustFontSize(-1)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func adjustFontSize(_ delta: CGFloat) {
        guard let highlighter else { return }
        highlighter.theme.fontSize = max(10, min(28, highlighter.theme.fontSize + delta))
        highlighter.restyle()
    }

    // MARK: - inline transforms

    private func wrapSelection(with open: String, closer: String, range: NSRange) {
        let text = nsString
        let content = text.substring(with: range)
        applyEdit(range: range, replacement: open + content + closer)
        setSelectedRange(NSRange(location: range.location + open.count, length: range.length))
    }

    @discardableResult
    func toggleWrap(_ marker: String) -> Bool {
        let selection = selectedRange()
        var range = selection
        if range.length == 0 {
            // expand to the word under the caret
            let text = nsString
            var start = range.location
            var end = range.location
            while start > 0 {
                let c = text.character(at: start - 1)
                guard !isMember(c, of: .whitespacesAndNewlines),
                      !isMember(c, of: .punctuationCharacters)
                else { break }
                start -= 1
            }
            while end < text.length {
                let c = text.character(at: end)
                guard !isMember(c, of: .whitespacesAndNewlines),
                      !isMember(c, of: .punctuationCharacters)
                else { break }
                end += 1
            }
            range = NSRange(location: start, length: end - start)
        }
        let text = nsString
        // unwrap when the selection is already wrapped
        let open = marker
        let around = range.length > 0
            && range.location >= open.count
            && NSMaxRange(range) + open.count <= text.length
            && text.substring(with: NSRange(location: range.location - open.count, length: open.count)) == open
            && text.substring(with: NSRange(location: NSMaxRange(range), length: open.count)) == marker
        if around {
            applyEdit(
                range: NSRange(location: NSMaxRange(range), length: marker.count),
                replacement: "")
            applyEdit(
                range: NSRange(location: range.location - open.count, length: open.count),
                replacement: "")
            setSelectedRange(NSRange(
                location: range.location - open.count, length: range.length))
            return true
        }
        guard range.length > 0 else { return false }
        wrapSelection(with: open, closer: marker, range: range)
        return true
    }

    // MARK: - block transforms

    private static let prefixRegex = try! NSRegularExpression(
        pattern: "^\\s{0,3}(?:#{1,6}[ \\t]+|(?:>[ \\t]?)+|[-*+][ \\t]+(?:\\[[ xX]\\][ \\t]+)?|\\d+[.)][ \\t]+(?:\\[[ xX]\\][ \\t]+)?)?",
        options: [])

    func setHeadingLevel(_ level: Int) {
        let insert = level > 0 ? String(repeating: "#", count: level) + " " : ""
        forEachSelectedLine { line in
            let stripped = Self.prefixRegex.firstMatch(in: nsString as String, range: line)?
                .range.length ?? 0
            applyEdit(range: NSRange(location: line.location, length: stripped),
                      replacement: insert)
        }
    }

    func toggleLinePrefix(_ prefix: String) {
        let lines = selectedLineRanges()
        let allPrefixed = lines.allSatisfy { range in
            nsString.substring(with: range).hasPrefix(prefix)
        }
        forEachSelectedLine { line in
            let stripped = Self.prefixRegex.firstMatch(in: nsString as String, range: line)?
                .range.length ?? 0
            applyEdit(range: NSRange(location: line.location, length: stripped),
                      replacement: allPrefixed ? "" : prefix)
        }
    }

    func toggleOrderedList() {
        // forEachSelectedLine walks lines last → first, so count down
        var number = selectedLineRanges().count
        forEachSelectedLine { line in
            let stripped = Self.prefixRegex.firstMatch(in: nsString as String, range: line)?
                .range.length ?? 0
            applyEdit(range: NSRange(location: line.location, length: stripped),
                      replacement: "\(number). ")
            number -= 1
        }
    }

    func toggleCodeBlock() {
        let lines = selectedLineRanges()
        guard let first = lines.first, let last = lines.last else { return }
        let text = nsString
        let firstIsFence = Regexes.fence.firstMatch(in: text as String, range: first) != nil
        let lastIsFence = Regexes.fence.firstMatch(in: text as String, range: last) != nil
        if firstIsFence && lastIsFence && lines.count > 2 {
            // already fenced: drop both fence lines
            applyEdit(range: last, replacement: "")
            applyEdit(range: first, replacement: "")
            return
        }
        let span = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var content = text.substring(with: span)
        if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
        applyEdit(range: span, replacement: "```\n" + content + "```\n")
    }

    /// Apply `transform` to every line touching the selection. Runs last →
    /// first so edits can't invalidate the ranges of lines not yet visited;
    /// the caret lands at the start of its original line.
    private func forEachSelectedLine(_ transform: (NSRange) -> Void) {
        let lines = selectedLineRanges()
        let anchor = nsString.lineRange(for: selectedRange()).location
        for line in lines.reversed() { transform(line) }
        setSelectedRange(NSRange(location: min(anchor, nsString.length), length: 0))
    }

    private func selectedLineRanges() -> [NSRange] {
        var selection = selectedRange()
        // a selection ending exactly on a line break shouldn't claim the
        // following empty line
        if selection.length > 0,
           charAt(NSMaxRange(selection) - 1)?.isNewline == true {
            selection.length -= 1
        }
        let text = nsString
        let whole = text.lineRange(for: selection)
        var ranges: [NSRange] = []
        var cursor = whole.location
        while cursor < NSMaxRange(whole) {
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            ranges.append(line)
            cursor = NSMaxRange(line)
        }
        if ranges.isEmpty { ranges.append(whole) }
        return ranges
    }

    // MARK: - links

    func insertLink() {
        let selection = selectedRange()
        var url = ""
        let board = NSPasteboard.general.string(forType: .string) ?? ""
        if board.hasPrefix("http://") || board.hasPrefix("https://") {
            url = board
        }
        if selection.length > 0 {
            let title = nsString.substring(with: selection)
            applyEdit(range: selection, replacement: "[\(title)](\(url))")
            // caret inside () when the URL slot is empty, else after the link
            let caret = url.isEmpty
                ? selection.location + title.count + 3
                : selection.location + title.count + 4 + url.count
            setSelectedRange(NSRange(location: caret, length: 0))
        } else {
            applyEdit(range: selection, replacement: "[](\(url))")
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        }
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        if let url = link as? URL {
            NSWorkspace.shared.open(url)
        } else if let string = link as? String, let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let container = textContainer {
            let point = convert(event.locationInWindow, from: nil)
            let origin = CGPoint(x: point.x - textContainerInset.width,
                                 y: point.y - textContainerInset.height)
            let index = layoutManager?.characterIndex(for: origin, in: container,
                                                      fractionOfDistanceBetweenInsertionPoints: nil)
                ?? NSNotFound
            if index != NSNotFound, index < nsString.length,
               let link = textStorage?.attribute(.link, at: index, effectiveRange: nil) {
                if let url = link as? URL {
                    NSWorkspace.shared.open(url)
                } else if let string = link as? String, let url = URL(string: string) {
                    NSWorkspace.shared.open(url)
                }
                return
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - file drops

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        if let urls = board.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            var insertion = ""
            for url in urls {
                let path = url.path
                let isImage = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"]
                    .contains(url.pathExtension.lowercased())
                insertion += isImage ? "![](\(path))" : "[\(url.lastPathComponent)](\(path))"
            }
            applyEdit(range: selectedRange(), replacement: insertion)
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: - file menu

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, .init(filenameExtension: "md")].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        applyEdit(range: NSRange(location: 0, length: nsString.length), replacement: content)
        setSelectedRange(NSRange(location: 0, length: 0))
        emitEvent?("path-changed", ["path": .string(url.path)])
    }

    @objc func saveDocument(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "untitled.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")].compactMap { $0 }
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? string.write(to: url, atomically: true, encoding: .utf8)
        emitEvent?("path-changed", ["path": .string(url.path)])
    }

    // MARK: - helpers

    /// Single funnel for every programmatic edit: storage mutation + change
    /// notification so the highlighter restyles and the model hears it.
    func applyEdit(range: NSRange, replacement: String) {
        guard let storage = textStorage else { return }
        // shouldChangeText registers the undo group and re-checks the delegate;
        // multi-char or empty replacements pass straight through it.
        guard shouldChangeText(in: range, replacementString: replacement)
        else { return }
        storage.replaceCharacters(in: range, with: replacement)
        // didChangeText fires textDidChange → emits to the model
        didChangeText()
    }

    // MARK: - placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: highlighter?.theme.fontSize ?? 15),
            .foregroundColor: placeholderColor,
        ]
        let origin = CGPoint(x: textContainerInset.width + 4,
                             y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: attrs)
    }
}

private enum Regexes {
    static let task = try! NSRegularExpression(
        pattern: "^(\\s*)([-*+]|\\d+[.)])[ \\t]+\\[( |x|X)\\][ \\t]+", options: [])
    static let bullet = try! NSRegularExpression(
        pattern: "^(\\s*)[-*+][ \\t]+", options: [])
    static let ordered = try! NSRegularExpression(
        pattern: "^(\\s*)(\\d+)[.)][ \\t]+", options: [])
    static let quote = try! NSRegularExpression(
        pattern: "^\\s{0,3}((?:>[ \\t]?)+)", options: [])
    static let fence = try! NSRegularExpression(
        pattern: "^\\s{0,3}(```|~~~)", options: [])
}
#endif
