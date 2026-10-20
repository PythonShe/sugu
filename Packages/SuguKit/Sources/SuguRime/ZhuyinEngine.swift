import SuguCore

/// Chinese typed in Zhuyin on the standard layout, composed as Taiwanese
/// input methods compose (D-073): each syllable ends with its tone, the
/// sentence stays converted as it grows, and choosing a word at the caret
/// fixes it while librime converts the rest around it. librime reads each
/// syllable as pinyin with its tone (`ni3`) and never sees Bopomofo.
@MainActor
public final class ZhuyinEngine: CompositionEngine {
    public let traits = EngineTraits(composition: .sentence, learnsCommits: true, takesSuguCandidates: false)
    public private(set) var state = CompositionState.empty

    private let session: RimeSession
    /// The toned syllables typed, and the text shown for each: one
    /// character as a rule, all of a word on its first syllable when
    /// librime's text does not split one per syllable.
    private var syllables: [Zhuyin.Syllable] = []
    private var texts: [String] = []
    /// The syllable being typed, before the caret's syllable.
    private var pending = Zhuyin.Syllable()
    /// Position among the syllables.
    private var caret = 0
    /// Words the user chose, by the syllables they cover; librime
    /// converts only the runs between them.
    private var fixed: [Fixed] = []
    /// The words offered at the caret while the candidate window is open,
    /// with the syllables each covers.
    private var choices: [Fixed] = []
    private var highlighted: Int?
    /// librime's sentences by input, for the session: a choice or a new
    /// syllable reconverts only the run it changed.
    private var sentences: [String: String] = [:]
    /// The last commit's choices, for a commit taken back.
    private var lastCommit: (reading: String, fixed: [Fixed])?

    /// Tells words from librime's sentences, which librime makes of words
    /// for any syllables no word covers: with Sugu's word list and the
    /// user's words, in Simplified, the list's script.
    public struct WordCheck {
        public var respeller: SentenceRespeller
        public var simplified: @MainActor () -> ScriptConverter?

        public init(respeller: SentenceRespeller, simplified: @escaping @MainActor () -> ScriptConverter?) {
            self.respeller = respeller
            self.simplified = simplified
        }
    }

    public var wordCheck: WordCheck?

    private struct Fixed: Equatable {
        var range: Range<Int>
        var text: String
    }

    /// Longest word offered at the caret, in syllables.
    private static let longestChoice = 6
    private static let singleCharacterLimit = 120
    private static let wordLimit = 20

    public init(runtime: RimeRuntime, script: ChineseScript = .simplified) {
        session = RimeSession(runtime: runtime, script: script)
    }

    /// Opens the librime session ahead of the first key.
    public func openSession() {
        _ = session.open()
    }

    /// Reopens the session so librime reads the user dictionary again,
    /// unless a composition is in progress; returns whether it reopened.
    public func reloadUserDictionary() -> Bool {
        guard state.isEmpty else { return false }
        session.destroy()
        sentences = [:]
        return session.open()
    }

    public func setScript(_ script: ChineseScript) {
        guard script != session.script else { return }
        session.script = script
        sentences = [:]
        guard !syllables.isEmpty else { return }
        reconvert()
        update()
    }

    // MARK: CompositionEngine

    public func accepts(_ character: Character) -> Bool {
        if Zhuyin.keyboard[character] != nil { return true }
        return Zhuyin.toneKeys[character] != nil && !pending.isEmpty
    }

    public func insert(_ text: String) {
        guard session.open() else { return }
        closeChoices()
        for character in text {
            if let symbol = Zhuyin.keyboard[character] {
                pending.type(symbol)
            } else if let tone = Zhuyin.toneKeys[character], !pending.isEmpty {
                finishPending(tone)
            }
        }
        update()
    }

    /// Ends the pending syllable with `tone` when librime knows it; one it
    /// does not stays pending, as in the standard input methods.
    private func finishPending(_ tone: Zhuyin.Tone) {
        var syllable = pending
        syllable.tone = tone
        guard let code = syllable.code, sentence(for: code) != nil else { return }
        // Typing inside a chosen word undoes the choice.
        fixed.removeAll { $0.range.lowerBound < caret && caret < $0.range.upperBound }
        fixed = fixed.map { $0.range.lowerBound >= caret ? Fixed(range: ($0.range.lowerBound + 1)..<($0.range.upperBound + 1), text: $0.text) : $0 }
        syllables.insert(syllable, at: caret)
        texts.insert("", at: caret)
        caret += 1
        pending = Zhuyin.Syllable()
        reconvert()
    }

