# Decisions log

Implementation decisions taken while building v1, newest last. Product-level
decisions stay in `docs/adr/`; this file records how they are carried out and
any call made without the owner present. Each entry: what, why, reversibility.

## D-001 · Repository layout (2026-10-20)
- `project.yml` → generated `Sugu.xcodeproj`; app target sources in `Sugu/`.
- All logic that can run headless lives in the local package
  `Packages/SuguKit`, split by responsibility: `SuguCore` (models, key model,
  punctuation, computed candidates, Latin inference, preferences),
  `SuguRime`, `SuguAzooKey`, `SuguLearning`, `SuguDictionaries`,
  `SuguDownloads`, `SuguUpdates`, `SuguInput` (the input state machine,
  engine-free behind `CompositionEngine` and `EngineSource`), and
  `SuguEngines` (`EngineHub` and `ModelLibrary`: the real engines and their
  downloadable data, which only the app and `sugu-bench` link).
- The app target is a thin shell: IMK wiring, windows, settings.
- Why: the input state machine can be tested with `swift test` without
  installing or activating an input method, so testing never interrupts the
  person working on the machine. Reversible.

## D-002 · librime build (2026-10-20)
- `scripts/build-librime.sh` builds librime 1.17.0 + librime-octagram
  (merged plugin) + leveldb, marisa-trie, yaml-cpp, OpenCC as static,
  universal (arm64 + x86_64) libraries, merged with `libtool` into one archive
  and wrapped as `Frameworks/librime.xcframework` with a `CRime` module map.
- Logging (glog) off; Boost is header-only (1.92.0, checksum-verified).
- Plugin modules register through static constructors that a static link
  drops unless referenced, so a C++ shim references
  `rime_require_module_octagram` and the traits name the module explicitly.
- Build output and sources live in `.vendor/` and `Frameworks/`, both
  gitignored; versions are pinned in `scripts/versions.sh`.

## D-003 · Learning ownership (2026-10-20)
- Sugu's SQLite store is the single source of learned data (ADR 0002 d10,
  ADR 0003 d18). Engine-internal learning is off: librime
  `translator/enable_user_dict: false`; AzooKey `learningType: .nothing`.
- Learned and user words reach conversion two ways: (1) exact and
  syllable-aligned prefix matches are injected into the candidate list by
  Sugu; (2) for Japanese they are also handed to AzooKey as a dynamic user
  dictionary so they take part in lattice search.
- Why: one inspector can list, pin, delete, and expire everything; deleting a
  word really removes it. Cost: librime's own phrase-combination learning is
  given up; Sugu learns the committed phrase as a whole instead. D-025
  brings learned words into librime's sentences without librime learning.

## D-004 · Composition ownership (2026-10-20)
- Chinese: librime owns raw input, caret, and partial selection (keys go
  through `process_key`; restoring a composition uses `set_input`).
- Japanese: AzooKey `ComposingText` owns kana input; Sugu owns the clause
  state (fixed clauses, focused clause length) on top of it.
- Sugu owns everything above the engines: modes, punctuation, computed and
  learned candidates, undo-after-commit, the fixed-prefix buffer for
  Sugu-injected candidates.

## D-005 · Single input source registration (2026-10-20)
- One IMK input source with no `ComponentInputModeDict` modes, so macOS
  never lists more than one Sugu entry. Modes are internal (ADR 0003 d1) and
  appear as checkable items in the input menu.
- Reconsidered after review: registering the three modes as input modes
  would put the mode in the menu-bar icon, but macOS then lists each mode
  as its own entry and ⌃Space cycles through them, which is the
  input-source switching ADR 0003 d1 keeps out. The caret indicator and the
  input menu's checkmarks show the mode instead.
- Bundle ID `io.github.pythonshe.inputmethod.Sugu` (IMK requires
  `inputmethod` in the identifier).

## D-006 · Minimum macOS (2026-10-20)
- macOS 14.0. AzooKey needs 13+; 14 gives current AppKit/IMK behavior and
  `NSTextInsertionIndicator`-era caret APIs. Liquid Glass materials are used
  on macOS 26+ through availability checks with a visual-effect fallback.

## D-007 · Zenzai is compiled in; C++ interop on the AzooKey chain (2026-10-20)
- AzooKey is built with its `Zenzai` trait (Metal) so the experimental
  option needs no second build. The trait compiles AzooKey with C++ interop,
  and Swift requires every importer of such a module to enable it too, so
  `SuguAzooKey`, `SuguInput`, `sugu-tool`, the app target and their tests
  build with `.interoperabilityMode(.Cxx)`. `@_implementationOnly` and
  `internal import` were tried and do not lift that requirement.
- Zenzai stays off at runtime until the user enables it and downloads a
  model (ADR 0002 d7 is amended accordingly).

## D-008 · One marisa-trie per namespace (2026-10-20)
- AzooKey links SwiftyMarisa's marisa-trie (0.2.x); librime uses 0.3.1 and
  OpenCC bundles 0.2.6. Same C++ symbol names across different versions is
  an ODR hazard that fails silently. librime, OpenCC and marisa are compiled
  with `-Dmarisa=rime_marisa`, OpenCC uses the shared 0.3.1 build, and the
  build script fails if any unrenamed marisa symbol remains.

## D-009 · Data-derived tables, not hand-written ones (2026-10-20)
- Lookup tables that exist in the bundled data (pinyin syllables, English
  word list) are extracted from it at data-build time and loaded at runtime.
  `LatinInference` takes them as inputs. They stay in step with the
  dictionary and are not retyped in source.

## D-010 · Chinese data shipped precompiled; one grammar model (2026-10-20)
- `scripts/build-data.sh` compiles the wanxiang tables with Sugu's own
  runtime and ships `sugu.table.bin` (46 MB), `sugu.reverse.bin` and the
  default `sugu.prism.bin` in `Rime/build/`, without the 54 MB of YAML
  sources. librime reuses a prebuilt table whose source is absent; other
  pinyin schemes only rebuild the small prism on first use.
- Spelling rules: Sugu's `toneless` section, then fuzzy sections, then
  wanxiang's `lite` scheme section (CC-BY-4.0), patched into the generated
  schema in that order.
- Only the `zh-hans` grammar model is offered: octagram scores sentences on
  dictionary text (Simplified) before the OpenCC script filter runs, so it
  serves Traditional output too. ADR 0002 d4's per-script download becomes a
  single download. It lives in the user data directory, where octagram
  resolves `.gram` files.

## D-011 · Japanese clause boundary from the best sentence (2026-10-20)
- AzooKey's `firstClauseResults` is sorted longest-first across N-best
  paths, so its head is not the best path's first clause (it produced
  "[私はが]九世です"). Sugu takes the best whole sentence and uses the
  highest-valued first-clause result that prefixes it as the boundary, then
  requests candidates for exactly that prefix. The first display therefore
  equals the converter's best sentence, and the list holds clause
  alternatives.

