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
