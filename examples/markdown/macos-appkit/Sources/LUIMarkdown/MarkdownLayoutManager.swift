#if canImport(AppKit)
import AppKit

// Draws block-level chrome the text attributes can't reach: full-width
// code/table/math panels, quote bars, horizontal rules. The highlighter
// re-feeds `decorations` on every pass; drawing reads them against the
// current glyph geometry so edits stay pixel-correct.

final class MarkdownLayoutManager: NSLayoutManager {

    var decorations: [MarkdownHighlighter.Decoration] = []
    var theme = MarkdownHighlighter.Theme()

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainers.first else { return }
        let containerWidth = container.size.width
        let shown = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        for decoration in decorations
        where NSIntersectionRange(decoration.range, shown).length > 0 {
            let glyphRange = self.glyphRange(forCharacterRange: decoration.range,
                                             actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            let bounds = boundingRect(forGlyphRange: glyphRange, in: container)
            switch decoration.kind {
            case .codeBlock:
                fill(
                    rect: fullWidthRect(bounds, containerWidth: containerWidth),
                    color: theme.codeBackground, radius: 6)
            case .tableBlock:
                fill(
                    rect: fullWidthRect(bounds, containerWidth: containerWidth),
                    color: theme.tableBackground, radius: 6)
            case .mathBlock:
                fill(
                    rect: fullWidthRect(bounds, containerWidth: containerWidth),
                    color: theme.mathBackground, radius: 6)
            case .frontMatter:
                fill(
                    rect: fullWidthRect(bounds, containerWidth: containerWidth),
                    color: theme.frontMatterBackground, radius: 0)
            case .quoteBar(let depth):
                for level in 0..<depth {
                    let x = bounds.origin.x - 10 + CGFloat(level) * 14
                    let bar = CGRect(x: x, y: bounds.origin.y,
                                     width: 3, height: bounds.height)
                    fill(rect: bar, color: theme.quoteBar, radius: 1.5)
                }
            case .rule:
                let y = bounds.midY - 0.5
                let rule = CGRect(x: 0, y: y, width: containerWidth, height: 1)
                fill(rect: rule, color: theme.ruleColor, radius: 0)
            case .imageChip:
                fill(rect: bounds.insetBy(dx: -4, dy: -1),
                     color: theme.codeBackground, radius: 4)
            }
        }
    }

    private func fullWidthRect(_ bounds: CGRect, containerWidth: CGFloat) -> CGRect {
        CGRect(
            x: -2,
            y: bounds.origin.y - 1,
            width: containerWidth + 4,
            height: bounds.height + 2)
    }

    private func fill(rect: CGRect, color: NSColor, radius: CGFloat) {
        color.setFill()
        if radius > 0 {
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        } else {
            rect.fill()
        }
    }
}
#endif