## D-012 · Key bindings without a precedent elsewhere (2026-10-20)
- Undo-after-commit: ⌃⌫ (Control-Delete), honored only as the key right
  after a commit; any other key ends the chance. Plain ⌫ keeps its meaning
  (ADR 0003 d6).
- Chinese ↔ Japanese: ⌃⇧Space, plus the input menu; かな and 英数 keys
  select Japanese and English directly. English toggle: Shift tap (default)
  or Caps Lock, set in General settings.
- Chinese mode: `v` starts a number/expression composition (common in
  Chinese input methods; no pinyin syllable starts with v). `-`/`=` and
  Page Up/Down turn pages. Arrows follow the layout: the list axis moves
  the highlight, the other axis moves the caret.
- Japanese mode follows the system input method: Space converts, Space
  again opens the list; ←/→ move between clauses; ⇧←/⇧→ resize; Esc and ⌫
  step back to kana.
- One `InputSession` serves every client, attaching the focused one, so
  the AzooKey dictionary and librime runtime load once per process.

## D-013 · Input source metadata and IMK isolation (2026-10-20)
- `TISIntendedLanguage` is `zh-Hans` (one source has to be listed under one
  language); the repertoire lists Hans, Hant, Jpan and Latn.
- InputMethodKit is not annotated for concurrency. The controller hops into
  the main actor with `MainActor.assumeIsolated` and passes IMK's objects
  through `nonisolated(unsafe)` locals; all logic lives in main-actor types.
- The client adapter never clears marked text it did not set: some apps
  replace the selection with an empty marked string.

## D-014 · The schema lives only in the user directory (2026-10-20)
- librime moves a user copy of a schema to `trash/` when the shared copy
  has a higher version, which silently dropped every setting. The bundled
  data no longer contains `sugu.schema.yaml`; Sugu always writes it.
- librime compares source timestamps in whole seconds, so Sugu deletes the
  compiled schema whenever it rewrites the source.

## D-015 · Pinned downloads; grammar model opt-in (2026-10-20)
- Each download is pinned to a URL and SHA-256 reviewed for the release:
  wanxiang `LTS` grammar model (CC-BY-4.0), rime-ice `2026.06.30`
  `cn_dicts.zip` (GPL-3.0, never bundled, user-initiated only), zenz-v3.1
  small Q5_K_M at a fixed Hugging Face revision (CC-BY-SA-4.0). A moving
  upstream file fails verification instead of installing unreviewed data.
- The grammar model is an optional download (ADR 0002 d4), on once
  installed. Measured with `sugu-bench --grammar` on the 50-sentence set:
  Chinese top-1 90% → 94% and characters 98.3% → 99.0% (it fixes 调/条,
  大雪/大学, 的/得); keystroke p99 3.5 → 3.7 ms with a warm page cache;
  footprint 58 → 59 MB, while resident grows ~220 MB of clean, evictable
  pages of the 398 MB file. The gain is real but the file is too large to
  bundle, so it stays a download.

## D-016 · Folder sync (2026-10-20)
- Each Mac writes only `<random id>.sugudict` in the chosen folder and reads
  the others, so no file has two writers. A per-file watermark (newest use
  already merged) keeps words deleted here from returning from an older
  copy. User words always sync; learned words only when the user opts in
  (ADR 0003 d24). Settings move by explicit export/import, not sync.

## D-017 · AppKit only (2026-10-20)
- At the owner's direction, no SwiftUI anywhere. Settings panes are
  NSGridView forms (right-aligned labels, standard controls) built by a
  small `SettingsForm` helper; lists are NSTableViews with the standard
  add/remove control.

## D-018 · Benchmark as the accuracy and latency gate (2026-10-20)
- `sugu-bench` drives `InputSession` with the real engines one key at a
  time, as the shell does, over `Bench/zh.tsv` and `Bench/ja.tsv` (original
  sentences, Apache-2.0). It reports top-1, first-page and character
  accuracy, keystroke and conversion percentiles, and memory; `--check`
  fails when a budget is exceeded, for CI.
- Seed results: Chinese top-1 90%, keystroke p99 3.4 ms; Japanese top-1
  76%, keystroke p99 ~4 ms, conversion p99 3.8 ms; footprint 60 MB.
- Japanese latency was 18.7 ms p99 because the emoji text replacer was
  rebuilt (reading its file) on every converter request; it is built once.
- Zenzai (zenz-v3.1 small) raises Japanese top-1 to 80% at +60 MB footprint
  (resident 270 MB) and ~2× keystroke time, so it stays experimental and
  opt-in (D-007).
- The candidate window's draw budget is checked by the app binary itself:
  `Sugu --measure-draw` lays out and draws full Chinese, Japanese and Latin
  pages offscreen in both appearances and three styles, and fails when p99
  reaches 16 ms. It runs in `scripts/ci.sh` after the Release build;
  measured p99 1.2 ms (the first draw, loading fonts, takes ~12 ms).

## D-019 · CI runs on demand while the repository is private (2026-10-20)
- `scripts/ci.sh` is the single full check (dependencies, Release build,
  package tests, `sugu-bench --check`); `.github/workflows/ci.yml` runs it
  on `workflow_dispatch` only, because macOS runner minutes are billed for
  private repositories. Adding `push`/`pull_request` triggers turns it on
  for every change. Native dependencies and data are cached by the hash of
  the scripts and versions that produce them.

## D-020 · Distribution and updates (2026-10-20)
- `scripts/release.sh` builds the release from the owner's credentials:
  Developer ID–signed app, a notarized, stapled `.pkg` that installs into
  `/Library/Input Methods` (component not relocatable), and a notarized
  `.zip` signed with Sparkle's EdDSA key plus `appcast.xml`, all in `dist/`.
  Nothing is uploaded; the appcast and archive go to the GitHub release that
  `SUFeedURL` points at.
- The package's postinstall stops a running Sugu and runs
  `Sugu --register` as the console user, which registers, enables and
  selects the input source (`TISRegisterInputSource`, `TISEnableInputSource`,
  `TISSelectInputSource`), so it is in use when the installer finishes.
  It selects only on a first installation; an upgrade leaves the input
  source the user has chosen.
- Sparkle 2.10.0 lives in the `SuguUpdates` package target, so Xcode and
  SwiftPM resolve one dependency graph and agree on `Package.resolved`.
  The public key is a build setting set only by the release script; builds
  without it never start the updater. System profiling is off in
  Info.plist and in the delegate. Automatic checks default on (update checks
  are allowed traffic, ADR 0002 d12), automatic installs off; both are in
  Advanced settings.
- `scripts/install-dev.sh` installs a build into `~/Library/Input Methods`
  for development; it is never run by automation here.

## D-021 · Cross-language names and script per app (2026-10-20)
- Japanese kanji forms are a Chinese script: an OpenCC chain (simplified →
  traditional → JPVariants, generated as `s2jp.json`) that librime applies
  like the other scripts, so `dongjing` gives 東京 and `hengbin` 横浜.
- Romaji gives Chinese forms only for words AzooKey tags as proper nouns
  (person, place, organization classes), inserted right after the name on
  the first page and only when Chinese is enabled; general vocabulary is
  left alone because its Chinese form is often a different word.
