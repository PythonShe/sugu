# Sugu

**Sugu** (すぐ — *"immediately"*) is a free, privacy-first input method for macOS, built for Japanese and Chinese composition.

The name is the thesis: the right word should appear *immediately* — in the first candidate slot, with no wait.

## Principles

- **Local-first, privacy-first** — an input method reads everything you type. Sugu sends nothing you type: composition, conversion and learning stay on your Mac, and you can see the words it has learned and delete what it has learned. Apple's language models can translate and rewrite if you turn them on, on your Mac or, only if you choose it, in Apple Private Cloud Compute, which can also suggest conversions.
- **One input source** — Chinese, Japanese and English live in one input source, so switching never depends on macOS input-source switching.
- **Fast and accurate, measured** — latency and memory budgets are checked by a benchmark that drives the whole input pipeline, and accuracy is measured on public test sets.
- **Free** — no price, no account, no paid tier.

## Features

- **Chinese** through [librime](https://github.com/rime/librime) with the [rime-wanxiang](https://github.com/amzxyz/rime_wanxiang) dictionary: full pinyin and the common shuangpin schemes, fuzzy pinyin, Zhuyin on the standard, Eten or IBM layouts, Simplified, Traditional (standard, Taiwan or Hong Kong forms) or Japanese kanji forms (per app if you like), sentences corrected by a character language model built from [Tatoeba](https://tatoeba.org), emoji and symbols after the words that name them (from [CLDR](https://cldr.unicode.org)), an optional grammar model, and rime-ice as an optional download.
- **Japanese** through [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter): romaji or kana input (JIS or US keyboards), clause-by-clause or live conversion ranked by a character language model built from [Tatoeba](https://tatoeba.org), predictions, typo tolerance, Chinese forms of Japanese names, and the experimental Zenzai neural converter as an optional download.
- **Modes** switched with Shift or Caps Lock, ⌃⇧Space, or the かな/英数 keys; per-app defaults, English in terminals and password fields.
- **Learning you control** — Sugu learns your words and phrasing as you write; an inspector to search, pin and delete learned words, "forget the last hour", per-app opt-out, expiry, undo of the last commit with ⌃⌫, ⇧⌫ to forget a learned candidate, and Add Word from the input menu.
- **Dictionaries** imported from Google Japanese Input, Microsoft IME, ATOK, Sogou, RIME and macOS text replacements; sync between Macs through a folder you choose.
- Words already before the caret — or, if you turn it on, anywhere in the field — rank first, without being stored.
- Habits from other input methods: reconversion of the selection, F6–F10 and the Emacs and Kotoeri control keys, 英数 twice to retype as romaji, `[` `]` to take one character of a word, Google's z-symbols, and symbols by their Japanese names.
- Dates, numbers and arithmetic as candidates; native candidate window with Liquid Glass on macOS 26; VoiceOver, Increase Contrast and Dark Mode; English, Simplified Chinese, Traditional Chinese and Japanese interface.

## Install

Requires macOS 14 or later. Download `Sugu-<version>.pkg` from [sugu.zheng-she.com](https://sugu.zheng-she.com) and open it; Sugu is added to the input menu. If it is missing, add it in **System Settings › Keyboard › Input Sources › Edit**, under Chinese, Simplified; log out and back in if it is not listed yet. Sugu checks for updates itself; this can be turned off in its settings.

To uninstall, remove Sugu from **Input Sources**, then in Terminal:

```bash
sudo rm -rf "/Library/Input Methods/Sugu.app"
sudo pkgutil --forget com.zheng-she.inputmethod.Sugu.pkg
rm -rf ~/Library/Application\ Support/Sugu   # learned words and downloads
defaults delete com.zheng-she.inputmethod.Sugu
```

Log out and back in to end the running copy.

## Building

Requires Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), CMake and Ninja.

```bash
scripts/build-librime.sh   # librime + octagram → Frameworks/librime.xcframework
scripts/fetch-data.sh      # rime-wanxiang dictionary sources, Tatoeba sentences, CLDR emoji names
scripts/build-data.sh      # compiled dictionaries and language model → Data/
xcodegen generate
xcodebuild -project Sugu.xcodeproj -scheme Sugu -destination 'platform=macOS' build
```

`scripts/ci.sh` runs everything above plus the tests and the benchmark (`sugu-bench`, with its test sets in `Bench/`). `scripts/install-dev.sh` installs a build for the current user; `scripts/package-dev.sh` makes an unsigned installer package of one, for testing the package install.

| Path | Contents |
|---|---|
| `Sugu/` | The input method app: InputMethodKit wiring, candidate window, settings |
| `Packages/SuguKit/` | Input state machine, engines, learning, dictionaries — testable without installing anything |
| `Bench/` | Accuracy test sets |
| `docs/` | [Architecture](docs/architecture.md) and architecture decisions (`adr/`) |
| `scripts/` | Dependency, data, release and install scripts |
| `todo.md`, `progress.md`, `decision.md`, `release.md` | Work plan, build log, implementation decisions and release plan |
| `site/` | The home page at [sugu.zheng-she.com](https://sugu.zheng-she.com) (Astro, Cloudflare Pages) |

## License

Proprietary, free of charge — see [LICENSE](LICENSE) and [ADR 0006](docs/adr/0006-proprietary-license-and-distribution.md). Sugu includes third-party software and data under their own licenses, listed in [ThirdPartyNotices.txt](Sugu/Resources/ThirdPartyNotices.txt); the Chinese dictionary is rime-wanxiang by amzxyz (CC-BY-4.0), and the language models are computed from sentences by the contributors of Tatoeba (CC BY 2.0 FR). rime-ice (GPL-3.0) and the Zenzai model (CC-BY-SA-4.0) are never bundled and are downloaded only at the user's request.
