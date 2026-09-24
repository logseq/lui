#if canImport(AppKit)
import AppKit

// The styling engine behind the seamless editor: every text change and every
// caret move re-derives paragraph + inline attributes for the whole document.
// Structural lines (fences, tables, math) also register "decorations" that
// MarkdownLayoutManager draws underneath the text — block backgrounds, quote
// bars, rules — because .backgroundColor attributes only cover glyphs.
//
// "Markers" are the delimiter runs (#, **, >, ``, |, [](url), $$, ---, ...) —
// they stay tinted while the caret is on their line and are concealed
// (0.1pt clear font) once it leaves: the file remains plain markdown while
// the screen reads as rendered output.

final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {

    // MARK: - theme

    struct Theme {
        var fontSize: CGFloat = 15

        var bodyFont: NSFont { NSFont.systemFont(ofSize: fontSize) }
        var codeFont: NSFont { NSFont.monospacedSystemFont(ofSize: fontSize - 1.5, weight: .regular) }
        func headingFont(_ level: Int) -> NSFont {
            let sizes: [CGFloat] = [26, 23, 20, 17.5, 16, 15]
            let size = sizes[max(0, min(level - 1, sizes.count - 1))]
            return NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
        }
        var boldFont: NSFont { NSFont.systemFont(ofSize: fontSize, weight: .semibold) }

        var textColor = NSColor.textColor
        var secondaryText = NSColor.secondaryLabelColor
        var markerDim = NSColor.tertiaryLabelColor
        var markerActive = NSColor.secondaryLabelColor
        var linkColor = NSColor.linkColor
        var codeText = NSColor.textColor
        var codeBackground = NSColor.quaternaryLabelColor
        var quoteBar = NSColor.systemBlue.withAlphaComponent(0.55)
        var quoteText = NSColor.secondaryLabelColor
        var tableBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.5)
        var mathText = NSColor.systemPurple
        var mathBackground = NSColor.systemPurple.withAlphaComponent(0.08)
        var highlightBackground = NSColor.systemYellow.withAlphaComponent(0.35)
        var frontMatterText = NSColor.secondaryLabelColor
        var frontMatterBackground = NSColor.quaternaryLabelColor.withAlphaComponent(0.4)
        var checkedTask = NSColor.tertiaryLabelColor
        var ruleColor = NSColor.separatorColor
    }

    struct Decoration {
        enum Kind: Equatable {
            case codeBlock
            case quoteBar(depth: Int)
            case rule
            case tableBlock
            case mathBlock
            case frontMatter
            case imageChip
        }
        var range: NSRange
        var kind: Kind
    }

    var theme = Theme()
    var decorations: [Decoration] = []

    /// Glyphs the caret touches reveal their markers; everything else hides them.
    var activeCharacterRange: NSRange = NSRange(location: 0, length: 0)
    /// Above this document size the active-line reveal is skipped so a huge
    /// file can never stall typing.
    var activeRevealLimit = 300_000
    /// Re-entrancy guard: styling mutates attributes, which re-fires
    /// didProcessEditing — bail while applying.
    private var isApplying = false

    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard !isApplying, editedMask.contains(.editedCharacters) || delta != 0 else { return }
        restyle()
    }

    // MARK: - public

    /// Re-run styling for the whole document. Called on every edit and every
    /// caret move; cheap enough for documents in the tens of KB.
    func restyle() {
        guard let textView, let storage = textView.textStorage, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let selection = textView.selectedRange()
        activeCharacterRange = selection

        storage.beginEditing()
        let base = NSMutableParagraphStyle()
        base.lineSpacing = 4
        base.paragraphSpacing = 6
        storage.setAttributes([
            .font: theme.bodyFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: base,
        ], range: full)

        decorations = []
        var markerRanges: [NSRange] = []      // hidden once the line loses the caret
        var alwaysDimRanges: [NSRange] = []   // structural noise kept faint always

        // Line-level pass: classify + style + collect decorations.
        var inFence = false
        var fenceMarker = ""
        var inMathBlock = false
        var inFrontMatter = false
        var frontMatterDone = false
        var tableOpen = false
        var tableStart = 0
        var lineIndex = 0

        text.enumerateSubstrings(in: full, options: [.byLines]) { _, lineRange, _, _ in
            let line = lineRange
            defer { lineIndex += 1 }
            let content = self.trimmedContent(of: line, in: text)

            // --- front matter: `---` .. `---`/`...` at document start
            if lineIndex == 0, !frontMatterDone, !inFrontMatter, self.isRuleLine(content, in: text) {
                inFrontMatter = true
            }
            if inFrontMatter {
                self.styleFrontMatterLine(line, in: text, dimmed: &alwaysDimRanges)
                if lineIndex > 0, self.isRuleLine(content, in: text) || self.isDotsLine(content, in: text) {
                    inFrontMatter = false
                    frontMatterDone = true
                }
                return
            }

            // --- fenced code: ``` or ~~~
            if let fence = self.fenceInfo(content, in: text) {
                if !inFence {
                    inFence = true
                    fenceMarker = fence.marker
                    self.markCodeStart(at: line.location)
                    self.styleFenceLine(line, font: self.theme.codeFont, dimmed: &alwaysDimRanges)
                } else if fence.marker == fenceMarker {
                    inFence = false
                    self.styleFenceLine(line, font: self.theme.codeFont, dimmed: &alwaysDimRanges)
                    self.markCodeEnd(at: NSMaxRange(line))
                }
                return
            }
            if inFence {
                self.styleCodeLine(line, font: self.theme.codeFont)
                return
            }

            // --- display math $$ .. $$
            if self.isMathFence(content, in: text) {
                if !inMathBlock {
                    inMathBlock = true
                    self.markMathStart(at: line.location)
                    self.styleDimLine(line, font: self.theme.codeFont, dimmed: &alwaysDimRanges)
                } else {
                    inMathBlock = false
                    self.styleDimLine(line, font: self.theme.codeFont, dimmed: &alwaysDimRanges)
                    self.markMathEnd(at: NSMaxRange(line))
                }
                return
            }
            if inMathBlock {
                self.styleMathLine(line)
                return
            }

            // --- tables
            if self.isTableRow(content, in: text) {
                if !tableOpen { tableOpen = true; tableStart = line.location }
                self.styleTableLine(line, content: content, in: text)
                return
            }
            self.flushTable(upTo: line.location, open: &tableOpen, start: &tableStart)

            // --- structural line kinds
            if let heading = self.headingInfo(content, in: text) {
                self.styleHeading(line, heading: heading, markers: &markerRanges)
            } else if self.isRuleLine(content, in: text) {
                self.decorations.append(.init(range: content, kind: .rule))
                markerRanges.append(content)
            } else if let quote = self.quoteInfo(content, in: text) {
                self.styleQuote(line, quote: quote, markers: &markerRanges)
            } else if let task = self.taskInfo(content, in: text) {
                self.styleTask(line, task: task, dimmed: &alwaysDimRanges)
            } else if let item = self.listItemInfo(content, in: text) {
                self.styleListItem(line, item: item)
            }

            // --- inline pass on the rendered content
            self.applyInline(in: text, line: line, markers: &markerRanges,
                             alwaysDim: &alwaysDimRanges)
        }

        self.flushTable(upTo: text.length, open: &tableOpen, start: &tableStart)
        self.closeCodeBlock(at: text.length)
        self.closeMathBlock(at: text.length)

        // Marker treatment: concealed everywhere except the active paragraph.
        let reveal = self.revealRange(in: text)
        for range in markerRanges {
            if reveal == nil || NSIntersectionRange(range, reveal!).length > 0 {
                storage.addAttributes([
                    .foregroundColor: theme.markerActive
                ], range: range)
            } else {
                storage.addAttributes([
                    .font: NSFont.systemFont(ofSize: 0.1),
                    .foregroundColor: NSColor.clear,
                ], range: range)
            }
        }
        for range in alwaysDimRanges {
            storage.addAttribute(.foregroundColor, value: theme.markerDim, range: range)
        }
        storage.endEditing()

        decorations = self.mergedDecorations()
        (textView.layoutManager as? MarkdownLayoutManager)?.decorations = decorations
        // Mid-edit the glyph layout can lag the storage by a character, so an
        // invalidation anchored at the doc end reads past the last index.
        // Defer it until after the current editing turn settles.
        OperationQueue.main.addOperation {
            textView.layoutManager?.invalidateDisplay(forCharacterRange: full)
        }
    }

    /// Paragraph range(s) that keep their markers visible.
    private func revealRange(in text: NSString) -> NSRange? {
        guard text.length <= activeRevealLimit, text.length > 0 else { return nil }
        // paragraphRange reads the character at range.location — out of bounds
        // when the caret sits at the end of the string, so clamp to the last char.
        let last = text.length - 1
        let start = min(activeCharacterRange.location, last)
        var range = text.paragraphRange(for: NSRange(location: start, length: 0))
        let end = min(NSMaxRange(activeCharacterRange), last)
        if end > start {
            range = NSUnionRange(range, text.paragraphRange(for: NSRange(
                location: start, length: end - start)))
        }
        return range
    }

    // MARK: - line classification

    private func trimmedContent(of line: NSRange, in text: NSString) -> NSRange {
        var range = line
        while range.length > 0,
              isMember(text.character(at: NSMaxRange(range) - 1), of: .newlines) {
            range.length -= 1
        }
        return range
    }

    private func substring(_ range: NSRange, in text: NSString) -> String {
        guard range.location + range.length <= text.length else { return "" }
        return text.substring(with: range)
    }

    private func isMember(_ code: unichar, of set: CharacterSet) -> Bool {
        Unicode.Scalar(code).map(set.contains) == true
    }

    private static let headingRegex = try! NSRegularExpression(
        pattern: "^(#{1,6})[ \\t]+", options: [])
    private static let ruleRegex = try! NSRegularExpression(
        pattern: "^\\s{0,3}(-{3,}|\\*{3,}|_{3,})\\s*$", options: [])
    private static let dotsRegex = try! NSRegularExpression(
        pattern: "^\\s{0,3}\\.\\.\\.\\s*$", options: [])
    private static let quoteRegex = try! NSRegularExpression(
        pattern: "^\\s{0,3}((?:>[ \\t]?)+)", options: [])
    private static let taskRegex = try! NSRegularExpression(
        pattern: "^(\\s*)([-*+]|\\d+[.)])[ \\t]+\\[( |x|X)\\][ \\t]+", options: [])
    private static let bulletRegex = try! NSRegularExpression(
        pattern: "^(\\s*)[-*+][ \\t]+", options: [])
    private static let orderedRegex = try! NSRegularExpression(
        pattern: "^(\\s*)(\\d+)[.)][ \\t]+", options: [])
    private static let fenceRegex = try! NSRegularExpression(
        pattern: "^\\s{0,3}(```|~~~)(.*)$", options: [])
    private static let mathFenceRegex = try! NSRegularExpression(
        pattern: "^\\s*\\$\\$\\s*$", options: [])
    private static let tableSepRegex = try! NSRegularExpression(
        pattern: "^\\s*\\|?[\\s:|-]+\\|?\\s*$", options: [])
    private static let pipeRegex = try! NSRegularExpression(pattern: "\\|", options: [])

    struct HeadingInfo { var level: Int; var marker: NSRange }
    struct QuoteInfo { var depth: Int; var marker: NSRange }
    struct TaskInfo {
        var indent: Int; var checked: Bool; var marker: NSRange; var content: NSRange
    }
    struct ListItemInfo {
        var indent: Int; var ordered: Bool; var number: Int
        var marker: NSRange; var content: NSRange
    }

    private func headingInfo(_ content: NSRange, in text: NSString) -> HeadingInfo? {
        let scope = NSRange(location: content.location, length: content.length)
        guard let match = Self.headingRegex.firstMatch(in: text as String, range: scope) else { return nil }
        return HeadingInfo(level: match.range(at: 1).length, marker: match.range)
    }

    private func quoteInfo(_ content: NSRange, in text: NSString) -> QuoteInfo? {
        guard let match = Self.quoteRegex.firstMatch(
            in: text as String, range: content) else { return nil }
        let marker = match.range(at: 1)
        let depth = substring(marker, in: text).filter { $0 == ">" }.count
        return QuoteInfo(depth: depth, marker: marker)
    }

    private func taskInfo(_ content: NSRange, in text: NSString) -> TaskInfo? {
        guard let match = Self.taskRegex.firstMatch(
            in: text as String, range: content) else { return nil }
        let checked = substring(match.range(at: 3), in: text).lowercased() == "x"
        let contentStart = NSMaxRange(match.range)
        return TaskInfo(
            indent: match.range(at: 1).length, checked: checked, marker: match.range,
            content: NSRange(location: contentStart,
                             length: NSMaxRange(content) - contentStart))
    }

    private func listItemInfo(_ content: NSRange, in text: NSString) -> ListItemInfo? {
        if let match = Self.bulletRegex.firstMatch(in: text as String, range: content) {
            return ListItemInfo(
                indent: match.range(at: 1).length, ordered: false, number: 0,
                marker: match.range,
                content: NSRange(location: NSMaxRange(match.range),
                                 length: NSMaxRange(content) - NSMaxRange(match.range)))
        }
        if let match = Self.orderedRegex.firstMatch(in: text as String, range: content) {
            let digits = match.range(at: 2)
            return ListItemInfo(
                indent: match.range(at: 1).length, ordered: true,
                number: Int(substring(digits, in: text)) ?? 1,
                marker: match.range,
                content: NSRange(location: NSMaxRange(match.range),
                                 length: NSMaxRange(content) - NSMaxRange(match.range)))
        }
        return nil
    }

    private func isRuleLine(_ content: NSRange, in text: NSString) -> Bool {
        Self.ruleRegex.firstMatch(in: text as String, range: content) != nil
    }

    private func isDotsLine(_ content: NSRange, in text: NSString) -> Bool {
        Self.dotsRegex.firstMatch(in: text as String, range: content) != nil
    }

    private func fenceInfo(_ content: NSRange, in text: NSString) -> (marker: String, info: NSRange)? {
        guard let match = Self.fenceRegex.firstMatch(in: text as String, range: content) else { return nil }
        return (substring(match.range(at: 1), in: text), match.range(at: 2))
    }

    private func isMathFence(_ content: NSRange, in text: NSString) -> Bool {
        Self.mathFenceRegex.firstMatch(in: text as String, range: content) != nil
    }

    private func isTableRow(_ content: NSRange, in text: NSString) -> Bool {
        guard content.length > 0 else { return false }
        let line = substring(content, in: text)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        // require a leading pipe or at least one interior pipe with text on both sides
        if trimmed.hasPrefix("|") { return true }
        return Self.pipeRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil
            && trimmed.split(separator: "|").count > 1
    }

    // MARK: - code/math block aggregation

    private var codeBlockStart: Int?
    private var mathBlockStart: Int?

    private func markCodeStart(at location: Int) { codeBlockStart = location }
    private func markCodeEnd(at end: Int) {
        guard let start = codeBlockStart else { return }
        decorations.append(.init(
            range: NSRange(location: start, length: end - start), kind: .codeBlock))
        codeBlockStart = nil
    }
    private func closeCodeBlock(at end: Int) { markCodeEnd(at: end) }
    private func markMathStart(at location: Int) { mathBlockStart = location }
    private func markMathEnd(at end: Int) {
        guard let start = mathBlockStart else { return }
        decorations.append(.init(
            range: NSRange(location: start, length: end - start), kind: .mathBlock))
        mathBlockStart = nil
    }
    private func closeMathBlock(at end: Int) { markMathEnd(at: end) }

    private func flushTable(upTo end: Int, open: inout Bool, start: inout Int) {
        guard open else { return }
        open = false
        decorations.append(.init(
            range: NSRange(location: start, length: end - start),
            kind: .tableBlock))
    }

    /// Merge adjacent same-kind spans (consecutive quote lines become one bar,
    /// contiguous front-matter lines one strip).
    private func mergedDecorations() -> [Decoration] {
        var merged: [Decoration] = []
        for decoration in decorations {
            if let last = merged.last, last.kind == decoration.kind,
               NSMaxRange(last.range) >= decoration.range.location {
                merged[merged.count - 1].range =
                    NSUnionRange(last.range, decoration.range)
            } else {
                merged.append(decoration)
            }
        }
        return merged
    }

    // MARK: - block styling

    private func styleHeading(
        _ line: NSRange, heading: HeadingInfo, markers: inout [NSRange]
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        let font = theme.headingFont(heading.level)
        storage.addAttribute(.font, value: font, range: line)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = heading.level == 1 ? 16 : heading.level == 2 ? 12 : 8
        paragraph.paragraphSpacing = 4
        storage.addAttribute(.paragraphStyle, value: paragraph, range: line)
        markers.append(heading.marker)
    }

    private func styleQuote(
        _ line: NSRange, quote: QuoteInfo, markers: inout [NSRange]
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        let paragraph = NSMutableParagraphStyle()
        let indent = CGFloat(quote.depth) * 14 + 10
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        paragraph.lineSpacing = 4
        storage.addAttributes([
            .foregroundColor: theme.quoteText,
            .paragraphStyle: paragraph,
        ], range: line)
        markers.append(quote.marker)
        decorations.append(.init(
            range: line, kind: .quoteBar(depth: quote.depth)))
    }

    private func styleTask(
        _ line: NSRange, task: TaskInfo, dimmed: inout [NSRange]
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        let paragraph = NSMutableParagraphStyle()
        let indent = CGFloat(task.indent) * 8 + 22
        paragraph.firstLineHeadIndent = CGFloat(task.indent) * 8
        paragraph.headIndent = indent
        storage.addAttributes([
            .paragraphStyle: paragraph,
            .foregroundColor: task.checked ? theme.checkedTask : theme.textColor,
        ], range: line)
        if task.checked {
            storage.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: task.content)
        }
        dimmed.append(task.marker)
    }

    private func styleListItem(
        _ line: NSRange, item: ListItemInfo
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        let paragraph = NSMutableParagraphStyle()
        let indent = CGFloat(item.indent) * 8
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent + (item.ordered ? 20 : 14)
        storage.addAttribute(.paragraphStyle, value: paragraph, range: line)
        storage.addAttribute(.foregroundColor, value: theme.linkColor, range: item.marker)
    }

    private func styleFenceLine(
        _ line: NSRange, font: NSFont, dimmed: inout [NSRange]
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.addAttribute(.font, value: font, range: line)
        dimmed.append(line)
    }

    private func styleCodeLine(_ line: NSRange, font: NSFont) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.addAttributes([
            .font: font,
            .foregroundColor: theme.codeText,
        ], range: line)
    }

    private func styleMathLine(_ line: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.addAttributes([
            .font: theme.codeFont,
            .foregroundColor: theme.mathText,
        ], range: line)
    }

    private func styleDimLine(
        _ line: NSRange, font: NSFont, dimmed: inout [NSRange]
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.addAttribute(.font, value: font, range: line)
        dimmed.append(line)
    }

    private func styleFrontMatterLine(
        _ line: NSRange, in text: NSString, dimmed: inout [NSRange]
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.addAttribute(.foregroundColor, value: theme.frontMatterText, range: line)
        decorations.append(.init(range: line, kind: .frontMatter))
        dimmed.append(line)
    }

    private func styleTableLine(
        _ line: NSRange, content: NSRange, in text: NSString
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        storage.addAttribute(.font, value: theme.codeFont, range: line)
        let isSeparator = Self.tableSepRegex.firstMatch(in: text as String, range: content) != nil
        if isSeparator {
            storage.addAttribute(.foregroundColor, value: theme.markerDim, range: line)
        }
        for match in Self.pipeRegex.matches(in: text as String, range: content) {
            storage.addAttribute(.foregroundColor, value: theme.markerDim, range: match.range)
        }
    }

    // MARK: - inline styling

    private static let codeRegex = try! NSRegularExpression(
        pattern: "(``?)([^`\\n]|[^`\\n][^`\\n]*?[^`\\n])\\1", options: [])
    private static let imageRegex = try! NSRegularExpression(
        pattern: "!\\[([^\\]]*)\\]\\(([^)\\s]+)(?:\\s+\"([^\"]*)\")?\\)", options: [])
    private static let linkRegex = try! NSRegularExpression(
        pattern: "\\[([^\\]]+)\\]\\(([^)\\s]+)(?:\\s+\"([^\"]*)\")?\\)", options: [])
    private static let autolinkRegex = try! NSRegularExpression(
        pattern: "<((?:https?|mailto):[^>\\s]+)>", options: [])
    private static let bareURLRegex = try! NSRegularExpression(
        pattern: "https?://[^\\s<>()\"']+", options: [])
    private static let boldRegex = try! NSRegularExpression(
        pattern: "(\\*\\*|__)(.+?)\\1", options: [])
    private static let italicStarRegex = try! NSRegularExpression(
        pattern: "\\*([^*\\n]+)\\*", options: [])
    private static let italicUnderRegex = try! NSRegularExpression(
        pattern: "(?<![\\w])_([^_\\n]+)_(?![\\w])", options: [])
    private static let strikeRegex = try! NSRegularExpression(
        pattern: "~~([^~\\n]+)~~", options: [])
    private static let highlightRegex = try! NSRegularExpression(
        pattern: "==([^=\\n]+)==", options: [])
    private static let mathInlineRegex = try! NSRegularExpression(
        pattern: "\\$([^$\\n]+)\\$", options: [])

    private var fontCache: [String: NSFont] = [:]

    private func fontTraits(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        let key = "\(font.fontName)|\(font.pointSize)|\(bold)|\(italic)"
        if let cached = fontCache[key] { return cached }
        var converted = font
        let manager = NSFontManager.shared
        if bold { converted = manager.convert(converted, toHaveTrait: .boldFontMask) }
        if italic { converted = manager.convert(converted, toHaveTrait: .italicFontMask) }
        fontCache[key] = converted
        return converted
    }

    private func font(at location: Int, in storage: NSTextStorage) -> NSFont {
        guard location < storage.length else { return theme.bodyFont }
        return (storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
            ?? theme.bodyFont
    }

    private func intersectsAny(_ range: NSRange, _ ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange(range, $0).length > 0 }
    }

    private func applyInline(
        in text: NSString, line: NSRange,
        markers: inout [NSRange], alwaysDim: inout [NSRange]
    ) {
        guard let textView, let storage = textView.textStorage else { return }
        let scope = trimmedContent(of: line, in: text)
        guard scope.length > 0 else { return }
        let source = text as String
        var protected: [NSRange] = []

        // inline code — protected from everything else
        for match in Self.codeRegex.matches(in: source, range: scope) {
            let ticks = match.range(at: 1)
            storage.addAttributes([
                .font: theme.codeFont,
                .foregroundColor: theme.codeText,
                .backgroundColor: theme.codeBackground,
            ], range: match.range)
            markers.append(ticks)
            markers.append(NSRange(
                location: NSMaxRange(match.range) - ticks.length, length: ticks.length))
            protected.append(match.range)
        }

        // inline math $x$
        for match in Self.mathInlineRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            storage.addAttribute(.foregroundColor, value: theme.mathText, range: match.range)
            let dollar = NSRange(location: match.range.location, length: 1)
            markers.append(dollar)
            markers.append(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
            protected.append(match.range)
        }

        // images ![alt](url)
        for match in Self.imageRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            let alt = match.range(at: 1)
            storage.addAttributes([
                .backgroundColor: theme.codeBackground,
                .foregroundColor: theme.secondaryText,
            ], range: match.range)
            markers.append(NSRange(location: match.range.location, length: 2))
            markers.append(NSRange(
                location: NSMaxRange(alt),
                length: NSMaxRange(match.range) - NSMaxRange(alt)))
            protected.append(match.range)
        }

        // links [title](url)
        for match in Self.linkRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            let title = match.range(at: 1)
            let url = match.range(at: 2)
            var attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: theme.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            if let link = URL(string: substring(url, in: text)) {
                attrs[.link] = link
            }
            storage.addAttributes(attrs, range: title)
            markers.append(NSRange(location: match.range.location, length: 1))
            markers.append(NSRange(
                location: NSMaxRange(title),
                length: NSMaxRange(match.range) - NSMaxRange(title)))
            protected.append(match.range)
        }

        // autolinks <https://…>
        for match in Self.autolinkRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            storage.addAttributes([
                .foregroundColor: theme.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: URL(string: substring(match.range(at: 1), in: text)) as Any,
            ], range: match.range(at: 1))
            markers.append(NSRange(location: match.range.location, length: 1))
            markers.append(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
            protected.append(match.range)
        }

        // bare urls
        for match in Self.bareURLRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            var attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: theme.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            if let link = URL(string: substring(match.range, in: text)) {
                attrs[.link] = link
            }
            storage.addAttributes(attrs, range: match.range)
            protected.append(match.range)
        }

        // bold **x** / __x__
        for match in Self.boldRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            let content = match.range(at: 2)
            let font = fontTraits(font(at: content.location, in: storage), bold: true, italic: false)
            storage.addAttribute(.font, value: font, range: content)
            let open = match.range(at: 1)
            markers.append(open)
            markers.append(NSRange(
                location: NSMaxRange(match.range) - open.length, length: open.length))
        }

        // italic *x* / _x_
        for match in Self.italicStarRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            let content = match.range(at: 1)
            let font = fontTraits(font(at: content.location, in: storage), bold: false, italic: true)
            storage.addAttribute(.font, value: font, range: content)
            markers.append(NSRange(location: match.range.location, length: 1))
            markers.append(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
        }
        for match in Self.italicUnderRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            let content = match.range(at: 1)
            let font = fontTraits(font(at: content.location, in: storage), bold: false, italic: true)
            storage.addAttribute(.font, value: font, range: content)
            markers.append(NSRange(location: match.range.location, length: 1))
            markers.append(NSRange(location: NSMaxRange(match.range) - 1, length: 1))
        }

        // ~~strike~~
        for match in Self.strikeRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: theme.secondaryText,
            ], range: match.range(at: 1))
            markers.append(NSRange(location: match.range.location, length: 2))
            markers.append(NSRange(location: NSMaxRange(match.range) - 2, length: 2))
        }

        // ==highlight==
        for match in Self.highlightRegex.matches(in: source, range: scope)
        where !intersectsAny(match.range, protected) {
            storage.addAttribute(
                .backgroundColor, value: theme.highlightBackground, range: match.range(at: 1))
            markers.append(NSRange(location: match.range.location, length: 2))
            markers.append(NSRange(location: NSMaxRange(match.range) - 2, length: 2))
        }
    }
}
#endif
