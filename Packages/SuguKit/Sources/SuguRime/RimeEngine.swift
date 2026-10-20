import CRime
import SuguCore

/// Chinese composition on one librime session. librime owns the raw input,
/// caret, and partial selection; this type mirrors its context into
/// `CompositionState` after every change.
@MainActor
public final class RimeEngine: CompositionEngine {
    private let runtime: RimeRuntime
    private var session: RimeSessionId = 0
    private var script: ChineseScript
    /// How many candidates are read from librime per update; the rest are
    /// fetched only when the user pages past them.
    private var candidateLimit: Int

    public let traits = EngineTraits(hasConversionPhase: false, learnsCommits: true, takesSuguCandidates: true)
    public private(set) var state = CompositionState.empty

    public init(runtime: RimeRuntime, script: ChineseScript = .simplified, candidateLimit: Int = 30) {
        self.runtime = runtime
        self.script = script
        self.candidateLimit = candidateLimit
    }

    isolated deinit {
        // A session left open would also keep the user dictionary it read
        // open for sessions created later.
        if session != 0 { _ = api.destroy_session?(session) }
    }

    private var api: RimeApi { runtime.api }

    /// Creates the session lazily; librime drops sessions on redeploy.
    private func ensureSession() -> Bool {
        if session != 0, api.find_session?(session) ?? 0 != 0 { return true }
        guard let id = try? runtime.makeSession() else { return false }
        session = id
        applyScript()
        return true
    }

    /// Opens the librime session ahead of the first key.
    public func openSession() {
        _ = ensureSession()
    }

    /// Reopens the session so librime reads the user dictionary again,
    /// unless a composition is in progress; returns whether it reopened.
    /// librime shares one open dictionary among sessions and closes it
    /// with the last, so the old session goes before the new one opens.
    public func reloadUserDictionary() -> Bool {
        guard state.isEmpty else { return false }
        if session != 0 {
            _ = api.destroy_session?(session)
            session = 0
        }
        return ensureSession()
    }

    public func setScript(_ script: ChineseScript) {
        self.script = script
        if session != 0 { applyScript(); refresh() }
    }

    private func applyScript() {
        let active = RimeSchema.option(for: script)
        for filter in RimeSchema.scriptFilters {
            api.set_option?(session, filter.option, filter.option == active ? 1 : 0)
        }
    }

    // MARK: CompositionEngine

    public func accepts(_ character: Character) -> Bool {
        if character.isASCIILowercaseLetter { return true }
        return character == "'" && !state.isEmpty
    }

    public func insert(_ text: String) {
        guard ensureSession() else { return }
        for scalar in text.unicodeScalars where scalar.isASCII {
            _ = api.process_key?(session, Int32(scalar.value), 0)
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
        guard session != 0 else { return }
        ensureLoaded(upTo: index)
        _ = api.highlight_candidate?(session, index)
        refresh()
    }

    public func select(_ index: Int) -> SelectionResult {
        guard session != 0 else { return .continued }
        ensureLoaded(upTo: index)
        let reading = currentInput()
        _ = api.select_candidate?(session, index)
        if let text = takeCommit() {
            refresh()
            return .committed(Commit(text: text, reading: reading))
        }
        refresh()
        return .continued
    }

    public func commitConverted() -> Commit? {
        guard session != 0, !state.isEmpty else { return nil }
        let reading = currentInput()
        // Select the highlighted candidate of each remaining segment.
        var guardCount = 0
        while api.get_input?(session) != nil, !currentInput().isEmpty, guardCount < 64 {
            let index = state.highlightedIndex ?? 0
            _ = api.select_candidate?(session, index)
            if let text = takeCommit() {
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
        guard session != 0, !state.isEmpty else { return nil }
        let reading = currentInput()
        clear()
        return Commit(text: reading, reading: reading)
    }

    public func clear() {
        if session != 0 { api.clear_composition?(session) }
        state = .empty
    }

    public func restore(reading: String) {
        guard ensureSession() else { return }
        api.clear_composition?(session)
        _ = api.set_input?(session, reading)
        refresh()
    }

    public func setLeftContext(_ text: String) {}

    // MARK: Reading librime state

    private func send(_ keycode: Int32) {
        guard session != 0 else { return }
        _ = api.process_key?(session, keycode, 0)
        refresh()
    }

    private func currentInput() -> String {
        guard let input = api.get_input?(session) else { return "" }
        return String(cString: input)
    }

    private func takeCommit() -> String? {
        var commit = RimeCommit()
        commit.data_size = RimeAPI.dataSize(of: RimeCommit.self)
        guard api.get_commit?(session, &commit) ?? 0 != 0 else { return nil }
        defer { _ = api.free_commit?(&commit) }
        return commit.text.map { String(cString: $0) }
    }

    private func ensureLoaded(upTo index: Int) {
        if index >= candidateLimit - 1 {
            candidateLimit = max(candidateLimit * 2, index + 10)
        }
    }

    /// Mirrors librime's context into `state`.
    private func refresh() {
        guard session != 0 else { state = .empty; return }
        var context = RimeContext()
        context.data_size = RimeAPI.dataSize(of: RimeContext.self)
        guard api.get_context?(session, &context) ?? 0 != 0 else { state = .empty; return }
        defer { _ = api.free_context?(&context) }

        let composition = context.composition
        guard composition.length > 0, let preeditPointer = composition.preedit else {
            state = .empty
            return
        }
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

        state = CompositionState(
            segments: segments,
            caret: caret,
            candidates: readCandidates(),
            highlightedIndex: highlighted,
            phase: .composing,
            reading: currentInput()
        )
    }

    private func readCandidates() -> [Candidate] {
        var iterator = RimeCandidateListIterator()
        guard api.candidate_list_begin?(session, &iterator) ?? 0 != 0 else { return [] }
        defer { api.candidate_list_end?(&iterator) }
        var result: [Candidate] = []
        result.reserveCapacity(candidateLimit)
        while result.count < candidateLimit, api.candidate_list_next?(&iterator) ?? 0 != 0 {
            let candidate = iterator.candidate
            let text = candidate.text.map { String(cString: $0) } ?? ""
            let comment = candidate.comment.map { String(cString: $0) }
            result.append(Candidate(text: text, annotation: comment?.isEmpty == false ? comment : nil, source: .engine(index: Int(iterator.index))))
        }
        return result
    }
}
