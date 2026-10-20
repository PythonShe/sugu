import Foundation
internal import KanaKanjiConverterModuleWithDefaultDictionary
import SuguCore

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

    private let converter: KanaKanjiConverter
    private var configuration: Configuration
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
    /// Text after the first clause of the best sentence, keyed by that
    /// clause's kana length.
    private var bestFollowing: (length: Int, text: String)?

    public let traits = EngineTraits(hasConversionPhase: true, learnsCommits: true, takesSuguCandidates: true)
    public private(set) var state = CompositionState.empty
    /// Built once: constructing it reads the emoji dictionary from disk,
    /// which cost more than the conversion itself on every keystroke.
    private let textReplacer = TextReplacer.withDefaultEmojiDictionary()

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.converter = KanaKanjiConverter.withDefaultDictionary()
    }

    public func update(_ configuration: Configuration) {
        self.configuration = configuration
    }

    /// Words from Sugu's learned store and user dictionary, given to the
    /// converter so they take part in lattice search.
    public func setUserWords(_ words: [(reading: String, text: String)]) {
        let elements = words.map { word in
            DicdataElement(
                word: word.text,
                ruby: WidthConversion.katakana(word.reading),
                cid: CIDData.一般名詞.cid,
                mid: MIDData.一般.mid,
                value: -5
            )
        }
        converter.importDynamicUserDictionary(elements)
    }

    private var inputStyle: InputStyle { configuration.kanaInput ? .direct : .roman2kana }

    private func options(predictions: Bool) -> ConvertRequestOptions {
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
        composing.insertAtCursorPosition(text, inputStyle: inputStyle)
        refreshComposing()
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
        refreshComposing()
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
        guard !fixed.isEmpty else { return commitRaw() }
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
        converter.stopComposition()
        state = .empty
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
            clauses.append(.init(reading: composing.convertTarget, text: composing.convertTarget))
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
            let result = converter.requestCandidates(composing, options: options(predictions: false))
            guard let best = result.mainResults.first else {
                focusCandidates = []
                followingText = ""
                publishConverting()
                return
            }
            let clause = result.firstClauseResults
                .filter { $0.rubyCount > 0 && $0.rubyCount < total && best.text.hasPrefix($0.text) }
                .max { $0.value < $1.value }
            guard let clause else {
                focusCandidates = result.mainResults
                updateFollowingText()
                publishConverting()
                return
            }
            focusLength = clause.rubyCount
            bestFollowing = (clause.rubyCount, String(best.text.dropFirst(clause.text.count)))
        }
        let length = min(focusLength ?? total, total)
        var prefix = composing
        _ = prefix.moveCursorFromCursorPosition(count: length - prefix.convertTargetCursorPosition)
        focusCandidates = converter.requestCandidates(prefix.prefixToCursorPosition(), options: options(predictions: false)).mainResults
        updateFollowingText()
        publishConverting()
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
        followingText = converter.requestCandidates(remainder, options: options(predictions: false)).mainResults.first?.text ?? remainder.convertTarget
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

    private func refreshComposing() {
        converting = false
        if composing.isEmpty && fixed.isEmpty {
            predictions = []
            state = .empty
            return
        }
        if configuration.predictions, !composing.isEmpty {
            predictions = Array(converter.requestCandidates(composing, options: options(predictions: true)).mainResults.prefix(9))
        } else {
            predictions = []
        }
        var segments = fixed.map { CompositionSegment($0.text, role: .converted) }
        if !composing.convertTarget.isEmpty { segments.append(CompositionSegment(composing.convertTarget, role: .input)) }
        let fixedLength = fixed.map(\.text.count).reduce(0, +)
        state = CompositionState(
            segments: segments,
            caret: fixedLength + composing.convertTargetCursorPosition,
            candidates: predictions.enumerated().map { candidate($1, index: $0) },
            highlightedIndex: nil,
            phase: .composing,
            reading: fullReading,
            typed: typedText
        )
    }
}
