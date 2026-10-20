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
| `SuguCore` | Modes, the key model, candidates, composition state, the `CompositionEngine` protocol and `EngineTraits`, punctuation, width and kana conversion, the kana keyboard layout, computed candidates, Latin inference, the pinyin syllabary, preferences, `Log` (unified-log channels) | — |
| `SuguLearning` | `LearnedStore`: learned and user words in SQLite with an in-memory index, deletions, expiry, pins | Core |
| `SuguInput` | `InputSession`, the input state machine, with `CandidateAssembler`, `CandidateList`, the `v` expression engine, the `LoadingEngine` that holds letters until librime is ready, `InputClient` and `EngineSource` protocols, `ShiftTapDetector` | Core, Learning |
| `SuguLM` | `CharacterLanguageModel`: the bundled character n-gram models that rerank Japanese sentences and respell Chinese ones (ADR 0005) | — |
| `SuguRime` | librime through the `CRimeShim` C target: schema generation, runtime, `RimeEngine` (pinyin) and `ZhuyinEngine`, OpenCC `ScriptConverter`, `ChineseRespelling` with the `SentenceRespeller`, the learned-word user dictionary and the pinyin decoder | Core, LM |
| `SuguAzooKey` | `AzooKeyEngine`: predictions, clause and live conversion over AzooKeyKanaKanjiConverter; Zenzai loaded on a background converter and adopted between compositions | Core, LM |
| `SuguEngines` | `EngineHub` (the real `EngineSource`: engines prepared at mode change and focus, deployment retries, preferences, script) and `ModelLibrary` (optional downloads) | Input, Rime, AzooKey, Learning, Downloads, LM |
| `SuguDictionaries` | Importers and exporters, Sugu's own dictionary format, folder sync (`SyncFolder`, `DictionarySync`) | Core, Learning |
| `SuguDownloads` | Pinned, checksum-verified downloads and zip extraction | — |
| `SuguUpdates` | Sparkle, with system profiling off | Sparkle |

`SuguInput` links no engine: it sees engines only through
`CompositionEngine` and `EngineSource`, and tests drive it with fakes.
`SuguAzooKey` and everything that links it (`SuguEngines`, the app,
`sugu-tool`, `sugu-bench`) build with C++ interoperability; the rest do
not.

Executables: `sugu-tool` builds the bundled data and converts readings from
the terminal; `sugu-bench` drives `InputSession` with the real engines and
checks accuracy and latency budgets.

## A keystroke

1. `SuguInputController` (IMK) receives the event and hands it to
   `InputCoordinator`, which drops duplicates, handles Shift taps and Caps
   Lock, and turns the `NSEvent` into a `KeyInput` (`KeyTranslator`).
2. `InputSession.handle(_:)` applies global keys (mode keys, shortcuts, vim
   Esc, F6–F10, and the Emacs and Kotoeri control keys inside a
   composition). With no composition, `start(_:)` picks the engine for the
   mode; while librime is still deploying, the `LoadingEngine` holds the
   letters and hands them over when `EngineSource.onEngineReady` fires.
   During a composition the active engine's traits choose the bindings:
   - **live candidates** (`handleLive`: librime, expressions): candidates
     follow every key, the first is chosen by default, Space commits it;
   - **staged conversion** (`handleStaged`: AzooKey): typing shows
     predictions, Space converts, arrows move and resize clauses. AzooKey's
     whole-input sentences are reordered by `CharacterLanguageModel`
     (`SuguLM`) after the left context, unless Zenzai is on;
   - **sentence** (`handleSentence`: Zhuyin): the sentence stays converted
     as syllables end with their tones; arrows move the caret through it,
     and the candidate window opens to choose a word at the caret.
3. After the engine changes, `refresh()` rebuilds the list:
   `CandidateAssembler` merges the engine's candidates with learned words,
   computed candidates, Latin text and Chinese forms of Japanese names,
   reranks by the left context and document vocabulary, and puts Sugu's own
   candidates in the Chinese script in use.
4. `publish()` produces a `SessionDisplay` (marked text and one page of
   candidates); the shell sets the marked text through `TextInputClient` and
   draws the page in `CandidateView` with Core Text.
5. A commit inserts text, and, when the engine's traits allow and the app is
   not excluded, teaches `LearnedStore`; `⌃⌫` can take the last commit back,
   and 英数 pressed twice retypes a Japanese one as its romaji. Neither
   edits committed text in terminals (`canEditCommitted`).

## Data and privacy

- Field text (left context, document vocabulary, reconversion) is read
  through one gate, `canReadField`: never in secure input or excluded apps,
  held in memory only. Secure input counts unless its holder plainly
  cannot own the field (the login window, another app in the background).
- Logging (`SuguCore.Log`) records lifecycle and failures, never readings
  or text; Settings › Advanced exports this run's entries on request.
- A damaged learned store is renamed `learned.sqlite.damaged-<date>` and a
  fresh one opened.
- Learned words stay in the store's directory, excluded from backups. The
  Chinese ones are also written, read-only for librime, into its user
  directory (`sugu_learned.txt`, likewise excluded) so they take part in
  sentences; it is regenerated from the store on every change. Sync
  writes one file per Mac to a folder the user picks, carrying deletions so a
  word deleted on one Mac stays deleted everywhere.
- The bundled Chinese data, the pinyin word list, and the Japanese and
  Chinese character language models (ADR 0005) are compiled by
  `scripts/build-data.sh` into `Data/`; GPL data (rime-ice) and the Zenzai
  model are user downloads only.

## Checks

- `swift test --package-path Packages/SuguKit`: session behavior with fake
  engines and fields, engines against real data, store, sync, downloads.
- `SuguTests` (the scheme's test action): shell code that needs
  InputMethodKit, such as `TextInputClient`'s UTF-16 offsets, against a fake
  field; a logic-test bundle with no host app.
- `sugu-bench`: accuracy and keystroke latency over `Bench/`, memory, and
  learned words in sentences (`--grammar`, `--zenzai` for the models).
- `Sugu --measure-draw`: candidate-window layout and drawing time, offscreen.
- `scripts/ci.sh` runs all of these after a Release build.
