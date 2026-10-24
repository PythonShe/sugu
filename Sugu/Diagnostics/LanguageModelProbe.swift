import Foundation
import FoundationModels
import SuguCore

/// Checks Apple's language models offscreen, at each level, with fixed
/// sample text — nothing typed by anyone is sent, and no settings or stores
/// are touched. Private Cloud Compute is asked only by a build entitled to
/// it (ADR 0004):
///   Sugu.app/Contents/MacOS/Sugu --probe-language-model
@MainActor
enum LanguageModelProbe {
    static func run() async -> Bool {
        guard #available(macOS 27.0, *) else {
            print("Language models need macOS 27.")
            return false
        }
        print("On this Mac: \(SystemLanguageModel.default.availability)")
        let entitled = AppleLanguageAssistant.privateCloudComputeAllowed
        if entitled {
            let cloud = PrivateCloudComputeLanguageModel()
            print("Private Cloud Compute: \(cloud.availability), quota limit reached: \(cloud.quotaUsage.isLimitReached)")
            // One direct request, whatever availability says, to see the error.
            do {
                let reply = try await LanguageModelSession(model: cloud).respond(to: "Reply with the single word: ready")
                print("Private Cloud Compute direct: \(reply.content)")
            } catch {
                print("Private Cloud Compute direct: \(error)")
            }
        } else {
            print("Private Cloud Compute: not entitled")
        }
        var answered = false
        for level in entitled ? [LanguageModelLevel.onDevice, .privateCloudCompute] : [.onDevice] {
            let suite = "sugu-probe-\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else { continue }
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = PreferencesStore(defaults: defaults, preferredLanguages: ["en"])
            preferences.update { $0.languageModel = level }
            let assistant = AppleLanguageAssistant(preferences: preferences)
            print("— \(level.rawValue)")
            let start = ContinuousClock.now
            let translation = await assistant.perform(.translate(to: .english), on: "今日はいい天気ですね。")
            print("  translate: \(translation) (\(start.duration(to: .now)))")
            let request = CompositionRequest(mode: .japanese, reading: "きしゃのきしゃがきしゃできしゃした", conversion: "貴社の記者が汽車で帰社した",
                                             context: "", convert: true, translations: [.chinese, .english])
            let suggestions = await assistant.suggestions(for: request)
            print("  suggestions: \(suggestions)")
            answered = answered || !translation.isEmpty
        }
        return answered
    }
}
