import SwiftUI

private struct LUIStyleVariablesKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

public extension EnvironmentValues {
    /// Host theme values for typography `var(--name, fallback)` references.
    /// Custom property names are case-sensitive.
    var luiStyleVariables: [String: String] {
        get { self[LUIStyleVariablesKey.self] }
        set { self[LUIStyleVariablesKey.self] = newValue }
    }
}

public extension View {
    /// Supply the current theme snapshot without rewriting retained properties.
    /// Updating this environment resolves inherited typography again.
    func luiStyleVariables(_ variables: [String: String]) -> some View {
        environment(\.luiStyleVariables, variables)
    }
}

/// Substitution only; callers own supported literal values. Invalid or cyclic
/// values fall back at the referring var().
struct LUIStyleVariableResolver {
    private let lookup: (String) -> String?

    init(variables: [String: String]) {
        lookup = { variables[$0] }
    }

    init(lookup: @escaping (String) -> String?) {
        self.lookup = lookup
    }

    private enum Failure: Error {
        case invalid
        case cycle(Set<String>)
    }

    func resolve(_ raw: String) -> String? {
        try? substitute(raw, path: [])
    }

    private func substitute(_ raw: String, path: [String]) throws -> String {
        guard path.count < 64 else { throw Failure.invalid }
        var result = ""
        var cursor = raw.startIndex
        while let start = raw.range(of: "var(", range: cursor..<raw.endIndex) {
            result += raw[cursor..<start.lowerBound]
            var end = start.upperBound
            var depth = 1
            var comma: String.Index?
            var quote: Character?
            var escaped = false
            while end < raw.endIndex {
                let character = raw[end]
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if let currentQuote = quote {
                    if character == currentQuote { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 { break }
                } else if character == ",", depth == 1, comma == nil {
                    comma = end
                }
                end = raw.index(after: end)
            }
            guard depth == 0 else { throw Failure.invalid }
            let name = raw[start.upperBound..<(comma ?? end)]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.hasPrefix("--"), name.count > 2 else { throw Failure.invalid }
            if let index = path.firstIndex(of: name) {
                throw Failure.cycle(Set(path[index...]))
            }
            var replacement: String?
            if let value = lookup(name) {
                do {
                    replacement = try substitute(value, path: path + [name])
                } catch Failure.cycle(let members) {
                    // A fallback inside a cycle cannot make that custom
                    // property valid. Let the caller outside the cycle fall back.
                    if let owner = path.last, members.contains(owner) { throw Failure.cycle(members) }
                } catch {
                    replacement = nil
                }
            }
            if replacement == nil, let comma {
                replacement = try substitute(String(raw[raw.index(after: comma)..<end]), path: path)
            }
            guard let replacement else { throw Failure.invalid }
            result += replacement
            cursor = raw.index(after: end)
        }
        result += raw[cursor...]
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
