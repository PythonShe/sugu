import Foundation
internal import KanaKanjiConverterModuleWithDefaultDictionary
import SuguCore
import SuguLM

/// Japanese composition on AzooKeyKanaKanjiConverter.
///
/// `ComposingText` owns the kana input. During conversion Sugu keeps the
/// clause state on top of it: clauses already fixed, the focused clause and
/// its candidates, and the best conversion of what follows.
@MainActor
public final class AzooKeyEngine: CompositionEngine {
    public struct Configuration: Sendable, Equatable {
        public var kanaInput = false
        public var predictions = true
        /// Shows the converter's best sentence in place of the kana while
        /// typing; Enter commits it.
        public var liveConversion = false
        public var typoCorrection = true
        /// Zenzai model file; nil keeps neural conversion off.
        public var zenzaiModel: URL?
        /// Where AzooKey may write its own files. Its learning is off (Sugu
        /// owns learning), but the converter still needs a writable path.
        public var workingDirectory: URL

        public init(workingDirectory: URL) {
            self.workingDirectory = workingDirectory
        }
    }

    private struct FixedClause {
        var text: String
        var reading: String
        /// The keys typed for this clause, for F9/F10.
        var typed: String
        /// The composition before this clause was fixed, to step back to.
        var before: ComposingText
    }

    private var converter: KanaKanjiConverter {
        didSet { lastRequest = nil }
    }
    /// The converter's last request and its result. Asked for the same
    /// input again, AzooKeyKanaKanjiConverter rebuilds its results from the
    /// lattice in a way that can trap when the lattice grew from other
    /// input (D-051, D-060), so the same input never reaches it twice in a
    /// row: every request asks for predictions alike, and an unchanged
    /// input takes the last result.
    private var lastRequest: (input: ComposingText, result: ConversionResult)?
    /// The dictionary the converter and the refiner read: from its files
    /// at each lookup until `adopt(_:)` hands over one held in memory.
    private var dictionary = DicdataStore.withDefaultDictionary()
    /// Made on the first ranking, not with the engine.
    private var loadedRefiner: HomophoneRefiner?
    /// Ranks the converter's sentences by how naturally they read
    /// (ADR 0005); nil ranks by the converter's costs alone.
    public var languageModel: CharacterLanguageModel?
    /// The Zenzai model the converter has loaded, if any.
    private var loadedZenzai: URL?
    private var configuration: Configuration
    private var userWords: [DicdataElement] = []
    private var composing = ComposingText()
    private var leftContext = ""

    private var converting = false
    private var fixed: [FixedClause] = []
    /// Clauses fixed before the current conversion began (kept when typing
    /// went on after a conversion); Esc and stepping back stop there.
    private var conversionStart = 0
    private var focusCandidates: [KanaKanjiConverterModule.Candidate] = []
    private var highlighted = 0
    /// Clause length chosen with Shift-arrows, in kana; nil lets the
    /// converter pick the first clause.
    private var focusLength: Int?
    private var predictions: [KanaKanjiConverterModule.Candidate] = []
    private var followingText = ""
    /// What live conversion shows for the unfixed input; nil shows kana.
    private var liveText: String?
    /// Text after the first clause of the best sentence, keyed by that
    /// clause's kana length.
    private var bestFollowing: (length: Int, text: String)?
    /// The focused clause as the best sentence writes it, while its
    /// candidates are requested.
    private var preferredFocus: KanaKanjiConverterModule.Candidate?

