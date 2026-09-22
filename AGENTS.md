# Sugu Rules

Sugu (すぐ — "immediately") is an open-source, privacy-first AI input method
for macOS, for Japanese and Chinese composition. This is a **single-component
repository** — Swift / AppKit / InputMethodKit only. This file is the sole
rules file for the whole repo; add a component-level `AGENTS.md` only if a
genuinely separate component ever appears (e.g. a `website/`).

Each `AGENTS.md` is a verbatim copy of its sibling `CLAUDE.md`. After editing
either one, re-copy it over the other in the same commit.

## 0. Tech Stack & Dev Commands

| Layer | Technology | Notes |
|------|------|------|
| Shell | Swift + AppKit + InputMethodKit (IMKServer / IMKInputController) | lives in `/Library/Input Methods`; native macOS only — no Electron, no cross-platform frameworks |
| Japanese engine | [mozc_server](https://github.com/google/mozc) (BSD-3-Clause) | protobuf over a local unix socket — never link Mozc C++ code into the app |
| Chinese engine | [libpinyin](https://github.com/libpinyin/libpinyin) (LGPL-3.0) | C API, **dynamically linked** (LGPL compliance); dictionary via opengram — verify dictionary licenses from actual COPYING files in a clone, never from search snippets |
| Ranking / AI layer | local frequency ranker + hesitation gate + BYOK boolean-model client | AI calls fire only when the user hesitates; uses the user's own API key |

```bash
# Dev commands: not yet defined — the Xcode project doesn't exist.
# Record build/test/install commands here when the scaffold lands.
```

## 1. Architecture Boundaries

- **Shell owns UI and IMK wiring only.** Conversion comes from the engines;
  ranking comes from the local ranker / AI layer. Never reimplement engine
  logic (segmentation, conversion, touch-tone) in Swift.
- **Engines are replaceable behind protocols** (`CandidateEngine`-style):
  Japanese talks protobuf IPC to `mozc_server`, Chinese calls libpinyin's C
  API. Neither engine's types may leak into the other's code path.
- **The AI layer is a reranker, never a gatekeeper**: it may reorder
  candidates, never block, delay, or drop composition. Confident typing never
  waits on a network.
- **Lazy language loading**: language-specific engines load on input-source
  switch and unload when inactive.

## 2. License & Product Policy (hard rules — do not renegotiate)

- **Apache-2.0, full stop.** No proprietary tier, no subscription, no
  relicensing plan. This was explicitly decided and dropped — never propose
  one again.
- **BYOK, no telemetry, no server of ours.** Optional AI ranking uses the
  user's own API key; composition text stays on-device; nothing is sent
  silently.
- **GPL engines are permanently excluded** (librime, Squirrel, fcitx5).
  Third-party licenses must be verified from COPYING/LICENSE files in an
  actual clone before shipping a dependency — not from memory or snippets.
- **DRM: never** implement or integrate DRM circumvention.
- No personal information (real name, email) in README or other public-facing
  docs.

## 3. Performance Budgets (product thesis)

- **Latency**: the right word appears in the first candidate slot
  immediately. The AI call fires only inside the hesitation window
  (~700ms+ pause); fast picks skip it entirely.
- **Cost**: well under ~$4.50/month for a heavy user (6,000 words/day) —
  target well under $1. 2-3 candidates max (1-2 pairwise comparisons),
  payloads are ~50-100 tokens/decision. Price is the primary constraint;
  latency is negotiable, price is not.
- **RAM**: 200MB+ resident is rejected as too heavy for an IME.

## 4. Git Conventions

### Git Write Operations

- The owner has granted **standing authorization to commit and push** in
  logical groups as work completes, directly to `main` (single-dev repo).
- Never add "Generated with Claude Code" / `Co-Authored-By: Claude` footers
  to commit messages or PR descriptions.

### Commit Message Format

```
<type>(<scope>): <description>
```

**type**: `feat` / `fix` / `refactor` / `docs` / `chore` / `test` / `perf` / `style`

**scope**:

| scope | Applicable scenario |
|-------|---------------------|
| `shell` | Swift / AppKit / InputMethodKit app code (composition UI, IMK wiring, candidate panel) |
| `engines` | Japanese (mozc) / Chinese (libpinyin) integration |
| `ai` | Local ranker, hesitation gate, BYOK decision client, learning loop |
| `docs` | Documentation changes (README, `docs/`) |
| `workspace` | Repository-root-level changes (`AGENTS.md`, `CLAUDE.md`, `.gitignore`, scripts) |

Cross-cutting changes may combine scopes (`shell,engines`); sub-dimensions
may refine them (`engines/pinyin`, `ai/gate`).

Examples:

```
feat(shell): preedit display with candidate panel
fix(ai/gate): skip API call when selection lands under 700ms
```

## 5. Directory Boundaries

- The repo root is the project root of this one app: do not accumulate
  nested sub-projects, `src/` copies, or vendored engine source at the root.
- Third-party engines are consumed as dependencies (socket IPC / dynamic
  library), never vendored into this repo.
- When the Xcode project is scaffolded, record its generated-artifact
  gitignore rules (`.xcodeproj`/`.swiftpm`/build dirs, whichever applies)
  here and in `.gitignore` in the same commit.
