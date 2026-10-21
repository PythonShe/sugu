# Apple language models, on this Mac and in Private Cloud Compute

Sugu's engines produce every candidate it offers while typing, on the Mac.
This ADR records the user's decision of 2026-10-20 to add features built on
Apple's language models — the on-device `SystemLanguageModel` and, when the
user allows it, `PrivateCloudComputeLanguageModel` — with the level of
integration chosen by the user. It is the new ADR that ADR 0001, decision 1
requires before text the engines did not produce may reach the document, and
it narrows ADR 0002, decision 1 ("no AI layer in v1") to third-party and
bring-your-own-key providers, which stay out.

## Decisions

### Provider

1. **Apple's models only.** `FoundationModels` on macOS 27 and later: the
   on-device system model, and Private Cloud Compute through the
   `com.apple.developer.private-cloud-compute` entitlement. No third-party
   providers, no keys, no Sugu servers. On earlier macOS the features and
   their settings do not appear.

### Levels, chosen by the user

2. **Three levels; off by default.** *Off* — no model is used. *On This
   Mac* — only the on-device model; nothing leaves the Mac. *On This Mac and
   Private Cloud Compute* — requests go to Private Cloud Compute, falling
   back to the on-device model when it is unavailable or its quota is used
   up.

3. **Each use is its own switch.** At any level other than Off, the user
   chooses what the model may see:
   - *Selected text* — Translate Selection (Chinese, Japanese, English) and
     Rewrite Selection (fix grammar, more formal, more casual, shorter),
     run only from the Input menu. On by default once a level is chosen.
   - *Long compositions* — a context-aware conversion of a long Chinese or
     Japanese composition, offered as a candidate. Off by default; at the
     Private Cloud Compute level only (amendment below).
   - *Translations while composing* — the composition in the other enabled
     languages, offered as candidates. Off by default.

### Authority

4. **Offered, never applied.** Model output only appears as candidates in
   Sugu's own window; it reaches the document only when the user picks it.
   The engine's best candidate keeps the first slot. A selection being
   translated or rewritten stays as it was until a result is chosen, and
   returns unchanged on Esc or focus loss.

### What leaves the device

5. **Bounded and gated.** At the Private Cloud Compute level a request may
   contain: the selected text (at most 2,000 characters) for selection
   actions; or the composition's reading, the engine's best conversion,
   and up to 40 characters before the caret for composition suggestions.
   Learned words, user dictionaries, app identity and field contents beyond
   that bound never leave the Mac. Nothing is sent in secure input or in
   apps excluded from learning (password managers by default), at any
   level.

### When a model is called

6. **Never on the keystroke path.** Selection actions run when chosen.
   Composition suggestions are requested after a typing pause, only for
   compositions of at least eight characters of reading, one request per
   composition state; results arrive asynchronously and are dropped if the
   composition changed. Keystroke budgets (ADR 0003, decision 22) are
   unaffected.

7. **Failures are quiet while typing.** A failed or unavailable model adds
   no candidates and shows nothing; Settings shows availability and, for
   Private Cloud Compute, the quota state.

## Amendment (2026-10-20): conversions from Private Cloud Compute only

Measured on the development Mac once Apple Intelligence was ready, the
on-device model's conversions of long compositions were worse than the
engines': it answered in kana, dropped particles, or repeated the engine's
text. Its translations were good when asked one language at a time, and
missing when asked together with a conversion. The user decided:

- *On This Mac* offers translations while composing; the *Long
  compositions* switch is available only at the Private Cloud Compute
  level, and is ignored at On This Mac.
- When Private Cloud Compute is unavailable or its quota is used up, the
  on-device fallback offers translations only.

## Amendment (2026-10-21): Private Cloud Compute only in development builds

Apple offers Private Cloud Compute to apps distributed on the App Store
(and their TestFlight and ad hoc tests). Input methods cannot be
distributed there: Apple's developer support confirmed this in 2020 and
again in April 2026. The account's approval enables the capability on the
App ID, and development profiles carry it, but a Developer ID profile
generated after the approval does not. So:

- Releases are Developer ID builds without the entitlement; the Private
  Cloud Compute level falls back to the on-device model (D-045).
- The owner's Macs run development-signed builds with the entitlement
  (`Config/Local.xcconfig`, `scripts/package-dev.sh`). They have no update
  key, so Sparkle never replaces them with a release.
- If Apple opens Private Cloud Compute to Developer ID, a profile with it
  in `APPLE_PROVISIONING_PROFILE` is all a release needs.

## Considered options

- **Automatic replacement (live rewrite, auto-correct by model):**
  rejected — text must reach the document only by the user's choice
  (decision 4).
- **Third-party providers / bring your own key (ADR 0001):** still out of
  scope; Apple's models need no key, keep requests under Apple's Private
  Cloud Compute guarantees, and cost the user nothing to try.
- **One switch for everything:** rejected — what may leave the Mac differs
  by use, and the user decides each.

## Consequences

- `CLAUDE.md`/`AGENTS.md`, ADR 0002 decision 12 and the README state that
  Private Cloud Compute requests, when the user turns them on, are network
  traffic alongside update checks and downloads.
- Development builds carry the entitlement only when signed through an
  untracked `Config/Local.xcconfig`; Developer ID profiles do not offer
  the capability (amendment 2026-10-21).
- `FoundationModels` is weak-linked; Sugu still runs on macOS 14.
