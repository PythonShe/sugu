# Progress

Running log of what was built, verified, and what is next. Newest first.

## 2026-10-20
- Candidate window: long candidates shortened in the middle, hover
  highlight (D-037); draw p99 1.0 ms.
- Input menu: Chinese Characters, Learn from Typing, Check for Updates…
  (D-036).
- Traditional Chinese quotes with 「」『』 (D-035).
- First launch takes the mode order and Chinese characters from the
  preferred languages; the mode order is kept everywhere (D-034).
- Kana input types kana by physical key on JIS and ANSI keyboards, with
  voicing marks joining the kana before them (D-033). Advisor pass 2
  listed the remaining v1 gaps (todo §9).
- Review of D-027–D-032 fixed: failed redeploys no longer look ready,
  no engine for a schema already replaced, hand-off keeps the caret, Space
  waits while Chinese loads, a Zenzai model replaced mid-load is reloaded,
  upgrades do not reselect Sugu, and secure input held by a helper process
  stays secure. CI passes (p99 3.9 ms).
- Zenzai loads in the background and is adopted between compositions
  (D-032): the first load was 8.6 s on the main thread after install.
  With Zenzai, Japanese top-1 90%; learned names do not survive its
  rewrite (open).
- Installing selects Sugu (`--register` also calls `TISSelectInputSource`);
  README updated. Menu-bar mode icons via input modes considered and kept
  out (D-005).
- Secure input left on by another process (seen live: loginwindow while
  the screen is locked) no longer turns Sugu off everywhere (D-031).
- Unified-log diagnostics and Export Diagnostics in Advanced (D-030); the
  `SuguTests` bundle checks the report reads the log back.
- A damaged learned store is set aside and a fresh one opened (D-029).
- Control keys inside a composition (D-028): Emacs editing keys, ⌃N/⌃P,
  ⌃G, ⌃M, Kotoeri's ⌃J ⌃K ⌃; ⌃L ⌃:, and ⌃[ as Escape. 129 package tests.
- Advisor review for v1 gaps (D-027 first): Chinese letters typed while
  librime deploys stay in the composition and move to librime when it is
  ready; a failed deployment retries with backoff from a fresh build and
  shows Failed / Try Again in Settings › Chinese; engines are prepared at
  mode change and focus. 127 package tests.
- Bench romaji fixed: `meeru` types めえる (メール is `me-ru`) and
  降りそう is `furisou`, not `furusou`. Learned Japanese sentences 80% →
  90%; the main set stays at 78%, since AzooKey still ranks 古そう first for
  ふりそう, as it does 強 for きょう before の. Typo correction is not the
  cause (checked with it off).
- Review of D-026: an apostrophe lookup no longer offers words stored for
  another split (`fan'gan` → 方案, `xi'anqu` → 先去); it checks the split
  with the bundled syllables, and exact matches come first. 125 package
  tests; CI passes (Chinese 90%, Japanese 78%, p99 3.8 ms).
- Learned-words bench for both languages (`Bench/ja-learned.tsv` added):
  taught names and places in sentences, Chinese 0% → 83%, Japanese 30% →
  80% (AzooKey's dynamic user dictionary); main sets unchanged after
  learning (90%, 78%).
  With the grammar model, taught-word sentences reach 92% and the main
  set 94%; keystroke p99 3.3–3.6 ms over warm runs (6.5 ms on a cold first
  run while the model pages in).
- Learned readings keep a needed apostrophe (D-026): 西安 picked for
  `xi'an` is no longer offered first for `xian`.
- Chinese learned words take part in librime's sentences (D-025): a
  read-only user dictionary generated from the store, codes decoded from
  the typed keys by the schema's own spelling rules, toneless syllables
  added to the bundled syllabary. Taught-word sentences 0% → 83% top-1,
  main set unchanged at 90%; reload ~1 ms. 119 package tests.
  Review fixes: use counts kept in librime's 32-bit range (capped at 9),
  a reload is retried until the session has read the latest file, the
  file follows the store even when Chinese is not loaded, writes land in
  order. The file holds the best 3,000 words (librime parses it on the
  main thread, ~1 ms per thousand) and the session opens after deployment.
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
