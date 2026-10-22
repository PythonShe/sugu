import AppKit
import SuguCore

/// Apple's language models (ADR 0004): the level, and what each may see.
@available(macOS 27.0, *)
final class LanguageModelPane: SettingsPane {
    override func build() {
        let model = model
        // Private Cloud Compute only where the build may use it; a level
        // chosen in a development build reads as On This Mac here.
        let cloud = AppleLanguageAssistant.privateCloudComputeAllowed
        var options: [(title: String, value: LanguageModelLevel)] = [
            (String(localized: "Off"), .off),
            (String(localized: "On This Mac"), .onDevice),
        ]
        if cloud { options.append((String(localized: "On This Mac and Apple Private Cloud Compute"), .privateCloudCompute)) }
        form.popUp(String(localized: "Language model:"), options: options, get: {
            let level = model.preferences.languageModel
            return level == .privateCloudCompute && !cloud ? .onDevice : level
        }, set: { model.preferences.languageModel = $0 })
        let notReady = NSTextField(labelWithString: String(localized: "Not Ready"))
        notReady.textColor = .secondaryLabelColor
        let status = form.row(String(localized: "Status:"), notReady)
        form.onRefresh {
            let level = model.preferences.languageModel
            status.isHidden = level == .off || AppleLanguageAssistant.isReady(level)
        }

        form.gap()
        let uses: [(String, WritableKeyPath<Preferences, Bool>)] = [
            (String(localized: "Translate and rewrite selected text"), \.modelForSelection),
            (String(localized: "Suggest conversions for long compositions"), \.modelForConversion),
            (String(localized: "Suggest translations while composing"), \.modelForTranslation),
        ]
        for (index, use) in uses.enumerated() {
            let box = form.checkbox(use.0, label: index == 0 ? String(localized: "Use for:") : nil,
                                    get: { model.preferences[keyPath: use.1] }, set: { model.preferences[keyPath: use.1] = $0 })
            // Conversions come from Private Cloud Compute only (D-081).
            let level: (LanguageModelLevel) -> Bool = use.1 == \.modelForConversion ? { $0 == .privateCloudCompute } : { $0 != .off }
            if use.1 == \.modelForConversion && !cloud { form.grid.cell(for: box)?.row?.isHidden = true }
            form.onRefresh { box.isEnabled = level(model.preferences.languageModel) }
        }
    }
}