    public func deleteBackward() {
        closeChoices()
        if !pending.isEmpty {
            pending.deleteLast()
        } else if caret > 0 {
            removeSyllable(at: caret - 1)
            caret -= 1
            reconvert()
        }
        update()
    }

    public func deleteForward() {
        closeChoices()
        if pending.isEmpty, caret < syllables.count {
            removeSyllable(at: caret)
            reconvert()
        }
        update()
    }

    private func removeSyllable(at index: Int) {
        syllables.remove(at: index)
        texts.remove(at: index)
        fixed.removeAll { $0.range.contains(index) }
        fixed = fixed.map { $0.range.lowerBound > index ? Fixed(range: ($0.range.lowerBound - 1)..<($0.range.upperBound - 1), text: $0.text) : $0 }
    }

    public func moveCaret(_ motion: CaretMotion) {
        guard pending.isEmpty else { return }
        closeChoices()
        switch motion {
        case .left: caret = max(0, caret - 1)
        case .right: caret = min(syllables.count, caret + 1)
        case .start: caret = 0
        case .end: caret = syllables.count
        }
        update()
    }

    /// Opens the candidate window on the words at the caret.
    @discardableResult public func convert() -> Bool {
        guard pending.isEmpty, !syllables.isEmpty else { return false }
        choices = words(at: caret)
        guard !choices.isEmpty else { return false }
        // The word shown there already, when it is among them.
        highlighted = choices.firstIndex { text(of: $0.range) == $0.text } ?? 0
        update()
        return true
    }

    public func cancelConversion() {
        closeChoices()
        update()
    }

    private func closeChoices() {
        choices = []
        highlighted = nil
    }

    public func moveFocus(forward: Bool) {}
    public func resizeFocus(by delta: Int) {}

    public func highlight(_ index: Int) {
        guard choices.indices.contains(index) else { return }
        highlighted = index
        update()
    }

    public func select(_ index: Int) -> SelectionResult {
        guard choices.indices.contains(index) else { return .continued }
        let choice = choices[index]
        fixed.removeAll { $0.range.overlaps(choice.range) }
        fixed.append(choice)
        fixed.sort { $0.range.lowerBound < $1.range.lowerBound }
        closeChoices()
        reconvert()
        update()
        return .continued
    }

    public func commitConverted() -> Commit? {
        if !pending.isEmpty { finishPending(.first) }
        guard !syllables.isEmpty else { return nil }
        if let highlighted, choices.indices.contains(highlighted) { _ = select(highlighted) }
        let commit = Commit(
            text: texts.joined(),
            reading: reading(of: syllables.indices),
            clauses: fixed.map { Commit.Clause(reading: reading(of: $0.range), text: $0.text) }
        )
        lastCommit = (commit.reading, fixed)
        clear()
        return commit
    }

    /// The syllables as written in Bopomofo, which teaches nothing.
    public func commitRaw() -> Commit? {
        guard !state.isEmpty else { return nil }
        let raw = syllables.map(\.text).joined() + pending.symbols
        clear()
        return Commit(text: raw, reading: raw)
    }

    public func clear() {
        session.clearComposition()
        syllables = []
        texts = []
        pending = Zhuyin.Syllable()
        caret = 0
        fixed = []
        closeChoices()
        state = .empty
    }

    /// Restores a reading written as codes (`ni3hao3`), with the choices
    /// it was committed with when it is the last commit.
    public func restore(reading: String) {
        clear()
        guard session.open(), let restored = Zhuyin.syllables(ofCodes: reading) else { return }
        syllables = restored
        texts = Array(repeating: "", count: restored.count)
        caret = restored.count
        if let lastCommit, lastCommit.reading == reading { fixed = lastCommit.fixed }
        reconvert()
        update()
    }

    public func setLeftContext(_ text: String) {}

    // MARK: Conversion

    private func reading(of range: some Sequence<Int>) -> String {
        range.compactMap { syllables[$0].code }.joined()
    }

