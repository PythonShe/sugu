import Foundation
import FoundationModels
import os
import SuguCore

/// Sugu's language features on Apple's models (ADR 0004): the on-device
/// system model, or Private Cloud Compute when the user chose that level,
/// falling back to the on-device model. Every failure returns nothing.
@available(macOS 27.0, *)
@MainActor
final class AppleLanguageAssistant: LanguageAssistant {
    private let preferences: PreferencesStore
    private lazy var privateCloud = PrivateCloudComputeLanguageModel()

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    /// Whether a model for `level` can answer now.
    static func isReady(_ level: LanguageModelLevel) -> Bool {
        switch level {
        case .off: false
        case .onDevice: SystemLanguageModel.default.isAvailable
        case .privateCloudCompute: PrivateCloudComputeLanguageModel().isAvailable || SystemLanguageModel.default.isAvailable
        }
    }

    /// The models to try, in order, for the user's level.
    private var models: [any LanguageModel] {
        let system = SystemLanguageModel.default
        let local: [any LanguageModel] = system.isAvailable ? [system] : []
        switch preferences.preferences.languageModel {
        case .off:
            return []
        case .onDevice:
            return local
        case .privateCloudCompute:
            let cloud = privateCloud
            guard cloud.isAvailable, !cloud.quotaUsage.isLimitReached else { return local }
            return [cloud] + local
        }
    }

    // MARK: Compositions

    @Generable
    struct Suggestion {
        @Guide(description: "The most natural text for the reading, in the composition's language; empty when the input method's conversion is already right.")
        var conversion: String
        @Guide(description: "The conversion translated into Japanese; empty unless asked.")
        var japanese: String
        @Guide(description: "The conversion translated into Simplified Chinese; empty unless asked.")
        var chinese: String
        @Guide(description: "The conversion translated into English; empty unless asked.")
        var english: String
    }

    func suggestions(for request: CompositionRequest) async -> CompositionSuggestions {
        let language = request.mode == .japanese ? "Japanese" : "Chinese"
        let readingKind = request.mode == .japanese ? "hiragana" : "pinyin"
        var lines = [
            "Input method composition in \(language).",
            "Reading (\(readingKind)): \(request.reading)",
            "The input method's conversion: \(request.conversion)",
        ]
        if !request.context.isEmpty { lines.append("Text before the cursor: \(request.context)") }
        lines.append(request.convert
            ? "Give the most natural \(language) text for the reading, fitting the text before the cursor."
            : "Leave the conversion field empty.")
        let asked = request.translations.map(\.englishName)
        lines.append(asked.isEmpty
            ? "Leave the translation fields empty."
            : "Translate the conversion into: \(asked.joined(separator: ", ")). Leave other translation fields empty.")
        let instructions = "You help an input method. Answer only with the fields asked for, with no explanations or quotation marks."
        guard let suggestion = await respond(lines.joined(separator: "\n"), instructions: instructions, generating: Suggestion.self) else {
            return CompositionSuggestions()
        }
        var result = CompositionSuggestions()
        if request.convert, !suggestion.conversion.isEmpty { result.conversions = [suggestion.conversion] }
        for language in request.translations {
            let text = switch language {
            case .japanese: suggestion.japanese
            case .chinese: suggestion.chinese
            case .english: suggestion.english
            }
            if !text.isEmpty { result.translations[language] = text }
        }
        return result
    }

    // MARK: Selected text

    @Generable
    struct Alternatives {
        @Guide(description: "Results, best first.", .count(1...3))
        var texts: [String]
    }

    func perform(_ task: TextTask, on text: String) async -> [String] {
        let instructions = "You edit text for the user. Answer only with the resulting text, with no explanations or quotation marks."
        let request = switch task {
        case .translate(let language):
            "Translate the text into \(language.englishName)\(language == .chinese ? " (Simplified Chinese)" : "")."
        case .rewrite(.fixGrammar):
            "Fix the grammar, spelling and punctuation of the text, keeping its language, meaning and tone."
        case .rewrite(.formal):
            "Rewrite the text to be more formal, keeping its language and meaning."
        case .rewrite(.casual):
            "Rewrite the text to be more casual, keeping its language and meaning."
        case .rewrite(.shorter):
            "Rewrite the text to be shorter, keeping its language and meaning."
        }
        let prompt = "\(request)\n\nText:\n\(text)"
        return await respond(prompt, instructions: instructions, generating: Alternatives.self)?.texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    // MARK: Models

    /// The first model that answers; nil when none does.
    private func respond<Content: Generable>(_ prompt: String, instructions: String, generating type: Content.Type) async -> Content? {
        for model in models {
            let session = LanguageModelSession(model: model, instructions: instructions)
            do {
                return try await session.respond(to: prompt, generating: type).content
            } catch {
                // The description of a refusal can quote the prompt; log the kind only.
                Log.app.error("Language model request failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        return nil
    }
}

extension AssistLanguage {
    var englishName: String {
        switch self {
        case .chinese: "Chinese"
        case .japanese: "Japanese"
        case .english: "English"
        }
    }
}
