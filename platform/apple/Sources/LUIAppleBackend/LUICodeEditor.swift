import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
private typealias LUIEditorColor = NSColor
private typealias LUIEditorFont = NSFont
#elseif canImport(UIKit)
private typealias LUIEditorColor = UIColor
private typealias LUIEditorFont = UIFont
#endif

/// Lightweight regex syntax highlighter for `LUICodeEditor`. Covers the
/// language names logseq code fences and query editors carry
/// (`lang`/`data-lang` props); unknown languages render as plain text.
///
/// Deliberately dependency-free: token classes are matched in a fixed
/// order and later classes overwrite earlier attributes, so comments win
/// over strings which win over keywords — a close approximation of a real
/// lexer for editor-sized buffers.
public enum LUICodeHighlighter {

    /// Skip highlighting past this size — regex passes are O(n) but a
    /// degenerate paste should never stall the editor.
    public static let maxHighlightLength = 200_000

    private struct RuleSet {
        var lineComments: [String] = []
        var blockComments: [(String, String)] = []
        var strings: [String] = []
        var keywords: String?
        var extras: [String] = []
    }

    private static let cLike: RuleSet = {
        var r = RuleSet()
        r.lineComments = ["//"]
        r.blockComments = [("/*", "*/")]
        r.strings = [#""(?:\\.|[^"\\])*""#, #"'(?:\\.|[^'\\])*'"#, #"`(?:\\.|[^`\\])*`"#]
        r.keywords = #"\b(?:as|async|await|break|case|catch|class|const|continue|def|default|do|else|enum|extends|false|final|finally|fn|for|func|function|if|impl|import|in|interface|let|match|mut|new|null|package|private|protected|pub|public|return|self|static|struct|super|switch|this|throw|throws|trait|true|try|type|typeof|use|val|var|void|where|while|yield|undefined|None|Some|Ok|Err|self|Self)\b"#
        r.extras = [#"^\s*#\s*(?:include|import|define|ifdef|ifndef|endif|pragma).*$"#]
        return r
    }()

    private static let lisp: RuleSet = {
        var r = RuleSet()
        r.lineComments = [";"]
        r.strings = [#""(?:\\.|[^"\\])*""#]
        r.keywords = #"(?<=[\s\(\[])(?:defn?|defmacro|defonce|defmulti|defmethod|defprotocol|defrecord|deftype|let|letfn|fn|if|if-let|when|when-let|when-not|cond|condp|case|do|doall|doseq|dotimes|loop|recur|for|map|filter|reduce|ns|require|import|use|quote|var|true|false|nil|throw|try|catch|finally|->>|->|doto|comment|declare)(?=[\s\)\]]|$)"#
        r.extras = [#"(?<=[\s\(])(:[a-zA-Z][\w\-\.\?]*)"#] // clojure keywords
        return r
    }()

    private static func rules(for language: String) -> RuleSet? {
        switch language.lowercased() {
        case "clojure", "clj", "cljs", "cljc", "edn", "lisp", "scheme",
             "emacs-lisp", "elisp", "racket":
            return lisp
        case "javascript", "js", "jsx", "typescript", "ts", "tsx",
             "java", "kotlin", "scala", "c", "cpp", "c++", "objc",
             "objective-c", "cs", "csharp", "c#", "go", "rust", "swift",
             "php", "dart", "groovy", "hcl", "zig", "ocaml", "fsharp", "f#":
            return cLike
        case "python", "py", "r", "julia", "shell", "bash", "sh", "zsh",
             "fish", "yaml", "yml", "toml", "powershell", "perl", "ruby",
             "rb", "dockerfile", "makefile", "make", "nim", "elixir",
             "erlang", "crystal", "coffee", "coffeescript":
            var r = cLike
            r.lineComments = ["#"]
            r.blockComments = []
            r.keywords = #"\b(?:and|as|assert|async|await|begin|break|case|class|const|continue|def|default|do|elif|else|elsif|end|enum|ensure|except|export|false|finally|fn|for|from|func|function|global|if|impl|import|in|is|lambda|let|local|match|module|mut|next|nil|none|nonlocal|not|or|pass|pub|raise|redo|require|rescue|retry|return|self|struct|then|true|try|type|unless|until|use|val|var|when|while|with|yield|None|True|False)\b"#
            r.extras = []
            return r
        case "sql", "mysql", "pgsql", "postgres", "sqlite", "hql", "datalog":
            var r = RuleSet()
            r.lineComments = ["--"]
            r.blockComments = [("/*", "*/")]
            r.strings = [#"'(?:''|\\.|[^'\\])*'"#, #""(?:\\.|[^"\\])*""#]
            r.keywords = #"(?i)\b(?:select|insert|update|delete|from|where|join|left|right|inner|outer|on|group|order|by|having|limit|offset|as|and|or|not|null|in|is|between|like|exists|case|when|then|else|end|distinct|union|all|create|table|index|view|alter|drop|primary|key|foreign|references|values|into|set|begin|commit|rollback|pull|find|in)\b"#
            return r
        case "html", "xml", "svg", "vue", "svelte":
            var r = RuleSet()
            r.blockComments = [("<!--", "-->")]
            r.strings = [#""(?:\\.|[^"\\])*""#, #"'(?:\\.|[^'\\])*'"#]
            r.keywords = nil
            r.extras = [#"</?[a-zA-Z][\w\-]*"#, #"[a-zA-Z\-:]+="#, #"/?>"#]
            return r
        case "json", "jsonc":
            var r = RuleSet()
            r.strings = [#""(?:\\.|[^"\\])*""#]
            r.keywords = #"\b(?:true|false|null)\b"#
            return r
        case "css", "scss", "less", "sass":
            var r = RuleSet()
            r.lineComments = ["//"]
            r.blockComments = [("/*", "*/")]
            r.strings = [#""(?:\\.|[^"\\])*""#, #"'(?:\\.|[^'\\])*'"#]
            r.keywords = nil
            r.extras = [#"(?:^|\s)([a-zA-Z\-]+)(?=\s*:)"#, #"[@#.][a-zA-Z_][\w\-]*"#]
            return r
        case "markdown", "md", "org":
            var r = RuleSet()
            r.strings = [#"`[^`\n]*`"#]
            r.extras = [
                #"^\s*#{1,6}\s.*$"#,            // headings
                #"\*\*[^*]+\*\*|__[^_]+__"#,    // bold
                #"(?<![*\w])\*[^*\n]+\*(?!\*)"#, // italic
                #"^\s*>.*$"#,                   // quotes
                #"^\s*(?:[-*+]|\d+\.)\s"#       // list markers
            ]
            return r
        case "diff", "patch":
            var r = RuleSet()
            r.extras = [ #"^\+.*$"#, #"^-.*$"#, #"^@@.*@@"#, #"^!.*$"# ]
            return r
        case "graphql", "gql":
            var r = cLike
            r.lineComments = ["#"]
            r.blockComments = []
            r.keywords = #"\b(?:query|mutation|subscription|fragment|on|type|interface|union|enum|input|schema|extend|implements|scalar|directive|true|false|null)\b"#
            return r
        case "lua", "haskell", "hs", "ada":
            var r = cLike
            r.lineComments = ["--"]
            r.blockComments = []
            return r
        default:
            return nil
        }
    }

    private static func compile(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// Re-derive token attributes over the whole string. Call after every
    /// edit — the editor-sized buffers this serves make a full re-pass
    /// cheaper than tracking dirty ranges.
    public static func highlight(
        _ storage: NSMutableAttributedString,
        language: String,
        fontSize: CGFloat
    ) {
        let full = NSRange(location: 0, length: storage.length)
        let base = LUIEditorFont.monospacedSystemFont(
            ofSize: fontSize, weight: .regular)
        storage.beginEditing()
        storage.setAttributes(
            [.font: base, .foregroundColor: LUIEditorColor.labelColor],
            range: full)
        guard storage.length <= maxHighlightLength,
              let rules = rules(for: language), storage.length > 0
        else {
            storage.endEditing()
            return
        }
        let text = storage.string as NSString
        let colors: [Int: LUIEditorColor] = [
            0: .systemBlue,      // keywords
            1: .systemPurple,    // extras (preprocessor/tags/selectors)
            2: .systemRed,       // strings
            3: .secondaryLabelColor, // comments
        ]
        func apply(_ pattern: String, _ color: LUIEditorColor,
                   _ options: NSRegularExpression.Options = []) {
            guard let re = compile(pattern, options: options) else { return }
            for m in re.matches(in: text as String, range: full) {
                storage.addAttribute(.foregroundColor, value: color,
                                     range: m.range)
            }
        }
        if let kw = rules.keywords {
            apply(kw, colors[0]!)
        }
        apply(#"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .systemTeal)
        for p in rules.extras { apply(p, colors[1]!, [.anchorsMatchLines]) }
        for p in rules.strings { apply(p, colors[2]!) }
        for marker in rules.lineComments {
            apply(
                NSRegularExpression.escapedPattern(for: marker) + ".*$",
                colors[3]!, [.anchorsMatchLines])
        }
        for (open, close) in rules.blockComments {
            let pattern = NSRegularExpression.escapedPattern(for: open)
                + "[\\s\\S]*?" + NSRegularExpression.escapedPattern(for: close)
            apply(pattern, colors[3]!)
        }
        storage.endEditing()
    }
}

#if canImport(AppKit)

/// NSTextView subclass routing command keys (Escape/Enter/Tab) through the
/// host's `onKey` before AppKit consumes them — the extension contract
/// reports keys OCaml-side so the shared model decides swallow/commit.
final class LUICodeTextView: NSTextView {
    var onCommandKey: ((String) -> Bool)?

    override func doCommand(by commandSelector: Selector) {
        let key: String?
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            key = "Escape"
        case #selector(NSResponder.insertNewline(_:)):
            key = "Enter"
        case #selector(NSResponder.insertTab(_:)):
            key = "Tab"
        default:
            key = nil
        }
        if let key, let onCommandKey, onCommandKey(key) { return }
        super.doCommand(by: commandSelector)
    }
}

/// A code/source editor surface for extension hosts: NSTextView with
/// monospaced font, optional regex syntax coloring and change/focus/key
/// callbacks. The host owns the text (`text` is authoritative while the
/// view is not focused — the same rule the DOM `value` prop follows).
public struct LUICodeEditor: NSViewRepresentable {
    public var text: String
    public var language: String
    public var isEditable: Bool
    public var fontSize: CGFloat
    public var onChange: (String) -> Void
    public var onFocusChange: (Bool) -> Void
    /// Command keys (Escape/Enter/Tab); return true to swallow the key.
    public var onKey: ((String) -> Bool)?

    public init(
        text: String,
        language: String = "",
        isEditable: Bool = true,
        fontSize: CGFloat = 13,
        onChange: @escaping (String) -> Void = { _ in },
        onFocusChange: @escaping (Bool) -> Void = { _ in },
        onKey: ((String) -> Bool)? = nil
    ) {
        self.text = text
        self.language = language
        self.isEditable = isEditable
        self.fontSize = fontSize
        self.onChange = onChange
        self.onFocusChange = onFocusChange
        self.onKey = onKey
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = LUICodeTextView()
        scrollView.documentView = textView
        textView.delegate = context.coordinator
        textView.onCommandKey = { [weak coordinator = context.coordinator] key in
            coordinator?.commandKey(key) ?? false
        }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        // Code does not soft-wrap — horizontal scroll like CodeMirror.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        context.coordinator.textView = textView
        context.coordinator.apply(text: text)
        context.coordinator.refreshHighlight(language: language, fontSize: fontSize)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? LUICodeTextView
        else { return }
        let coordinator = context.coordinator
        coordinator.textView = textView
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        // While focused the user's typing is authoritative — a prop update
        // carrying the not-yet-committed buffer must not clobber keystrokes.
        let focused = scrollView.window?.firstResponder === textView
        if !focused, textView.string != text {
            coordinator.apply(text: text)
        }
        coordinator.refreshHighlight(language: language, fontSize: fontSize)
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: LUICodeTextView?
        private let owner: LUICodeEditor
        private var suppressCallbacks = false
        private var highlightedLanguage: String?

        init(_ owner: LUICodeEditor) { self.owner = owner }

        func apply(text: String) {
            guard let textView else { return }
            suppressCallbacks = true
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(
                location: min(selection.location, length),
                length: min(selection.length, length - selection.location)))
            suppressCallbacks = false
            // string= dropped the previous attributes
            highlightedLanguage = nil
        }

        func refreshHighlight(language: String, fontSize: CGFloat) {
            guard let textView, let storage = textView.textStorage,
                  highlightedLanguage != language else { return }
            highlightedLanguage = language
            LUICodeHighlighter.highlight(
                storage, language: language,
                fontSize: fontSize)
        }

        func commandKey(_ key: String) -> Bool {
            owner.onKey?(key) ?? false
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView, let storage = textView.textStorage else { return }
            LUICodeHighlighter.highlight(
                storage, language: owner.language,
                fontSize: owner.fontSize)
            guard !suppressCallbacks else { return }
            owner.onChange(textView.string)
        }

        public func textDidBeginEditing(_ notification: Notification) {
            owner.onFocusChange(true)
        }

        public func textDidEndEditing(_ notification: Notification) {
            owner.onFocusChange(false)
        }
    }
}

#elseif canImport(UIKit)

/// UITextView twin of `LUICodeEditor` — same props and callbacks; command
/// keys are a desktop concept so `onKey` is unused on iOS.
public struct LUICodeEditor: UIViewRepresentable {
    public var text: String
    public var language: String
    public var isEditable: Bool
    public var fontSize: CGFloat
    public var onChange: (String) -> Void
    public var onFocusChange: (Bool) -> Void
    public var onKey: ((String) -> Bool)?

    public init(
        text: String,
        language: String = "",
        isEditable: Bool = true,
        fontSize: CGFloat = 13,
        onChange: @escaping (String) -> Void = { _ in },
        onFocusChange: @escaping (Bool) -> Void = { _ in },
        onKey: ((String) -> Bool)? = nil
    ) {
        self.text = text
        self.language = language
        self.isEditable = isEditable
        self.fontSize = fontSize
        self.onChange = onChange
        self.onFocusChange = onFocusChange
        self.onKey = onKey
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        context.coordinator.textView = textView
        context.coordinator.apply(text: text)
        context.coordinator.refreshHighlight(language: language, fontSize: fontSize)
        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.textView = textView
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        if !textView.isFirstResponder, textView.text != text {
            coordinator.apply(text: text)
        }
        coordinator.refreshHighlight(language: language, fontSize: fontSize)
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    public final class Coordinator: NSObject, UITextViewDelegate {
        weak var textView: UITextView?
        private let owner: LUICodeEditor
        private var suppressCallbacks = false
        private var highlightedLanguage: String?

        init(_ owner: LUICodeEditor) { self.owner = owner }

        func apply(text: String) {
            guard let textView else { return }
            suppressCallbacks = true
            let selection = textView.selectedRange
            let storage = textView.textStorage
            storage.replaceCharacters(
                in: NSRange(location: 0, length: storage.length),
                with: text)
            let length = (text as NSString).length
            if let selection {
                textView.selectedRange = NSRange(
                    location: min(selection.location, length),
                    length: min(selection.length, length - selection.location))
            }
            suppressCallbacks = false
            // replaced storage dropped the previous attributes
            highlightedLanguage = nil
        }

        func refreshHighlight(language: String, fontSize: CGFloat) {
            guard let textView,
                  highlightedLanguage != language else { return }
            highlightedLanguage = language
            LUICodeHighlighter.highlight(
                textView.textStorage, language: language,
                fontSize: fontSize)
        }

        public func textViewDidChange(_ textView: UITextView) {
            LUICodeHighlighter.highlight(
                textView.textStorage, language: owner.language,
                fontSize: owner.fontSize)
            guard !suppressCallbacks else { return }
            owner.onChange(textView.text)
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            owner.onFocusChange(true)
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            owner.onFocusChange(false)
        }
    }
}
#endif
