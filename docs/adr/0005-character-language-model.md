# Character language model for ranking conversions

The Japanese engine ranks a sentence by word costs and part-of-speech
connection costs only. It has no notion of which words go together, so it
writes 雨が古そう for 雨が降りそう, 行きが for 雪が, and 強の会議 for
今日の会議, even when the right sentence is among its first five. This ADR
records the user's request of 2026-10-20 for n-gram ranking, and how Sugu
does it.

## Decisions

1. **A character n-gram model, built from open text.** A 5-gram model over
   characters, smoothed with interpolated Kneser-Ney, scores how natural a
   candidate reads after the text before the caret. Characters need no
   tokenizer and cover any word the dictionary has. Built from Tatoeba
   (CC BY 2.0 FR) at a versioned OPUS snapshot pinned by checksum in
   `scripts/versions.sh`; n-grams of three or more characters seen once are
   pruned. The model is bundled (16.4 MB for Japanese, 1.4 million
   entries), memory-mapped, and attributed in the notices. Corpora under share-alike or unclear terms
   (Wikipedia, ReazonSpeech, web crawls without a stated license) are not
   used.

2. **It reranks; it does not convert.** The engine still builds the lattice
   and proposes sentences. The model reorders the engine's whole-sentence
   candidates by the engine's cost plus the model's log probability. A
   sentence the engine did not propose is never produced, so the model
   cannot introduce words the dictionary lacks or learned words would
   override.

3. **On the keystroke path, within budget.** Scoring five sentences costs a
   few hundred lookups in sorted arrays; keystroke p99 stays under 5 ms
   (ADR 0003, decision 22). The text before the caret is read only in
   memory, as for Zenzai, and never stored.

4. **No setting.** Ranking is part of conversion, like the engine's own
   costs. With Zenzai on, Zenzai's choice stands.

5. **Measured, not assumed.** Bench sentences are left out of the model's
   corpus (15 of Tatoeba's sentences match them). On the Japanese seed set
   `sugu-bench` top-1 goes from 78% to 86% and characters from 95.7% to
   97.5%; learned names stay first; keystroke p99 is unchanged.

6. **Chinese gets the same data through librime.** librime builds one
   sentence and offers no alternatives to rerank, but it already scores
   collocations with librime-octagram. Sugu bundles a small grammar model
   (1.7 MB) built from Tatoeba's Mandarin sentences in Simplified script:
   character collocations of two to six characters and sentence endings
   seen at least twice, counts scaled to octagram's penalties. The
   downloaded wanxiang model (ADR 0002, decision 4) replaces it when the
   user turns that on. On the Chinese seed set top-1 goes from 90% to 94%,
   the same as the download.

## Later phases

- A personal model from what the user commits, kept in the learned store
  with the same gates as learned words, blended with the bundled one; it
  can also feed Zenzai's personalization.

## Considered options

- **Word n-grams over AzooKey's segmentation:** need a tokenizer at build
  time whose output matches the dictionary's words; characters avoid both.
- **Lexical costs inside AzooKey's lattice:** would also fix sentences the
  engine does not propose, but needs a change upstream; reranking ships
  without a fork, and the hook can follow.
- **A larger web corpus (FineWeb-2, ODC-By):** more coverage, but gigabytes
  to fetch at build time and crawl terms to review; Tatoeba is enough for
  the gain measured and can be joined later.
