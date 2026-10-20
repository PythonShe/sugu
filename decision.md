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
  は゜ → ぱ, う゛ → ゔ); otherwise they are typed as they are.

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
  modes in it, and turning a mode off and on keeps its place.

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
