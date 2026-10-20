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
   pruned. The models are bundled (16.4 MB for Japanese, 5.5 MB for
   Chinese), memory-mapped, and attributed in the notices. Corpora under share-alike or unclear terms
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
   corpus (19 of Tatoeba's sentences match them). On the first 50
   Japanese sentences `sugu-bench` top-1 went from 78% to 86%; on 51
   written afterwards to check it, from 78% to 84%; learned names stay
   first; keystroke p99 is unchanged.

6. **No grammar for librime.** librime builds one sentence and offers no
   alternatives to rerank. A small octagram grammar built from Tatoeba's
   Mandarin sentences scored 94% against 90% on the first 50 bench
   sentences, but on 50 more it broke as many common words as it fixed
   (老师 → 老是, 医生 → 一生) at every scale tried: 92 thousand sentences
   are too few for collocation counts inside librime's search. The
   wanxiang grammar model stays the download.

7. **Respelling within a sentence.** The engine proposes at most five
   sentences, and the right one is often missing when it differs in a
   single word (雪が for 行きが, 何時に for 汝に). After ranking, each
   content word of the best sentence may be replaced by another spelling
   of its reading from the same dictionary, as one word or several,
   when the engine's cost of the words and their connections plus the
   model's score is higher. Words from the user's dictionary and learned
   words, and text that spells one, keep their spelling. A particle the
   engine joined to the next word (を引き) is split off first, so the word
   is respelled too. Top-1 went from 85% to 90%.

8. **Respelling Chinese sentences.** librime's sentence is read as words
   of the dictionary's list (two or three syllables, weight at least
   1,000, and every single character), and each span of up to three
   syllables may be rewritten as another spelling of the same syllables,
   one word or several, when the character model, given the text before
   the span and after it, reads it as more natural by a clear margin
   (4 in natural log probability, with the list's own word probabilities
   at weight 0.3). The respelled sentence is shown first and librime's
   own follows it; learned words and text that spells one keep their
   spelling. The model and list are Simplified: a sentence in Traditional
   or Japanese forms is respelled in Simplified and only the characters
   that changed are converted back. Top-1
   went from 91% to 97% on 150 sentences and learned words from 83% to
   92%, with no sentence broken; on 50 sentences written before the
   method was tried on them, 44 to 49.

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
