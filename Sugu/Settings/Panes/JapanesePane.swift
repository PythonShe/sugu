import AppKit
import SuguCore

final class JapanesePane: SettingsPane {
    private var zenzaiDownload: DownloadControl?

    override func build() {
        let model = model
        form.segmented(String(localized: "Input:"), options: [
            (String(localized: "Romaji"), false),
            (String(localized: "Kana"), true),
        ], get: { model.preferences.kanaInput }, set: { model.preferences.kanaInput = $0 })
        form.popUp(String(localized: "Punctuation:"), options: JapanesePunctuationStyle.allCases.map { ("\($0.comma) \($0.period)", $0) },
                   get: { model.preferences.japanesePunctuation }, set: { model.preferences.japanesePunctuation = $0 })
        form.checkbox(String(localized: "Type spaces in full width"),
                      get: { model.preferences.fullWidthSpace }, set: { model.preferences.fullWidthSpace = $0 })

        form.gap()
        form.checkbox(String(localized: "Use live conversion"), label: String(localized: "Conversion:"),
                      get: { model.preferences.liveConversion }, set: { model.preferences.liveConversion = $0 })
        form.checkbox(String(localized: "Show predictions while typing"),
                      get: { model.preferences.japanesePredictions }, set: { model.preferences.japanesePredictions = $0 })
        form.checkbox(String(localized: "Correct typos"),
                      get: { model.preferences.typoCorrection }, set: { model.preferences.typoCorrection = $0 })
        let phonetic = form.checkbox(String(localized: "Type particles as pronounced (wa, e, o)"),
                                     get: { model.preferences.phoneticRomaji }, set: { model.preferences.phoneticRomaji = $0 })
        form.onRefresh { phonetic.isEnabled = !model.preferences.kanaInput }

        form.gap()
        let zenzaiLabel = String(localized: "Neural conversion:")
        let zenzai = form.checkbox(String(localized: "Use Zenzai (Experimental)"), label: zenzaiLabel,
                                   get: { model.preferences.zenzaiEnabled && model.isInstalled(.zenzaiModel) },
                                   set: { model.preferences.zenzaiEnabled = $0 })
        form.onRefresh { zenzai.isEnabled = model.isInstalled(.zenzaiModel) }
        let download = DownloadControl(item: .zenzaiModel, name: SettingsForm.name(zenzaiLabel), model: model)
        zenzaiDownload = download
        form.row(nil, download)
    }

    override func modelDidChange(_ change: SettingsModel.Change) {
        if change == .downloads { zenzaiDownload?.update() }
    }
}
