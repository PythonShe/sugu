import Foundation
import Testing
@testable import SuguCore

struct LoanwordSpellingTests {
    @Test func foldsToWhatALatinKeyboardTypes() {
        #expect(LoanwordSpelling.key("Computer") == "computer")
        #expect(LoanwordSpelling.key("café") == "cafe")
        #expect(LoanwordSpelling.key("Müller") == "muller")
        #expect(LoanwordSpelling.key("Dvořák") == "dvorak")
        #expect(LoanwordSpelling.key("Straße") == "strasse")
        #expect(LoanwordSpelling.key("Søren") == "soren")
        #expect(LoanwordSpelling.key("rock 'n' roll") == "rocknroll")
        #expect(LoanwordSpelling.key("coca-cola") == "cocacola")
        #expect(LoanwordSpelling.key("ＰＡＲＩＳ") == "paris")
    }

    @Test func refusesWhatIsNoSpelling() {
        #expect(LoanwordSpelling.key("こんぷ") == nil)
        #expect(LoanwordSpelling.key("Москва") == nil)
        #expect(LoanwordSpelling.key("a+b") == nil)
        #expect(LoanwordSpelling.key("123") == nil)
        #expect(LoanwordSpelling.key("") == nil)
    }
}

struct RomajiReadingTests {
    @Test func readsRomajiAsKana() {
        #expect(RomajiReading("watashi").kana == "わたし")
        #expect(RomajiReading("kyou").kana == "きょう")
        #expect(RomajiReading("gakkou").kana == "がっこう")
        #expect(RomajiReading("hon").kana == "ほん")
        #expect(RomajiReading("kanji").kana == "かんじ")
        #expect(!RomajiReading("watashi").looksForeign)
    }

    @Test func aSyllableStillBeingTypedIsNotForeign() {
        #expect(!RomajiReading("watash").looksForeign)
        #expect(RomajiReading("watash").kana == nil)
        #expect(!RomajiReading("ky").looksForeign)
    }

    @Test func spotsLettersNoSyllableUses() {
        #expect(RomajiReading("arbeit").looksForeign)
        #expect(RomajiReading("computer").looksForeign)
        #expect(RomajiReading("hotel").looksForeign)
        #expect(RomajiReading("test").looksForeign)
        #expect(RomajiReading("xylophone").looksForeign)
        #expect(!RomajiReading("chikatetsu").looksForeign)
    }

    /// Foreign words made only of syllables read as romaji, so nothing marks
    /// them as foreign.
    @Test func foreignWordsThatScanAsRomajiAreNotSpotted() {
        #expect(!RomajiReading("antonio").looksForeign)
        #expect(RomajiReading("banana").kana == "ばなな")
    }
}

struct LoanwordTableTests {
    private func table() throws -> LoanwordTable {
        try LoanwordTable(data: LoanwordTable.encode([
            .init(key: "paris", words: ["パリ", "パリス"]),
            .init(key: "computer", words: ["コンピューター"]),
            .init(key: "take", words: ["テーク"], alsoJapanese: true),
            .init(key: "a", words: ["エー"]),
        ]))
    }

    @Test func findsEntriesWhateverOrderTheyWereGiven() throws {
        let table = try table()
        #expect(table.count == 4)
        #expect(table.entry(for: "paris")?.words == ["パリ", "パリス"])
        #expect(table.entry(for: "computer")?.words == ["コンピューター"])
        #expect(table.entry(for: "a")?.words == ["エー"])
        #expect(table.entry(for: "take")?.alsoJapanese == true)
        #expect(table.entry(for: "paris")?.alsoJapanese == false)
    }

    @Test func missesWhatItDoesNotHold() throws {
        let table = try table()
        #expect(table.entry(for: "pari") == nil)
        #expect(table.entry(for: "pariss") == nil)
        #expect(table.entry(for: "") == nil)
        #expect(table.entry(for: "zzz") == nil)
    }

    @Test func anEmptyTableWorks() throws {
        let table = try LoanwordTable(data: LoanwordTable.encode([]))
        #expect(table.count == 0)
        #expect(table.entry(for: "paris") == nil)
    }

