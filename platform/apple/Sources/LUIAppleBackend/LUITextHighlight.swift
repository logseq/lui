#if !SKIP
import SwiftUI

extension EnvironmentValues {
    @Entry public var luiTextHighlightQuery: String = ""
}

enum LUITextHighlight {
    static func preview(_ title: String, query: String) -> AttributedString {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let firstMatch = terms.compactMap { title.range(of: $0, options: options)?.lowerBound }.min()
        let matchOffset = firstMatch.map { title.distance(from: title.startIndex, to: $0) } ?? 0
        let start = title.index(title.startIndex, offsetBy: max(0, matchOffset - 32))
        let end = title.index(start, offsetBy: 240, limitedBy: title.endIndex) ?? title.endIndex
        let snippet = (start > title.startIndex ? "…" : "")
            + String(title[start..<end]) + (end < title.endIndex ? "…" : "")
        var result = AttributedString(snippet)
        for term in terms {
            var cursor = snippet.startIndex
            while cursor < snippet.endIndex,
                  let range = snippet.range(of: term, options: options, range: cursor..<snippet.endIndex) {
                if let lower = AttributedString.Index(range.lowerBound, within: result),
                   let upper = AttributedString.Index(range.upperBound, within: result) {
                    result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                }
                cursor = range.upperBound
            }
        }
        return result
    }
}
#endif