    /// The codes librime reads for `range`, split where the syllables are.
    private func input(for range: Range<Int>) -> String {
        syllables[range].compactMap(\.code).joined(separator: "'")
    }

    private func text(of range: Range<Int>) -> String {
        texts[range].joined()
    }

    private func sentence(for input: String) -> String? {
        if let known = sentences[input] { return known }
        guard let sentence = session.sentence(for: input) else { return nil }
        if sentences.count >= 512 { sentences = [:] }
        sentences[input] = sentence
        return sentence
    }

    /// Converts every run of syllables between the chosen words.
    private func reconvert() {
        var start = 0
        for word in fixed + [Fixed(range: syllables.count..<syllables.count, text: "")] {
            if start < word.range.lowerBound { convertRun(start..<word.range.lowerBound) }
            place(word.text, in: word.range)
            start = word.range.upperBound
        }
    }

    private func convertRun(_ range: Range<Int>) {
        if let sentence = sentence(for: input(for: range)), sentence.count == range.count {
            place(sentence, in: range)
            return
        }
        // Text that does not split one character per syllable goes
        // syllable by syllable.
        for index in range {
            place(syllables[index].code.flatMap { sentence(for: $0) } ?? syllables[index].text, in: index..<(index + 1))
        }
    }

    private func place(_ text: String, in range: Range<Int>) {
        guard !range.isEmpty else { return }
        let characters = Array(text)
        if characters.count == range.count {
            for (offset, character) in characters.enumerated() { texts[range.lowerBound + offset] = String(character) }
        } else {
            texts[range.lowerBound] = text
            for index in range.dropFirst() { texts[index] = "" }
        }
    }

    /// Words of librime's dictionary and the user's that end at
    /// `position`, or start there at the start of the composition; the
    /// longest first.
    private func words(at position: Int) -> [Fixed] {
        var result: [Fixed] = []
        let longest = min(Self.longestChoice, position == 0 ? syllables.count : position)
        guard longest > 0 else { return [] }
        for length in stride(from: longest, through: 1, by: -1) {
            let range = position == 0 ? 0..<length : (position - length)..<position
            session.clearComposition()
            session.setInput(input(for: range))
            let found = session.candidates(limit: length == 1 ? Self.singleCharacterLimit : Self.wordLimit)
                .filter { $0.text.count == length && $0.text.allSatisfy(\.isHan) }
            // librime makes a sentence only where no word covers all the
            // syllables, and then offers it alone.
            if length > 1, found.count == 1, !isWord(found[0].text, at: range) { continue }
            result += found.map { Fixed(range: range, text: $0.text) }
        }
        session.clearComposition()
        return result
    }

    private func isWord(_ text: String, at range: Range<Int>) -> Bool {
        guard let wordCheck else { return true }
        let simplified = wordCheck.simplified()?.convert(text) ?? text
        return wordCheck.respeller.knows(simplified, readAs: syllables[range].compactMap(\.pinyin))
    }

    // MARK: State

    private func update() {
        guard !syllables.isEmpty || !pending.isEmpty else {
            state = .empty
            return
        }
        var segments: [CompositionSegment] = []
        func add(_ text: String, _ role: CompositionSegment.Role) {
            if !text.isEmpty { segments.append(CompositionSegment(text, role: role)) }
        }
        let shownCaret: Int
        var candidates: [Candidate] = []
        if let highlighted, choices.indices.contains(highlighted) {
            let choice = choices[highlighted]
            add(text(of: 0..<choice.range.lowerBound), .converted)
            add(choice.text, .focused)
            add(text(of: choice.range.upperBound..<syllables.count), .converted)
            shownCaret = text(of: 0..<choice.range.lowerBound).count + choice.text.count
            candidates = choices.enumerated().map { Candidate(text: $0.element.text, source: .engine(index: $0.offset)) }
        } else {
            let before = text(of: 0..<caret)
            add(before, .converted)
            add(pending.symbols, .input)
            add(text(of: caret..<syllables.count), .converted)
            shownCaret = before.count + pending.symbols.count
        }
        state = CompositionState(
            segments: segments,
            caret: shownCaret,
            candidates: candidates,
            highlightedIndex: highlighted,
            phase: highlighted == nil ? .composing : .converting,
            reading: reading(of: syllables.indices)
        )
    }
}
