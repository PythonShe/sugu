import CRime
import SuguCore

/// Chinese composition on one librime session. librime owns the raw input,
/// caret, and partial selection; this type mirrors its context into
/// `CompositionState` after every change.
@MainActor
public final class RimeEngine: CompositionEngine {
    private let session: RimeSession
    private var script: ChineseScript { session.script }
    /// How many candidates are read from librime per update; the rest are
    /// fetched only when the user pages past them.
    /// How many candidates are read from librime per change: the first
    /// pages, more as the highlight reaches the end, then the first pages
    /// again for the next input.
    private var candidateLimit: Int
    private let initialCandidateLimit: Int
    /// Respells librime's sentence where the language model reads it better.
    public var respelling: Respelling?
    /// librime's sentence respelled, shown ahead of librime's candidates;
    /// librime's own indices are one further down while it is.
    private var respelled: String?
    /// Whether the respelled sentence, rather than a librime candidate, is
    /// highlighted; typing highlights it again.
    private var respelledHighlighted = true
    private var leftContext = ""

    public struct Respelling {
        public var respeller: SentenceRespeller
        /// Reads typed keys as syllables in the schema's scheme.
        public var decoder: PinyinDecoder
        /// Converts text into a script, for sentences in scripts other than
        /// Simplified, which the model and word list are written in.
        public var converter: @MainActor (ChineseScript) -> ScriptConverter?

        public init(respeller: SentenceRespeller, decoder: PinyinDecoder, converter: @escaping @MainActor (ChineseScript) -> ScriptConverter?) {
            self.respeller = respeller
            self.decoder = decoder
            self.converter = converter
        }
    }

    public let traits = EngineTraits(composition: .live, learnsCommits: true, takesSuguCandidates: true)
    public private(set) var state = CompositionState.empty

    public init(runtime: RimeRuntime, script: ChineseScript = .simplified, candidateLimit: Int = 30) {
        session = RimeSession(runtime: runtime, script: script)
        self.candidateLimit = candidateLimit
        initialCandidateLimit = candidateLimit
    }

    /// Opens the librime session ahead of the first key.
    public func openSession() {
        _ = session.open()
    }

    /// Reopens the session so librime reads the user dictionary again,
    /// unless a composition is in progress; returns whether it reopened.
    /// librime shares one open dictionary among sessions and closes it
    /// with the last, so the old session goes before the new one opens.
    public func reloadUserDictionary() -> Bool {
        guard state.isEmpty else { return false }
        session.destroy()
        return session.open()
    }

    public func setScript(_ script: ChineseScript) {
        session.script = script
        if session.isOpen { refresh() }
    }

    // MARK: CompositionEngine

    public func accepts(_ character: Character) -> Bool {
        if character.isASCIILowercaseLetter { return true }
        return character == "'" && !state.isEmpty
    }

    public func insert(_ text: String) {
        guard session.open() else { return }
        respelledHighlighted = true
        candidateLimit = initialCandidateLimit
        for scalar in text.unicodeScalars where scalar.isASCII {
            session.processKey(Int32(scalar.value))
        }
        refresh()
    }

    public func deleteBackward() { send(RimeKey.backspace) }
    public func deleteForward() { send(RimeKey.delete) }

    public func moveCaret(_ motion: CaretMotion) {
        switch motion {
        case .left: send(RimeKey.left)
        case .right: send(RimeKey.right)
        case .start: send(RimeKey.home)
        case .end: send(RimeKey.end)
        }
    }

    /// Chinese candidates are live while typing; there is no separate
    /// conversion step.
    public func convert() -> Bool { !state.isEmpty }
    public func cancelConversion() {}
    public func moveFocus(forward: Bool) {}
    public func resizeFocus(by delta: Int) {}

    public func highlight(_ index: Int) {
        guard session.isOpen else { return }
        if respelled != nil {
            respelledHighlighted = index == 0
            if index == 0 { refresh(); return }
        }
        let index = librimeIndex(index)
        ensureLoaded(upTo: index)
        session.highlight(index)
        refresh()
    }

    public func select(_ index: Int) -> SelectionResult {
        guard session.isOpen else { return .continued }
        if index == 0, let commit = commitRespelled() { return .committed(commit) }
        let index = librimeIndex(index)
        ensureLoaded(upTo: index)
        let reading = session.input
        session.select(index)
        if let text = session.takeCommit() {
            refresh()
            return .committed(Commit(text: text, reading: reading))
        }
        refresh()
        return .continued
    }

    public func commitConverted() -> Commit? {
        guard session.isOpen, !state.isEmpty else { return nil }
        if respelledHighlighted, let commit = commitRespelled() { return commit }
        let reading = session.input
        // Select the highlighted candidate of each remaining segment.
        var guardCount = 0
        while !session.input.isEmpty, guardCount < 64 {
            let index = librimeIndex(state.highlightedIndex ?? 0)
            session.select(index)
            if let text = session.takeCommit() {
                refresh()
                return Commit(text: text, reading: reading)
            }
            refresh()
            guardCount += 1
        }
        refresh()
        return nil
    }

    public func commitRaw() -> Commit? {
        guard session.isOpen, !state.isEmpty else { return nil }
        let reading = session.input
        clear()
        return Commit(text: reading, reading: reading)
    }

