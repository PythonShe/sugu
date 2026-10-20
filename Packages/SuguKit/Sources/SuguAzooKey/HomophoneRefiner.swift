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
        var words = sentence.data
        guard !words.isEmpty, words.map(\.word).joined() == sentence.text else { return sentence }
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
            var choice: (elements: [DicdataElement], value: PValue, score: Float)?
            for spelling in spellings(of: word.ruby) where spelling.map(\.word).joined() != word.word {
                var trial = words
                trial.replaceSubrange(index...index, with: spelling)
                let trialValue = value - base + cost(of: spelling, between: previous, and: next)
                let trialScore = trialValue + model.logProbability(of: trial.map(\.word).joined(), after: history)
                if trialScore > choice?.score ?? score { choice = (spelling, trialValue, trialScore) }
            }
            guard let choice else {
                index += 1
                continue
            }
            words.replaceSubrange(index...index, with: choice.elements)
            value = choice.value
            score = choice.score
            index += choice.elements.count
        }
        guard words != sentence.data else { return sentence }
        return KanaKanjiConverterModule.Candidate(text: words.map(\.word).joined(), value: value, composingCount: sentence.composingCount, lastMid: sentence.lastMid, data: words)
    }

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

    /// Content words of two to six kana; particles and auxiliaries
    /// (147...554 in the dictionary's word classes) have no spellings worth
    /// a lookup.
    private static func mayRespell(_ word: DicdataElement) -> Bool {
        (2...6).contains(word.ruby.count) && word.metadata.isEmpty && !(147...554).contains(word.lcid)
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
