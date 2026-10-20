/// How far Sugu may use Apple's language models (ADR 0004).
public enum LanguageModelLevel: String, Codable, Sendable, CaseIterable {
    case off
    /// The on-device model only; nothing leaves the Mac.
    case onDevice
    /// Private Cloud Compute, falling back to the on-device model.
    case privateCloudCompute
}

/// A language a model result is written in.
public enum AssistLanguage: String, Codable, Sendable, CaseIterable {
    case chinese, japanese, english
}

/// What the Rewrite Selection command asks for.
public enum RewriteStyle: String, Codable, Sendable, CaseIterable {
    case fixGrammar, formal, casual, shorter
}

/// A command on selected text.
public enum TextTask: Sendable, Hashable {
    case translate(to: AssistLanguage)
    case rewrite(RewriteStyle)
}

/// What a composition suggestion request may carry off the keystroke path
/// (ADR 0004, decision 5).
public struct CompositionRequest: Sendable, Equatable {
    public var mode: InputMode
    /// The reading: hiragana for Japanese, full pinyin for Chinese.
    public var reading: String
    /// The engine's best conversion.
    public var conversion: String
    /// At most 40 characters before the caret.
    public var context: String
    /// Whether to propose a better conversion.
    public var convert: Bool
    /// Languages to translate the composition into.
    public var translations: [AssistLanguage]

    public static let contextLimit = 40

    public init(mode: InputMode, reading: String, conversion: String, context: String, convert: Bool, translations: [AssistLanguage]) {
        self.mode = mode
        self.reading = reading
        self.conversion = conversion
        self.context = String(context.suffix(Self.contextLimit))
        self.convert = convert
        self.translations = translations
    }
}

public struct CompositionSuggestions: Sendable, Equatable {
    public var conversions: [String]
    public var translations: [AssistLanguage: String]

    public init(conversions: [String] = [], translations: [AssistLanguage: String] = [:]) {
        self.conversions = conversions
        self.translations = translations
    }

    public var isEmpty: Bool { conversions.isEmpty && translations.isEmpty }
}

/// Apple's language models behind one seam, so the session never touches
/// FoundationModels. Implementations pick the model for the user's level
/// and return nothing on any failure.
@MainActor
public protocol LanguageAssistant: AnyObject {
    func suggestions(for request: CompositionRequest) async -> CompositionSuggestions
    func perform(_ task: TextTask, on text: String) async -> [String]
}
