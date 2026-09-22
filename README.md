# Sugu

**Sugu** (直ぐ — *"immediately"*) is an open-source, privacy-first AI input method for macOS, built for Japanese and Chinese composition.

The name is the thesis: the right word should appear *immediately* — in the first candidate slot, and within the pause you take while typing.

## Status

**Pre-alpha.** Nothing works yet. This repo is the seed.

## Principles

- **Local-first, privacy-first** — an input method reads everything you type. Sugu is auditable, sends nothing silently, and keeps composition on your machine.
- **BYOK intelligence** — optional AI-assisted ranking uses *your own* API key. No accounts, no telemetry, no server of ours in the middle.
- **Fast by architecture, not by hope** — the AI layer only fires when *you* hesitate; confident typing never waits on a network.
- **Open source** — Apache-2.0. Full stop, no proprietary tier.

## Architecture (planned)

```
┌─ Swift / InputMethodKit shell ────────────────────────────┐
│                                                            │
│  CandidateEngine (protocol)                                │
│    ├─ JapaneseEngine  → mozc_server   (protobuf IPC)       │
│    └─ PinyinEngine    → libpinyin     (C API)              │
│                                                            │
│  LocalRanker          — adapts to your personal frequency  │
│  HesitationGate       — fires AI decisions only on pause   │
│  AI client (BYOK)     — boolean/typed decisions, your key  │
│  Learner              — fast picks are free training data  │
└────────────────────────────────────────────────────────────┘
```

### Stack

| Layer | Choice | License |
|---|---|---|
| Shell | Swift + InputMethodKit (AppKit) | — (ours, Apache-2.0) |
| Japanese engine | [Mozc](https://github.com/google/mozc) | BSD-3-Clause |
| Chinese engine | [libpinyin](https://github.com/libpinyin/libpinyin) | LGPL-3.0 (dynamically linked) |
| Ranking / AI layer | local ranker + BYOK boolean-model calls | Apache-2.0 |

## Roadmap

- [ ] MVP: installable IME, preedit + candidate panel, pinyin composition via libpinyin
- [ ] Japanese via `mozc_server` (protobuf over local socket)
- [ ] Local ranker (frequency → personalization)
- [ ] Hesitation gate + BYOK decision client
- [ ] Learning loop: confident picks train the local ranker offline

## Contributing

Not yet — until the MVP shape settles. Issues and discussion welcome.

## License

[Apache-2.0](LICENSE)