    public let traits = EngineTraits(hasConversionPhase: true, learnsCommits: true, takesSuguCandidates: true)
    public private(set) var state = CompositionState.empty
    /// Built once: constructing it reads the emoji dictionary from disk,
    /// which cost more than the conversion itself on every keystroke.
    private let textReplacer = TextReplacer.withDefaultEmojiDictionary()

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.converter = KanaKanjiConverter(dicdataStore: dictionary)
    }

    public func update(_ configuration: Configuration) {
        self.configuration = configuration
        lastRequest = nil
        releaseZenzaiIfUnused()
    }

    /// Words from Sugu's learned store and user dictionary, given to the
    /// converter so they take part in lattice search.
    public func setUserWords(_ words: [(reading: String, text: String)]) {
        userWords = words.map { word in
            DicdataElement(
                word: word.text,
                ruby: WidthConversion.katakana(word.reading),
                cid: CIDData.一般名詞.cid,
                mid: MIDData.一般.mid,
                value: -5
            )
        }
        converter.importDynamicUserDictionary(userWords)
        lastRequest = nil
        loadedRefiner?.userWords = Set(words.map(\.text))
    }

    /// A converter that has loaded a Zenzai model, made off the main thread:
    /// the first load compiles Metal shaders, seconds after an install or a
    /// system update, which must not happen inside a keystroke.
    public struct ZenzaiConverter: @unchecked Sendable {
        // Handed from the thread that made it to the engine, never shared.
        fileprivate let converter: KanaKanjiConverter
        public let model: URL
    }

    /// nil when the model does not load: AzooKey would otherwise try again,
    /// on the main thread, at every conversion.
    public nonisolated static func loadZenzai(_ model: URL, workingDirectory: URL) async -> ZenzaiConverter? {
        await Task.detached(priority: .utility) {
            let converter = KanaKanjiConverter.withDefaultDictionary()
            var configuration = Configuration(workingDirectory: workingDirectory)
            configuration.zenzaiModel = model
            var composing = ComposingText()
            composing.insertAtCursorPosition("あ", inputStyle: .direct)
            _ = converter.requestCandidates(composing, options: options(configuration, leftContext: "", textReplacer: .empty, predictions: false))
            converter.stopComposition()
            // AzooKey reports a failed load only in this status line.
            guard converter.zenzStatus == "load \(model.absoluteString)" else { return nil }
            return ZenzaiConverter(converter: converter, model: model)
        }.value
    }

    /// Takes over a converter that loaded Zenzai; call between compositions.
    public func adopt(_ loaded: ZenzaiConverter) {
        precondition(state.isEmpty, "a converter is swapped only between compositions")
        converter = loaded.converter
        loadedZenzai = loaded.model
        converter.importDynamicUserDictionary(userWords)
    }

    /// Swaps a converter holding a Zenzai model that is no longer used for a
    /// plain one, freeing the model's memory; waits for the composition to end.
    private func releaseZenzaiIfUnused() {
        guard loadedZenzai != nil, loadedZenzai != configuration.zenzaiModel, state.isEmpty else { return }
        converter = KanaKanjiConverter(dicdataStore: dictionary)
        loadedZenzai = nil
        converter.importDynamicUserDictionary(userWords)
    }

    /// AzooKey's dictionary read into memory, so a lookup no longer opens
    /// and maps one of its files (D-070). Reading it takes ~40 ms, too long
    /// for the first Japanese keystroke, so it is made off the main thread.
    public struct MemoryDictionary: @unchecked Sendable {
        // Handed from the thread that made it to the engine, never shared.
        fileprivate let store: DicdataStore
    }

    public nonisolated static func loadMemoryDictionary() async -> MemoryDictionary {
        await Task.detached(priority: .utility) {
            MemoryDictionary(store: DicdataStore.withDefaultDictionary(preloadDictionary: true))
        }.value
    }

    /// Takes over a dictionary held in memory; call between compositions.
    /// A converter holding Zenzai keeps its own until it is released.
    public func adopt(_ loaded: MemoryDictionary) {
        precondition(state.isEmpty, "the dictionary is swapped only between compositions")
        dictionary = loaded.store
        loadedRefiner = nil
        guard loadedZenzai == nil else { return }
        converter = KanaKanjiConverter(dicdataStore: dictionary)
        converter.importDynamicUserDictionary(userWords)
    }

    /// Whether the converter holds a Zenzai model (for tests).
    public var holdsZenzai: Bool { loadedZenzai != nil }

    private var inputStyle: InputStyle { configuration.kanaInput ? .direct : .roman2kana }

    /// The converter's results for `input`, with predictions when they
    /// are on.
    private func request(_ input: ComposingText) -> ConversionResult {
        if let lastRequest, lastRequest.input == input { return lastRequest.result }
        let result = converter.requestCandidates(input, options: options(predictions: configuration.predictions))
        lastRequest = (input, result)
        return result
    }

    /// Conversions of `input`: its results without the predictions, which
    /// read further than the input.
    private func conversions(of input: ComposingText) -> ConversionResult {
        var result = request(input)
        let length = input.convertTarget.count
        result.mainResults.removeAll { $0.rubyCount > length }
        result.firstClauseResults.removeAll { $0.rubyCount > length }
        return result
    }

    private func options(predictions: Bool) -> ConvertRequestOptions {
        Self.options(configuration, leftContext: leftContext, textReplacer: textReplacer, predictions: predictions)
    }

    private nonisolated static func options(_ configuration: Configuration, leftContext: String, textReplacer: TextReplacer, predictions: Bool) -> ConvertRequestOptions {
        var zenzai = ConvertRequestOptions.ZenzaiMode.off
        if let model = configuration.zenzaiModel {
            zenzai = .on(
                weight: model,
                inferenceLimit: 10,
                personalizationMode: nil,
                versionDependentMode: .v3(.init(leftSideContext: leftContext.isEmpty ? nil : String(leftContext.suffix(40))))
            )
        }
        return ConvertRequestOptions(
            N_best: 10,
            needTypoCorrection: configuration.typoCorrection,
            requireJapanesePrediction: predictions,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            // Asks the system spell checker over XPC on every key, most of
            // the keystroke time; Sugu offers typed English words itself.
            englishCandidateInRoman2KanaInput: false,
            fullWidthRomanCandidate: true,
            halfWidthKanaCandidate: true,
            learningType: .nothing,
            maxMemoryCount: 0,
            memoryDirectoryURL: configuration.workingDirectory,
            sharedContainerURL: configuration.workingDirectory,
            textReplacer: textReplacer,
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            zenzaiMode: zenzai,
            metadata: .init(versionString: "Sugu")
        )
    }

    // MARK: CompositionEngine

    public func accepts(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        if configuration.kanaInput { return !scalar.properties.isWhitespace && scalar.value >= 0x21 }
        return (0x21...0x7E).contains(scalar.value)
    }

    public func insert(_ text: String) {
        if converting { commitFixedPrefixForTyping() }
        if let voiced = voicing(text) {
            composing.deleteBackwardFromCursorPosition(count: 1)
            composing.insertAtCursorPosition(String(voiced), inputStyle: inputStyle)
        } else {
            composing.insertAtCursorPosition(text, inputStyle: inputStyle)
        }
        refreshComposing()
    }

    /// In kana input a voicing mark joins the kana before the caret
    /// (か゛ → が) when it takes one; otherwise it is typed as it is.
    private func voicing(_ text: String) -> Character? {
        guard configuration.kanaInput, text.count == 1, let mark = text.first,
              mark == KanaLayout.voicedMark || mark == KanaLayout.semiVoicedMark,
              composing.convertTargetCursorPosition > 0 else { return nil }
        let target = composing.convertTarget
        let before = target[target.index(target.startIndex, offsetBy: composing.convertTargetCursorPosition - 1)]
        return KanaLayout.applying(mark, to: before)
    }

    public func deleteBackward() {
        if converting { cancelConversion(); return }
        guard !composing.isEmpty else { return }
        composing.deleteBackwardFromCursorPosition(count: 1)
        refreshComposing()
    }

    public func deleteForward() {
        if converting { cancelConversion(); return }
        composing.deleteForwardFromCursorPosition(count: 1)
        refreshComposing()
    }

    public func moveCaret(_ motion: CaretMotion) {
        guard !converting else { return }
        switch motion {
        case .left: _ = composing.moveCursorFromCursorPosition(count: -1)
        case .right: _ = composing.moveCursorFromCursorPosition(count: 1)
        case .start: _ = composing.moveCursorFromCursorPosition(count: -composing.convertTargetCursorPosition)
        case .end: _ = composing.moveCursorFromCursorPosition(count: composing.convertTarget.count - composing.convertTargetCursorPosition)
        }
        refreshComposing()
    }

    @discardableResult
    public func convert() -> Bool {
        if converting {
            highlight(highlighted + 1)
            return true
        }
        guard !composing.isEmpty else { return false }
        _ = composing.moveCursorFromCursorPosition(count: composing.convertTarget.count - composing.convertTargetCursorPosition)
        finishRomaji()
        converting = true
        conversionStart = fixed.count
        focusLength = nil
        refocus()
        return true
    }

    public func cancelConversion() {
        guard converting else { return }
        if fixed.count > conversionStart {
            composing = fixed[conversionStart].before
            fixed.removeSubrange(conversionStart...)
        }
        converting = false
        focusLength = nil
        endConversionLattice()
        refreshComposing()
    }

    /// The converter reuses its lattice for input changed at its end. After
    /// conversion asked for a clause, the whole input again would grow that
    /// clause's lattice back, which AzooKeyKanaKanjiConverter can leave
    /// inconsistent and trap on at the next request; typing starts afresh.
    private func endConversionLattice() {
        converter.stopComposition()
        lastRequest = nil
    }

    public func highlight(_ index: Int) {
        guard converting, !focusCandidates.isEmpty else { return }
        highlighted = (index % focusCandidates.count + focusCandidates.count) % focusCandidates.count
        updateFollowingText()
        publishConverting()
    }

    public func select(_ index: Int) -> SelectionResult {
        if !converting {
            // Choosing a prediction while typing commits it whole.
            guard predictions.indices.contains(index) else { return .continued }
            let candidate = predictions[index]
            let commit = Commit(text: candidate.text, reading: composing.convertTarget, clauses: [.init(reading: composing.convertTarget, text: candidate.text)])
            clear()
            return .committed(commit)
        }
        guard focusCandidates.indices.contains(index) else { return .continued }
        fix(focusCandidates[index])
        if composing.isEmpty {
            let commit = makeCommit(trailing: nil)
            clear()
            return .committed(commit)
        }
        // The next clause is the best sentence's, not one of the same length.
        focusLength = nil
        refocus()
        return .continued
    }

    public func moveFocus(forward: Bool) {
        guard converting else { return }
        if forward {
            guard focusCandidates.indices.contains(highlighted) else { return }
            let candidate = focusCandidates[highlighted]
            var remainder = composing
            remainder.prefixComplete(composingCount: candidate.composingCount)
            guard !remainder.isEmpty else { return }
            fix(candidate)
        } else {
            guard fixed.count > conversionStart, let last = fixed.popLast() else { return }
            composing = last.before
        }
        focusLength = nil
        refocus()
    }

    public func resizeFocus(by delta: Int) {
        guard converting else { return }
        let current = focusLength ?? focusCandidates[safe: highlighted]?.rubyCount ?? composing.convertTarget.count
        let length = min(max(1, current + delta), composing.convertTarget.count)
        guard length != focusLength else { return }
        focusLength = length
        refocus()
    }

    public func commitConverted() -> Commit? {
        if converting {
            let commit = makeCommit(trailing: focusCandidates[safe: highlighted])
            clear()
            return commit
        }
        if configuration.liveConversion {
            finishRomaji()
            liveText = liveConversion()
        }
        guard !fixed.isEmpty || liveText != nil else { return commitRaw() }
        let commit = makeCommit(trailing: nil)
        clear()
        return commit
    }

    public func commitRaw() -> Commit? {
        if !converting { finishRomaji() }
        let reading = fullReading
        guard !reading.isEmpty else { return nil }
        clear()
        return Commit(text: reading, reading: reading)
    }

    public func clear() {
        composing = ComposingText()
        converting = false
        fixed = []
        conversionStart = 0
        focusCandidates = []
        predictions = []
        highlighted = 0
        focusLength = nil
        followingText = ""
        liveText = nil
        converter.stopComposition()
        lastRequest = nil
        state = .empty
        releaseZenzaiIfUnused()
    }

    /// Ends romaji input at the caret, as a separator would: a pending
    /// "n" becomes ん, so "imasen" converts as いません.
    private func finishRomaji() {
        guard inputStyle == .roman2kana, composing.convertTargetCursorPosition == composing.convertTarget.count,
              composing.convertTarget.last == "n" else { return }
        composing.insertAtCursorPosition([ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .roman2kana)])
    }

    public func restore(reading: String) {
        clear()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        convert()
    }

    public func setLeftContext(_ text: String) {
        if text != leftContext { lastRequest = nil }
        leftContext = text
    }

    // MARK: Conversion state

    private func fix(_ candidate: KanaKanjiConverterModule.Candidate) {
        let before = composing
        composing.prefixComplete(composingCount: candidate.composingCount)
        let reading = String(before.convertTarget.dropLast(composing.convertTarget.count))
        let typed = Self.typed(before.input.dropLast(composing.input.count))
        fixed.append(FixedClause(text: candidate.text, reading: reading, typed: typed, before: before))
    }

    /// Typing during conversion commits nothing; it keeps the fixed clauses
    /// and the focused candidate as converted text and resumes input after
    /// them, as the system Japanese input method does.
    private func commitFixedPrefixForTyping() {
        endConversionLattice()
        if let candidate = focusCandidates[safe: highlighted] {
            var remainder = composing
            remainder.prefixComplete(composingCount: candidate.composingCount)
            fix(candidate)
            composing = remainder
        }
        converting = false
    }

    private func makeCommit(trailing candidate: KanaKanjiConverterModule.Candidate?) -> Commit {
        var clauses = fixed.map { Commit.Clause(reading: $0.reading, text: $0.text) }
        if let candidate {
            var remainder = composing
            remainder.prefixComplete(composingCount: candidate.composingCount)
            clauses.append(.init(reading: String(composing.convertTarget.dropLast(remainder.convertTarget.count)), text: candidate.text))
            if !remainder.isEmpty {
                clauses.append(.init(reading: remainder.convertTarget, text: followingText.isEmpty ? remainder.convertTarget : followingText))
            }
        } else if !composing.isEmpty {
            clauses.append(.init(reading: composing.convertTarget, text: liveText ?? composing.convertTarget))
        }
        return Commit(
            text: clauses.map(\.text).joined(),
            reading: clauses.map(\.reading).joined(),
            clauses: clauses
        )
    }

    /// Recomputes candidates for the focused clause at the start of the
    /// unfixed input. Without a chosen length the boundary is the first
    /// clause of the best sentence, so the first display is exactly the
    /// converter's best conversion. Candidates are then requested for that
    /// prefix, so the list holds alternatives for the clause.
    private func refocus() {
        highlighted = 0
        bestFollowing = nil
        let total = composing.convertTarget.count
        if focusLength == nil {
            let result = conversions(of: composing)
            let sentences = ranked(result.mainResults, length: total, after: history)
            guard let best = sentences.first else {
                focusCandidates = []
                followingText = ""
                publishConverting()
                return
            }
            // One clause: the ranked sentences are its candidates.
            guard let clause = firstClause(of: best, among: result.firstClauseResults, total: total) else {
                focusCandidates = sentences
                updateFollowingText()
                publishConverting()
                return
            }
            focusLength = clause.rubyCount
            // The clause list has its own order; it yields only to a
            // sentence the language model preferred.
            if best.text != result.mainResults.first?.text { preferredFocus = clause }
            bestFollowing = (clause.rubyCount, String(best.text.dropFirst(clause.text.count)))
        }
        let length = min(focusLength ?? total, total)
        var prefix = composing
        _ = prefix.moveCursorFromCursorPosition(count: length - prefix.convertTargetCursorPosition)
        focusCandidates = conversions(of: prefix.prefixToCursorPosition()).mainResults
        // The clause as the ranked sentence wrote it comes first, so the
        // first display is that sentence.
        if let preferredFocus {
            focusCandidates.removeAll { $0.text == preferredFocus.text }
            focusCandidates.insert(preferredFocus, at: 0)
        }
        preferredFocus = nil
        updateFollowingText()
        publishConverting()
    }

    /// The first clause of `best`: one the converter proposed, or, when
    /// refinement rewrote that clause, the converter's clause of the same
    /// length as `best` writes it.
    private func firstClause(
        of best: KanaKanjiConverterModule.Candidate,
        among clauses: [KanaKanjiConverterModule.Candidate],
        total: Int
    ) -> KanaKanjiConverterModule.Candidate? {
        let spans = clauses.filter { $0.rubyCount > 0 && $0.rubyCount < total }
        if let proposed = spans.filter({ best.text.hasPrefix($0.text) }).max(by: { $0.value < $1.value }) {
            return proposed
        }
        guard best.data.map(\.word).joined() == best.text else { return nil }
        return spans.compactMap { clause -> KanaKanjiConverterModule.Candidate? in
            var words: [DicdataElement] = []
            var length = 0
            for word in best.data where length < clause.rubyCount {
                words.append(word)
                length += word.ruby.count
            }
            guard length == clause.rubyCount, let last = words.last else { return nil }
            return KanaKanjiConverterModule.Candidate(
                text: words.map(\.word).joined(), value: clause.value, composingCount: clause.composingCount,
                lastMid: last.mid, data: words
            )
        }.max { $0.value < $1.value }
    }

    private var refiner: HomophoneRefiner {
        if let loadedRefiner { return loadedRefiner }
        let refiner = HomophoneRefiner(
            dictionary: dictionary,
            options: Self.options(configuration, leftContext: "", textReplacer: .empty, predictions: false)
        )
        refiner.userWords = Set(userWords.map(\.word))
        loadedRefiner = refiner
        return refiner
    }

    /// Text before the unfixed input: the document's, then fixed clauses.
    private var history: String {
        leftContext + fixed.map(\.text).joined()
    }

    /// The converter's whole-input sentences, at most five at the head of
    /// its results, reordered by its cost plus the language model's log
    /// probability after `history`, with the best one respelled ahead of
    /// them when the model prefers it; the rest keep their place. Zenzai,
    /// when on, has already chosen.
    private func ranked(_ results: [KanaKanjiConverterModule.Candidate], length: Int, after history: String) -> [KanaKanjiConverterModule.Candidate] {
        guard let languageModel, configuration.zenzaiModel == nil else { return results }
        let sentences = results.prefix(5).prefix { $0.rubyCount == length }
        guard !sentences.isEmpty else { return results }
        var reordered = sentences
            .map { (candidate: $0, score: $0.value + languageModel.logProbability(of: $0.text, after: history)) }
            .enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map(\.element.candidate)
        let best = refiner.refined(reordered[0], after: history, model: languageModel)
        var rest = Array(results.dropFirst(sentences.count))
        if best.text != reordered[0].text {
            // A sentence the converter also proposed moves up rather than
            // showing twice.
            reordered.removeAll { $0.text == best.text }
            rest.removeAll { $0.text == best.text }
            reordered.insert(best, at: 0)
        }
        return reordered + rest
    }

    /// Converts what follows the highlighted clause candidate, reusing the
    /// best sentence when the clause length matches it.
    private func updateFollowingText() {
        followingText = ""
        guard let candidate = focusCandidates[safe: highlighted] else { return }
        if let bestFollowing, bestFollowing.length == candidate.rubyCount {
            followingText = bestFollowing.text
            return
        }
        var remainder = composing
        remainder.prefixComplete(composingCount: candidate.composingCount)
        guard !remainder.isEmpty else { return }
        let results = conversions(of: remainder).mainResults
        followingText = ranked(results, length: remainder.convertTarget.count, after: history + candidate.text).first?.text ?? remainder.convertTarget
    }

    private func publishConverting() {
        var segments = fixed.map { CompositionSegment($0.text, role: .converted) }
        let focused = focusCandidates[safe: highlighted]?.text ?? composing.convertTarget
        segments.append(CompositionSegment(focused, role: .focused))
        if !followingText.isEmpty { segments.append(CompositionSegment(followingText, role: .converted)) }
        let caret = segments.prefix(fixed.count + 1).map(\.text.count).reduce(0, +)
        state = CompositionState(
            segments: segments,
            caret: caret,
            candidates: focusCandidates.enumerated().map { candidate($1, index: $0) },
            highlightedIndex: highlighted,
            phase: .converting,
            reading: fullReading,
            typed: typedText
        )
    }

    /// The whole composition's kana: fixed clauses and what is still being
    /// typed or converted.
    private var fullReading: String {
        fixed.map(\.reading).joined() + composing.convertTarget
    }

    /// Romaji (or kana keys) as typed, for F9/F10.
    private var typedText: String {
        fixed.map(\.typed).joined() + Self.typed(composing.input[...])
    }

    private static func typed(_ input: ArraySlice<ComposingText.InputElement>) -> String {
        input.map { element -> String in
            if case .character(let c) = element.piece { return String(c) }
            return ""
        }.joined()
    }

    /// The candidate's reading in hiragana, shown as a reading hint when it
    /// differs from the text.
    private func candidate(_ candidate: KanaKanjiConverterModule.Candidate, index: Int) -> SuguCore.Candidate {
        SuguCore.Candidate(
            text: candidate.text, annotation: readingHint(candidate), source: .engine(index: index),
            isProperNoun: !candidate.data.isEmpty && candidate.data.allSatisfy { Self.properNounClasses.contains($0.lcid) }
        )
    }

    /// Word classes of names: places, people, organizations.
    private static let properNounClasses: Set<Int> = Set(
        [CIDData.固有名詞, .人名一般, .人名姓, .人名名, .固有名詞組織, .地名一般].map(\.cid)
    )

    private func readingHint(_ candidate: KanaKanjiConverterModule.Candidate) -> String? {
        let reading = WidthConversion.hiragana(candidate.data.map(\.ruby).joined())
        return reading == candidate.text || reading.isEmpty ? nil : reading
    }

    /// The best sentence for the unfixed input, with romaji not yet kana
    /// left as typed; nil while the caret is inside the input, which shows
    /// the kana being edited.
    private func liveConversion() -> String? {
        let target = composing.convertTarget
        guard !target.isEmpty, composing.convertTargetCursorPosition == target.count else { return nil }
        let pending = target.reversed().prefix { $0.isASCII }.count
        guard pending < target.count else { return nil }
        var kana = composing
        _ = kana.moveCursorFromCursorPosition(count: -pending)
        let input = kana.prefixToCursorPosition()
        let result = conversions(of: input)
        return ranked(result.mainResults, length: input.convertTarget.count, after: history).first.map { $0.text + target.suffix(pending) }
    }

    private func refreshComposing() {
        converting = false
        if composing.isEmpty && fixed.isEmpty {
            predictions = []
            state = .empty
            releaseZenzaiIfUnused()
            return
        }
        if configuration.predictions, !composing.isEmpty {
            predictions = Array(request(composing).mainResults.prefix(9))
        } else {
            predictions = []
        }
        liveText = configuration.liveConversion ? liveConversion() : nil
        var segments = fixed.map { CompositionSegment($0.text, role: .converted) }
        let shown = liveText ?? composing.convertTarget
        if !shown.isEmpty { segments.append(CompositionSegment(shown, role: .input)) }
        let fixedLength = fixed.map(\.text.count).reduce(0, +)
        state = CompositionState(
            segments: segments,
            caret: fixedLength + (liveText?.count ?? composing.convertTargetCursorPosition),
            candidates: predictions.enumerated().map { candidate($1, index: $0) },
            highlightedIndex: nil,
            phase: .composing,
            reading: fullReading,
            typed: typedText
        )
    }
}
