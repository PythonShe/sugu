import Foundation
internal import KanaKanjiConverterModuleWithDefaultDictionary
import SuguCore
import SuguLM

/// Rewrites words of a converted sentence as other spellings of the same
/// reading when the language model reads the result as more natural
/// (ADR 0005, decision 7). The converter proposes only its best few
/// sentences, so one that differs from them in a single word, 雪が for 行きが,
/// is often missing although the model would prefer it.
@MainActor
final class HomophoneRefiner {
    private let dictionary: DicdataStore
    /// Looks up spellings; separate from the converter that composes, whose
    /// lattice is reused from keystroke to keystroke.
    private let lookup: KanaKanjiConverter
    private let options: ConvertRequestOptions
    /// Spellings by reading, kept for the session: a lookup is a small
    /// conversion and costs most of a millisecond.
    private var spellings: [String: [[DicdataElement]]] = [:]
    private static let cacheLimit = 4096

    init(dictionary: DicdataStore, options: ConvertRequestOptions) {
        self.dictionary = dictionary
        lookup = KanaKanjiConverter(dicdataStore: dictionary)
        var options = options
        options.N_best = 10
        options.needTypoCorrection = false
        options.zenzaiMode = .off
        options.requireJapanesePrediction = false
        options.fullWidthRomanCandidate = false
        options.halfWidthKanaCandidate = false
        options.specialCandidateProviders = []
        options.textReplacer = .empty
        self.options = options
    }

    /// `sentence` with each content word replaced by the spelling of its
    /// reading that scores best, by the converter's cost of the words and
    /// their connections plus the model's log probability after `history`.
    /// Words from the user's dictionary and learned words stay, also where
    /// the converter spelled one out of several words.
    func refined(_ sentence: KanaKanjiConverterModule.Candidate, after history: String, model: CharacterLanguageModel) -> KanaKanjiConverterModule.Candidate {
        guard !sentence.data.isEmpty, sentence.data.map(\.word).joined() == sentence.text else { return sentence }
        var words: [DicdataElement] = []
        // Whether each word stands in for one of another class, which it is
        // only compared with spellings of its own classes, and with its
        // reading in kana: the same word, priced the same, so the model
        // alone decides (沢山 or たくさん).
        var standIns: [Bool] = []
        for element in sentence.data {
            let parts = split(element) ?? (elements: [element], standIn: false)
            words += parts.elements
            standIns += parts.elements.indices.map { parts.standIn && $0 > 0 }
        }
        let kept = userWordCharacters(in: sentence.text)
        // Where the word at `index` starts in `sentence.text`; words after
        // `index` are still the sentence's own.
        var start = 0
        var value = sentence.value
        var score = value + model.logProbability(of: sentence.text, after: history)
        var index = 0
        while index < words.count {
            let word = words[index]
            let span = start..<(start + word.word.count)
            start = span.upperBound
            guard Self.mayRespell(word), !kept.intersects(integersIn: span) else {
                index += 1
                continue
            }
            let previous = index > 0 ? words[index - 1].rcid : CIDData.BOS.cid
            let next = index + 1 < words.count ? words[index + 1].lcid : CIDData.EOS.cid
            let base = cost(of: [word], between: previous, and: next)
            // The model reads each character after the four before it, so a
            // spelling changes only its own characters' scores and those of
            // the four after it.
            let before = (history.isEmpty ? Self.start : history) + words[..<index].map(\.word).joined()
            let after = String(words[(index + 1)...].map(\.word).joined().prefix(model.order - 1))
            func local(_ text: String) -> Float { model.logProbability(of: text + after, after: String(before.suffix(model.order - 1))) }
            let baseLocal = local(word.word)
            var choice: (elements: [DicdataElement], value: PValue, score: Float)?
            var candidates = spellings(of: word.ruby)
            if standIns[index] {
                let kana = WidthConversion.hiragana(word.ruby)
                candidates.append([DicdataElement(word: kana, ruby: word.ruby, lcid: word.lcid, rcid: word.rcid, mid: word.mid, value: word.value())])
            }
            for spelling in candidates where spelling.map(\.word).joined() != word.word {
                if standIns[index], spelling[0].lcid != word.lcid || spelling[spelling.count - 1].rcid != word.rcid { continue }
                let trialValue = value - base + cost(of: spelling, between: previous, and: next)
                let trialScore = score - value + trialValue - baseLocal + local(spelling.map(\.word).joined())
                if trialScore > choice?.score ?? score { choice = (spelling, trialValue, trialScore) }
            }
            guard let choice else {
                index += 1
                continue
            }
            words.replaceSubrange(index...index, with: choice.elements)
            standIns.replaceSubrange(index...index, with: repeatElement(false, count: choice.elements.count))
            value = choice.value
            score = choice.score
            index += choice.elements.count
        }
        guard words.map(\.word).joined() != sentence.text else { return sentence }
        return KanaKanjiConverterModule.Candidate(text: words.map(\.word).joined(), value: value, composingCount: sentence.composingCount, lastMid: sentence.lastMid, data: words)
    }