- Sugu's own candidates (learned, computed, Chinese forms) go through the
  same OpenCC chain in-process (`ScriptConverter`), so they match the
  script librime outputs.
- An app rule may choose its own script; the session applies it on focus.

## D-022 · Document vocabulary (2026-10-20)
- Off by default. When on, up to 2,000 characters on each side of the caret
  are read once when the field gains focus, plus what is committed during
  focus, and kept in memory only. Its words get the same reranking as the
  left context (same length as the engine's first choice, within the first
  ten).
- The engines' own left context stays at 200 characters before the caret,
  so a long document does not slow conversion; reading happens at focus,
  not on the keystroke path, and never in secure input or excluded apps.
- Learned words still come first: they are the user's own choices.

## D-023 · Built-in input method comparison deferred (2026-10-20)
- ADR 0003 d21 asks for the built-in input methods to be scored on the
  bench sets. macOS exposes no conversion API for them: they only convert
  keys delivered to the frontmost app's key window, so scoring them means
  synthesized typing in the foreground, which would take over the owner's
  screen during this build. It is left open until it can run on a machine
  nobody is using; the bench sets and scoring are ready for it.


## D-024 · Maintainability track (2026-10-20)
- An advisor review of the whole repository found the app/package split and
  the `CompositionEngine`/`InputClient` seams sound, and named where a
  maintainer would struggle: `InputSession` branching on mode and engine
  type, its size, `EngineHub`/`ModelLibrary` living in the session module,
  untested clause navigation and app-target logic, and duplicated helpers.
  These are worked as todo §8, each change behind the existing tests.
- Pause-gated candidates (ADR 0003 d16) show after a pause only. "When the
  top candidate is uncertain" needs a confidence the engines do not expose
  (librime and AzooKey return ranked lists without comparable scores), so
  that trigger is not built.

## D-025 · Chinese learned words in librime's sentences (2026-10-20)
- Before, a Chinese learned word surfaced only when its reading was typed
  alone or as a prefix (D-003): a name taught once never appeared inside a
  longer sentence. Now the store's Chinese words (2–5 Han characters) are
  written into librime's user dictionary, which takes part in sentence
  making, and librime opens it read-only (`db_class: stabledb`), so it
  never learns on its own and the store stays the one place words live.
- Codes are the toneless syllables the user typed. `sugu-tool build-data`
  adds one weight-0 entry per toneless syllable (`sugu_syllables`, imported
  last so a repeat of a wanxiang entry is the copy dropped) so the
  syllabary holds them; typed keys are read back as syllables by running
  the schema's own spelling rules in Swift (`SpellingAlgebra`,
  `PinyinDecoder`), so words learned in double pinyin, with typo spellings,
  or imported as full pinyin all decode. Readings with abbreviations do
  not, and those words keep the exact-reading path only.
- librime scores a read-only phrase from its commit count alone; 2×10⁸ per
  use places a word used once among common words, counted up to 9 uses
  (librime adds one in 32-bit arithmetic and changes formula at 2×10⁹). One-character words are
  left out so one choice does not reorder a syllable in every sentence.
- The file is rewritten at launch and 2 s after changes settle, off the
  main thread and in order, whether or not Chinese is loaded, so cleared
  or expired words leave it too. The Chinese session is reopened between
  compositions (about 1 ms) until it has read the latest file:
  librime shares one open dictionary among sessions and frees it with the
  last, so `RimeEngine` now closes its session when it goes away.
- librime parses the text file on the main thread when a session opens,
  about 1 ms per thousand lines (20,000 words: 24 ms). The file holds the
  best 3,000 words by the store's score (pinned, user words, then use);
  the rest still match by their whole reading. The session opens right
  after deployment rather than on the first key.
- `sugu-bench` measures it (`Bench/zh-learned.tsv`): sentences using ten
  taught names and terms go from 0% to 83% top-1, and the main Chinese set
  stays at 90% after learning. Cost: Chinese keystroke p99 3.45 → ~3.8 ms,
  about half from the user-dictionary lookup and half from the toneless
  syllables; the budget is 5 ms. With the grammar model (D-015) the
  taught-word sentences reach 92%; librime scores learned words in a
  sentence like any other.

## D-026 · Apostrophes in learned readings (2026-10-20)
- Readings were stored without apostrophes, so a word picked after typing
  `xi'an` (西安) was offered first for `xian`, where the user means 先 or
  现 — the behavior of the built-in input method this project wants to
  avoid. A learned reading now keeps an apostrophe where pinyin needs one
  to split differently: before a syllable starting with a, o or e, or
  between n and g (`fan'gan`). Elsewhere (`ni'hao`) it is dropped, so it
  does not split one word's uses.
- Typing with an apostrophe also finds, after the exact matches, words
  stored without it whose letters split into a syllable per character in
  one way only, breaking where the apostrophes do (`PinyinSyllabary`): 西安
  under `xian` for `xi'an`, but not 先, not 先去 under `xianqu` for
  `xi'anqu`, and not 方案 under `fangan` for `fan'gan` (either split). The
  vowelless interjections m, n, ng are not syllables here, or `xian` would
  also read `xia n`. Added and imported words drop every apostrophe, since
  import formats separate each syllable.
- Left as they are after review: a word picked for `xi'an` and for `xian`
  is two entries, one per reading, like any word typed two ways; readings
  typed in double pinyin get the same rule though their keys are not
  pinyin letters, which only matters if the user types an apostrophe
  there, and no apostrophe ever changes a double-pinyin split.
- Words whose reading kept an apostrophe stay out of librime's user
  dictionary (D-025): librime reads `xian` both ways and would offer them
  for the bare keys. Sugu's exact-reading match serves them.


## D-027 · Keys typed before Chinese is ready stay in the composition (2026-10-20)
- librime deploys in the background: ~35 ms from the bundled build, seconds
  after a scheme or dictionary change, or with rime-ice. Until then the hub
  had no Chinese engine, and the session let letters through to the
  document as Latin text; after a failed deployment that went on until the
  settings changed, with nothing shown anywhere.
- Now letters typed in that window go to a `LoadingEngine` in the session:
  marked text without candidates. The hub calls `onEngineReady` when
  librime is up, and the session hands the letters over as a new
  composition, so `nihao` typed during deployment shows 你好 with nothing
  lost, with the caret where it was. Space waits for librime rather than
  committing letters; Return commits them as typed, as always, and once
  setup has failed Space does too. Nothing typed this way is learned.
- The session asks the hub to `prepare` a mode on a mode change and on
  focus, so deployment (Chinese) and converter creation (Japanese, ~20 ms)
  happen there rather than on the first key.
- A failed deployment is retried, not abandoned: after 5 s, doubling to
  ten minutes, on the next use of Chinese, each retry rebuilding librime's
  compiled copy from the bundled data. Settings › Chinese shows a Status
  row (Failed, Try Again) only while it is failing.
- Review fixes: a failed deployment leaves librime not ready (it had
  reported ready on the previous schema with its sessions gone), and a
  deployment that finishes after settings changed makes no engine for the
  old schema, going straight to the next deployment.

