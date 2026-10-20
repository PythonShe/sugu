import CRime
import SuguCore

/// One librime session with the script Sugu shows, made when first needed
/// and made again after a redeployment, which drops librime's sessions.
@MainActor
final class RimeSession {
    private let runtime: RimeRuntime
    private var id: RimeSessionId = 0
    var script: ChineseScript {
        didSet { if id != 0 { applyScript() } }
    }

    init(runtime: RimeRuntime, script: ChineseScript) {
        self.runtime = runtime
        self.script = script
    }

    isolated deinit {
        // A session left open would also keep the user dictionary it read
        // open for sessions created later.
        destroy()
    }

    private var api: RimeApi { runtime.api }

    var isOpen: Bool { id != 0 }

    /// Opens the session unless it is open; false when librime cannot.
    func open() -> Bool {
        if id != 0, api.find_session?(id) ?? 0 != 0 { return true }
        guard let made = try? runtime.makeSession() else { return false }
        id = made
        applyScript()
        return true
    }

    /// Closes the session; librime shares one open user dictionary among
    /// sessions and closes it with the last.
    func destroy() {
        guard id != 0 else { return }
        _ = api.destroy_session?(id)
        id = 0
    }

    private func applyScript() {
        let active = RimeSchema.option(for: script)
        for filter in RimeSchema.scriptFilters {
            api.set_option?(id, filter.option, filter.option == active ? 1 : 0)
        }
    }

    // MARK: Composition

    var input: String {
        guard id != 0, let input = api.get_input?(id) else { return "" }
        return String(cString: input)
    }

    func setInput(_ text: String) {
        guard id != 0 else { return }
        _ = api.set_input?(id, text)
    }

    func processKey(_ keycode: Int32) {
        guard id != 0 else { return }
        _ = api.process_key?(id, keycode, 0)
    }

    func clearComposition() {
        guard id != 0 else { return }
        api.clear_composition?(id)
    }

    func highlight(_ index: Int) {
        guard id != 0 else { return }
        _ = api.highlight_candidate?(id, index)
    }

    func select(_ index: Int) {
        guard id != 0 else { return }
        _ = api.select_candidate?(id, index)
    }

    /// The text librime committed since the last call, if any.
    func takeCommit() -> String? {
        guard id != 0 else { return nil }
        var commit = RimeCommit()
        commit.data_size = RimeAPI.dataSize(of: RimeCommit.self)
        guard api.get_commit?(id, &commit) ?? 0 != 0 else { return nil }
        defer { _ = api.free_commit?(&commit) }
        return commit.text.map { String(cString: $0) }
    }

    /// Reads librime's context while it is valid.
    func withContext<T>(_ body: (RimeContext) -> T) -> T? {
        guard id != 0 else { return nil }
        var context = RimeContext()
        context.data_size = RimeAPI.dataSize(of: RimeContext.self)
        guard api.get_context?(id, &context) ?? 0 != 0 else { return nil }
        defer { _ = api.free_context?(&context) }
        return body(context)
    }

    /// The first `limit` candidates of the current menu, with librime's
    /// comments as annotations.
    func candidates(limit: Int) -> [Candidate] {
        guard id != 0 else { return [] }
        var iterator = RimeCandidateListIterator()
        guard api.candidate_list_begin?(id, &iterator) ?? 0 != 0 else { return [] }
        defer { api.candidate_list_end?(&iterator) }
        var result: [Candidate] = []
        result.reserveCapacity(limit)
        while result.count < limit, api.candidate_list_next?(&iterator) ?? 0 != 0 {
            let candidate = iterator.candidate
            let text = candidate.text.map { String(cString: $0) } ?? ""
            let comment = candidate.comment.map { String(cString: $0) }
            result.append(Candidate(text: text, annotation: comment?.isEmpty == false ? comment : nil, source: .engine(index: Int(iterator.index))))
        }
        return result
    }

    /// The sentence librime makes of `input`, choosing its first candidate
    /// until all of the input is chosen; nil when it chooses none.
    func sentence(for input: String) -> String? {
        guard open() else { return nil }
        clearComposition()
        setInput(input)
        defer { clearComposition() }
        for _ in 0..<64 {
            guard !self.input.isEmpty else { break }
            select(0)
            if let text = takeCommit() { return text }
        }
        return takeCommit()
    }
}

/// A Chinese engine on librime, as the engine hub keeps it.
@MainActor
public protocol ChineseEngine: CompositionEngine {
    /// Opens the librime session ahead of the first key.
    func openSession()
    /// Reopens the session so librime reads the user dictionary again,
    /// unless a composition is in progress; returns whether it reopened.
    func reloadUserDictionary() -> Bool
    func setScript(_ script: ChineseScript)
}

extension RimeEngine: ChineseEngine {}
extension ZhuyinEngine: ChineseEngine {}
