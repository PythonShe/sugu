# Katakana for foreign words

Japanese writes foreign words in katakana, and the spelling a writer knows is
often the foreign one. This ADR records the user's decisions of 2026-11-04 on
offering katakana for words typed in Latin letters, in any language: `computer`
to コンピューター, `arbeit` to アルバイト, `beethoven` to ベートーベン. Loanwords
are a growing vocabulary, so the design has to keep up with new words.

## Decisions

1. **Japanese mode only, with a switch.** On by default, off in Settings. It
   reads the letters the composition already keeps beside the kana; nothing
   typed leaves the Mac.

2. **A word that leads is taken by Space.** A dictionary match leads the candidate
   list, ahead of the hiragana, unless its letters also read as a native Japanese
   word (`take`, 竹), when it stays behind the ordinary conversions and Space
   converts the kana as before. While a dictionary word leads, the composition
   shows the letters typed rather than half-formed kana (mcどなlds), Return commits
   those letters, Space takes the katakana, and Space again goes down the list.
   Changed after 1.2.0 from Space always converting the kana: with the letters on
   screen, that showed kana nobody had seen. The native-word flag is what keeps
   ordinary romaji from being taken.

3. **A permissive dictionary in the app, a larger one as a download.** UniDic
   (BSD), CLDR (Unicode) and filtered Wikidata (CC0) ship with Sugu. JMdict and
   Wiktionary are share-alike, so they stay an optional download.

4. **A guess for what no dictionary holds.** A trigram model over aligned
   letters and kana, trained at build time on the same permissive pairs and
   searched in Swift within the keystroke budget. A guess shows only when the
   letters do not read as romaji, and is never first.

5. **Choosing teaches the spelling.** A chosen word is learned under the typed
   letters, so a correction sticks. Words the user adds by hand under a Latin
   reading are offered the same way, which also covers guesses that were wrong.

6. **New words arrive with releases.** Each release rebuilds the data from the
   newest upstream, so there is no separate updater.

## Rejected

- **Dictionary only:** coinages and unseen names would show nothing.
- **Space always converting the kana:** chosen first and dropped after 1.2.0 (see
  2). The cost of the change remains: a Japanese word mistyped into a known
  spelling takes the katakana, and a second Space moves on from it.
- **Bundling JMdict:** the better coverage does not justify share-alike terms on
  the app's data.
- **Training on VOICEVOX's kanalizer dataset:** better on English, but it has no
  license file and is the output of a language model whose terms were not
  reviewed.
- **ICU's Latin-Katakana transform:** it reads letters as romaji, so
  `Schwarzenegger` becomes スチワルゼネッゲル.