## D-028 · Control keys inside a composition (2026-10-20)
- Any ⌃ or ⌘ key committed the composition and went to the app, so ⌃H or
  ⌃A in a composition fired an app command over freshly committed text,
  and Kotoeri's ⌃J/⌃K did nothing Japanese.
- While composing, the text system's Emacs keys act on the composition
  (⌃H ⌃D delete, ⌃A ⌃E ⌃B ⌃F move, ⌃B ⌃F moving the focused clause while
  converting), ⌃N ⌃P choose the next and previous candidate, ⌃G cancels,
  ⌃M commits, and Apple's Japanese input method keys ⌃J ⌃K ⌃; ⌃L ⌃: are
  F6–F10 (hiragana, katakana, half-width katakana, full-width and plain
  romaji; F9 and F10 also in Chinese). ⌃[ is Escape with or without a
  composition, so vim's English rule (ADR 0003 d3) sees it.
- They are read from the layout's characters, as the text system reads
  them. Without a composition, other ⌃ keys stay the app's; ⌘ always is.

## D-029 · A damaged learned store is set aside (2026-10-20)
- The store opened with `try?`: a damaged `learned.sqlite` (power loss
  mid-write, a bad sector, a partial copy from sync tools) left Sugu with
  no store for good — no learning, no Chinese user dictionary, no import or
  sync — with nothing to show why.
- Opening now runs SQLite's `quick_check`. On corruption (`SQLITE_CORRUPT`,
  `SQLITE_NOTADB`, or a failed check) the file and its journal files are
  renamed `learned.sqlite.damaged-<date>` in the data folder (Advanced ›
  Show Data Folder) and a fresh store opens. Other failures — locked, not
  yet readable before the first unlock, disk full — are not corruption and
  never move the file.

## D-030 · Diagnostics in the unified log, exported by the user (2026-10-20)
- Sugu logged nothing, so "it stopped working" left the user and the
  maintainer with nothing to go on. `SuguCore.Log` gives one `Logger` per
  area (app, engines, input, learning, sync, downloads) under the app's
  bundle identifier. Logged: launch, engine readiness and timings, failed
  deployments and their retry, secure input turning on and off, a damaged
  or unavailable store, sync and download failures. Never logged:
  readings, candidates, learned words, or document text.
- Settings › Advanced › Diagnostics › Export… saves a text file with the
  version, macOS version, the settings file, and this run's Sugu log
  entries (`OSLogStore`, current process). It is made only on that click
  and saved where the user picks; Sugu sends nothing (ADR 0003, zero
  telemetry).

## D-031 · Secure input counts only in the app that holds it (2026-10-20)
- Sugu passed every key through while `IsSecureEventInputEnabled()` was
  true. That flag is global: an app in the background that leaves secure
  input on (Terminal's Secure Keyboard Entry, a password manager), or the
  login window while the screen is locked, turned Sugu into plain English in
  every app, with nothing to show why.
- The window server names the process holding secure input
  (`kCGSSessionSecureInputPID` in `CGSessionCopyCurrentDictionary()`).
  Sugu sets secure input aside only when that holder cannot own the field
  being typed in: the login window, or another regular app that is neither
  the client nor active. Anything else — a helper process such as a
  browser's web content, an unreadable holder — stays secure. Reading it costs ~70 µs and happens only while secure input is
  on. The check runs before a new field is attached, so a secure field's
  text is never read for vocabulary.

## D-032 · Zenzai loads off the main thread (2026-10-20)
- AzooKey loads the Zenzai model on the first conversion that asks for
  it, on the thread converting — Sugu's main thread, inside a keystroke.
  Measured: 8.6 s the first time after the model is installed (llama.cpp
  compiles its Metal shaders), ~60 ms in later processes. The app being
  typed in froze for that long.
- Japanese now starts without Zenzai. The hub loads a second converter with
  the model in a detached task (one throwaway conversion), and the engine
  adopts it between compositions, re-importing the user words; from then on
  conversions use Zenzai. A model that fails to load leaves Zenzai off and
  is logged, rather than AzooKey retrying the load at every conversion. A
  model installed or removed is loaded afresh, including one replaced while
  a load was running.
- Measured with `sugu-bench --zenzai` (which now waits for the load):
  Japanese top-1 90% (78% without), keystroke p99 ~20 ms, resident 270 MB.
  Zenzai stays experimental and outside the default-configuration budgets.
- Known and unchanged by this: with Zenzai on, learned Japanese words lose
  to the model's own reading in sentences (taught names 0% → 0%, against
  30% → 90% without it). Zenzai reranks AzooKey's lattice by the language
  model and rewrites the result, and the dynamic user dictionary does not
  bind it.

## D-033 · Kana input maps physical keys (2026-10-20)
- Kana input was selectable but typed the Latin layout's letters, so
  AzooKey's direct input received `asdf`. The session now looks up the
  kana for the key's virtual key code (`KanaLayout`), so the Latin layout
  in use does not matter.
