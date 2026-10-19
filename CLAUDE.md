# Sugu Rules

Sugu is an open-source, privacy-first input method for macOS for Japanese and
Chinese composition. Single-component repo — Swift / AppKit / InputMethodKit.
`AGENTS.md` is a verbatim copy of `CLAUDE.md`; after editing either, re-copy it
over the other in the same commit. Decisions live in `docs/adr/`; domain
language in `CONTEXT.md`.

## 0. Tech Stack & Dev Commands

| Layer | Technology | Notes |
|------|------|------|
| Shell | Swift + AppKit + InputMethodKit (IMKServer / IMKInputController) | one input source, installed in `/Library/Input Methods` |
| Project | XcodeGen + SwiftPM | `project.yml` is the source of truth; `Sugu.xcodeproj` is generated and gitignored |
| Chinese engine | librime (BSD-3-Clause) + rime-wanxiang data (CC-BY-4.0) | C API; built by script into a static `.xcframework` |
| Japanese engine | AzooKeyKanaKanjiConverter (MIT) | SwiftPM, in-process; Zenzai traits off |
| Updates | Sparkle | system-profile reporting off |

Verify third-party licenses from COPYING files in a clone before shipping a
dependency.

```bash
xcodegen generate     # after any project.yml change
xcodebuild -project Sugu.xcodeproj -scheme Sugu \
  -destination 'platform=macOS' build   # must pass
```

## 1. Architecture

- The shell owns UI, IMK wiring, and mode switching between Chinese,
  Japanese, and English inside a single input source.
- Conversion comes from the engines behind a `CandidateEngine`-style protocol;
  engine types stay behind that boundary.
- Learned words live in Sugu's own store behind one interface over both
  engines; text read from the document is never persisted.
- Engines load lazily on first use of their mode.

## 2. App Code Conventions

- Swift 6 language mode (strict concurrency), latest Xcode and Swift.
- UI is laid out programmatically in code, organized in feature folders with
  one primary view controller per window. The candidate window is drawn with
  Core Text and `CALayer` — no Auto Layout or SwiftUI on the keystroke path.
- Every user-facing string is a key in the String Catalog
  (`Localizable.xcstrings`) from the first commit; lookups stay at
  view-controller level.
- Dark mode and VoiceOver accessibility work from the first commit;
  newer-OS APIs are availability-gated with a fallback.

## 3. Product & License

- License: **Apache-2.0**. Zero telemetry; composition, conversion, and
  learning resolve on-device. The only network traffic is update checks and
  user-initiated downloads.
- Budgets: keystroke to updated candidates < 5 ms p99; candidate-window draw
  < 16 ms; resident memory < 200 MB in the default configuration.
- GPL-licensed code or data is never bundled.
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
| `engines` | librime / AzooKey integration and dictionary data |
| `learning` | learned-word store, inspector, dictionary import/export |
| `docs` | README, `docs/` |
| `workspace` | repo-root files (`AGENTS.md`, `CLAUDE.md`, `.gitignore`, scripts) |

- Combine scopes for cross-cutting changes (`shell,engines`); refine with
  sub-dimensions (`engines/rime`, `engines/azookey`).

## 5. Boundaries

- Third-party engines enter the project as dependencies: librime as a prebuilt
  static `.xcframework` from a build script, AzooKeyKanaKanjiConverter through
  SwiftPM. GPL-licensed dictionaries (e.g. rime-ice) are user downloads only.
- `Sugu.xcodeproj` stays generated from `project.yml`; when the scaffold
  lands, record all generated-artifact ignore rules here and in `.gitignore`
  in the same commit.
