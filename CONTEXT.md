# Sugu

Sugu is an open-source, privacy-first AI input method for macOS covering Japanese
and Chinese composition. This glossary pins the domain language; decisions live
in `docs/adr/`.

## Language

**Composition**:
The pre-edit text the user is assembling before it is committed to the application.
_Avoid_: preedit, raw input, buffer

**Conversion**:
Replacing a composition with a chosen candidate string.
_Avoid_: resolution, transformation

**Candidate**:
A string proposed by a local engine for the current composition.
_Avoid_: suggestion, completion, proposal

**Engine**:
A local component that produces candidates for one language (Mozc for Japanese,
libpinyin for Chinese).
_Avoid_: backend, provider — _provider_ means a model, see below

**Hesitation Window**:
The pause in typing after which the AI layer is permitted to act; AI never
intervenes mid-keystroke.
_Avoid_: idle time, debounce

**Comparison**:
Ordering the candidates for one composition — either thorough (every pair
contested) or by challenge (each candidate contests only the current leader).
_Avoid_: rerank, ranking-off

**AI Layer**:
The part of Sugu that reorders or suppresses candidates. By definition it never
introduces strings the engines did not produce.
_Avoid_: smart layer, assistant

**Provider**:
An external model service reached through the decision seam. Capability-declared
and replaceable; never called except inside the hesitation window.
_Avoid_: engine — _engine_ means a local component, see above