- JIS keyboards use the JIS kana layout. ANSI and ISO keyboards use the
  arrangement the Mac's Japanese input method uses there, which moves け,
  む, ろ, ー, the voicing marks and 「」 to keys an ANSI keyboard has (the
  same table as AzooKey's `defaultKanaUS`). The shell reads the keyboard
  type from `KBGetLayoutType(LMGetKbdType())` per key.
- ゛ and ゜ join the kana before the caret when it takes them (か゛ → が,
  は゜ → ぱ, う゛ → ゔ); otherwise they are typed as they are. AzooKey's
  engine does the joining on its kana, since what the field shows (live
  conversion, fixed clauses) is not kana.

## D-034 · First launch follows the preferred languages (2026-10-20)
- Every install started in Chinese, so someone who types Japanese met
  pinyin first. A first launch now takes its defaults from
  `Locale.preferredLanguages`: the first Chinese or Japanese language in
  the list leads the modes, so a Japanese reader starts in Japanese with
  Chinese still on; Taiwan, Hong Kong and Macau, or a `Hant` script, set
  the Chinese characters. Without either language the defaults are as
  before.
- The seeded settings are saved at once, so changing the system language
  later does not move them.
- The order of `enabledModes` is the user's: the session starts in the
  first, ⌃⇧Space and the Input menu follow it, the General pane lists the
  modes in it, and a mode turned back on takes its place for the
  preferred languages, as on first launch.

## D-035 · Traditional Chinese punctuation (2026-10-20)
- Quotes followed Simplified usage whatever the characters. With
  Traditional characters (any of the three Traditional choices, globally or
  per app) `"` types 「」 and `'` types 『』, as Taiwan and Hong Kong write
  them, and `$` types ＄ rather than ￥. Simplified and Japanese forms
  keep “” ‘’ and ￥.

## D-036 · More in the Input menu (2026-10-20)
- The Input menu gains the settings people change while typing rather than
  in Settings: Chinese Characters (a submenu of the five scripts, shown
  when Chinese is on), Learn from Typing (the Learning pane's switch), and
  Check for Updates… in builds that can update. Each edits the same
  preference as Settings, so both stay in step.
- The script submenu sets the global choice; an app with its own script
  rule keeps it.
- IMK passes the chosen item to `performMenuAction`, submenu items
  included; items are told apart by tag. Not yet seen in a live menu bar
  (no foreground testing here).

## D-037 · Long candidates and hover (2026-10-20)
- A candidate is drawn at most 20 font-sizes wide and shortened in the
  middle beyond that (`CTLineCreateTruncatedLine`), so a long sentence or
  learned phrase no longer stretches the window across the screen; the
  start and end stay visible. VoiceOver still reads the whole candidate.
- The row under the pointer takes the unemphasized selection colour, so a
  click's target is visible before it is made. The tracking area is
  active always, since the panel never becomes key; the hover clears when
  the page changes.
- `--measure-draw` adds a page with an over-long candidate: p99 1.0 ms.

## D-038 · Undo after commit is not re-verified (2026-10-20)
- Considered: after ⌃⌫ deletes the last commit, read the field again and
  restore the composition only if the text is gone, for hosts that ignore
  `replacementRange`. Declined. Browsers and Electron apps report the
  selection asynchronously, so an immediate re-read sees the old text even
  when the deletion happened; giving up then would drop the commit from
  the field without restoring the composition, the one outcome worse than
  a duplicate.
- Undo already runs only where the field can be read and the text before
  the caret is exactly the commit (D-012); hosts that cannot be read get
  ⌃⌫ as a plain key.

## D-039 · Japanese live conversion, as a preference (2026-10-20)
- With Use live conversion on (Settings › Japanese, off by default), the
  composition shows the converter's best sentence instead of kana while
  typing, as the Mac's Japanese input method does by default; romaji not
  yet kana stays as typed at the end (私は学生ですk). Enter, focus loss or
  a key that ends the composition commits what is shown; Space opens
  clause conversion on the same sentence; with the caret moved inside the
  input, the kana being edited is shown.
- Off by default: Sugu's Japanese shows kana with predictions and
  converts on Space (D-011). With live conversion the predictions still
  list below the field.
- A live commit is one clause (reading → sentence), learned only when
  short enough to be a word, as an unedited Space-and-Enter commit is.
- Cost: one more conversion per key. `sugu-bench --live-conversion`:
  Japanese keystroke p99 3.7 ms (2.8 ms without), within the 5 ms budget;
  top-1 moved 78% → 76% on one sentence (十分 → 10分), from AzooKey's
  lattice cache being reused across the extra requests.

## D-040 · Zhuyin deferred past v1 (2026-10-20)
- wanxiang's algebra has no Zhuyin section, and rime-bopomofo is LGPL, so
  the spelling rules would be Sugu's own (pinyin → Zhuyin keys on the
  standard layout, tone keys 3 4 6 7). The rules are the small part.
- Zhuyin also changes the composition model, not just the spelling:
  digits and `- ; , . /` become syllable keys, so number keys cannot pick
  live candidates; tone keys end syllables and narrow them; Space types
  the first tone; and Taiwanese users expect the field to show the whole
  converted sentence with ↓ or Space opening candidates for the character
  at the caret (Apple Zhuyin, Microsoft Bopomofo). Learned readings,
  `PinyinDecoder`, the Learning pane's reading column and the bench would
  each need a Zhuyin form.
- Shipping the spelling without that model would type Zhuyin keys into an
  input method built for pinyin. Deferred until it can be done whole, as
  its own mode of Chinese composition with its own test set.

## D-041 · Shift taps: not Shift-clicks; typed letters stay letters (2026-10-20)
- IMK sends an input method key and modifier events only, so Shift
  pressed for a Shift-click or Shift-scroll looked like a tap and switched
  to English. The tap now also needs no click, drag or scroll since Shift
  went down, read from the window server
  (`CGEventSource.secondsSinceLastEventType`, no permission needed).
- A Shift tap with a Chinese composition of plain letters commits those
  letters, then switches to English: someone who tapped Shift after
  `hello` meant English, as Sogou, Microsoft Pinyin and Rime's
  `commit_code` treat it. A composition with a choice in it, an F-key
  form, or Japanese commits as it shows, as before.

## D-042 · Punctuation width from what Sugu typed (2026-10-20)
- Automatic punctuation width read the character before the caret from
  the field on every punctuation key. Browsers and Electron apps answer
  late (D-038) and some fields cannot be read, so `3.14` became `3。14`
  and 我 typed fast was taken as a Latin letter.
- The session now keeps the character it last committed or let through to
  the app and trusts it over the field. It forgets it when a key the app
  handles moves the caret or edits (arrows, ⌫, shortcuts), on focus
  change, and when the window server reports a click since the last key;
  then the field is read as before.

## D-043 · Apple language models, built (2026-10-20)
- ADR 0004 as built. `LanguageAssistant` (SuguCore) is the seam; the
  session never imports FoundationModels. `AppleLanguageAssistant` (app
  target, macOS 27, FoundationModels weak-linked) picks the models for the
  level — Private Cloud Compute then the on-device model, or the
  on-device model alone — and asks for typed results (`@Generable`).
- Selected text: Input menu › Translate Selection (Chinese, Japanese,
  English) and Rewrite Selection (Fix Grammar, More Formal, More Casual,
  Shorter), shown when the level and the switch allow it and the field can
  be read. The selection becomes a `RevisionEngine` composition whose first
  candidate is the text itself, so Space, Enter, focus loss, Esc and any
  other key leave it unchanged; results join as further candidates.
- Long compositions (≥ 8 characters of reading, full pinyin or kana) ask
  once per reading, 450 ms after the last key, for a conversion and the
  asked translations; they join after the engine's first candidate. A
  chosen conversion is learned; a translation is not.
- Never in secure input or in apps excluded from learning.
- Signing: the entitlement needs a profile for
  `com.zheng-she.inputmethod.Sugu` (the bundle ID moved from
  `io.github.pythonshe…` for the developer account; it must keep
  `.inputmethod.`). `Config/Local.xcconfig` signs development builds with
  the team; `--probe-language-model` checks both models offscreen with
  fixed text. First run on this Mac: entitlement present, both models
  report not ready (`modelNotReady`, `systemNotReady`).

## D-044 · Turning Zenzai off frees the model (2026-10-20)
- The Japanese engine remembers which Zenzai model its converter loaded.
  When the configuration no longer names it (Zenzai turned off, model
  removed), the engine swaps in a plain converter and re-imports the user
  words — at once if nothing is being composed, otherwise when the
  composition ends. The hub forgets the loaded model on disable, so turning
  it back on loads it again off the main thread (D-032).
- Tested against a real model only when `SUGU_ZENZAI_MODEL` names one.

## D-045 · Private Cloud Compute in release builds (2026-10-20)
- The entitlement is restricted, so a build may carry it only with a
  provisioning profile that grants it; signed without one, macOS refuses
  to launch the app. `scripts/release.sh` adds it only when
  `DEVELOPER_ID_PROFILE` names an installed Developer ID profile with the
  capability, and then checks the signed app has it. Otherwise the release
  has no entitlement, and the Private Cloud Compute level falls back to
  the on-device model.
- Signing settings go through `SUGU_ENTITLEMENTS` and `SUGU_PROFILE` in
  `Config/Signing.xcconfig`, which only the app target includes: passed
  as `CODE_SIGN_ENTITLEMENTS` on the command line they also reached the
  Swift package targets and failed the build. Command-line values override
  a developer's `Config/Local.xcconfig`.

## D-046 · Model suggestions belong to their composition (2026-10-20)
- Review of D-043. A request waiting out the pause is asked again before
  it is sent — field, settings and composition — so focus moving to a
  password field or a no-learn app within the pause sends nothing.
- Suggestions and pending requests end with the composition, on focus
  change and on any settings change; model candidates are merged only
  while the level and the field allow them. A reading typed away and back
  before the pause is still asked once.
- Model errors are logged by kind only: a refusal's description can quote
  the prompt.

## D-047 · Character language model for Japanese ranking (2026-10-20)
- ADR 0005 as built. `SuguLM` holds `CharacterLanguageModel` (reader) and
  `CharacterLanguageModelBuilder`: interpolated Kneser-Ney 5-grams over
  NFKC scalars, one discount per order from the counts of counts, pruned
  (≥ 3 characters, seen once) with backoff weights renormalized so each
  context still sums to one (tested). Contexts made only of start markers
  are stored for their backoff weights. Builds are byte-identical.
- File: sorted 64-bit FNV-1a keys, then Int16 thousandths of log
  probability and backoff; binary search over the memory-mapped file. No
  marisa: one lookup structure Sugu owns, no new dependency.
- `AzooKeyEngine.ranked` reorders at most the first five whole-input
  results by AzooKey's value plus the model's natural log probability
  (weight 1: any weight from 0.1 to 100 gave the same picks in the
  prototype) after the left context and fixed clauses. Used for the best
  sentence, the text after a chosen clause, and live conversion. When the
  model picked a different sentence than AzooKey, the clause list puts the
  clause that sentence wrote first; otherwise AzooKey's clause order
  stands, which is better than its sentence order (moving it always cost
  6 points).
- Corpus: OPUS's versioned Tatoeba snapshot, since Tatoeba's own exports
  are replaced weekly. The bench sentences are left out at build time.
- Measured: Japanese top-1 78% → 86%, characters 95.7% → 97.5%, learned
  names 90% → 100% after learning, keystroke p99 unchanged (~2.7 ms).
  Remaining misses are sentences AzooKey does not propose (弾き, 開いて),
  numerals (十分 → 10分) and orthography (宜しく, 子ども).
- Also found: AzooKey bundles its Zenz tokenizer (CC BY-SA 4.0) as a
  resource; it is now attributed in the notices.

## D-048 · Bundled Chinese grammar from Tatoeba (2026-10-20)
- librime offers one whole sentence, so the Japanese reranking has nothing
  to choose from in Chinese. octagram does score sentences: it adds
  `collocation_penalty` (-14) to the log value of the longest collocation
  of context and word it finds, and compares that with
  `non_collocation_penalty` (-6). Its `.gram` keys are character strings
  (and `word$` for sentence ends) with a value.
- `sugu-tool build-grammar` counts collocations of 2–6 characters and
  endings of 1–5 in Tatoeba's Mandarin sentences after OpenCC t2s, keeps
  those seen twice, scales counts by 100 and runs octagram's own
  `build_grammar`. Scale on `Bench/zh.tsv`: 30 → 92%, 100 and 300 → 94%,
  1000 → 92%, 3000 → 90%, 30000 → 88%; 100 also keeps learned words at
  83% and the main set after learning at 94%.
- Named `sugu-zh-hans` in the shared data directory. librime resolves a
  `.gram` from the user directory first; the download is
  `wanxiang-lts-zh-hans` there, so the schema names whichever applies and
  turning the download off returns to the bundled one. The setting now
  says "large grammar model".
- Bench sentences are left out; builds are identical (octagram sorts its
  input).

## D-049 · The Chinese keystroke tail is librime's (2026-10-20)
- Measured per key on the Chinese bench: librime's `process_key` is
  0.56 ms on average and 4–6 ms for the slowest keys, all past 25 letters
  of a single composition; Sugu's refresh and session work add about
  0.1 ms. The first run after rebuilding `Data/` also showed 20–120 ms keys
  from cold pages of the memory-mapped tables, which a running input
  method pays once.
- Variants, alternated four times: `enable_completion: false` and
  `max_homophones: 4` move the p99 by 0.1–0.3 ms with the same accuracy.
  Not worth narrowing what librime considers; settings unchanged. Bench
  p99 runs 3.9–4.2 ms on an idle machine and higher under load.

## D-050 · Bundled Chinese grammar withdrawn; bench doubled (2026-10-20)
- The bench gained 51 Japanese and 50 Chinese original sentences, aimed at
  homophones and collocations (書く/描く, 暑い/熱い/厚い, 会う/合う, 取钱,
  晚饭). The new sentences are left out of the corpora like the others.
- Japanese holds: top-1 78% → 85% with the character model over 101
  sentences, characters 96.3% → 97.8%.
- Chinese does not: on 100 sentences the D-048 grammar gives 91% against
  92% without it, and 92% at best (scale 10, where it does almost
  nothing). It fixes 大雪 and 大家的 and breaks 老师, 医生, 衣服 for
  frequent strings like 老是 and 一生. The scale was fitted to 50
  sentences. Reverted: no bundled grammar, the setting is again "Use the
  grammar model", and `build-grammar` is gone.
- Lesson kept for later tuning: fit on one half of the bench, confirm on
  the other.

## D-051 · Live conversion trapped after Esc from a conversion (2026-10-20)
- With live conversion on, `sugu-bench --live-conversion` ended on a trap
  in three runs of four, on Esc after converting さかなをつりにいきます: an
  index out of range in AzooKey's `kana2lattice_no_change`. Which sentence
  traps depends on the process's hash seed, so the committed build did it
  too.
- Cause: conversion asks the converter for the first clause (さかなを), so its
  cached lattice shrinks to that clause; Esc asks for the whole input
  again, which AzooKey grows back from the clause's lattice, and the
  request after it (the same input, for live conversion) reuses a lattice
  whose nodes no longer match their scores. Backspace and retyping, which
  change one kana at a time, never trapped.
- Fix: the lattice is dropped when a conversion ends (Esc, or typing on
  after it), so typing converts afresh from there. Converting clauses on a
  second, always-fresh converter also worked, but changed results (a fresh
  conversion is not the incremental one: a learned name came out as レン)
  and cost 3 ms more per Space.

## D-052 · Respelling words the converter did not propose (2026-10-20)
- Weight of the model against AzooKey's cost, fitted on the first 50
  sentences and checked on the other 51: 0.5–5 all give 43/50; on the
  held-out half 1 gives 43, 3 and 5 give 44. Within noise; the weight
  stays 1.
- More text does not help either: Tatoeba plus Japanese Wikinews (CC BY,
  34,000 sentences) misses exactly the same sentences.
- What does: half the misses are sentences AzooKey never offers, one word
  away from its best (行きが for 雪が). `HomophoneRefiner` looks up the
  other spellings of each content word's reading (two to six kana, not
  particles or auxiliaries) with a separate converter on the same
  dictionary, prices a swap by the word costs and the connection costs
  on both sides, and keeps it when that plus the model's score is
  higher. A swap may be several dictionary words (効き+まし+た for
  聞きました). Spellings are cached per reading for the session.
