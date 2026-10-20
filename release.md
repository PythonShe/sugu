# Release and updater plan

Everything between today's `main` and a 1.0 with working updates.
Decisions it builds on: D-020 (distribution), D-045 (Private Cloud
Compute signing), D-072 (release readiness), D-084 (feed domain), D-085
(pipeline, signed feed), D-086 (proprietary, private repository), D-087
(releases on R2), ADR 0006. Rewritten 2026-10-20.

## Shape

- **Artifacts** (`scripts/release.sh`): a Developer ID–signed app inside
  - a notarized, stapled `.pkg` (Developer ID Installer) that installs into `/Library/Input Methods`;
  - a notarized `.zip` of the stapled app, EdDSA-signed, for Sparkle;
  - `release.json` and `appcast.xml`, signed with the notes in it (the app requires a signed feed).
- **Where they go** (`scripts/publish-release.sh`, bucket `sugu-updates`, served at `https://sugu.zheng-she.com`):
  - `releases/<version>/Sugu-<version>.{pkg,zip}` (immutable; never replaced by different bytes);
  - `releases/<version>/notes/<lang>.md`;
  - `releases.json`, `latest.json`, then `appcast.xml` last.
- **Home page:** `site/` (Astro) on Cloudflare Pages project `sugu`; its functions serve the same paths from the bucket, plus `/download/` → newest `.pkg`.
- **Repository:** private. No GitHub releases; tags mark releases.

## Built (not yet run)

- [x] `release.sh`: notary profile or API key, temporary keychain, `RELEASE_VERSION` check, clean tree (untracked files too), Developer ID / hardened runtime / staple / Gatekeeper checks, notarization log on rejection or timeout, `release.json`, signed appcast with notes.
  - Sparkle's helpers are re-signed with Developer ID (its XPC services removed: Sugu is not sandboxed), and every piece of nested code is checked for Developer ID and a timestamp.
  - The archive's EdDSA signature is checked against the app's own `SUPublicEDKey` (`scripts/check-ed-signature.swift`), so a mismatched key pair cannot ship.
  - Sparkle's tools are downloaded and checked against their SHA-256 on every run, never taken from a cache.
  - The package is neither relocatable nor version checked: it always installs its own version.
- [x] `scripts/appcast.py` (one item, `<description sparkle:format="markdown" xml:lang>` per language), `scripts/release-notes.py` (split / fallback).
- [x] `publish-release.sh`: AWS CLI (CI) or `cf` (local); rollback guard; downloads verified byte-for-byte through the public URL; index merge keeps first dates; polls until the feed serves the new build.
  - Every guard runs before the first upload. A list the site answers 404 for counts as empty only when the bucket has none either (checked with the AWS CLI).
  - After a failed publish, re-run **failed jobs only**: re-running all of them rebuilds the release with different bytes (new signature timestamps), and that version can no longer be published.
- [x] `release.yml`: publishes one tag at a time (`release-publish`); every action pinned to a commit. `deploy-site.yml` deploys `main`, also when a release calls it from its tag.
- [x] `.github/workflows/release.yml`: prepare → notes → build (macos-26) → publish (R2) → site. Dry run = dispatch without tag, publish off.
- [x] `.github/workflows/release-notes.yml`: Claude, four languages, end_turn + shape check, fixed fallback; body through stdin.
- [x] `.github/workflows/deploy-site.yml`: push to `main` on site paths, after each release, manual; `pnpm check`, build, `wrangler pages deploy`; skips deploying without the Cloudflare secrets.
- [x] `site/`: home, changelog (from `releases.json` and notes at build time), privacy, licenses (`LICENSE` + notices), en/ja/zh-Hans/zh-Hant, security headers, no cookies or scripts beyond the language redirect.

## 1. Keys and accounts (owner)

