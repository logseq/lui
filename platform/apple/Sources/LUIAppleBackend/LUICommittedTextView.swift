import SwiftUI
#if os(macOS)
import AppKit
typealias LUIPlatformTextView = NSView
private typealias LUITextFont = NSFont
private typealias LUITextColor = NSColor
#else
import UIKit
typealias LUIPlatformTextView = UIView
private typealias LUITextFont = UIFont
private typealias LUITextColor = UIColor
#endif

extension EnvironmentValues {
    @Entry var luiTextForeground: Color = .primary
}

/// Existing hosts retain their SwiftUI Text. Geometry queries opt only their
/// requested nodes into a renderer whose committed glyph layout is accessible.
struct LUIQueryableText<Content: View>: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @ViewBuilder let content: () -> Content

    var body: some View {
        if backend.hostQueries.textQueries.contains(model.id) {
            LUICommittedTextContent(model: model, backend: backend)
        } else {
            content()
        }
    }
}

/// Read-only TextKit drawing keeps the rendered glyphs and host geometry on
/// one layout engine on macOS 14 and iOS 17, including ligatures and bidi text.
@MainActor
final class LUICommittedTextNativeView: LUIPlatformTextView {
    weak var backend: LUIAppleBackend?
    weak var model: LUINodeModel?
    var renderGeneration = -1
    private var incarnation: UInt64 = 0
    private var attributedText = NSAttributedString(string: "")
    private var lineLimit: Int?
    private var layout: LUITextLayout?
    private var drawnLayout: LUITextLayout?
    private var layoutIdentity = UUID()
    private var drawnSize = CGSize.zero
    private var sourceText = ""

    init() {
        super.init(frame: .zero)
        #if os(iOS)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        #else
        setAccessibilityRole(.staticText)
        #endif
    }

    required init?(coder: NSCoder) { nil }

    func configure(model: LUINodeModel, backend: LUIAppleBackend,
                   text: NSAttributedString, lineLimit: Int?) {
        if self.model !== model {
            backend.hostQueries.nextIncarnation &+= 1
            incarnation = backend.hostQueries.nextIncarnation
        }
        self.backend = backend
        self.model = model
        backend.hostQueries.textViews[model.id] = .init(value: self)
        sourceText = model.text
        renderGeneration = backend.generation
        if !attributedText.isEqual(to: text) || self.lineLimit != lineLimit {
            attributedText = text
            self.lineLimit = lineLimit
            layout = nil
        }
        drawnLayout = nil
        #if os(macOS)
        setAccessibilityLabel(text.string)
        needsLayout = true
        needsDisplay = true
        #else
        accessibilityLabel = text.string
        setNeedsLayout()
        setNeedsDisplay()
        #endif
    }

    func invalidateCommit() {
        drawnLayout = nil
        // Only currently mounted native text views need a new publication.
        // Reading revision in LUICommittedTextContent renews even unchanged
        // leaves after an ancestor/style patch or a coalesced commit.
        model?.invalidateResource()
    }

    func measure(width: CGFloat?) -> CGSize {
        let proposed = width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 1_000_000
        return LUITextLayout(text: attributedText, width: proposed, lineLimit: lineLimit).size
    }

    private func render() {
        guard bounds.width > 0 else { return }
        if layout?.container.size.width != bounds.width {
            layout = LUITextLayout(text: attributedText, width: bounds.width, lineLimit: lineLimit)
            layoutIdentity = UUID()
        }
        guard let layout else { return }
        let glyphs = layout.manager.glyphRange(for: layout.container)
        layout.manager.drawBackground(forGlyphRange: glyphs, at: .zero)
        layout.manager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
        drawnLayout = layout
        drawnSize = bounds.size
        backend?.scheduleFramesReport()
    }

    func committedGeometry() -> LUICommittedTextGeometry? {
        guard let backend, let model, let layout = drawnLayout,
              layout === self.layout, drawnSize == bounds.size,
              backend.model(id: model.id) === model,
              renderGeneration == backend.generation, sourceText == model.text,
              let frame = windowFrame() else { return nil }
        return LUICommittedTextGeometry(nodeID: model.id, generation: Int64(renderGeneration),
            incarnation: incarnation, text: layout.storage.string, frame: frame,
            identity: layoutIdentity, layout: layout)
    }

    private func windowFrame() -> CGRect? {
        guard let window else { return nil }
        #if os(macOS)
        guard !isHiddenOrHasHiddenAncestor, let content = window.contentView else { return nil }
        let rect = convert(bounds, to: content)
        return content.isFlipped ? rect : CGRect(x: rect.minX,
            y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        #else
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden { return nil }
            ancestor = view.superview
        }
        return convert(bounds, to: window)
        #endif
    }

    #if os(macOS)
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { render() }
    #else
    override func draw(_ rect: CGRect) { render() }
    #endif
}

