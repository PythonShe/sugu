# Progress

Running log of what was built, verified, and what is next. Newest first.

## 2026-10-20
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
