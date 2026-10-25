# Contributing

Thanks for helping. For a bug or a wrong conversion, open an issue with what you typed, what you expected and what you got. For anything larger than a small fix, open an issue before writing code, so we can agree on the approach first.

## Pull requests

- Build and test as in the [README](README.md#building); `scripts/ci.sh` must pass.
- Follow the existing code: Swift 6, AppKit only (no SwiftUI), every user-facing string in `Localizable.xcstrings`.
- Nothing you type may leave the Mac: no telemetry, and no network traffic beyond update checks and downloads the user starts.
- Bundled code and data must be under a permissive or attribution-only license.
- Commit titles follow `<type>(<scope>): <description>`, e.g. `fix(engines/azookey): …`. The types are `feat` `fix` `refactor` `docs` `chore` `test` `perf` `style`.

## Sign-off

Every commit needs a `Signed-off-by` line, certifying the [Developer Certificate of Origin](https://developercertificate.org): that you wrote the change or otherwise have the right to submit it under Sugu's license. `git commit -s` adds the line. A check on each pull request verifies it.

Contributions are licensed under the GNU General Public License, version 3 or later, like the rest of Sugu.
