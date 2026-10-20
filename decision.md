# Decisions log

Implementation decisions taken while building v1, newest last. Product-level
decisions stay in `docs/adr/`; this file records how they are carried out and
any call made without the owner present. Each entry: what, why, reversibility.

## D-001 · Repository layout (2026-10-20)
- `project.yml` → generated `Sugu.xcodeproj`; app target sources in `Sugu/`.
- All logic that can run headless lives in the local package
  `Packages/SuguKit`, split by responsibility: `SuguCore` (models, key model,
  punctuation, computed candidates, Latin inference, preferences),
  `SuguRime`, `SuguAzooKey`, `SuguLearning`, `SuguDictionaries`, and
  `SuguInput` (the input state machine that ties them together).
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
  given up; Sugu learns the committed phrase as a whole instead.

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
- The grammar model adds ~90 MB of resident clean pages and did not improve
  a small probe, so it stays an optional download (ADR 0002 d4).

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
  `Sugu --register` as the console user, which registers and enables the
  input source (`TISRegisterInputSource`/`TISEnableInputSource`).
- Sparkle 2.10.0 lives in the `SuguUpdates` package target, so Xcode and
  SwiftPM resolve one dependency graph and agree on `Package.resolved`.
  The public key is a build setting set only by the release script; builds
  without it never start the updater. System profiling is off in
  Info.plist and in the delegate. Automatic checks default on (update checks
  are allowed traffic, ADR 0002 d12), automatic installs off; both are in
  Advanced settings.
- `scripts/install-dev.sh` installs a build into `~/Library/Input Methods`
  for development; it is never run by automation here.