- Spans that spell one of the user's words are left alone: AzooKey can
  write a learned name out of pieces, and respelling a piece (蓮 → 連)
  broke it.
- When the respelled first clause is not among AzooKey's clause
  candidates, the clause of the same length is written as the sentence
  writes it and put first.
- Measured: top-1 85% → 89% (first 50: 43 → 45, other 51: 43 → 45),
  characters 97.8% → 98.5%, learned names 100%. Fixed: 雪が, 息が, 何時に,
  行って, 開いて. Not fixed: 熱い/厚い, 速い, 効き, 描く, where the
  model has no evidence either way.
- Cost: a lookup is a small conversion, 0.3–1 ms, because AzooKey reads
  dictionary files from disk for each one. Space conversion went from
  1.3 to 2.7 ms at the median and 2.7 to 6.0 ms at p99 on the bench,
  where most words are new to the cache; typing is unchanged, and with
  live conversion keystroke p99 is 4.4 ms.

## D-053 · Respelling librime's Chinese sentences (2026-10-20)
- librime returns one sentence, so there is nothing to rerank; the misses
  are one word away from it (吃完饭 for 吃晚饭, 药失望 for 钥匙忘). The
  sentence is split into words of a list built from wanxiang's zi and
  jichu dictionaries (every character, and words of two or three
  syllables weighted 1,000 or more: 121 thousand entries), by the
  likeliest split for the syllables the typed keys decode to. Each span
  of up to three syllables may become another spelling of them, as one
  listed word or several (the six likeliest per reading, at most 400
  spellings), scored by the character model on the span and the
  characters after it that it conditions, plus 0.3 times the change in
  the list's log probability; it must beat librime's words by 4.
