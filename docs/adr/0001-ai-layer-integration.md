# AI layer authority, model seam, and token discipline

Sugu's AI layer ranks candidates; it does not compose text. This ADR records the
full shape of that layer in one place — what it may do, how it talks to models,
what leaves the device, when it may be called, what it costs, and what evidence a
model swap requires — so future contributors know which parts are load-bearing
product principles and which are tunable knobs.

## Decisions

1. **Authority ceiling: select, never introduce.** The AI layer may reorder or
   suppress candidates produced by the local engines (Mozc, libpinyin). It may
   never introduce a string the engines did not produce, regardless of what a
   model is capable of. Augmentation and free-form generation are out of scope;
   they require a new ADR and evidence that engine *recall* — not ranking — is
   the actual bottleneck. Rationale: boolean/typed models (Jev and its class)
   naturally express "which of these is better", and the ceiling preserves the
   property that nothing unverifiable enters the user's document.

2. **Provider-agnostic seam, decided now.** Exactly one interface — a
   `DecisionProvider` seam taking typed questions about local state and returning
   typed answers with confidence — sits between the AI layer and every model.
   Each adapter capability-declares what it supports (boolean only, choice sets,
   calibrated probabilities, …) and the layer above degrades to local ranking
   when a capability is missing. Jev is the first adapter, not the architecture.
   Rationale: nearly free at zero-codebase stage, expensive to retrofit, and it
   is the structural answer to "a cheaper/better/faster model appeared".

3. **What may leave the device.** A provider call's state may contain: the
   current composition string; a bounded window of recently committed text; and
   the surrounding marked sentence — all three inside a fixed state-token budget.
   App or field identity may be included only as a coarse enum that fits that
   budget (never a bundle ID). User dictionary contents and learned frequency
   data never leave the device, under any model, ever.

4. **Call gating plus local pre-filter.** A provider call requires all of: the
   user is inside the hesitation window; the engine's own top-2 score margin is
   below an ambiguity threshold (if the engine is confident, don't ask); a local
   filter has not already ruled the composition out; and budget allows. At most
   one batched call per hesitation window — never per keystroke or per candidate.
   Rationale: cost scales with user uncertainty, which is where AI is worth
   paying for.

5. **Local decision cache.** Decisions are cached on-device, keyed by a hash of
   composition + bounded context + provider + model version. Only the outcome is
   stored, never the raw context text. The model-version component prevents a
   provider swap from silently serving stale rankings.

6. **Cost is the user's; runaway calls are ours.** Sugu is BYOK: we publish a
   gross cost prognosis and take no responsibility for the user's API spend. We
   must, however, ship a local guard that prevents unbounded API calls (rate /
   budget ceiling, user-adjustable). AI-layer errors are surfaced to the user,
   never silently swallowed — the user owns the key and deserves to know when
   their calls fail.

7. **Model rotation is evidence-gated.** No provider swap without: (a) passing
   a golden set of JA/ZH ambiguous compositions with correct target orderings,
   run locally; and (b) a shadow/canary period where the candidate provider's
   ranking is computed but not shown, compared against the incumbent. The golden
   set and its test prompts stay **private** — outside this repository — and are
   never published to the community.

## Considered options

- **Deeper integration (augmenter/generator):** rejected — breaks the "only
  engine-produced strings reach the document" guarantee and overfits to one
  model class's strengths.
- **Silent budget shutoff:** rejected — BYOK means the user's own key is behind
  these calls; failures must be visible.
- **Open-sourcing the evaluation suite:** rejected — public ranking targets invite
  provider overfitting and leak what we consider correct orderings.

## Consequences

- README/AGENTS "composition text stays on-device" must be reworded: composition
  *resolves* on-device, but a bounded context window (decision 3) may be sent to
  the user's own provider.
- The private golden set needs a home outside this repo; add a `.gitignore` rule
  if a local copy ever appears here.
- The `DecisionProvider` seam's exact question-types are still open and follow
  from decision 1 — as are confidence-threshold rules, distill-to-local-model,
  and offline/no-key behavior.
