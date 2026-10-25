# Proprietary license and distribution from Sugu's own domain

> Since 2026-10-25 Sugu is GPL-3.0-or-later and its repository is public;
> decisions 1, 2 and 5 no longer hold. Releases stay
> on `sugu.zheng-she.com` (decision 4), and bundled components stay
> permissive (decision 3).

Sugu was licensed Apache-2.0 with the intent to publish its repository.
On 2026-10-20 the owner decided to make it proprietary and free of charge,
and to release it from the project's own domain rather than GitHub
Releases. This ADR records what that means for the code, the bundled
components and the release pipeline.

## Decisions

1. **Proprietary, free of charge.** `LICENSE` grants use of unmodified
   copies downloaded from `https://sugu.zheng-she.com`, at no cost, and
   reserves everything else: no redistribution, modification or reverse
   engineering beyond what law allows. Sugu is not sold. Copies published
   earlier under Apache-2.0 stay under that license; every later version
   is under `LICENSE`.

2. **The repository stays private.** Nothing in it is published except
   release builds and the home page. CI stays manual-only, since macOS
   runner minutes are billed for private repositories.

3. **Bundled components stay permissive.** Every bundled library and data
   set is under a permissive or attribution-only license (BSD, MIT,
   Apache-2.0, BSL-1.0, Unicode, CC-BY-4.0, CC BY 2.0 FR), all of which
   allow a proprietary product as long as their notices ship;
   `ThirdPartyNotices.txt` remains in the app and its check in
   `scripts/ci.sh`. Dual-licensed libraries (marisa-trie, SwiftyMarisa) are
   used under their BSD option. GPL, LGPL and share-alike components
   (rime-ice, the Zenzai model) remain downloads the user starts, never
   bundled.

4. **Releases on R2, under `sugu.zheng-she.com`.** The package, the update
   archive and the release notes go to the `sugu-updates` bucket at
   `releases/<version>/`, with `latest.json` and `releases.json` describing
   them, and the signed `appcast.xml` last (D-084 and the release pipeline
   in `.github/workflows/release.yml`). Tags still mark each release in
   git; there are no GitHub releases.

5. **What the app says.** Settings › Advanced links to the website instead
   of the source code; the copyright line names the owner; the
   acknowledgements are unchanged.

## Consequences

- Trust in an input method that sees every keystroke can no longer rest on
  reading its source; it rests on the privacy behavior stated on the site
  (no telemetry, the network traffic listed in CLAUDE.md) and on Apple's
  notarization.
- The home page is the only place users download Sugu, so it must keep
  `latest.json` and the download links working through any hosting change.
- A future outside contribution needs a contributor agreement before it
  can ship under `LICENSE`.