- Fitted in a simulation on the first 50 bench sentences, then checked
  on 50 more and on 50 written for the check. In the bench: 45 → 48,
  47 → 49, 44 → 49 (91% → 97%), no sentence broken, learned words
  83% → 92% (林知夏的生日是). Raw dictionary weights summed across words
  broke about 40 sentences, and a greedy split broke 上市; log
  probabilities and the likeliest split fixed both. Left: 游泳, 大雪,
  咸, 老师, where the model has no evidence.
- The respelled sentence is a candidate ahead of librime's, which keep
  their order one index down; choosing it commits it and clears
  librime's composition. Not after a partial selection; other scripts
  follow in D-054.
- The Chinese model is now built from Tatoeba's Mandarin sentences
  converted to Simplified with OpenCC, the bench sentences left out.
- Memory: as strings the list took 45 MB; it is read in one streaming
  pass into 64-bit hashed keys and one array of the kept spellings,
  11 MB, and the respeller's caches are keyed by hash too. Footprint in
  the bench 91 → 104 MB, resident 198 MB of which most is clean mapped
  dictionary and model pages; keystroke p50 0.2 → 0.7 ms, p99 3.9 → 4.0
  ms.

## D-054 · Respelling in Traditional and Japanese forms (2026-10-20)
- librime writes the sentence through its OpenCC filter, and the model
  and word list are Simplified. The sentence is converted to Simplified
  with the tables the filters use, respelled, and converted back; only
  the characters the respelling changed take the converted form, so the
  rest keeps librime's (喫 stays 喫 where a round trip writes 吃). When
  a conversion changes the length, the sentence is left as it is.
- Learned words are compared in Simplified too, whatever script they
  were committed in.

## D-055 · Words joined to their particle; model order and pruning (2026-10-20)
- AzooKey can hand back a particle and the next word as one element
  (を引き, は足, が早い), with the particle's class on the left. The
  refiner skipped them as particles, which is why 弾きます and 速い never
  came up. Such an element is now split into the particle and the
  word's own dictionary entry, looked up by the rest of the reading.
- When no entry ends in the element's class (引き is found as a noun,
  the sentence used the verb's stem), the noun stands in and is compared
  only with spellings of its own classes. Comparing it with all of them
  let verb spellings win on the connection to ます alone: 送ります →
  贈ります and a learned 勤めて → 努めて.
- Japanese top-1 89% → 90% (弾きます), learned words 100%. Space
  conversion p50 2.7 → 3.3 ms, p99 5.7 ms, from the extra lookups.
- Model shape re-checked on both languages: order 4 and 6 and no pruning
  of single n-grams. Order 4 loses two Japanese sentences, order 6
  loses one; without pruning Japanese gains one sentence for a model
  three times the size (46 MB, 22 MB for Chinese) and 50 MB more
  resident memory. Order 5 with pruning stays. Chinese is 97% in all
  five.

## D-056 · Respelling with fuzzy pinyin, and an engine made mid-load (2026-10-20)
- The key decoder gave the respeller only the readings that need the
  fewest derived spellings: with fuzzy pinyin, zi typed for 吃's chi is
  read as zi only, the sentence does not split into listed words, and
  nothing is respelled. Readings needing more derived spellings now
  follow, cheapest first, up to 16; learned-word tables keep the fewest
  only, so zangsan still stays zang san there.
- `sugu-bench --fuzzy-pinyin` turns every fuzzy rule on. Chinese top-1
  82% without the model, 85% with it. librime alone has a keystroke p99
  of 11 ms with all ten rules on: the budget is for the default
  configuration, and nobody needs all ten, but it is worth knowing.
- A Chinese engine created between librime becoming ready and the model
  finishing its load ran without respelling until the next restart; the
  load now attaches it to that engine.
- Checked and left: a respelled commit is learned as any librime
  sentence is (the whole commit, when short enough; librime does not
  learn on its own, D-003). Live conversion keeps the refiner on each
  keystroke: keystroke p99 4.6 ms, and the shown sentence stays the one
  Space would give.

## D-057 · Conversions after text that decides them (2026-10-20)
- Every ranking and respelling step reads the text before the caret, but
  the bench field showed none, so none of it was measured.
  `Bench/{zh,ja}-context.tsv` hold pairs that share a reading and differ
  by what came before (花束を贈ります, 資料を送ります; 一场大雪, 上大学).
  The bench types each with the field hidden and with it read, and the
  pairs' sentences are left out of the corpora like the others.
- First run: no difference at all in either language. Japanese: a
  conversion that is one clause showed the converter's own sentences,
  not the ranked ones, so the model never ranked a single word, with or
  without context. Fixed; a respelled sentence the converter also
  proposed moves up instead of appearing twice. Japanese context set 38%
  → 50% without the text before and 71% with it; main set 90% → 91%.
