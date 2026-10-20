import AppKit
import SuguCore
import SuguInput

final class ChinesePane: SettingsPane {
    private var downloads: [DownloadControl] = []

    override func build() {
        let model = model
        let failed = NSTextField(labelWithString: String(localized: "Failed"))
        failed.textColor = .systemRed
        let tryAgain = form.makeButton(String(localized: "Try Again")) { model.retryChinese() }
        let status = form.row(String(localized: "Status:"), NSStackView(views: [failed, tryAgain]))
        form.onRefresh { status.isHidden = !model.chineseFailed }
        form.popUp(String(localized: "Keyboard:"), options: ChineseKeyboard.allCases.map { ($0.title, $0) },
                   get: { model.preferences.chineseKeyboard }, set: { keyboard in
                       // Zhuyin is typed in Taiwan, so it brings Taiwan's characters
                       // to a Simplified setting.
                       var preferences = model.preferences
                       if keyboard == .zhuyin, preferences.chineseKeyboard != .zhuyin, preferences.chineseScript == .simplified {
                           preferences.chineseScript = .traditionalTaiwan
                       }
                       preferences.chineseKeyboard = keyboard
                       model.preferences = preferences
                   })
        let scheme = form.popUp(String(localized: "Pinyin:"), options: PinyinScheme.allCases.map { ($0.title, $0) },
                                get: { model.preferences.pinyinScheme }, set: { model.preferences.pinyinScheme = $0 })
        let layout = form.popUp(String(localized: "Zhuyin:"), options: ZhuyinLayout.allCases.map { ($0.title, $0) },
                                get: { model.preferences.zhuyinLayout }, set: { model.preferences.zhuyinLayout = $0 })
        form.popUp(String(localized: "Characters:"), options: ChineseScript.allCases.map { ($0.title, $0) },
                   get: { model.preferences.chineseScript }, set: { model.preferences.chineseScript = $0 })

        form.gap()
        form.row(String(localized: "Fuzzy pinyin:"), fuzzyGrid())
        // Pinyin's schemes and fuzzy sounds have no part in Zhuyin, nor
        // Zhuyin's layouts in pinyin.
        form.onRefresh {
            scheme.isEnabled = model.preferences.chineseKeyboard == .pinyin
            layout.isEnabled = model.preferences.chineseKeyboard == .zhuyin
        }

        form.gap()
        let dictionary = form.popUp(String(localized: "Dictionary:"), options: [
            (String(localized: "Wanxiang"), ChineseDictionary.wanxiang),
            (String(localized: "rime-ice"), ChineseDictionary.rimeIce),
        ], get: { model.preferences.chineseDictionary }, set: { model.preferences.chineseDictionary = $0 })
        dictionary.autoenablesItems = false
        form.onRefresh { dictionary.item(at: 1)?.isEnabled = model.isInstalled(.rimeIce) }
        let iceLabel = String(localized: "rime-ice:")
        let ice = DownloadControl(item: .rimeIce, name: SettingsForm.name(iceLabel), model: model)
        downloads.append(ice)
        form.row(iceLabel, ice)

        form.gap()
        let grammarLabel = String(localized: "Grammar model:")
        let grammar = form.checkbox(String(localized: "Use the grammar model"), label: grammarLabel,
                                    get: { model.preferences.useGrammarModel && model.isInstalled(.grammarModel) },
                                    set: { model.preferences.useGrammarModel = $0 })
        form.onRefresh { grammar.isEnabled = model.isInstalled(.grammarModel) }
        let grammarDownload = DownloadControl(item: .grammarModel, name: SettingsForm.name(grammarLabel), model: model)
        downloads.append(grammarDownload)
        form.row(nil, grammarDownload)
    }

    override func modelDidChange(_ change: SettingsModel.Change) {
        if change == .downloads { downloads.forEach { $0.update() } }
    }

    private func fuzzyGrid() -> NSView {
        let model = model
        // One row per kind of confusion: retroflex initials, other
        // initials, then finals.
        let rows: [[FuzzyPinyin]] = [[.zZh, .cCh, .sSh], [.nL, .fH, .rL], [.rY, .kG], [.enEng, .inIng]]
        let boxes = rows.map { $0.map { pair in
            let box = NSButton(checkboxWithTitle: pair.title, target: nil, action: nil)
            form.bind(box) { control in
                if (control as? NSButton)?.state == .on {
                    model.preferences.fuzzyPinyin.insert(pair)
                } else {
                    model.preferences.fuzzyPinyin.remove(pair)
                }
            }
            form.onRefresh {
                box.state = model.preferences.fuzzyPinyin.contains(pair) ? .on : .off
                box.isEnabled = model.preferences.chineseKeyboard == .pinyin
            }
            return box as NSView
        } }
        let grid = NSGridView(views: boxes.map { $0 + Array(repeating: NSGridCell.emptyContentView, count: 3 - $0.count) })
        grid.rowSpacing = 6
        grid.columnSpacing = 16
        return grid
    }
}

extension ChineseKeyboard {
    var title: String {
        switch self {
        case .pinyin: String(localized: "Pinyin")
        case .zhuyin: String(localized: "Zhuyin")
        }
    }
}

extension ZhuyinLayout {
    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .eten: String(localized: "Eten")
        case .ibm: String(localized: "IBM")
        }
    }
}

extension ChineseScript {
    var title: String {
        switch self {
        case .simplified: String(localized: "Simplified")
        case .traditional: String(localized: "Traditional")
        case .traditionalTaiwan: String(localized: "Traditional (Taiwan)")
        case .traditionalHongKong: String(localized: "Traditional (Hong Kong)")
        case .japanese: String(localized: "Japanese Kanji")
        }
    }
}

extension PinyinScheme {
    var title: String {
        switch self {
        case .fullPinyin: String(localized: "Full Pinyin")
        case .xiaohe: String(localized: "Xiaohe Shuangpin")
        case .ziranma: String(localized: "Ziranma Shuangpin")
        case .microsoft: String(localized: "Microsoft Shuangpin")
        case .sogou: String(localized: "Sogou Shuangpin")
        case .ziguang: String(localized: "Ziguang Shuangpin")
        case .abc: String(localized: "Intelligent ABC Shuangpin")
        case .pinyinPlusPlus: String(localized: "Pinyin Jiajia Shuangpin")
        }
    }
}

extension FuzzyPinyin {
    /// Sound pairs read the same in every language.
    var title: String {
        switch self {
        case .zZh: "z = zh"
        case .cCh: "c = ch"
        case .sSh: "s = sh"
        case .nL: "n = l"
        case .fH: "f = h"
        case .rL: "r = l"
        case .rY: "r = y"
        case .kG: "k = g"
        case .enEng: "en = eng"
        case .inIng: "in = ing"
        }
    }
}