    @Test func refusesDamagedData() throws {
        #expect(throws: LoanwordTable.LoadError.self) { try LoanwordTable(data: Data([1, 2, 3])) }
        #expect(throws: LoanwordTable.LoadError.self) { try LoanwordTable(data: Data(repeating: 0, count: 64)) }
        let whole = LoanwordTable.encode([.init(key: "paris", words: ["パリ"])])
        #expect(throws: LoanwordTable.LoadError.self) { try LoanwordTable(data: whole.dropLast(2)) }
    }
}

struct KatakanaGuesserTests {
    /// A model that knows two readings of `c`, preferring カ, and `a`, `t`.
    private func guesser() throws -> KatakanaGuesser {
        let graphones: [KatakanaGuesser.Model.Graphone] = [
            .init(letters: "", kana: "", unigram: 0, backoff: 0.1),
            .init(letters: "", kana: "", unigram: 0.2, backoff: 0),
            .init(letters: "a", kana: "", unigram: 0.05, backoff: 0.1),
            .init(letters: "ca", kana: "カ", unigram: 0.4, backoff: 0.1),
            .init(letters: "ca", kana: "ケ", unigram: 0.1, backoff: 0.1),
            .init(letters: "t", kana: "ト", unigram: 0.25, backoff: 0.1),
        ]
        return try KatakanaGuesser(data: KatakanaGuesser.encode(.init(
            graphones: graphones, unigramBackoff: 0.01,
            bigrams: [(last: 0, graphone: 3, value: 0.5), (last: 3, graphone: 5, value: 0.6), (last: 5, graphone: 1, value: 0.7)],
            trigrams: [(previous: 0, last: 3, graphone: 5, value: 0.8)],
            secondOrderBackoffs: [(previous: 0, last: 0, value: 0.2), (previous: 0, last: 3, value: 0.2)]
        )))
    }

    @Test func ranksTheLikeliestFirst() throws {
        let guesses = try guesser().guesses(for: "cat")
        #expect(guesses.map(\.text) == ["カト", "ケト"])
        #expect(guesses[0].score > guesses[1].score)
    }

    @Test func aLimitKeepsTheBest() throws {
        #expect(try guesser().guesses(for: "cat", limit: 1).map(\.text) == ["カト"])
    }

    @Test func noGuessForWhatItCannotRead() throws {
        let guesser = try guesser()
        #expect(guesser.guesses(for: "").isEmpty)
        #expect(guesser.guesses(for: "zzz").isEmpty)
        #expect(guesser.guesses(for: "cat1").isEmpty)
        #expect(guesser.guesses(for: String(repeating: "cat", count: 20)).isEmpty)
    }

    @Test func refusesDamagedData() {
        #expect(throws: KatakanaGuesser.LoadError.self) { try KatakanaGuesser(data: Data([1, 2, 3])) }
        #expect(throws: KatakanaGuesser.LoadError.self) { try KatakanaGuesser(data: Data(repeating: 0, count: 256)) }
    }
}

struct ForeignWordsTests {
    private func words(extra: [LoanwordTable.Entry] = []) throws -> ForeignWords {
        let bundled = try LoanwordTable(data: LoanwordTable.encode([
            .init(key: "computer", words: ["コンピューター"]),
            .init(key: "take", words: ["テーク"], alsoJapanese: true),
        ]))
        var tables = [bundled]
        if !extra.isEmpty { tables.append(try LoanwordTable(data: LoanwordTable.encode(extra))) }
        return ForeignWords(tables: tables, guesser: nil)
    }

    @Test func aDownloadedDictionaryAddsToTheBundledOne() throws {
        let words = try words(extra: [
            .init(key: "computer", words: ["コンピューター", "コンピュータ"]),
            .init(key: "karte", words: ["カルテ"]),
        ])
        #expect(words.match(typed: "computer")?.words == ["コンピューター", "コンピュータ"])
        #expect(words.match(typed: "karte")?.words == ["カルテ"])
    }

    @Test func matchesWhateverTheCase() throws {
        #expect(try words().match(typed: "Computer")?.words == ["コンピューター"])
        #expect(try words().match(typed: "Computer")?.spelling == "computer")
    }

    @Test func kanaKeysAreNoSpelling() throws {
        #expect(try words().match(typed: "こんにちは") == nil)
    }

    @Test func anUnknownSpellingStillMatchesForLearnedWords() throws {
        let match = try words().match(typed: "kubernetes")
        #expect(match?.spelling == "kubernetes")
        #expect(match?.words.isEmpty == true)
        #expect(match?.guesses.isEmpty == true)
    }
}
