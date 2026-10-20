import AppKit
import SuguCore

final class GeneralPane: SettingsPane {
    override func build() {
        let model = model
        for (index, mode) in model.orderedModes.filter({ $0 != .english }).enumerated() {
            form.checkbox(mode.localizedName, label: index == 0 ? String(localized: "Input modes:") : nil,
                          get: { model.isEnabled(mode) }, set: { model.setEnabled(mode, $0) })
        }
        form.popUp(String(localized: "Switch to English with:"), options: [
            (String(localized: "Shift"), EnglishToggle.shiftTap),
            (String(localized: "Caps Lock"), EnglishToggle.capsLock),
            (String(localized: "Off"), EnglishToggle.none),
        ], get: { model.preferences.englishToggle }, set: { model.preferences.englishToggle = $0 })
        form.checkbox(String(localized: "Show mode at cursor"),
                      get: { model.preferences.showModeIndicator }, set: { model.preferences.showModeIndicator = $0 })

        form.gap()
        form.segmented(String(localized: "Candidate layout:"), options: [
            (String(localized: "Vertical"), CandidateLayout.vertical),
            (String(localized: "Horizontal"), CandidateLayout.horizontal),
        ], get: { model.preferences.candidateLayout }, set: { model.preferences.candidateLayout = $0 })
        form.popUp(String(localized: "Candidates per page:"), options: (5...10).map { ("\($0)", $0) },
                   get: { model.preferences.candidatesPerPage }, set: { model.preferences.candidatesPerPage = $0 })
        let sizeLabel = String(localized: "Text size:")
        form.row(sizeLabel, fontSizeSlider(named: SettingsForm.name(sizeLabel)))
        form.checkbox(String(localized: "Show readings"),
                      get: { model.preferences.readingHints }, set: { model.preferences.readingHints = $0 })
        form.checkbox(String(localized: "Show candidates after a pause"),
                      get: { model.preferences.pauseGatedWindow }, set: { model.preferences.pauseGatedWindow = $0 })

        form.gap()
        form.popUp(String(localized: "Punctuation width:"), options: [
            (String(localized: "Automatic"), PunctuationWidth.automatic),
            (String(localized: "Full Width"), PunctuationWidth.full),
            (String(localized: "Half Width"), PunctuationWidth.half),
        ], get: { model.preferences.punctuationWidth }, set: { model.preferences.punctuationWidth = $0 })
        form.checkbox(String(localized: "Rank candidates by the text before the cursor"), label: String(localized: "Context:"),
                      get: { model.preferences.leftContextRanking }, set: { model.preferences.leftContextRanking = $0 })
        let vocabulary = form.checkbox(String(localized: "Prefer words already in the document"),
                                       get: { model.preferences.documentVocabulary }, set: { model.preferences.documentVocabulary = $0 })
        form.onRefresh { vocabulary.isEnabled = model.preferences.leftContextRanking }
        form.textField(String(localized: "Always type as English:"),
                       get: { model.preferences.latinAllowList.joined(separator: " ") },
                       set: { model.preferences.latinAllowList = $0.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init) })
    }

    private func fontSizeSlider(named name: String) -> NSView {
        let model = model
        let slider = NSSlider(value: 16, minValue: 12, maxValue: 28, target: nil, action: nil)
        slider.numberOfTickMarks = 9
        slider.allowsTickMarkValuesOnly = true
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        slider.setAccessibilityLabel(name)
        form.bind(slider) { model.preferences.candidateFontSize = ($0 as? NSSlider)?.doubleValue ?? 16 }
        form.onRefresh { slider.doubleValue = model.preferences.candidateFontSize }
        let small = NSImageView(image: NSImage(systemSymbolName: "textformat.size.smaller", accessibilityDescription: nil)!)
        let large = NSImageView(image: NSImage(systemSymbolName: "textformat.size.larger", accessibilityDescription: nil)!)
        small.setAccessibilityElement(false)
        large.setAccessibilityElement(false)
        let stack = NSStackView(views: [small, slider, large])
        stack.spacing = 6
        return stack
    }
}
