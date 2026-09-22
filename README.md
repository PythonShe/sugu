# Sugu

**Sugu** (すぐ — *"immediately"*) is an open-source, privacy-first AI input method for macOS, built for Japanese and Chinese composition.

The name is the thesis: the right word should appear *immediately* — in the first candidate slot, and within the pause you take while typing.

## Status

**Pre-alpha.** Single-developer project until the first release; nothing works yet. This repo is the seed.

## Principles

- **Local-first, privacy-first** — an input method reads everything you type. Sugu is auditable, sends nothing silently, and keeps composition on your machine.
- **BYOK intelligence** — optional AI-assisted ranking uses *your own* API key. No accounts, no telemetry, no server of ours in the middle.
- **Fast by architecture, not by hope** — the AI layer only fires when *you* hesitate; confident typing never waits on a network.
- **Open source** — Apache-2.0. Full stop, no proprietary tier.

## License

[Apache-2.0](LICENSE)