    public func clear() {
        session.clearComposition()
        respelled = nil
        respelledHighlighted = true
        candidateLimit = initialCandidateLimit
        state = .empty
    }

    public func restore(reading: String) {
        guard session.open() else { return }
        respelledHighlighted = true
        session.clearComposition()
        session.setInput(reading)
        refresh()
    }

    public func setLeftContext(_ text: String) {
        leftContext = text
    }

    /// Commits the respelled sentence, which librime never proposed, so
    /// librime's composition is cleared rather than committed.
    private func commitRespelled() -> Commit? {
        guard let respelled else { return nil }
        let reading = session.input
        clear()
        return Commit(text: respelled, reading: reading)
    }

    /// librime's index for a shown index.
    private func librimeIndex(_ index: Int) -> Int {
        respelled == nil ? index : max(0, index - 1)
    }

    // MARK: Reading librime state

    private func send(_ keycode: Int32) {
        guard session.isOpen else { return }
        respelledHighlighted = true
        candidateLimit = initialCandidateLimit
        session.processKey(keycode)
        refresh()
    }

    private func ensureLoaded(upTo index: Int) {
        if index >= candidateLimit - 1 {
            candidateLimit = max(candidateLimit * 2, index + 10)
        }
    }

    /// Mirrors librime's context into `state`.
    private func refresh() {
        guard let mirrored = session.withContext({ context -> (segments: [CompositionSegment], caret: Int, highlighted: Int, confirmed: Bool)? in
            let composition = context.composition
            guard composition.length > 0, let preeditPointer = composition.preedit else { return nil }
            let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(preeditPointer).assumingMemoryBound(to: UInt8.self), count: Int(composition.length)))
            func text(_ range: Range<Int>) -> String {
                let clamped = max(0, min(range.lowerBound, bytes.count))..<max(0, min(range.upperBound, bytes.count))
                return String(decoding: bytes[clamped], as: UTF8.self)
            }
            let selStart = Int(composition.sel_start)
            let selEnd = Int(composition.sel_end)
            var segments: [CompositionSegment] = []
            let confirmed = text(0..<selStart)
            if !confirmed.isEmpty { segments.append(CompositionSegment(confirmed, role: .converted)) }
            let active = text(selStart..<max(selStart, selEnd))
            if !active.isEmpty { segments.append(CompositionSegment(active, role: .input)) }
            let rest = text(max(selStart, selEnd)..<bytes.count)
            if !rest.isEmpty { segments.append(CompositionSegment(rest, role: .input)) }
            let caret = text(0..<Int(composition.cursor_pos)).count
            let menu = context.menu
            let highlighted = Int(menu.page_no) * Int(menu.page_size) + Int(menu.highlighted_candidate_index)
            return (segments, caret, highlighted, !confirmed.isEmpty)
        }), let mirrored else {
            state = .empty
            return
        }
        var highlighted = mirrored.highlighted
        var candidates = session.candidates(limit: candidateLimit)
        respelled = mirrored.confirmed ? nil : candidates.first.flatMap { respell($0.text) }
        if let respelled {
            candidates = [Candidate(text: respelled, source: .engine(index: 0))] + candidates.map {
                Candidate(text: $0.text, annotation: $0.annotation, source: .engine(index: ($0.engineIndex ?? 0) + 1))
            }
            highlighted = respelledHighlighted ? 0 : highlighted + 1
        }

        state = CompositionState(
            segments: mirrored.segments,
            caret: mirrored.caret,
            candidates: candidates,
            highlightedIndex: highlighted,
            phase: .composing,
            reading: session.input
        )
    }

    /// librime's sentence for the whole input respelled, when the language
    /// model reads another spelling as clearly better. The model and word
    /// list are Simplified: a sentence in another script is respelled in
    /// Simplified, and only the characters that changed are converted back,
    /// so the rest keeps librime's forms.
    private func respell(_ sentence: String) -> String? {
        guard let respelling else { return nil }
        // Readings that type all the input as one syllable per character;
        // none when the candidate covers only part of it. Fuzzy pinyin can
        // mean that librime read a derived spelling (zong for zhong), so
        // those follow the readings as typed.
        let readings = respelling.decoder.syllables(typedAs: session.input, count: sentence.count, limit: 16, fewestDerivedOnly: false)
        guard !readings.isEmpty else { return nil }
        let context = String(leftContext.suffix(respelling.respeller.contextLength))
        guard script != .simplified else {
            return respelling.respeller.respelled(sentence, readings: readings, after: context)
        }
        guard let toSimplified = respelling.converter(.simplified), let toScript = respelling.converter(script) else { return nil }
        let simplified = toSimplified.convert(sentence)
        guard let respelled = respelling.respeller.respelled(simplified, readings: readings, after: toSimplified.convert(context)) else { return nil }
        let original = Array(sentence), before = Array(simplified), after = Array(respelled), converted = Array(toScript.convert(respelled))
        guard Set([original.count, before.count, after.count, converted.count]).count == 1 else { return nil }
        let result = String(original.indices.map { after[$0] == before[$0] ? original[$0] : converted[$0] })
        return result == sentence ? nil : result
    }
}
