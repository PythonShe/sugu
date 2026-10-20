# Architecture

How Sugu's code is laid out and how a keystroke travels through it. The
reasons behind each choice are in `docs/adr/` (product) and `decision.md`
(implementation); the words are defined in `CONTEXT.md`.

## Two halves

- **`Sugu/`** is the input method app: InputMethodKit wiring, the candidate
  window, the mode indicator, the input menu and the settings window. It is
  AppKit only and holds no input logic it could not hand to the package.
- **`Packages/SuguKit/`** holds everything that runs headless, so `swift test`
  and `sugu-bench` exercise real behavior without installing or activating an
  input method.

## Package modules

| Module | Role | Depends on |
|---|---|---|
| `SuguCore` | Modes, the key model, candidates, composition state, the `CompositionEngine` protocol and `EngineTraits`, punctuation, width and kana conversion, computed candidates, Latin inference, preferences | — |
| `SuguLearning` | `LearnedStore`: learned and user words in SQLite with an in-memory index, deletions, expiry, pins | Core |
| `SuguInput` | `InputSession`, the input state machine, with `CandidateAssembler`, `CandidateList`, the `v` expression engine, `InputClient` and `EngineSource` protocols, `ShiftTapDetector` | Core, Learning |
| `SuguRime` | librime through the `CRimeShim` C target: schema generation, runtime, `RimeEngine`, OpenCC `ScriptConverter` | Core |
| `SuguAzooKey` | `AzooKeyEngine`: predictions and clause conversion over AzooKeyKanaKanjiConverter, Zenzai options | Core |
| `SuguEngines` | `EngineHub` (the real `EngineSource`: lazy engines, preferences, script) and `ModelLibrary` (optional downloads) | Input, Rime, AzooKey, Downloads |
| `SuguDictionaries` | Importers and exporters, Sugu's own dictionary format, folder sync (`SyncFolder`, `DictionarySync`) | Core, Learning |
| `SuguDownloads` | Pinned, checksum-verified downloads and zip extraction | — |
| `SuguUpdates` | Sparkle, with system profiling off | Sparkle |

`SuguInput` links no engine: it sees engines only through
`CompositionEngine` and `EngineSource`, and tests drive it with fakes. Only
`SuguEngines`, the app and `sugu-bench` link librime and AzooKey, and only
they need C++ interoperability.

Executables: `sugu-tool` builds the bundled data and converts readings from
the terminal; `sugu-bench` drives `InputSession` with the real engines and
checks accuracy and latency budgets.

## A keystroke

1. `SuguInputController` (IMK) receives the event and hands it to
   `InputCoordinator`, which drops duplicates, handles Shift taps and Caps
   Lock, and turns the `NSEvent` into a `KeyInput` (`KeyTranslator`).
2. `InputSession.handle(_:)` applies global keys (mode keys, shortcuts, vim
   Esc, F6–F10). With no composition, `start(_:)` picks the engine for the
   mode. During a composition the active engine's traits choose the
   bindings:
   - **live candidates** (`handleLive`: librime, expressions): candidates
     follow every key, the first is chosen by default, Space commits it;
   - **staged conversion** (`handleStaged`: AzooKey): typing shows
     predictions, Space converts, arrows move and resize clauses.
3. After the engine changes, `refresh()` rebuilds the list:
   `CandidateAssembler` merges the engine's candidates with learned words,
   computed candidates, Latin text and Chinese forms of Japanese names,
   reranks by the left context and document vocabulary, and puts Sugu's own
   candidates in the Chinese script in use.
4. `publish()` produces a `SessionDisplay` (marked text and one page of
   candidates); the shell sets the marked text through `TextInputClient` and
   draws the page in `CandidateView` with Core Text.
5. A commit inserts text, and, when the engine's traits allow and the app is
   not excluded, teaches `LearnedStore`; `⌃⌫` can take the last commit back.

## Data and privacy

- Field text (left context, document vocabulary, reconversion) is read
  through one gate, `canReadField`: never in secure input or excluded apps,
  held in memory only.
- Learned words stay in the store's directory, excluded from backups. Sync
  writes one file per Mac to a folder the user picks, carrying deletions so a
  word deleted on one Mac stays deleted everywhere.
- The bundled Chinese data is compiled by `scripts/build-data.sh` into
  `Data/`; GPL data (rime-ice) and the Zenzai model are user downloads only.

## Checks

- `swift test --package-path Packages/SuguKit`: session behavior with fake
  engines and fields, engines against real data, store, sync, downloads.
- `sugu-bench`: accuracy and keystroke latency over `Bench/`, memory.
- `Sugu --measure-draw`: candidate-window layout and drawing time, offscreen.
- `scripts/ci.sh` runs all of these after a Release build.
