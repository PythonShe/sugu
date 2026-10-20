# Sugu

Sugu is an open-source, privacy-first input method for macOS covering Japanese
and Chinese composition. This glossary pins the domain language; decisions live
in `docs/adr/`.

## Language

**Composition**:
The pre-edit text the user is assembling before it is committed to the application.
_Avoid_: preedit, raw input, buffer

**Conversion**:
Replacing a composition with a chosen candidate string.
_Avoid_: resolution, transformation

**Commit**:
Inserting text into the application, ending the composition.
_Avoid_: confirm, submit

**Candidate**:
A string proposed for the current composition — by an engine, or computed by
Sugu (dates, numerals, arithmetic).
_Avoid_: suggestion, completion, proposal

**Engine**:
A local component that produces candidates for one language (librime for
Chinese, AzooKeyKanaKanjiConverter for Japanese).
_Avoid_: backend, provider

**Input Source**:
The entry macOS lists in its input menu. Sugu registers exactly one.
_Avoid_: input method (for this sense), keyboard

**Mode**:
Chinese, Japanese, or English — the state inside Sugu's input source that
decides which engine, if any, receives keystrokes.
_Avoid_: input source, language

**Left Context**:
Committed text before the caret, read from the focused field to inform
candidate order. Held in memory only.
_Avoid_: history, surrounding text

**Learned Word**:
An entry Sugu has learned from the user's commits, visible and deletable in the
inspector.
_Avoid_: user dictionary (that is what the user adds explicitly), history

**No-Learn List**:
Apps where Sugu neither learns from commits nor reads left context.
_Avoid_: blocklist, private mode

**Reading**:
The input as typed, before conversion: pinyin letters or Zhuyin codes for
Chinese, kana for Japanese (romaji typed is kept beside it).
_Avoid_: raw input, pinyin (for the Japanese sense)

**Chinese Keyboard**:
How Chinese is typed: pinyin (full or a double-pinyin scheme) or Zhuyin on
one of its layouts.
_Avoid_: input source, layout (for the pinyin/Zhuyin choice)

**Script**:
The character forms Chinese is written in: Simplified, Traditional (with its
Taiwan or Hong Kong forms), or Japanese kanji.
_Avoid_: font, variant

**Clause**:
A span of a Japanese conversion converted as a unit, which the user can move
between and resize.
_Avoid_: segment, bunsetsu (in code)

**Prediction**:
A candidate for more than has been typed, offered while composing Japanese.
_Avoid_: completion, suggestion

**Live Conversion**:
Japanese shown converted as it is typed, without pressing Space.
_Avoid_: auto conversion

**Reconversion**:
Turning committed text (the selection) back into a composition of its reading.
_Avoid_: re-edit, undo

**Respelling**:
Sugu's language model replacing characters of librime's sentence where it
reads another spelling of the same syllables as clearly better.
_Avoid_: correction, autocorrect

**Document Vocabulary**:
Words anywhere in the focused field, read once per focus to rank candidates
already used there. Held in memory only, and off by default.
_Avoid_: history, context (that is the Left Context)

**User Word**:
A word the user adds explicitly; unlike a Learned Word it does not expire.
_Avoid_: custom word, phrase

**Pinned**:
A learned word kept from expiry and from forgetting the last hour.
_Avoid_: favorite, locked