struct LUICommittedTextContent: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    @Environment(\.luiTypography) private var typography
    @Environment(\.luiTextHighlightQuery) private var highlightQuery
    @Environment(\.luiTextForeground) private var foreground
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let _ = model.revision
        LUICommittedTextRepresentable(model: model, backend: backend,
            text: attributedText, lineLimit: LUITextLinePolicy.lineLimit(styleClass: model.derived.styleClass))
    }

    private var attributedText: NSAttributedString {
        let classes = model.derived.styleClassTokens
        let highlighted = classes.contains("search-match")
            ? LUITextHighlight.preview(model.text, query: highlightQuery) : AttributedString(model.text)
        let text = String(highlighted.characters)
        let font = resolvedFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = direction == .rightToLeft ? .rightToLeft : .leftToRight
        paragraph.alignment = switch model.property(.textAlignment)?.stringValue {
        case "center": .center
        case "end": direction == .rightToLeft ? .left : .right
        default: direction == .rightToLeft ? .right : .left
        }
        paragraph.lineSpacing = typography.lineSpacing(baseSize: font.pointSize)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: LUITextColor(foreground), .paragraphStyle: paragraph,
            .kern: typography.letterSpacing ?? 0,
        ]
        if typography.underline == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if typography.strikethrough == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        for run in highlighted.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            let prefix = String(highlighted[highlighted.startIndex..<run.range.lowerBound].characters).utf16.count
            let length = String(highlighted[run.range].characters).utf16.count
            result.addAttribute(.font, value: bold(font), range: NSRange(location: prefix, length: length))
        }
        return result
    }

    private var resolvedFont: LUITextFont {
        let classes = model.derived.styleClassTokens
        var style: LUITextFont.TextStyle = .body
        if model.kind == .heading {
            style = switch model.property(.headingLevel)?.intValue ?? 1 {
            case 1: .largeTitle
            case 2: .title1
            case 3: .title2
            case 4: .title3
            case 5: .headline
            default: .subheadline
            }
        } else if classes.contains("title2") { style = .title2 }
        else if classes.contains("headline") { style = .headline }
        else if classes.contains("subheadline") { style = .subheadline }
        else if classes.contains("caption") { style = .caption1 }
        else if classes.contains("footnote") { style = .footnote }
        #if os(macOS)
        var font = NSFont.preferredFont(forTextStyle: style)
        #else
        let categories: [DynamicTypeSize: UIContentSizeCategory] = [
            .xSmall: .extraSmall, .small: .small, .medium: .medium, .large: .large,
            .xLarge: .extraLarge, .xxLarge: .extraExtraLarge, .xxxLarge: .extraExtraExtraLarge,
            .accessibility1: .accessibilityMedium, .accessibility2: .accessibilityLarge,
            .accessibility3: .accessibilityExtraLarge, .accessibility4: .accessibilityExtraExtraLarge,
            .accessibility5: .accessibilityExtraExtraExtraLarge,
        ]
        let traits = UITraitCollection(preferredContentSizeCategory: categories[dynamicTypeSize] ?? .large)
        var font = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        #endif
        let size = typography.fontSize ?? font.pointSize
        let family = typography.fontFamily
        if let family, !LUITypographySpec.isSystemFamily(family),
           !LUITypographySpec.isMonospaced(family), !LUITypographySpec.isSerif(family) {
            font = LUITextFont(name: family, size: size) ?? font
        } else {
            #if os(macOS)
            font = LUITextFont(descriptor: font.fontDescriptor, size: size) ?? font
            #else
            font = LUITextFont(descriptor: font.fontDescriptor, size: size)
            #endif
            if classes.contains("mono") || family.map(LUITypographySpec.isMonospaced) == true {
                font = LUITextFont.monospacedSystemFont(ofSize: size, weight: .regular)
            } else if family.map(LUITypographySpec.isSerif) == true,
                      let descriptor = font.fontDescriptor.withDesign(.serif) {
                #if os(macOS)
                font = LUITextFont(descriptor: descriptor, size: size) ?? font
                #else
                font = LUITextFont(descriptor: descriptor, size: size)
                #endif
            }
        }
        let headingBold = model.kind == .heading && LUIHeadingTypography.isBold(level: model.property(.headingLevel)?.intValue ?? 1)
        let weight = typography.fontWeight ?? ((classes.contains("semibold") || style == .headline || style == .subheadline || headingBold) ? 600 : 400)
        let weights: [LUITextFont.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let nativeWeight = weights[max(0, min(8, (weight + 50) / 100 - 1))]
        #if os(macOS)
        let descriptor = font.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: nativeWeight]])
        font = NSFont(descriptor: descriptor, size: size) ?? font
        if typography.italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        #else
        let descriptor = font.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: nativeWeight]])
        font = UIFont(descriptor: descriptor, size: size)
        if typography.italic == true, let italic = font.fontDescriptor.withSymbolicTraits(.traitItalic) {
            font = UIFont(descriptor: italic, size: size)
        }
        #endif
        return font
    }

    private func bold(_ font: LUITextFont) -> LUITextFont {
        #if os(macOS)
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #else
        font.fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
        #endif
    }
}

#if os(macOS)
private struct LUICommittedTextRepresentable: NSViewRepresentable {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let text: NSAttributedString
    let lineLimit: Int?
    func makeNSView(context: Context) -> LUICommittedTextNativeView { LUICommittedTextNativeView() }
    func updateNSView(_ view: LUICommittedTextNativeView, context: Context) {
        view.configure(model: model, backend: backend, text: text, lineLimit: lineLimit)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LUICommittedTextNativeView, context: Context) -> CGSize? {
        nsView.measure(width: proposal.width)
    }
}
#else
private struct LUICommittedTextRepresentable: UIViewRepresentable {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let text: NSAttributedString
    let lineLimit: Int?
    func makeUIView(context: Context) -> LUICommittedTextNativeView { LUICommittedTextNativeView() }
    func updateUIView(_ view: LUICommittedTextNativeView, context: Context) {
        view.configure(model: model, backend: backend, text: text, lineLimit: lineLimit)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LUICommittedTextNativeView, context: Context) -> CGSize? {
        uiView.measure(width: proposal.width)
    }
}
#endif
