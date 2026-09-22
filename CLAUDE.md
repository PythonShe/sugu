# Sugu Rules

Sugu is an open-source, privacy-first AI input method for macOS for Japanese
and Chinese composition. Single-component repo — Swift / AppKit /
InputMethodKit. `AGENTS.md` is a verbatim copy of `CLAUDE.md`; after editing
either, re-copy it over the other in the same commit.

## 0. Tech Stack & Dev Commands

| Layer | Technology | Notes |
|------|------|------|
| Shell | Swift + AppKit + InputMethodKit (IMKServer / IMKInputController) | installed in `/Library/Input Methods` |
| Project | XcodeGen | `project.yml` is the source of truth; `Sugu.xcodeproj` is generated and gitignored |
| Japanese engine | mozc_server (BSD-3-Clause) | protobuf over a local unix socket |
| Chinese engine | libpinyin (LGPL-3.0) | C API, dynamically linked |
| Ranking / AI layer | local frequency ranker + hesitation gate + BYOK boolean-model client | fires inside the user's hesitation window (~700ms+) |

Verify third-party licenses from COPYING files in a clone before shipping a
dependency.

```bash
xcodegen generate     # after any project.yml change
xcodebuild -project Sugu.xcodeproj -scheme Sugu \
  -destination 'platform=macOS' build   # must pass
```

## 1. Architecture

- The shell owns UI and IMK wiring; conversion comes from the engines behind
  a `CandidateEngine`-style protocol; ranking comes from the ranker and AI
  layer.
- The AI layer reranks candidates; composition itself always resolves
  locally, and engine types stay behind their own protocol boundary.
- Engines load lazily on input-source switch.

## 2. App Code Conventions

- Swift 6 language mode (strict concurrency), latest Xcode and Swift.
- UI is laid out programmatically in code, organized in feature folders with
  one primary view controller per window.
- Every user-facing string is a key in the String Catalog
  (`Localizable.xcstrings`) from the first commit; lookups stay at
  view-controller level.
- Dark mode and VoiceOver accessibility work from the first commit;
  newer-OS APIs are availability-gated with a fallback.

## 3. Product & License

- License: **Apache-2.0**. Model: BYOK AI with the user's own key, zero
  telemetry — composition and conversion always resolve on-device; a bounded
  context window may be sent only to the user's own provider (BYOK).
- Budgets: AI cost well under $1/month for heavy use (3 candidates by default,
  user-adjustable 2–8; ~100 tokens/decision); resident memory well under 200MB.
- Public-facing docs describe the project only.

## 4. Git Conventions

- Standing authorization: commit and push in logical groups as work
  completes, directly to `main`.
- Commit messages are a single title line:
  `<type>(<scope>): <description>` — types: `feat` `fix` `refactor` `docs`
  `chore` `test` `perf` `style`.

| scope | Applies to |
|-------|-----------|
| `shell` | Swift / AppKit / InputMethodKit app code |
| `engines` | mozc / libpinyin integration |
| `ai` | local ranker, hesitation gate, BYOK client, learning loop |
| `docs` | README, `docs/` |
| `workspace` | repo-root files (`AGENTS.md`, `CLAUDE.md`, `.gitignore`, scripts) |

- Combine scopes for cross-cutting changes (`shell,engines`); refine with
  sub-dimensions (`engines/pinyin`).

## 5. Boundaries

- Third-party engines enter the project as dependencies: socket IPC for
  Mozc, a dynamic library for libpinyin.
- `Sugu.xcodeproj` stays generated from `project.yml`; when the scaffold
  lands, record all generated-artifact ignore rules here and in `.gitignore`
  in the same commit.
