import SuguCore

extension InputSession {
    // MARK: Document context

    /// The one gate for reading the field: never in secure input or in apps
    /// excluded from learning and context.
    var canReadField: Bool {
        !isSecureInput && preferences.readsContext(in: client?.bundleIdentifier)
    }

    static let contextLimit = 200
    static let vocabularyLimit = 2_000

    func readContext() -> String {
        guard preferences.leftContextRanking, canReadField else { return "" }
        return client?.textBeforeCaret(limit: Self.contextLimit) ?? ""
    }

    /// Text on both sides of the caret, read once when the field gains
    /// focus rather than on the keystroke path.
    func readVocabulary() -> String {
        guard preferences.leftContextRanking, preferences.documentVocabulary, canReadField, let client else { return "" }
        let before = client.textBeforeCaret(limit: Self.vocabularyLimit) ?? ""
        let after = client.textAfterCaret(limit: Self.vocabularyLimit) ?? ""
        return before + "\n" + after
    }

    func lastCharacterBeforeCaret() -> Character? {
        canReadField ? client?.textBeforeCaret(limit: 1)?.last : nil
    }
}