- Chinese: the model does prefer 大雪 after 一场 and 骑车 after 喜欢, by
  1.7–2.8, but respelling needs 4. A margin of 2 gives 55% with context
  and keeps 97% on the main set, by fixing two sentences and breaking
  two others (开机变快, 钥匙), with characters 99.4% → 99.0%; the
  margin stays at 4. Short Chinese words decided by context need a
  ranking of librime's whole-input candidates, not respelling.
- Left as the model's limits: 熱い after 熱湯を注いだ and 弾いて after ピアノ
  教室 sit beyond five characters.

## D-058 · One Chinese word after text that decides it (2026-10-20)
- When all that was typed is one listed word and text comes before it,
  another spelling needs a margin of 1 instead of 4. librime orders
  words by frequency alone; the text before is evidence it lacks. A
  smaller margin for whole sentences broke sentences (D-057); a word
  alone has only other words to lose to.
- Without text before, the margin stays 4: at a margin of 1 a lone
  youyong became 游泳 over librime's 有用, which is the model's taste for
  Tatoeba's sentences, not evidence.
- Chinese context pairs 45% → 60% with the text before, unchanged
  without it (the same misses); main set 97%, learned words 92%. 0.5
  gives the same as 1; 2 gives 55%. Left: 大雪 after 一场 gains 1.7 from
  the model but loses more than that on the word list's frequencies.

## D-059 · Choosing a clause kept its length for the next one (2026-10-20)
- Choosing a clause candidate during a conversion fixed it and focused
  the next clause at the chosen clause's length: after 今日は (three
  kana) the rest of 今日はいい天気ですね became いいて + 点機ですね. Moving
  the focus with the arrow keys already went to the best sentence's next
  clause; choosing now does the same. Found by a review of the language
  model work.

## D-060 · The same Japanese input never reaches the converter twice (2026-10-20)
- A fuzz run (`sugu-bench --fuzz`: random keys through the input session,
  checking caret, marked text, candidate pages and Return after each key)
  trapped in AzooKey's `kana2lattice_no_change` again, on ⇧→ after
  typing うぃ: the caret move asked for the same input as the key before.
  AzooKey takes an unchanged input as a cue to rebuild its results from
  the lattice it holds, which traps when that lattice grew from other
  input; D-051 removed one way to get there, not the cause.
- Fix: one converter and one request. Every request asks for predictions
  alike (when they are on), and an input equal to the last one takes the
  last result, so the no-change path is never reached. Conversion views
  (the sentence, clauses, the rest after a fixed clause) drop the
  predictions, which read further than the input.
- Rejected: a converter for predictions and one for conversions. It kept
  the converter growing key by key but converted Space from scratch, and
  a whole input converted at once prunes the paths that find learned
  words (星宮蓮 became 星宮連): learned words (ja) 100% → 90%, Space p50
  2.7 → 5.8 ms. Stopping the composition whenever the options changed
  put live conversion over the keystroke budget (p99 7.2 ms).
- After: 0 failures in 300 sessions per language for five seeds (also
  with live conversion, fuzzy pinyin, no predictions) under random hash
  seeds; Japanese 91%, learned words 100%, keystroke p99 2.3 ms (3.6 ms
  live). CI runs 200 fuzz sessions.

## D-061 · What the remaining context misses need (2026-10-20)
- Chinese pairs still missed with the text before them, by the model's
  log probability after the last four characters (chosen − librime's):
  游泳 +0.6 and 大雪 +1.7, lost to the word list's frequencies (0.3 ×
  −1.3 and −4.1); 誓言 −3.5, 共识 −1.4, 异议 −12.3, 试用 −2.9, 实用 −5.7,
  输血 −10.1, where the model has not seen the collocation at all
  (没有任何意义 is in Tatoeba, 没有任何异议 is not). No margin or weight
  fixes the second group.
- Japanese: 描く after 絵を gains 5.7 from the model but costs 13.1 in
  AzooKey's connections (描く is class 695, 書く 679, before のが好きです);
  効きました and 聞きました score the same (−28.27, −28.25).
- So the model needs more text, not tuning. The candidate found is the
  Leipzig Corpora Collection (download corpora under CC BY by its terms
  page, as reported by search; the site refuses automated reading, so
  not verified here): zho-cn web 2015, 1 M sentences, 427 MB. Its
  Wikipedia corpora are out (share-alike sources). Left for the owner:
  whether web-crawled sentences under CC BY may train a bundled model.

## D-062 · The candidate window follows the focused clause (2026-10-20)
- The window opened under the composition's first character whatever
  the candidates were for: converting the third clause of a long
  sentence, or a Chinese composition after librime confirmed words, left
  it far from the text it offered to replace, and on a wrapped line on
  the line before. Apple's input methods place it under the focused
  clause.
- `SessionDisplay.candidateAnchor` names the character: the focused
  clause, or else the first segment that is not fixed (the text after
  fixed clauses, librime's active segment). The field reports its
  rectangle by UTF-16 offset into the marked text; a field that reports
  none there gives the first character's, as before. The rectangle is
  read once per marked text and anchor, so paging through predictions
  leaves the window still. Found by an advisor survey (pass 4).
- Not checked on screen: the owner's Mac is not driven while they work;
  the anchor is unit-tested and the shell builds.

## D-063 · The learned store has a schema version (2026-10-20)
- The store created its tables if missing and nothing else, so the first
  release that changes them would have met old files with no way to
  tell them apart, and learning would fail with its errors swallowed.
  It now keeps SQLite's `user_version`: the schema is a list of steps, a
  store runs the steps past its version in one transaction, and records
  the count. Version 1 is today's tables; files from before versions
  existed have them and come to version 1 unchanged.
- Steps only add (tables, columns, indexes), so a store a newer Sugu
  wrote is read as it is after a downgrade rather than set aside.
- A learn or unlearn that fails is logged before the store reloads from
  disk. Found by an advisor survey (pass 4).

## D-064 · Mode indicator on app switches; Japanese engine start (2026-10-20)
- A mode set by the focused app's rule or remembered mode showed the
  indicator like a switch the user made, and where the field reports no
  caret (no marked text, many apps) at the pointer: ⌘-Tab between a
  terminal and an editor flashed 中/A wherever the mouse was.
  `onModeChange` now says whether the user switched (its documentation
  already promised it); a switch that came with the focus shows only at
  a caret the field reports. `setMode(_:remember:)` became
  `setMode(_:byUser:)`, the one meaning both had.
- Measured and left: the Japanese engine is made on the main thread at
  the first Japanese focus, 18–22 ms (dictionary store and emoji table),
  with the model mapped in 0.1 ms and 500 user words in 0.3 ms; the first
  keys then take 5–6 ms while AzooKey reads its dictionary. Chinese moved
  off the main thread because librime's deploy takes seconds (D-027); a
  one-time 20 ms is not worth a second hand-over path.
- Also from the advisor survey (pass 4), left: a Shift tap commits a
  Japanese composition as it shows (D-041 chose that); capitals in a
  romaji composition stay Latin, as on Apple's Japanese input.

