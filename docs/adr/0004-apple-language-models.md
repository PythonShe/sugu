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
     Japanese composition, offered as a candidate. Off by default.
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
  untracked `Config/Local.xcconfig`; release signing needs a Developer ID
  profile with the capability.
- `FoundationModels` is weak-linked; Sugu still runs on macOS 14.
