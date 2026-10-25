# Sugu

**Sugu** (すぐ, *"immediately"*) is a free, open-source input method for macOS for Japanese and Chinese. The right word should appear immediately, in the first candidate slot.

- **Private:** composition, conversion and learning stay on your Mac. Sugu sends nothing you type; it only checks for updates and downloads what you ask for.
- **One input source:** Chinese, Japanese and English in one input source, switched with Shift, Caps Lock or the かな/英数 keys.
- **Measured:** latency, memory and accuracy are checked by a benchmark that drives the whole input pipeline.

## Features

- **Chinese** with [librime](https://github.com/rime/librime) and the [rime-wanxiang](https://github.com/amzxyz/rime_wanxiang) dictionary: full pinyin, shuangpin, fuzzy pinyin and Zhuyin; Simplified or Traditional characters; emoji and symbols; rime-ice as an optional download.
- **Japanese** with [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter): romaji or kana input, clause-by-clause or live conversion, predictions, typo tolerance; the Zenzai neural converter as an optional download.
- **Learning you control:** an inspector to search, pin and delete learned words, "forget the last hour", per-app opt-out, and undo of the last commit.
- **Dictionaries** imported from Google Japanese Input, Microsoft IME, ATOK, Sogou, RIME and macOS text replacements, and synced between Macs through a folder you choose.
- Familiar keys from other input methods: reconversion, F6–F10, Emacs and Kotoeri control keys, Google's z-symbols.
- Interface in English, Japanese, and Simplified and Traditional Chinese, with VoiceOver and Dark Mode.

## Install

Requires macOS 14 or later. Download the installer from [sugu.zheng-she.com](https://sugu.zheng-she.com) or [GitHub Releases](https://github.com/PythonShe/sugu/releases) and open it; Sugu then appears in the input menu. If it doesn't, add it in **System Settings › Keyboard › Input Sources › Edit**, under Chinese, Simplified. Sugu updates itself.

<details>
<summary>Uninstall</summary>

Remove Sugu from **Input Sources**, then in Terminal:

```bash
killall Sugu
sudo rm -rf "/Library/Input Methods/Sugu.app"
sudo pkgutil --forget com.zheng-she.inputmethod.Sugu.pkg
rm -rf ~/Library/Application\ Support/Sugu   # learned words and downloads
rm -rf ~/Library/Caches/com.zheng-she.inputmethod.Sugu ~/Library/HTTPStorages/com.zheng-she.inputmethod.Sugu
defaults delete com.zheng-she.inputmethod.Sugu
```

</details>

## Building

Requires Xcode 27 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), CMake and Ninja.

```bash
scripts/build-librime.sh   # librime → Frameworks/
scripts/fetch-data.sh      # dictionary and corpus sources
scripts/build-data.sh      # dictionaries and language models → Data/
scripts/generate-project.sh
xcodebuild -project Sugu.xcodeproj -scheme Sugu -destination 'platform=macOS' build
scripts/install-dev.sh     # install the build for the current user
```

`scripts/ci.sh` runs the full check: builds, tests and the benchmark. The app is in `Sugu/`, and the engines, input logic and learning are in `Packages/SuguKit/`, which builds and tests on its own. [docs/architecture.md](docs/architecture.md) describes how they fit together.

## Contributing

Bug reports, ideas and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues privately, as described in [SECURITY.md](SECURITY.md).

## License

Copyright © 2026 Zheng She. Sugu is licensed under the [GNU General Public License, version 3 or later](LICENSE). Bundled third-party software and data keep their own licenses, listed in [ThirdPartyNotices.txt](Sugu/Resources/ThirdPartyNotices.txt).
