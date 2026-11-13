import SwiftUI
import SwiftDraw
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An immutable snapshot of the layout actually drawn by a mounted text node.
/// `frame` uses window-content top-left points. Query points and rectangles use
/// text-local points; all string offsets and ranges use UTF-16 code units.
@MainActor
public struct LUICommittedTextGeometry {
    public let nodeID: Int
    public let generation: Int64
    public let incarnation: UInt64
    public let text: String
    public let frame: CGRect
    public var lineRanges: [NSRange] {
        guard sourceRange != nil else { return layout.lines.map(\.range) }
        return layout.lines.compactMap { localRange(for: $0) }
    }
    let identity: UUID
    let layout: LUITextLayout
    var sourceRange: NSRange? = nil
    var sourceOrigin: CGPoint = .zero
    private var effectiveRange: NSRange {
        sourceRange ?? NSRange(location: 0, length: layout.storage.length)
    }

    private func localRange(for line: LUITextLayout.Line) -> NSRange? {
        let intersection = NSIntersectionRange(line.range, effectiveRange)
        if intersection.length > 0 {
            return NSRange(location: intersection.location - effectiveRange.location,
                           length: intersection.length)
        }
        let end = NSMaxRange(effectiveRange)
        // The downstream insertion line can belong to a later run or be the
        // document's empty final line. Both carry this run's end caret.
        if line.range.location == end, line.carets.contains(where: { $0.offset == end }) {
            return NSRange(location: effectiveRange.length, length: 0)
        }
        return nil
    }

    /// Returns nil for an invalid offset or a position hidden by truncation.
    public func caretRect(atUTF16Offset offset: Int) -> CGRect? {
        guard offset >= 0, offset <= effectiveRange.length else { return nil }
        return layout.caretRect(at: effectiveRange.location + offset)?
            .offsetBy(dx: -sourceOrigin.x, dy: -sourceOrigin.y)
    }

    /// Returns visual fragments, including discontiguous bidirectional runs.
    /// Invalid or out-of-bounds ranges return an empty array.
    public func selectionRects(in range: NSRange) -> [CGRect] {
        guard range.location >= 0, range.length > 0,
              range.location <= effectiveRange.length,
              range.length <= effectiveRange.length - range.location else { return [] }
        return layout.selectionRects(in: NSRange(location: effectiveRange.location + range.location,
                                                length: range.length)).compactMap {
            let rect = $0.offsetBy(dx: -sourceOrigin.x, dy: -sourceOrigin.y)
                .intersection(CGRect(origin: .zero, size: frame.size))
            return !rect.isNull && rect.width > 0 ? rect : nil
        }
    }

    /// Hit-tests a local point against native insertion positions. Points
    /// outside the committed text view return nil.
    public func offset(at point: CGPoint) -> Int? {
        guard point.x.isFinite, point.y.isFinite,
              CGRect(origin: .zero, size: frame.size).contains(point),
              let line = layout.lines.filter({
                  sourceRange == nil || localRange(for: $0) != nil
              }).min(by: {
                  abs($0.rect.midY - point.y - sourceOrigin.y) < abs($1.rect.midY - point.y - sourceOrigin.y)
              }) else { return nil }
        return line.carets.filter {
            $0.offset >= effectiveRange.location && $0.offset <= NSMaxRange(effectiveRange)
        }.min(by: {
            abs($0.x - point.x - sourceOrigin.x) < abs($1.x - point.x - sourceOrigin.x)
        }).map { $0.offset - effectiveRange.location }
    }
}

/// Each layout is constructed once and then shared by drawing and snapshots.
/// Resizes and source/style changes create a new layout; old snapshots retain
/// their original native glyph data rather than a mutable live text container.
@MainActor
final class LUITextLayout {
    struct Caret { let offset: Int; let x: CGFloat }
    struct Line { let range: NSRange; let rect: CGRect; let carets: [Caret] }
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container: NSTextContainer
    private(set) var lines: [Line] = []
    private(set) var size = CGSize.zero

    init(text: NSAttributedString, width: CGFloat, lineLimit: Int?) {
        storage = NSTextStorage(attributedString: text)
        container = NSTextContainer(size: CGSize(width: max(0, width), height: 10_000_000))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = lineLimit ?? 0
        container.lineBreakMode = lineLimit == nil ? .byWordWrapping : .byTruncatingTail
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        var collected: [Line] = []
        manager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, glyphRange, _ in
            let range = self.manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard range.length > 0 else { return }
            let count = self.manager.getLineFragmentInsertionPoints(
                forCharacterAt: range.location, alternatePositions: false,
                inDisplayOrder: true, positions: nil, characterIndexes: nil)
            var positions = [CGFloat](repeating: 0, count: count)
            var indexes = [Int](repeating: 0, count: count)
            _ = self.manager.getLineFragmentInsertionPoints(
                forCharacterAt: range.location, alternatePositions: false,
                inDisplayOrder: true, positions: &positions, characterIndexes: &indexes)
            let truncated = self.manager.truncatedGlyphRange(inLineFragmentForGlyphAt: glyphRange.location)
            let carets = zip(indexes, positions).compactMap { index, x -> Caret? in
                if truncated.location != NSNotFound, index < self.storage.length {
                    let glyph = self.manager.glyphIndexForCharacter(at: index)
                    if NSLocationInRange(glyph, truncated) { return nil }
                }
                return Caret(offset: index, x: rect.minX + x)
            }
            collected.append(Line(range: range, rect: rect, carets: carets))
        }
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentRect
        if manager.extraLineFragmentTextContainer === container {
            collected.append(Line(range: NSRange(location: text.length, length: 0),
                                  rect: extra, carets: [Caret(offset: text.length, x: extra.minX)]))
        }
        lines = collected
        size = CGSize(width: ceil(used.maxX), height: ceil(max(used.maxY, extra.maxY)))
    }

    func caretRect(at offset: Int) -> CGRect? {
        guard offset >= 0, offset <= storage.length else { return nil }
        // Prefer the next line at a soft wrap (the native downstream affinity).
        for line in lines.reversed() {
            if let caret = line.carets.first(where: { $0.offset == offset }) {
                return CGRect(x: caret.x, y: line.rect.minY, width: 1, height: line.rect.height)
            }
        }
        return nil
    }

    func selectionRects(in range: NSRange) -> [CGRect] {
        guard range.length > 0 else { return [] }
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var result: [CGRect] = []
        manager.enumerateEnclosingRects(
            forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container
        ) { rect, _ in result.append(rect) }
        return result
    }

    /// Include insertion positions so whitespace and zero-width runs keep a
    /// real line height and the same origin as the glyph layout they belong to.
    func bounds(for range: NSRange) -> CGRect? {
        var bounds = CGRect.null
        for rect in selectionRects(in: range) { bounds = bounds.union(rect) }
        for offset in [range.location, NSMaxRange(range)] {
            if var caret = caretRect(at: offset) {
                caret.size.width = 0
                bounds = bounds.union(caret)
            }
        }
        return bounds.isNull ? nil : bounds
    }
}

