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
