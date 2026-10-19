# Sugu — work plan

Jobs in build order. `[x]` done, `[~]` in progress, `[ ]` open. Scope is
ADR 0002 + ADR 0003 + Zenzai as an experimental option (decision.md D-007).
Progress notes live in `progress.md`; decisions in `decision.md`.

## 1. Foundation
- [x] Plan files: `todo.md`, `progress.md`, `decision.md`
- [x] `scripts/build-librime.sh` → `Frameworks/librime.xcframework` (librime + octagram, static, universal)
- [x] `scripts/fetch-data.sh` + `scripts/build-data.sh` → prebuilt Rime tables, OpenCC, syllable/word lists
- [ ] Repo layout: `project.yml`, `Sugu/` app target, `Packages/SuguKit/` local package
- [x] `.gitignore` generated-artifact rules (+ Xcode `Package.resolved` exception), recorded in `CLAUDE.md`/`AGENTS.md`
- [ ] Clean `xcodebuild` of the app and `swift test` of SuguKit

## 2. Core (SuguKit, headless, tested)
- [x] `SuguCore`: modes, key model, candidates, composition snapshot, engine protocol
- [x] Punctuation: width-aware, paired quotes/brackets, per-language tables
- [x] Computed candidates: dates, Chinese/kanji numerals (incl. 壹贰叁), full-width digits, arithmetic
- [x] Latin inference + allow-list
- [x] `InputSession` state machine: compose / convert / select / commit / cancel / undo-after-commit
- [x] Preferences model (Codable, UserDefaults-backed)

## 3. Engines
- [~] `SuguRime`: runtime setup, schema generator (full pinyin + shuangpin variants, script, fuzzy), session wrapper
- [ ] Grammar model (octagram) toggle per script; dictionary-only fallback
- [x] `SuguAzooKey`: converter wrapper, clause conversion, romaji/kana input, prediction
- [ ] Zenzai (experimental): trait, model download, runtime toggle, left context
- [ ] Engine lazy loading per mode

## 4. Learning & data
- [x] `SuguLearning`: SQLite store (learn, pin, delete, forget last hour, expiry); pause + no-learn list are enforced by the input session
- [x] Reranking + injection of learned words (exact reading); user words share the store
- [x] File protection + backup exclusion
- [ ] `SuguDictionaries`: import macOS text replacements, Google IME, ATOK, Sogou, RIME; export
- [ ] Sync through a user-picked folder

## 5. Shell (IMK app)
- [ ] App entry, IMKServer, Info.plist, input-source metadata, icon
- [ ] `SuguInputController`: key routing, marked text, commit, client capability probing
- [ ] Candidate window (NSPanel, Core Text, CALayer; vertical/horizontal; paging; system materials)
- [ ] Caret mode indicator
- [ ] Mode toggle keys (Shift tap, Caps Lock, 英数/かな), per-app mode rules, secure-input/terminal English, vim Esc
- [ ] Mac-standard keys: F6–F10, Option symbols, numpad, caret movement, romaji typo tolerance
- [ ] Reconvert selection, left context, document vocabulary (off by default)
- [ ] Pause-gated candidate window (off by default)
- [ ] VoiceOver announcements, scaling, increased contrast
- [ ] Input menu (modes, Settings…, Learned Words…)

## 6. Settings (native, toolbar-style window)
- [ ] General · Chinese · Japanese · Apps · Learning · Dictionaries · Advanced
- [ ] Downloads manager (grammar models, rime-ice, Zenzai model) with progress + verification
- [ ] String Catalog for every string (en, zh-Hans, zh-Hant, ja)

## 7. Proof & delivery
- [ ] `sugu-bench`: accuracy harness (top-1, keystrokes/char) + latency/memory measurement
- [ ] CI workflow: build, tests, budgets
- [ ] Packaging: signed/notarized `.pkg` scripts, Sparkle (profile off), dev install script
- [ ] README, third-party notices/attribution, ADR updates
- [ ] Code review passes (reviewer agents) and fixes
