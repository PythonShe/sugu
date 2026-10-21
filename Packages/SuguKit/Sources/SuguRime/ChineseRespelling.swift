import SuguCore

/// Sugu's word list, the user's words and the language model, which tell
/// words from librime's sentences and respell them (ADR 0005). They are in
/// Simplified: a sentence in another script is respelled in Simplified,
/// and only the characters that changed are converted back, so the rest
/// keeps librime's forms.
public struct ChineseRespelling {
    public var respeller: SentenceRespeller
    /// Reads typed pinyin keys as syllables in the schema's scheme; nil
    /// for Zhuyin, whose syllables are known as they are typed, or while
    /// the schema in use has no decoder yet.
    public var decoder: PinyinDecoder?
    /// Converts text into a script.
    public var converter: @MainActor (ChineseScript) -> ScriptConverter?

    public init(respeller: SentenceRespeller, decoder: PinyinDecoder? = nil, converter: @escaping @MainActor (ChineseScript) -> ScriptConverter?) {
        self.respeller = respeller
        self.decoder = decoder
        self.converter = converter
    }

    /// `sentence` in `script` respelled where the model reads it as
    /// clearly better after `context`; nil when nothing changes.
    @MainActor
    func respelled(_ sentence: String, readings: [[String]], after context: String, script: ChineseScript) -> String? {
        let result: String?
        if script == .simplified {
            // Read in Simplified even where a character in another script
            // reached the sentence, which then leaves in Simplified too.
            let toSimplified = converter(.simplified)
            let simplified = toSimplified?.convert(sentence) ?? sentence
            result = respeller.respelled(simplified, readings: readings, after: toSimplified?.convert(context) ?? context) ?? simplified
        } else {
            guard let toSimplified = converter(.simplified), let toScript = converter(script) else { return nil }
            let simplified = toSimplified.convert(sentence)
            guard let respelled = respeller.respelled(simplified, readings: readings, after: toSimplified.convert(context)) else { return nil }
            let original = Array(sentence), before = Array(simplified), after = Array(respelled), converted = Array(toScript.convert(respelled))
            guard Set([original.count, before.count, after.count, converted.count]).count == 1 else { return nil }
            result = String(original.indices.map { after[$0] == before[$0] ? original[$0] : converted[$0] })
        }
        return result == sentence ? nil : result
    }

    /// Whether `text`, in any script, is a known word read as `syllables`.
    @MainActor
    func knows(_ text: String, readAs syllables: [String]) -> Bool {
        respeller.knows(converter(.simplified)?.convert(text) ?? text, readAs: syllables)
    }
}
