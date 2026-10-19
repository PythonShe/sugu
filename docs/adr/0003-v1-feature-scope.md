# v1 feature scope

Research on 2026-10-20 (GitHub issues of Squirrel, Fcitx5-macOS and
azooKey-Desktop; V2EX; Apple Community; READMEs of the input-source switcher
tools users install) found that the loudest unmet needs on macOS are not
accuracy: input that silently stops after a switch, unclear mode state, candidate
windows placed wrongly, configuration that requires YAML, and learning nobody
can see or control. This ADR records the features Sugu v1 commits to, the trust
rules that bound them, and what is ruled out. All of it is v1; there is no
staged MVP (ADR 0002, decision 2).

## Decisions

### Modes and switching

1. **One input source, three internal modes.** Sugu registers a single macOS
   input source holding Chinese, Japanese and English modes. Mode changes
   never go through macOS input-source switching, which is where the "menu bar
   changed, input didn't" failure lives.

2. **Mode is always knowable.** A mode indicator appears at the caret on change;
   the toggle key is configurable (Shift tap, Caps Lock, 英数/かな).

3. **Per-app mode rules.** Per-app default mode, remembered last mode per app,
   and automatic English in secure-input fields and terminals. On Esc in vim
   normal-mode contexts, the composition is committed or cancelled, then
   English mode is entered.

4. **Latin inference.** Input that cannot be pinyin or romaji (`github`, `v2`)
   is offered as Latin first; common English words appear as a Latin candidate.
   A user allow-list covers abbreviations that collide (`nb`, `yyds`).

5. **Width-aware punctuation.** Half-width after Latin letters and digits,
   full-width after CJK, with paired quotes and brackets.

### Conversion

6. **Undo after commit.** A dedicated key restores the last commit as a
   composition with the candidate list open. Plain Backspace keeps its meaning.

7. **Reconvert selected text** in apps that expose it through InputMethodKit.

8. **Left-context conversion.** Committed text left of the caret (bounded to
   ~200 characters) informs candidate order. Where an engine takes no context,
   Sugu reranks its candidates locally.

9. **Document vocabulary.** CJK words already in the focused field rank first
   for the duration of focus, without entering the learned store. Off by default.

10. **Computed candidates.** Dates from readings like `jintian` / `きょう`, Chinese
    and kanji numerals (including financial 壹贰叁), full-width digits, and
    simple arithmetic.

11. **Cross-language proper nouns.** Pinyin offers Japanese forms of Japanese
    names and places (`dongjing` → 東京); romaji offers Chinese forms; per-app
    Simplified / Traditional / Japanese variant choice.

12. **Layout-independent composition.** Pinyin and romaji compose from the
    characters the active layout produces (Dvorak, Colemak, JIS); shortcuts stay
    physical.

13. **Reading hints.** Optional pinyin or furigana on candidates.

### Key behavior and candidate window

14. **Mac-standard keys.** F6–F10 conversions, Option-key symbols, numpad,
    caret movement inside the composition, romaji typo tolerance.

15. **Robust candidate window.** Fallback and caching when the host reports a
    wrong caret rect; correct multi-display placement; duplicate key events
    dropped.

16. **Pause-gated candidate window.** An option to show the window only after a
    pause or when the top candidate is uncertain; inline composition otherwise.
    Off by default.

17. **Accessible from the start.** VoiceOver announces the composition and
    candidates; candidate size scales and honors increased contrast.

### Learning and data

18. **Learning is inspectable.** A list of learned words with per-word delete
    and pin, "forget the last hour", a pause switch, expiry of unused words (on
    by default), and a per-app no-learn list seeded with password managers.

19. **Dictionaries move in and out.** Import the macOS user dictionary and
    Google Japanese Input, ATOK, Sogou and RIME dictionaries; export settings and
    the user dictionary. Sync is a folder the user picks; there is no Sugu cloud.

20. **Native settings with good defaults.** Every option above is a control in
    a settings window. A fresh install is accurate without configuration.

### Proof

21. **Accuracy is measured, in public.** A harness scores Sugu and the built-in
    input methods on the same Japanese and Chinese test sets: top-1 accuracy and
    keystrokes per character.

22. **Budgets enforced in CI.** Keystroke to updated candidates < 5 ms p99;
    candidate-window draw < 16 ms; resident memory < 200 MB in the default
    configuration.

### Trust boundary

23. **Field text stays in memory.** Text read from the document (decisions 7–9)
    is never persisted and never enters the learned store, and is not read in
    secure-input fields or apps on the no-learn list.

24. **The learned store is private by construction.** Stored with file data
    protection, excluded from backups and sync unless the user opts in;
    plaintext export requires confirmation.

## Considered options

- **Passive clipboard reading** (as in cloud input methods): rejected — reading
  the clipboard without a per-use action would make an input method spyware.
- **Sugu cloud sync:** rejected — decision 19 uses a user-chosen folder.
- **Plain Backspace as undo-after-commit:** rejected — it collides with deleting
  the last character.
- **A staged MVP:** rejected — ADR 0002, decision 2.

## Consequences

- The budgets in decision 22 replace the AI cost budget in `AGENTS.md`.
- Decisions 7–9 depend on `selectedRange` / `attributedSubstring(from:)`, which
  many Electron apps and terminals do not implement; the features degrade to
  off there, silently.
- The threshold values (latency budgets, ~200-character context bound, expiry
  period) are reversible knobs, not product boundaries.
