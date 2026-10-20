# Progress

Running log of what was built, verified, and what is next. Newest first.

## 2026-10-20
- Grammar model measured (`sugu-bench --grammar`): Chinese top-1 90% → 94%,
  keystroke p99 3.7 ms, footprint unchanged; D-015 updated with the data.
- Cross-language proper nouns and per-app script (D-021): Japanese kanji
  forms as a Chinese script, Chinese forms after Japanese names, Sugu's own
  candidates in the script in use, a script column in the Apps pane.
- Regression review of the refactors: no key-path changes found; fixed
  AzooKey dropping clauses fixed before a second conversion and a delayed
  sync export outliving a folder reset. `docs/architecture.md` describes
  the module graph and a keystroke's path. A `SuguTests` logic-test bundle
  (no host app) covers `TextInputClient`'s UTF-16 offsets; `scripts/ci.sh`
  runs it. 114 package tests + 4 shell tests, CI green.
- Maintainability track (D-024, todo §8): `InputSession` now asks the
  engine's traits (conversion phase, learning, Sugu candidates) instead of
  branching on mode or engine type, and is split into keys, composition,
  candidate-list and field files with `CandidateList` and `PendingUndo`
  types; `EngineHub`/`ModelLibrary` moved to a `SuguEngines` target so
  `SuguInput` links no engine and builds without C++ interop;
  `ShiftTapDetector` and `DictionarySync` moved into the package;
  CONTEXT.md vocabulary applied. New tests cover AzooKey clause navigation,
  session paging and navigation, the candidate list, Shift taps, sync and
  backoff, and model installs. They found AzooKey dropping keys typed after
  a fixed clause from the reading (F6–F10 and raw commit), now fixed.
  112 package tests.
- Draw budget now measured in CI (`Sugu --measure-draw`, p99 1.2 ms).
  Japanese bench row 49 typed いけんい (romaji `nn` is ん); fixed, top-1
  76 → 78%. The remaining Japanese misses are AzooKey's own first choice
  with the right sentence second or third; Zenzai is the path for those.
- Third review pass fixed: Chinese forms no longer enter the Japanese
  store; a learned word shown in another script is learned in its stored
  form; numpad keys continue `v` expressions; script converters open at
  focus and are kept per script; a script change refreshes candidates on
  screen. CI (`scripts/ci.sh`) passes: Chinese top-1 90%, Japanese 76%,
  keystroke p99 3.5 ms, footprint 58 MB. 89 package tests.
- Document vocabulary wired (D-022); numpad digits no longer select in
  Japanese conversion; Option and numpad session tests. 88 package tests.
- Second review pass fixed: pins sync on existing words, one unreadable
  file no longer stops sync, turning on learned-word sync re-reads older
  files, ⌃⌫ also unlearns, a highlighted Sugu candidate is what Enter and
  focus loss commit, cancelled downloads are not failures, model removal
  waits for a running download, `make-notices.sh` fails on a checksum
  mismatch.
- First review pass fixed: computed candidates no longer learned; ⌃⌫ undo
  checks the text left of the caret and restores into the engine that
  composed it (expressions are not undoable); one gate for reading the
  field; focus loss finishes a partial Rime selection; a failed Chinese
  deploy is not retried per keystroke and `isReady` needs a deployed
  schema; download cancel/remove ordered; sync carries deletions
  (tombstones) so deleted words stay deleted on every Mac, reads files off
  the main actor with coordination and iCloud downloads, backs off after
  failures. 69 package tests.
- `sugu-bench` added with 50-sentence Chinese and Japanese seed sets
  (D-018). Fixes it surfaced: Japanese keystroke p99 18.7 → ~4 ms (emoji
  replacer built once), trailing n → ん before conversion, romaji symbol
  keys (ー 「」 ・), and toned ü syllables missing from the pinyin list
  (lü/nü were treated as English). Chinese top-1 88 → 90%, Japanese 70 →
  76%. Zenzai measured: 80% top-1, +60 MB.
- Settings window in AppKit (toolbar tabs, NSGridView forms, NSTableView
  lists): modes and toggles, candidate style, pinyin scheme/script/fuzzy,
  dictionary choice, downloads with progress, Japanese options and Zenzai,
  per-app rules, learned-word inspector (search, sort, pin, delete, forget
  last hour, add word), no-learn apps, import/export, sync folder, settings
  file import/export/reset. Debug-only `--snapshot-settings` renders panes
  offscreen for review; checked in light, dark and Japanese.
