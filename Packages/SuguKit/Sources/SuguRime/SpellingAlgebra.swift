import Foundation

/// The part of librime's spelling algebra that Sugu's schemes use, run in
/// Swift over toneless syllables: the key sequences that type a syllable.
/// librime applies the same rules to build its prism; Sugu runs them to
/// read typed keys back as syllables.
struct SpellingAlgebra {
    struct Spelling: Hashable {
        var text: String
        /// Produced by a `derive` or `fuzz` rule (typo tolerance, fuzzy
        /// pinyin) rather than the scheme's own mapping.
        var isDerived: Bool
    }

    private enum Rule {
        case transform(NSRegularExpression, String)
        case derive(NSRegularExpression, String)
        case erase(NSRegularExpression)
        case transliterate([Character: Character])
    }

    private let rules: [Rule]

    /// Rules written as in a schema, such as `xform/^zh/v/`. Abbreviations
    /// are left out: a reading typed with them names no single syllable.
    init(rules: [String]) {
        self.rules = rules.compactMap(Self.parse)
    }

    private static func parse(_ text: String) -> Rule? {
        guard let slash = text.firstIndex(of: "/") else { return nil }
        let operation = text[..<slash]
        let fields = text[text.index(after: slash)...].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let left = fields.first else { return nil }
        let right = fields.count > 1 ? fields[1] : ""
        if operation == "xlit" {
            let from = Array(left), to = Array(right)
            guard from.count == to.count else { return nil }
            return .transliterate(Dictionary(zip(from, to)) { first, _ in first })
        }
        // librime erases on a whole match.
        guard let pattern = try? NSRegularExpression(pattern: operation == "erase" ? "^(?:\(left))$" : left) else { return nil }
        switch operation {
        case "xform": return .transform(pattern, right)
        case "derive", "fuzz": return .derive(pattern, right)
        case "erase": return .erase(pattern)
        default: return nil
        }
    }

    /// Every spelling of `syllable` after the rules, in librime's order:
    /// `xform` replaces, `derive` adds, `erase` removes on a whole match.
    func spellings(of syllable: String) -> Set<Spelling> {
        var spellings: Set<Spelling> = [Spelling(text: syllable, isDerived: false)]
        for rule in rules {
            var next = Set<Spelling>()
            for spelling in spellings {
                switch rule {
                case .transform(let pattern, let template):
                    next.insert(Spelling(text: Self.replace(spelling.text, pattern, template), isDerived: spelling.isDerived))
                case .derive(let pattern, let template):
                    next.insert(spelling)
                    let derived = Self.replace(spelling.text, pattern, template)
                    if derived != spelling.text { next.insert(Spelling(text: derived, isDerived: true)) }
                case .erase(let pattern):
                    if pattern.firstMatch(in: spelling.text, range: NSRange(spelling.text.startIndex..., in: spelling.text)) == nil {
                        next.insert(spelling)
                    }
                case .transliterate(let map):
                    next.insert(Spelling(text: String(spelling.text.map { map[$0] ?? $0 }), isDerived: spelling.isDerived))
                }
            }
            spellings = next.filter { !$0.text.isEmpty }
        }
        return spellings
    }

    private static func replace(_ text: String, _ pattern: NSRegularExpression, _ template: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// The rules a schema patch such as `wanxiang_algebra:/lite/全拼` adds:
    /// the `__append` list under that key path in `<name>.yaml`.
    static func rules(patch: String, in directory: URL) -> [String]? {
        let parts = patch.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let text = try? String(contentsOf: directory.appendingPathComponent("\(parts[0]).yaml"), encoding: .utf8)
        else { return nil }
        return rules(at: parts[1].split(separator: "/").map(String.init) + ["__append"], inYAML: text)
    }

    /// The list items under a key path in YAML indented by key, as the
    /// algebra files are; enough of YAML for them, not a general parser.
    static func rules(at path: [String], inYAML text: String) -> [String]? {
        var depth = 0
        var indents: [Int] = []
        var items: [String]?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let content = line.drop { $0 == " " }
            guard !content.isEmpty, !content.hasPrefix("#") else { continue }
            let indent = line.count - content.count
            while let last = indents.last, indent <= last {
                indents.removeLast()
                depth -= 1
                if items != nil { return items }
            }
            if depth == path.count {
                guard content.hasPrefix("- ") else { continue }
                items?.append(item(content.dropFirst(2)))
            } else if content == "\(path[depth]):", depth > 0 || indent == 0 {
                indents.append(indent)
                depth += 1
                if depth == path.count { items = [] }
            }
        }
        return items
    }

    private static func item(_ text: Substring) -> String {
        var value = String(text)
        if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]) }
        value = value.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
