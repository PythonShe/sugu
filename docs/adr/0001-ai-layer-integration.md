# AI layer authority, model seam, and token discipline

> **Deferred 2026-10-20.** Withdrawn from v1 scope by ADR 0002, decision 1.
> Kept as a record awaiting a flip decision; nothing here binds current work.
> ADR 0004 adds Apple's language models as user-chosen features instead.

Sugu's AI layer ranks candidates; it does not compose text. This ADR records the
complete design of that layer as settled across the design interview of
2026-09-22: what it may do, how it talks to models, what leaves the device, when
it may be called, what it costs, who controls it, and what evidence a model
rotation requires.

## Decisions

### Authority

1. **Select, never introduce.** The AI layer may reorder or suppress candidates
   produced by the local engines (Mozc, libpinyin). It may never introduce a
   string the engines did not produce. This is a product boundary, not a
   limitation of any one model class — augmentation and free-form generation are
   out of scope and require a new ADR, backed by evidence that engine *recall*,
   not ranking, is the actual bottleneck.

### The model seam

2. **Provider-agnostic seam, decided now.** Exactly one interface — a
   `DecisionProvider` seam taking typed questions about local state and
   returning typed answers with confidence — sits between the AI layer and every
   model. Adapters capability-declare what they support and the layer above
   degrades to local ranking when a capability is missing. Jev is the first
   adapter, not the architecture.

3. **Pairwise is the contract; N-way is a capability.** The guaranteed baseline
   unit is the pairwise question ("which of these two ranks higher?"), because
   every decision-style model can answer it. Adapters may additionally advertise
   `noul` (suppress: is this candidate junk?), `score` (ambiguity check), and
   `choice` (select from a set in one parallel pass). On `choice`-capable
   adapters a full N-way comparison is a single call; on boolean-only adapters
   the seam degrades to pairwise expansion. Same user-facing behavior either
   way; only cost and latency differ.

4. **Everything is an option; defaults do the thinking.** End users choose:
   candidate count, **2–8, default 3**; and comparison strategy —
   **Auto (default) / Thorough / Faster**. Thorough contests every pair
   (non-linear cost, more evidence); Faster is challenge form — each candidate
   contests only the current leader (linear, quicker). Auto means Thorough at
   n≤3 (it is only 1–3 questions) and Faster above. Labels must stay free of
   developer vocabulary; intuitiveness for non-technical users is a requirement,
   not a nicety.

### What leaves the device

5. **State contents.** A provider call's state may contain: the current
   composition string; a bounded window of recently committed text; and the
   surrounding marked sentence — all inside a fixed token budget. App or field
   identity only as a coarse enum that fits the budget (never a bundle ID).
   User dictionary contents and learned frequency data never leave the device,
   under any model, ever.

6. **Token constants (v1).** Composition ≤ 20, committed window ≤ 40, marked
   sentence ≤ 25, enum ≤ 5, batched questions ≤ 50 → **~100 tokens typical,
   ~140 worst case per call**. Truncation when over budget: enum → marked
   sentence → committed window; the composition itself is never dropped.
   **Conditional expansion:** longer context is sent only when the call is below
   the confidence floor — context earns its tokens only when the call is
   actually uncertain.

### When AI may be called

7. **Gating, hard-coded.** A provider call requires all of: the user is inside
   the hesitation window; the engine's top-2 score margin is below an ambiguity
   threshold (confident engines don't ask); a local pre-filter has not already
   ruled the composition out; and budget allows. At most one batched call per
   hesitation window — never per keystroke or per candidate.

8. **Confidence floor τ.** The provider's ordering is applied only when
   confidence ≥ τ; below τ the local order stands, untouched and silent — that
   is calibrated behavior working, not an error. τ ships as a constant in v1.
   A stricter second floor (never demote the engine's #1 below slot 2 without
   stronger confidence) is a noted future knob, not a launch constant.

### Cost and failure

9. **BYOK economics: the spend is the user's, the guard is ours.** We publish a
   gross cost prognosis and take no responsibility for the user's API spend. We
   must ship a local guard preventing unbounded API calls (rate/budget ceiling,
   user-adjustable).

10. **Failures are visible.** Nothing new appears while typing — the IME never
    draws attention to itself. Accountability lives in settings: per-reason skip
    counters (no key / offline / provider error / budget / below-τ), last-error
    timestamp, and a running locally-computed cost estimate. One first-run and
    one first-failure notice explain a missing key; after that, stop nagging.

### Cache

11. **Local decision cache.** Decisions are cached on-device, keyed by a hash
    of composition + bounded context + provider + model version. Only the
    outcome is stored, never raw context text. The model-version component keeps
    a provider swap from serving stale rankings.

### Model rotation

12. **Rotation is evidence-gated.** No provider swap without passing a private
    golden set of JA/ZH ambiguous compositions with correct target orderings,
    run by maintainers, plus a maintainer-side shadow comparison against the
    incumbent. The golden set and its test prompts live **outside this
    repository** and are never published — public ranking targets invite
    provider overfitting and leak what we consider correct orderings. Users
    never run shadow calls on their own keys.

13. **Distill-to-local-model: rejected.** Training a local ranker on cached
    user decisions is not seen as possible or useful for average users within
    the foreseeable future. The cache exists for token savings only and carries
    no training-schema obligations.

## Considered options

- **Deeper integration (augmenter/generator):** rejected — breaks the "only
  engine-produced strings reach the document" guarantee.
- **Silent budget shutoff / silent AI failure:** rejected — BYOK means the
  user's own key is behind these calls; failures must be visible.
- **Open-sourcing the evaluation suite:** rejected — see decision 12.
- **Pairwise-only seam:** rejected after fact-check — `choice`-capable adapters
  can do N-way full comparison in one parallel call; hard-coding pairwise would
  discard that for no benefit (decisions 3–4 keep user-facing behavior intact).
- **Distill-to-local-model:** rejected — see decision 13.

## Consequences

- The on-device wording in README / `AGENTS.md` / `CLAUDE.md` was reworded in
  `d91c6f8` ("composition and conversion always resolve on-device; a bounded
  context window may be sent only to the user's own provider").
- The `AGENTS.md` candidates budget is amended to default 3 (adjustable 2–8)
  and ~100 tokens/decision to match decisions 4 and 6.
- Deliberately deferred as reversible implementation knobs: τ and any τ₂ value,
  per-language pre-filter threshold, cache eviction policy.
- The "Auto / Thorough / Faster" labels and the candidate-count control are a
  stated intuitiveness requirement — user-test them before release.