@Observable @MainActor
final class LUIHostQueries {
    var iconRevision: UInt64 = 0
    var textQueries: Set<Int> = []
    var imageQueries: Set<Int> = []
    var scrollQueries: Set<Int> = []
    @ObservationIgnored var scrollViews: [Int: WeakScrollView] = [:]
    struct WeakScrollView { weak var value: LUIHostScrollMarker? }
    @ObservationIgnored var textViews: [Int: WeakTextView] = [:]
    @ObservationIgnored var nextIncarnation: UInt64 = 0
    @ObservationIgnored var images: [Int: LoadedImage] = [:]
    struct WeakTextView { weak var value: LUICommittedTextNativeView? }
    struct LoadedImage {
        let model: LUINodeModel
        let source: String
        let size: CGSize
    }
    func invalidateText() {
        var invalidated: Set<ObjectIdentifier> = []
        for (id, weakView) in textViews {
            guard let view = weakView.value else { textViews[id] = nil; continue }
            if invalidated.insert(ObjectIdentifier(view)).inserted { view.invalidateCommit() }
        }
    }
}

extension LUIAppleBackend {
    /// Returns nil until native drawing has committed the current patch and
    /// layout. Non-text, hidden and unmounted nodes have no text geometry.
    public func textGeometry(nodeID: Int) -> LUICommittedTextGeometry? {
        guard let model = model(id: nodeID),
              [.text, .heading, .paragraph, .label].contains(model.kind) else { return nil }
        // Only hosts using this new API opt a node into native committed text.
        // Existing SwiftUI text presentation is unchanged for all other nodes.
        if !hostQueries.textQueries.contains(nodeID) {
            hostQueries.textQueries.insert(nodeID)
            scheduleFramesReport()
        }
        guard let view = hostQueries.textViews[nodeID]?.value,
              view.contains(model: model),
              view.renderGeneration == generation else { return nil }
        return view.committedGeometry(nodeID: nodeID)
    }

    /// Snapshots expire on patch application, source/style/layout changes,
    /// scrolling, unmounting, or reuse of a node id by a different native view.
    public func isCurrent(_ geometry: LUICommittedTextGeometry) -> Bool {
        guard let current = textGeometry(nodeID: geometry.nodeID) else { return false }
        return current.identity == geometry.identity && current.frame == geometry.frame
            && current.incarnation == geometry.incarnation && current.generation == geometry.generation
    }

    /// Decoded pixel dimensions, before layout scaling or source-rectangle
    /// cropping. This query never starts a load and never invents a zero size.
    public func naturalImageSize(nodeID: Int) -> CGSize? {
        guard let model = model(id: nodeID),
              [.image, .avatar, .fileImage].contains(model.kind) else { return nil }
        if model.kind != .fileImage, let image = model.registeredImage(in: self) {
            return CGSize(width: image.width, height: image.height)
        }
        if !hostQueries.imageQueries.contains(nodeID) { hostQueries.imageQueries.insert(nodeID) }
        guard let loaded = hostQueries.images[nodeID], loaded.model === model,
              loaded.source == imageSourceKey(model) else { return nil }
        return loaded.size
    }

    func imageSourceKey(_ model: LUINodeModel) -> String {
        model.kind == .fileImage
            ? "file:\(model.property(.maxPixelSize)?.intValue ?? LUIFileImageLoader.defaultMaxPixelSize)|\(model.property(.path)?.stringValue ?? "")"
            : model.property(.url)?.stringValue ?? ""
    }

    func reportLoadedImage(model: LUINodeModel, source: String, size: CGSize) {
        guard self.model(id: model.id) === model, imageSourceKey(model) == source,
              size.width > 0, size.height > 0 else { return }
        hostQueries.images[model.id] = .init(model: model, source: source, size: size)
        scheduleFramesReport()
    }
}

enum LUISVGIcon {
    static func validate(name: String, data: Data) throws {
        let slug = name.hasPrefix("app:") ? String(name.dropFirst(4)) : ""
        let parts = slug.split(separator: "-", omittingEmptySubsequences: false)
        guard !slug.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0)
        } }) else { throw LUIBackendError.invalidBatch("icon name must be canonical app:slug") }
        guard data.count <= 1 << 20, let svg = SVG(data: data),
              svg.size.width.isFinite, svg.size.height.isFinite,
              svg.size.width > 0, svg.size.height > 0 else {
            throw LUIBackendError.invalidBatch("invalid SVG document or dimensions")
        }
    }
}
