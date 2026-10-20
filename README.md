# Sugu

**Sugu** (すぐ — *"immediately"*) is an open-source, privacy-first input method for macOS, built for Japanese and Chinese composition.

The name is the thesis: the right word should appear *immediately* — in the first candidate slot, with no wait.

## Principles

- **Local-first, privacy-first** — an input method reads everything you type. Sugu is auditable and sends nothing: composition, conversion and learning stay on your Mac, and you can see and delete everything it has learned.
- **One input source** — Chinese, Japanese and English live in one input source, so switching never depends on macOS input-source switching.
- **Fast and accurate, measured** — latency and memory budgets are checked by a benchmark that drives the whole input pipeline, and accuracy is measured on public test sets.
- **Open source** — Apache-2.0. Full stop, no proprietary tier.

## Features

- **Chinese** through [librime](https://github.com/rime/librime) with the [rime-wanxiang](https://github.com/amzxyz/rime_wanxiang) dictionary: full pinyin and the common shuangpin schemes, fuzzy pinyin, Simplified, Traditional or Japanese kanji forms (per app if you like), an optional grammar model, and rime-ice as an optional download.
- **Japanese** through [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter): romaji or kana input, clause-by-clause conversion, predictions, typo tolerance, Chinese forms of Japanese names, and the experimental Zenzai neural converter as an optional download.
- **Modes** switched with Shift or Caps Lock, ⌃⇧Space, or the かな/英数 keys; per-app defaults, English in terminals and password fields.
- **Learning you control** — an inspector to search, pin and delete learned words, "forget the last hour", per-app opt-out, expiry, and undo of the last commit with ⌃⌫.
- **Dictionaries** imported from Google Japanese Input, Microsoft IME, ATOK, Sogou, RIME and macOS text replacements; sync between Macs through a folder you choose.
- Words already before the caret — or, if you turn it on, anywhere in the field — rank first, without being stored.
- Dates, numbers and arithmetic as candidates; native candidate window with Liquid Glass on macOS 26; VoiceOver, Increase Contrast and Dark Mode; English, Simplified Chinese, Traditional Chinese and Japanese interface.

## Install

Requires macOS 14 or later. Download `Sugu-<version>.pkg` from the [releases](https://github.com/PythonShe/sugu/releases), open it, then add Sugu in **System Settings › Keyboard › Input Sources**. Sugu checks for updates itself; this can be turned off in its settings.

## Building

Requires Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), CMake and Ninja.

```bash
scripts/build-librime.sh   # librime + octagram → Frameworks/librime.xcframework
scripts/fetch-data.sh      # rime-wanxiang dictionary sources
scripts/build-data.sh      # compiled dictionaries → Data/
xcodegen generate
xcodebuild -project Sugu.xcodeproj -scheme Sugu -destination 'platform=macOS' build
```

`scripts/ci.sh` runs everything above plus the tests and the benchmark (`sugu-bench`, with its test sets in `Bench/`). `scripts/install-dev.sh` installs a build for the current user.

| Path | Contents |
|---|---|
| `Sugu/` | The input method app: InputMethodKit wiring, candidate window, settings |
| `Packages/SuguKit/` | Input state machine, engines, learning, dictionaries — testable without installing anything |
| `Bench/` | Accuracy test sets |
| `docs/adr/` | Architecture decisions |
| `scripts/` | Dependency, data, release and install scripts |

## License

[Apache-2.0](LICENSE). Sugu includes third-party software and data under their own licenses, listed in [ThirdPartyNotices.txt](Sugu/Resources/ThirdPartyNotices.txt); the Chinese dictionary is rime-wanxiang by amzxyz (CC-BY-4.0). rime-ice (GPL-3.0) and the Zenzai model (CC-BY-SA-4.0) are never bundled and are downloaded only at the user's request.
