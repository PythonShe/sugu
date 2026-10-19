# Engines, data, and stack

Sugu is a native macOS input method for Chinese and Japanese whose bar is
better accuracy than the built-in input methods at no cost in latency. This ADR
records which engines and data produce candidates, how they enter the build, and
what the shell is made of, as settled on 2026-10-20. It replaces the engine
choices of the original plan (Mozc over socket IPC, libpinyin as a dynamic
library) and withdraws the AI layer of ADR 0001 from current scope.

## Decisions

### Scope

1. **No AI layer in v1.** ADR 0001 is deferred, kept as a record awaiting a
   flip decision. No provider calls, no BYOK client. Accuracy comes from
   engines, data, and on-device learning.

2. **No MVP; both languages from the start.** Chinese and Japanese are built
   together, so the single-input-source design (ADR 0003, decision 1) is
   exercised from the first build.

### Chinese

3. **librime (BSD-3-Clause), driven through its C API.** It is mature, actively
   maintained, and covers full pinyin, shuangpin, zhuyin and other schemes
   through schemas. Sugu generates and deploys schemas from its own settings;
   users never edit YAML.

4. **Data: rime-wanxiang (CC-BY-4.0).** The base dictionaries (~25 MB) are
   bundled with attribution. The wanxiang grammar model loaded through
   librime-octagram (BSD-3-Clause) is ~380 MB per script, so it is an
   optional download, one per script (`zh-hans`, `zh-hant`), toggled in
   settings. Generated schemas carry `grammar/language` only while the file is
   installed; removing it falls back to dictionary ranking. octagram
   memory-maps the file, so only touched pages are resident. It becomes the
   default only after its resident-memory cost is measured against the budget
   in `AGENTS.md`.

5. **rime-ice (GPL-3.0) is never bundled.** Users may download it from
   settings as an alternative dictionary.

### Japanese

6. **AzooKeyKanaKanjiConverter (MIT), through Swift Package Manager.** Pure
   Swift, in-process, no server and no IPC. Default dictionary:
   azooKey_dictionary_storage (Apache-2.0).

7. **Zenzai is a later, optional download.** The converter's neural mode
   (package traits `Zenzai` / `ZenzaiCPU`, llama.cpp underneath) stays out of
   the v1 build. When added, the model is user-downloaded and on-device only;
   its license and memory cost are verified first.

### Shell

8. **Own shell on AppKit and InputMethodKit; no Squirrel fork.** Squirrel is
   GPL-3.0 and already native AppKit — forking it would end Apache-2.0
   licensing and leave no reason for Sugu to exist. Its source is not copied.

9. **Candidate window is a custom `NSPanel`** drawn with Core Text and
   `CALayer`; no Auto Layout, no SwiftUI on the keystroke path.

10. **Learning and dictionaries live in Sugu's own store** in Application
    Support, behind one interface over both engines, so a single inspector
    can list, pin, delete, and expire learned words (ADR 0003).

### Build and distribution

11. **XcodeGen + SwiftPM.** A script builds librime and its dependencies with
    CMake into an `.xcframework` linked statically. No Bazel.

12. **Signed, notarized `.pkg`; updates through Sparkle** with system-profile
    reporting disabled. Update checks and user-initiated downloads (dictionaries,
    grammar model, Zenzai) are the only network traffic Sugu makes.

## Considered options

- **libpinyin:** rejected — it is GPL-3.0-or-later (verified from `COPYING`
  and source headers), not LGPL; dynamic linking does not avoid that.
- **RIME for Japanese:** rejected — RIME Japanese schemas are lookup tables
  without sentence-level kana-kanji conversion.
- **Mozc:** rejected — Bazel build, a separate server process over IPC, and an
  open-source dictionary noticeably weaker than Google Japanese Input's.
- **Forking Squirrel:** rejected — see decision 8.
- **Bundling rime-ice:** rejected — GPL-3.0 data; see decision 5.

## Consequences

- `AGENTS.md` / `CLAUDE.md`, README, and `CONTEXT.md` are rewritten to this
  stack in the same change; the `ai` commit scope becomes `learning`.
- Licenses above were read from each repository on 2026-10-20; re-verify from
  `COPYING`/`LICENSE` in a clone before shipping, per `AGENTS.md`.
- Open before the build lands: grammar-model resident memory (decision 4),
  Zenzai model license and size (decision 7).