    /// The model's start-of-text marker, before a sentence with nothing
    /// before it.
    private static let start = String(repeating: "\u{2}", count: 8)

    /// Texts of the user's dictionary and learned words.
    var userWords: Set<String> = [] {
        didSet { longestUserWord = userWords.map(\.count).max() ?? 0 }
    }
    private var longestUserWord = 0

    /// Character offsets of `text` inside a user word it contains.
    private func userWordCharacters(in text: String) -> IndexSet {
        var kept = IndexSet()
        guard longestUserWord > 0 else { return kept }
        let characters = Array(text)
        for start in characters.indices {
            for end in (start + 1)...min(characters.count, start + longestUserWord) where userWords.contains(String(characters[start..<end])) {
                kept.insert(integersIn: start..<end)
            }
        }
        return kept
    }

    /// A particle and the word after it as two elements, where the
    /// converter wrote them as one (を引き, が早い): the particle's class on
    /// the left and the word's on the right. The word is the dictionary's
    /// entry for its reading, so it is priced and respelled like any other;
    /// `standIn` when no entry ends in the element's class and one of
    /// another class takes its place (引き as a noun for the verb's stem).
    private func split(_ element: DicdataElement) -> (elements: [DicdataElement], standIn: Bool)? {
        guard Self.isFunctionWord(element.lcid), !Self.isFunctionWord(element.rcid), element.metadata.isEmpty else { return nil }
        let ruby = Array(element.ruby)
        let text = Array(element.word)
        guard ruby.count >= 3 else { return nil }
        for length in stride(from: min(3, ruby.count - 2), through: 1, by: -1) {
            let particleRuby = String(ruby[..<length])
            let particle = WidthConversion.hiragana(particleRuby)
            guard text.count > length, String(text[..<length]) == particle else { continue }
            let rest = String(text[length...])
            let entries = spellings(of: String(ruby[length...])).filter { $0.map(\.word).joined() == rest }
            let exact = entries.first { $0.last?.rcid == element.rcid }
            guard let word = exact ?? entries.first(where: { $0.count == 1 }) else { continue }
            let value = element.value() - word.map { $0.value() }.reduce(0, +)
            return ([DicdataElement(word: particle, ruby: particleRuby, cid: element.lcid, mid: element.mid, value: value)] + word, exact == nil)
        }
        return nil
    }

    /// Particles and auxiliaries, 147...554 in the dictionary's word classes.
    private static func isFunctionWord(_ cid: Int) -> Bool {
        (147...554).contains(cid)
    }

    /// Content words of two to six kana; particles and auxiliaries have no
    /// spellings worth a lookup.
    private static func mayRespell(_ word: DicdataElement) -> Bool {
        (2...6).contains(word.ruby.count) && word.metadata.isEmpty && !isFunctionWord(word.lcid)
    }

    /// The words' own costs and the connections into, between, and out of
    /// them, as the converter's lattice adds them.
    private func cost(of elements: [DicdataElement], between previous: Int, and next: Int) -> PValue {
        var total = dictionary.getCCValue(previous, elements[0].lcid) + dictionary.getCCValue(elements[elements.count - 1].rcid, next)
        for (offset, element) in elements.enumerated() {
            total += element.value()
            if offset > 0 { total += dictionary.getCCValue(elements[offset - 1].rcid, element.lcid) }
        }
        return total
    }

    /// Ways to write a reading (katakana) as one or more dictionary words.
    private func spellings(of ruby: String) -> [[DicdataElement]] {
        if let known = spellings[ruby] { return known }
        var text = ComposingText()
        text.insertAtCursorPosition(WidthConversion.hiragana(ruby), inputStyle: .direct)
        let result = lookup.requestCandidates(text, options: options)
        lookup.stopComposition()
        var seen = Set<[String]>()
        let found = (result.mainResults + result.firstClauseResults)
            .filter { !$0.data.isEmpty && $0.data.map(\.ruby).joined() == ruby && $0.data.map(\.word).joined() == $0.text }
            .map(\.data)
            .filter { seen.insert($0.map { "\($0.word)\t\($0.lcid)\t\($0.rcid)" }).inserted }
        if spellings.count >= Self.cacheLimit { spellings = [:] }
        spellings[ruby] = found
        return found
    }
}