- All 127 interface strings translated (zh-Hans, zh-Hant, ja).
- `SuguDictionaries`: importers for Google Japanese Input / Microsoft IME,
  ATOK (UTF-16), Sogou .scel and text, RIME, Text Replacements plist; Sugu's
  own format; per-Mac sync files with watermarks. 8 tests.
- `SuguDownloads` + `ModelLibrary`: pinned URL + SHA-256 downloads for the
  grammar model, rime-ice (GPL, user download) and Zenzai. rime-ice compiles
  in 3.6 s and converts correctly through a generated `sugu_ice` dictionary.
- Grammar model measured: +~90 MB resident (clean mmapped pages; footprint
  unchanged); on a 10-sentence probe it changed 2 top candidates, both for
  the worse. Stays opt-in until the accuracy harness says otherwise.
- Fixed: librime trashed the generated user schema (bundled copy had a
  higher version), and in-process redeploys within one second were skipped.
  Engine tests now cover schemes, fuzzy pinyin, script, and AzooKey.
- App shell (`Sugu/`, XcodeGen `project.yml`): IMK server and controller,
  `InputCoordinator` (one shared session, Shift-tap and Caps Lock toggles,
  duplicate-key filter, secure input), client adapter (IMK mark styles,
  left context, delete-before-caret for undo), candidate window (Core Text
  drawing in a non-activating panel; Liquid Glass on macOS 26+, menu
  material before; vertical/horizontal; paging chevrons, click, scroll;
  pause gating; VoiceOver announcements; increased-contrast border), caret
  mode indicator, input menu, generated icons, String Catalog (en, zh-Hans,
  zh-Hant, ja). `xcodebuild` passes; the app is not installed or launched.
- `EngineHub`: lazy engines, off-main librime deploy at launch, preference
  sync (schema redeploy, script, AzooKey options, Zenzai model).
- `SuguInput`: `InputSession` (modes, Chinese/Japanese key handling,
  paging, function keys F6–F10, `v` expressions, width-aware punctuation,
  undo-after-commit on ⌃⌫, per-app rules and remembered modes, vim Esc,
  secure input, learning gate) and `CandidateAssembler` (learned, computed,
  Latin candidates; left-context reranking). 17 session tests with fake
  engines and a fake field; whole suite green.
- `SuguLearning`: `LearnedStore` (SQLite, WAL, in-memory index for
  keystroke lookups, events table for "forget the last hour", expiry,
  pinning, user words, import). 7 tests pass.
- `SuguAzooKey`: `AzooKeyEngine` with predictions while typing, clause
  conversion (focus, resize, step back), learned words as a dynamic user
  dictionary, Zenzai options wired. First display equals the converter's
  best sentence: [今日は]いい天気ですね, [私は]学生です, [東京].
  Release timings for whole-word insertion are 15–30 ms per request; the
  per-keystroke budget is still to be measured incrementally (todo §7).
- `SuguRime`: schema generator, runtime (setup, off-main deploy, sessions),
  `RimeEngine`. `sugu-tool build-data` compiles the dictionary in 2.5 s
  (46 MB table); `sugu-tool convert` gives 你好 / 中国人 / 我爱北京天安门 /
  输入法 first, 0.1–2.6 ms per reading in a debug build.
- `SuguKit` package: `SuguCore` (modes, key model, candidates, composition
  state, engine protocol, punctuation, width/kana conversion, numerals,
  arithmetic, dates, Latin inference, preferences). 26 tests pass.
- AzooKey 0.11.2 with the Zenzai trait and librime link into one binary;
  `sugu-tool` probe printed librime 1.17.0 and an AzooKey composition.
- marisa-trie ODR clash found and fixed (decision D-008).
- wanxiang v18.1.6 dictionaries fetched and checksum-verified.
- Note: the API output filter blocked three replies while a long verbatim
  syllable table was being written; tables now come from data (D-009).
- Planning files created (`todo.md`, `progress.md`, `decision.md`).
- librime 1.17.0 + octagram built as a universal static xcframework
  (`scripts/build-librime.sh`, ~17 MB archive). `rime_get_api` and octagram
  symbols present. OpenCC tables copied to `.vendor/opencc`.
- Verified licenses from clones: librime BSD-3, librime-octagram BSD-3,
  AzooKeyKanaKanjiConverter MIT, rime-wanxiang CC-BY-4.0.
