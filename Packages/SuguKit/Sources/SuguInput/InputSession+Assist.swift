import Foundation
import SuguCore

/// Apple's language models in the session (ADR 0004): commands on selected
/// text, and suggestions for long compositions. Never on the keystroke
/// path: requests run after the key is handled, and their results are
/// dropped when the composition moved on.
extension InputSession {
    static let revisionLimit = 2_000
    static let suggestionMinimumReading = 8
    static let suggestionPause: Duration = .milliseconds(450)

    var modelEnabled: Bool { assistant != nil && preferences.languageModel != .off }

    /// Whether the model may see this field at all: never in secure input
    /// or in apps excluded from learning.
    private var modelMaySeeField: Bool {
        !isSecureInput && preferences.learns(in: client?.bundleIdentifier)
    }

    // MARK: Selected text

    /// Whether Translate and Rewrite Selection can run here now.
    public var canReviseSelection: Bool {
        modelEnabled && preferences.modelForSelection && isEmpty && canReadField && modelMaySeeField
    }

    /// Translates or rewrites the selection. The selection becomes a
    /// composition of itself; results join its candidates when they arrive.
    public func revise(selectionWith task: TextTask) {
        guard canReviseSelection, let assistant, let selected = client?.selectedText(),
              !selected.isEmpty, selected.count <= Self.revisionLimit else { return }
        let engine = RevisionEngine(original: selected, task: task)
        active = engine
        refresh()
        Task { [weak self] in
            let results = await assistant.perform(task, on: selected)
            guard let self, self.active === engine else { return }
            engine.show(results)
            self.refreshKeepingHighlight()
        }
    }

    /// Esc, and the app rule that turns Esc into English: a revised
    /// selection goes back as it was; a composition is dropped.
    func abandonComposition() {
        if let engine = active, engine.traits.revisesText {
            commit(engine.commitRaw())
        } else {
            cancelComposition()
        }
    }

    // MARK: Composition suggestions

    /// Asks for suggestions for the composition after a pause, once per
    /// reading.
    func scheduleSuggestions() {
        guard let request = suggestionRequest() else {
            cancelSuggestionRequest()
            return
        }
        guard suggestions?.reading != request.reading, pendingSuggestion != request.reading else { return }
        suggestionTask?.cancel()
        pendingSuggestion = request.reading
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: Self.suggestionPause)
            // Asked again after the pause: the field, the settings and the
            // composition may all have changed.
            guard !Task.isCancelled, let self, let assistant, suggestionRequest() == request else { return }
            let result = await assistant.suggestions(for: request)
            guard !Task.isCancelled else { return }
            pendingSuggestion = nil
            guard active?.state.reading == request.reading, !result.isEmpty else { return }
            suggestions = (request.reading, request.translations, result)
            refreshKeepingHighlight()
        }
    }

    private func cancelSuggestionRequest() {
        suggestionTask?.cancel()
        suggestionTask = nil
        pendingSuggestion = nil
    }

    /// Drops requests and results when the composition ends, the field
    /// changes or the settings do; a result belongs to its context.
    func endSuggestions() {
        cancelSuggestionRequest()
        suggestions = nil
    }

    private func suggestionRequest() -> CompositionRequest? {
        guard modelEnabled, preferences.modelForConversion || preferences.modelForTranslation, mode != .english,
              modelMaySeeField, let engine = active, engine.traits.takesSuguCandidates, transformed == nil else { return nil }
        let state = engine.state
        guard !state.isEmpty, state.reading.count >= Self.suggestionMinimumReading else { return nil }
        let conversion = state.phase == .converting
            ? state.segments.map(\.text).joined()
            : state.candidates.first?.text ?? state.reading
        // Pinyin typed in a double-pinyin scheme is no reading a model knows.
        let readable = mode == .japanese || preferences.pinyinScheme == .fullPinyin
        var translations: [AssistLanguage] = []
        if preferences.modelForTranslation {
            if mode == .chinese, preferences.enabledModes.contains(.japanese) { translations.append(.japanese) }
            if mode == .japanese, preferences.enabledModes.contains(.chinese) { translations.append(.chinese) }
            translations.append(.english)
        }
        // The on-device model's conversions were worse than the engines'
        // (D-081); conversions come from Private Cloud Compute only.
        let convert = preferences.modelForConversion && readable && preferences.languageModel == .privateCloudCompute
        guard convert || !translations.isEmpty else { return nil }
        return CompositionRequest(
            mode: mode, reading: state.reading, conversion: conversion,
            context: preferences.leftContextRanking ? context : "",
            convert: convert, translations: translations
        )
    }

    /// The model's candidates for this reading, placed after the engine's
    /// best (ADR 0004, decision 4), without repeating what is listed.
    func mergingSuggestions(into candidates: [Candidate], reading: String) -> [Candidate] {
        guard let suggestions, suggestions.reading == reading, !candidates.isEmpty, modelEnabled, modelMaySeeField else { return candidates }
        var seen = Set(candidates.map(\.text))
        var added: [Candidate] = []
        func add(_ text: String, learns: Bool) {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted else { return }
            added.append(Candidate(text: text, source: .model(learns: learns)))
        }
        for text in suggestions.result.conversions {
            add(mode == .chinese ? engines.chineseText(text) ?? text : text, learns: true)
        }
        for language in suggestions.languages {
            guard let text = suggestions.result.translations[language] else { continue }
            add(language == .chinese ? engines.chineseText(text) ?? text : text, learns: false)
        }
        var merged = candidates
        merged.insert(contentsOf: added, at: 1)
        return merged
    }

    /// Rebuilds the list where the highlight stays on the same candidate.
    private func refreshKeepingHighlight() {
        let highlighted = list.highlighted?.text
        refresh()
        if let highlighted, let index = list.candidates.firstIndex(where: { $0.text == highlighted }), index != list.highlight {
            list.setHighlight(index)
            publish()
        }
    }
}