- [x] **Developer ID Installer certificate:** in the login keychain (G2, 2026-10-20 to 2027-11-19; renew before then and update the secret). Export as `.p12` with a password.
- [x] **Developer ID Application certificate:** in the login keychain (G2, to 2031-02-10).
- [ ] **App Store Connect API key** (Developer role): the `.p8`, key ID, issuer ID.
- [ ] **Optional: Developer ID provisioning profile** for `com.zheng-she.inputmethod.Sugu` with Private Cloud Compute (D-045). Without it, release builds use the on-device model only.
- [ ] **Sparkle keys:** `generate_keys`, then `generate_keys -x sparkle.key` (private) and `generate_keys -p` (public). Back up the private key offline: losing it strands every install on its version, and it also signs the feed.
- [ ] **Cloudflare R2 API token:** Object Read & Write on `sugu-updates` only.
- [ ] **Cloudflare API token:** "Cloudflare Pages: Edit", for the site.
- [ ] **Anthropic API key**, for the notes.

## 2. GitHub secrets and variables (owner)

| Purpose | Secrets |
|---|---|
| Signing the app | `APPLE_CERTIFICATE` (base64 `.p12`), `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY` |
| Signing the `.pkg` | `APPLE_INSTALLER_CERTIFICATE`, `APPLE_INSTALLER_CERTIFICATE_PASSWORD`, `APPLE_INSTALLER_SIGNING_IDENTITY` |
| Notarization | `APPLE_API_KEY` (base64 `.p8`), `APPLE_API_KEY_ID`, `APPLE_API_ISSUER` |
| Private Cloud Compute (optional) | `APPLE_PROVISIONING_PROFILE` (base64) |
| Sparkle | `SPARKLE_PRIVATE_KEY` (the contents of the file from `generate_keys -x`) |
| R2 | `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` |
| Pages | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` |
| Release notes | `ANTHROPIC_API_KEY` |

Variables: `APPLE_TEAM_ID`, `SPARKLE_PUBLIC_ED_KEY`, optional `LLM_MODEL` (default `claude-opus-5-5`) and `LLM_EFFORT` (default `medium`). No workflow needs `contents: write`.

## 3. Hosting (before the first real release)

- [ ] Create the Pages project `sugu` (production branch `main`) and run `deploy-site.yml` once; check `https://sugu.pages.dev/` and that its functions read the bucket (`/latest.json` answers 404 until the first release).
- [ ] Bind the R2 bucket in the Pages project settings if the `wrangler.toml` binding is not picked up.
- [ ] **Move `sugu.zheng-she.com` from the bucket's custom domain to the Pages project.** Before the first release this carries no risk (nothing is installed yet); afterwards, check `/appcast.xml` and the downloads answer throughout.
- [ ] Optionally a cache rule for `/releases/*`, so downloads come from the edge rather than the function.

## 4. Proving it

- [ ] **Dry run** of `release.yml` (dispatch, no tag, publish off): notarizes, staples, passes Gatekeeper; notes in the four-language shape.
- [ ] **First release `v0.9.0`** (or 1.0): install the `.pkg` from `/download/` on a clean user account; the input source registers, enables and selects (D-020).
- [ ] **One Sparkle update between two notarized builds** (todo §15), with a second tag: offered, notes in the system language, EdDSA verified, installs into `/Library/Input Methods`, the input source and learned words survive.
  - A scheduled check shows **Update Available…** in the input menu rather than a window behind the frontmost app.
  - Also check: Sugu running for a second logged-in user while the update installs, and Sparkle's relaunch while macOS starts Sugu for a key.
- [ ] **Signed feed:** an installed build rejects a feed edited after signing.
- [ ] **Rollback guard:** publishing an older build is refused; republishing a version with different bytes is refused.
- [ ] **Soak test** (`sugu-bench --fuzz N --soak K`): footprint flat over a long run; record the peak during a librime deploy.

## 5. Before shipping (device checks and open work)

- [ ] On-device checks: the login window and Wi-Fi sheets see no composition; Alacritty takes punctuation; `hidePalettes` runs on screen lock; a click elsewhere commits in TextEdit and Chrome.
- [ ] VoiceOver announcements from the candidate panel.
- [ ] Settings come forward when opened from the input menu while another app is active.
- [ ] Taiwanese readings and forms (Zhuyin).
- [ ] Score the built-in Chinese and Japanese input methods on the same sets (needs foreground typing).
- [ ] Measure the installed app's footprint during real typing, next to Apple Pinyin (24 MB) and Apple Japanese (46 MB).
- [ ] Have a lawyer read `LICENSE` (D-086).
