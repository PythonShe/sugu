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
    /// Text typed as is, by position, where `syllables` has an empty
    /// syllable: punctuation and Latin letters stay in the sentence and
    /// split it into runs librime converts apart.
    private var literals: [String?] = []
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
    /// The last commit's choices and literals, for a commit taken back.
    private var lastCommit: (reading: String, syllables: [Zhuyin.Syllable], literals: [String?], fixed: [Fixed])?
    /// The start of a sentence grown past `longestSentence`, let go of.
    private var overflow: Commit?

    /// Sugu's word list, the user's words and the language model, in
    /// Simplified, their script: they tell words from librime's sentences,
    /// which librime makes for any syllables no word covers, and respell
    /// librime's sentence as for pinyin (ADR 0005), where the characters
    /// that change are librime's under their tones.
    public struct Respelling {
        public var respeller: SentenceRespeller
        /// Converts text into a script.
        public var converter: @MainActor (ChineseScript) -> ScriptConverter?

        public init(respeller: SentenceRespeller, converter: @escaping @MainActor (ChineseScript) -> ScriptConverter?) {
            self.respeller = respeller
            self.converter = converter
        }
    }

    public var respelling: Respelling? {
        didSet { respelled = [:] }
    }
    /// Respelled sentences by input and the text before them.
    private var respelled: [String: String] = [:]
    private var leftContext = ""

    private struct Fixed: Equatable {
        var range: Range<Int>
        var text: String
    }

    /// Longest word offered at the caret, in syllables.
    private static let longestChoice = 6
    /// Syllables a sentence holds before its start is committed, as in
    /// McBopomofo; librime reconverts all of an unchosen run on each one.
    static let longestSentence = 20
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
        // Chosen words are in the old script; librime chooses afresh.
        fixed = []
        lastCommit = nil
        guard !syllables.isEmpty else { return }
        reconvert()
        update()
    }

    // MARK: CompositionEngine

    /// Symbols, and tones: one ends the pending syllable or, with none,
    /// changes the tone of the syllable before the caret (Space, the first
    /// tone, opens the candidate window there instead).
    public func accepts(_ character: Character) -> Bool {
        if Zhuyin.keyboard[character] != nil { return true }
        guard Zhuyin.toneKeys[character] != nil else { return false }
        return !pending.isEmpty || (character != " " && caret > 0)
    }

    public func insert(_ text: String) {
        guard session.open() else { return }
        closeChoices()
        for character in text {
            if let symbol = Zhuyin.keyboard[character] {
                pending.type(symbol)
            } else if let tone = Zhuyin.toneKeys[character] {
                if !pending.isEmpty { finishPending(tone) } else if character != " ", caret > 0 { retone(caret - 1, tone) }
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
        pending = Zhuyin.Syllable()
        add(syllable, literal: nil)
    }

    /// Ends the pending syllable with the first tone, then keeps `text`;
    /// false when the pending syllable cannot end.
    public func insertLiteral(_ text: String) -> Bool {
        guard !text.isEmpty, session.open() else { return false }
        closeChoices()
        if !pending.isEmpty { finishPending(.first) }
        guard pending.isEmpty else { return false }
        add(Zhuyin.Syllable(), literal: text)
        update()
        return true
    }

    private func add(_ syllable: Zhuyin.Syllable, literal: String?) {
        // Typing inside a chosen word undoes the choice.
        fixed.removeAll { $0.range.lowerBound < caret && caret < $0.range.upperBound }
        fixed = fixed.map { $0.range.lowerBound >= caret ? Fixed(range: ($0.range.lowerBound + 1)..<($0.range.upperBound + 1), text: $0.text) : $0 }
        syllables.insert(syllable, at: caret)
        literals.insert(literal, at: caret)
        texts.insert(literal ?? "", at: caret)
        caret += 1
        reconvert()
        letGoOfStart()
    }

    /// Gives the syllable at `index` another tone when librime knows it.
    private func retone(_ index: Int, _ tone: Zhuyin.Tone) {
        guard literals[index] == nil else { return }
        var syllable = syllables[index]
        guard syllable.tone != tone else { return }
        syllable.tone = tone
        guard let code = syllable.code, sentence(for: code) != nil else { return }
        syllables[index] = syllable
        fixed.removeAll { $0.range.contains(index) }
        reconvert()
    }

    /// Commits the start of a sentence past `longestSentence` syllables,
    /// not splitting a chosen word, while the caret is past it.
    private func letGoOfStart() {
        guard syllables.count > Self.longestSentence else { return }
        var cut = syllables.count - Self.longestSentence
        if let word = fixed.first(where: { $0.range.lowerBound < cut && cut < $0.range.upperBound }) { cut = word.range.upperBound }
        guard cut <= caret else { return }
        let head = 0..<cut
        // librime's guess, not yet the user's; only chosen words teach.
        var commit = self.commit(of: head)
        commit.mayBeWord = false
        overflow = overflow.map { Commit(text: $0.text + commit.text, reading: $0.reading + commit.reading, clauses: $0.clauses + commit.clauses, mayBeWord: false) } ?? commit
        leftContext += commit.text
        syllables.removeSubrange(head)
        literals.removeSubrange(head)
        texts.removeSubrange(head)
        caret -= cut
        fixed = fixed.filter { $0.range.lowerBound >= cut }.map { Fixed(range: ($0.range.lowerBound - cut)..<($0.range.upperBound - cut), text: $0.text) }
        reconvert()
    }

    public func clearPending() -> Bool {
        guard !pending.isEmpty else { return false }
        pending = Zhuyin.Syllable()
        update()
        return true
    }

    public func takeOverflow() -> Commit? {
        defer { overflow = nil }
        return overflow
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
        literals.remove(at: index)
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
        // Symbols that end no syllable go as written, and the commit
        // teaches nothing.
        if !pending.isEmpty {
            let text = texts.joined() + pending.symbols
            clear()
            return Commit(text: text, reading: text)
        }
        var commit = commit(of: syllables.indices)
        lastCommit = (commit.reading, syllables, literals, fixed)
        // Ending the pending syllable may have let go of the start.
        if let head = takeOverflow() {
            commit = Commit(text: head.text + commit.text, reading: head.reading + commit.reading, clauses: head.clauses + commit.clauses, mayBeWord: false)
            lastCommit = nil
        }
        clear()
        return commit
    }

    /// The text of `range`, read as its codes with its literals as typed,
    /// teaching the words chosen in it; the whole only without literals.
    private func commit(of range: Range<Int>) -> Commit {
        Commit(
            text: text(of: range),
            reading: reading(of: range),
            clauses: fixed.filter { $0.range.upperBound <= range.upperBound && $0.range.lowerBound >= range.lowerBound }
                .map { Commit.Clause(reading: reading(of: $0.range), text: $0.text) },
            mayBeWord: literals[range].allSatisfy { $0 == nil }
        )
    }

    /// The syllables as written in Bopomofo, which teaches nothing.
    public func commitRaw() -> Commit? {
        guard !state.isEmpty else { return nil }
        let raw = syllables.indices.map { literals[$0] ?? syllables[$0].text }.joined() + pending.symbols
        clear()
        return Commit(text: raw, reading: raw)
    }

    public func clear() {
        session.clearComposition()
        overflow = nil
        syllables = []
        literals = []
        texts = []
        pending = Zhuyin.Syllable()
        caret = 0
        fixed = []
        closeChoices()
        state = .empty
    }

    /// Restores a reading written as codes (`ni3hao3`), any literals as
    /// typed, with the choices it was committed with when it is the last
    /// commit.
    public func restore(reading: String) {
        clear()
        guard session.open() else { return }
        if let lastCommit, lastCommit.reading == reading {
            (syllables, literals, fixed) = (lastCommit.syllables, lastCommit.literals, lastCommit.fixed)
        } else {
            guard let restored = Zhuyin.syllables(ofCodes: reading) else { return }
            syllables = restored
            literals = Array(repeating: nil, count: restored.count)
        }
        texts = Array(repeating: "", count: syllables.count)
        caret = syllables.count
        reconvert()
        update()
    }

    public func setLeftContext(_ text: String) {
        leftContext = text
    }

    /// Codes that type `text`, read as toneless `syllables`, one per
    /// character, with the tones librime has for its words: a word of two
    /// or three characters takes the tones under which librime offers it
    /// whole, its later characters perhaps in the neutral tone (谢谢 xie4
    /// xie5); any other character the tone under which librime ranks it
    /// highest. Nil when a character is under none, or while composing.
    public func codes(typing text: String, readAs syllables: [String]) -> String? {
        let characters = Array(text).map(String.init)
        guard state.isEmpty, characters.count == syllables.count, session.open() else { return nil }
        defer { session.clearComposition() }
        /// Where librime offers `text` for `codes`, and whether it is
        /// surely a word under those tones: librime's sentence comes
        /// alone at its length, so two or more there are all words.
        func rank(of text: String, typedAs codes: [String]) -> (rank: Int, sure: Bool)? {
            session.clearComposition()
            session.setInput(codes.joined(separator: "'"))
            let candidates = session.candidates(limit: codes.count == 1 ? Self.singleCharacterLimit : Self.wordLimit)
            guard let rank = candidates.firstIndex(where: { $0.text == text }) else { return nil }
            let sure = codes.count == 1 || candidates.filter { $0.text.count == codes.count }.count > 1
            if !sure, !isWord(text, readAs: toneless(codes)) { return nil }
            return (rank, sure)
        }
        func toneless(_ codes: [String]) -> [String] {
            codes.compactMap { Zhuyin.syllables(ofCodes: $0)?.first?.pinyin }
        }
        // Each character's tones, the likeliest first.
        var tones: [[String]] = []
        for (character, syllable) in zip(characters, syllables) {
            let ranked = Zhuyin.Tone.allCases.compactMap { tone -> (code: String, rank: Int)? in
                let code = syllable + String(tone.rawValue)
                guard Zhuyin.syllables(ofCodes: code) != nil, let found = rank(of: character, typedAs: [code]) else { return nil }
                return (code, found.rank)
            }.sorted { ($0.rank, $0.code.hasSuffix("5") ? 1 : 0, $0.code) < ($1.rank, $1.code.hasSuffix("5") ? 1 : 0, $1.code) }
            guard !ranked.isEmpty else { return nil }
            tones.append(ranked.map(\.code))
        }
        var codes: [String] = []
        var index = 0
        while index < characters.count {
            var best: (codes: [String], score: [Int])?
            for length in [3, 2] where index + length <= characters.count {
                let range = index..<(index + length)
                // The two likeliest tones of each, and the neutral after the first.
                var options: [[String]] = [[]]
                for position in range {
                    var choices = Array(tones[position].prefix(2))
                    let neutral = syllables[position] + String(Zhuyin.Tone.neutral.rawValue)
                    if position > index, !choices.contains(neutral), Zhuyin.syllables(ofCodes: neutral) != nil { choices.append(neutral) }
                    options = options.flatMap { prefix in choices.map { prefix + [$0] } }
                }
                let word = characters[range].joined()
                // A sure word first, then librime's rank, then fewer neutral tones.
                for option in options {
                    guard let found = rank(of: word, typedAs: option) else { continue }
                    let score = [found.sure ? 0 : 1, found.rank, option.filter { $0.hasSuffix("5") }.count]
                    if let best, best.score.lexicographicallyPrecedes(score) || best.score == score { continue }
                    best = (option, score)
                }
                if best != nil { break }
            }
            if let best {
                codes += best.codes
                index += best.codes.count
            } else {
                codes.append(tones[index][0])
                index += 1
            }
        }
        return codes.joined()
    }

    // MARK: Conversion

    private func reading(of range: some Sequence<Int>) -> String {
        range.compactMap { literals[$0] ?? syllables[$0].code }.joined()
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

    /// Converts every run of syllables between the chosen words and the
    /// literals.
    private func reconvert() {
        var start = 0
        let literalSpans = literals.indices.compactMap { index in literals[index].map { Fixed(range: index..<(index + 1), text: $0) } }
        let spans = (fixed + literalSpans).sorted { $0.range.lowerBound < $1.range.lowerBound }
        for span in spans + [Fixed(range: syllables.count..<syllables.count, text: "")] {
            if start < span.range.lowerBound { convertRun(start..<span.range.lowerBound) }
            place(span.text, in: span.range)
            start = span.range.upperBound
        }
    }

    private func convertRun(_ range: Range<Int>) {
        if let sentence = sentence(for: input(for: range)), sentence.count == range.count {
            place(respell(sentence, at: range) ?? sentence, in: range)
            return
        }
        // Text that does not split one character per syllable goes
        // syllable by syllable.
        for index in range {
            place(syllables[index].code.flatMap { sentence(for: $0) } ?? syllables[index].text, in: index..<(index + 1))
        }
    }

    /// librime's sentence for `range` respelled where the model reads
    /// another spelling of its toneless syllables as clearly better and
    /// every character it changes is librime's under its tone. A sentence
    /// in another script is respelled in Simplified, and only the
    /// characters that changed are converted back.
    private func respell(_ sentence: String, at range: Range<Int>) -> String? {
        guard let respelling, range.count > 1 else { return nil }
        let before = leftContext + text(of: 0..<range.lowerBound)
        let context = String(before.suffix(respelling.respeller.contextLength))
        let key = input(for: range) + "\t" + context
        if let known = respelled[key] { return known.isEmpty ? nil : known }
        let result = respelled(sentence, context: context, readings: syllables[range].compactMap(\.pinyin), respelling: respelling)
            .flatMap { candidate -> String? in
                let new = Array(candidate), old = Array(sentence)
                guard new.count == old.count else { return nil }
                return new.indices.allSatisfy { new[$0] == old[$0] || types(new[$0], as: syllables[range.lowerBound + $0]) } ? candidate : nil
            }
        if respelled.count >= 512 { respelled = [:] }
        respelled[key] = result ?? ""
        return result
    }

    private func respelled(_ sentence: String, context: String, readings: [String], respelling: Respelling) -> String? {
        let script = session.script
        guard script != .simplified else { return respelling.respeller.respelled(sentence, readings: [readings], after: context) }
        guard let toSimplified = respelling.converter(.simplified), let toScript = respelling.converter(script) else { return nil }
        let simplified = toSimplified.convert(sentence)
        guard let respelled = respelling.respeller.respelled(simplified, readings: [readings], after: toSimplified.convert(context)) else { return nil }
        let original = Array(sentence), before = Array(simplified), after = Array(respelled), converted = Array(toScript.convert(respelled))
        guard Set([original.count, before.count, after.count, converted.count]).count == 1 else { return nil }
        let result = String(original.indices.map { after[$0] == before[$0] ? original[$0] : converted[$0] })
        return result == sentence ? nil : result
    }

    /// Whether librime offers `character` for `syllable` with its tone.
    private func types(_ character: Character, as syllable: Zhuyin.Syllable) -> Bool {
        guard let code = syllable.code else { return false }
        session.clearComposition()
        session.setInput(code)
        defer { session.clearComposition() }
        return session.candidates(limit: Self.singleCharacterLimit).contains { $0.text == String(character) }
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
        // Words stop at literals.
        let reach = position == 0
            ? (literals.firstIndex { $0 != nil } ?? syllables.count)
            : position - ((literals[..<position].lastIndex { $0 != nil }).map { $0 + 1 } ?? 0)
        let longest = min(Self.longestChoice, reach)
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
        isWord(text, readAs: syllables[range].compactMap(\.pinyin))
    }

    private func isWord(_ text: String, readAs syllables: [String]) -> Bool {
        guard let respelling else { return true }
        let simplified = respelling.converter(.simplified)?.convert(text) ?? text
        return respelling.respeller.knows(simplified, readAs: syllables)
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
