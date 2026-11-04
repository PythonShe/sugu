import Foundation
import Testing
import SuguCore
import SuguLearning
@testable import SuguInput

/// Foreign words typed in Latin letters offer katakana in Japanese mode.
extension InputSessionTests {
    private func foreignSession(_ configure: (inout Preferences) -> Void = { _ in }) throws -> InputSession {
        source.foreignWords = ForeignWords(tables: [try LoanwordTable(data: LoanwordTable.encode([
            .init(key: "computer", words: ["コンピューター", "コンピュータ"]),
            .init(key: "take", words: ["テーク"], alsoJapanese: true),
            .init(key: "tv", words: ["テレビ"]),
        ]))], guesser: try Self.guesser())
        japanese.table["computer"] = ["こんぷてr"]
        japanese.table["take"] = ["竹", "丈", "岳", "嶽"]
        japanese.table["tv"] = ["tv"]
        japanese.table["blog"] = ["ぶぉg", "ぶぉぐ", "ぼぐ"]
        let session = makeSession(configure)
        session.setMode(.japanese)
        return session
    }

    /// Guesses ブログ then ブログー for `blog`, whatever else it is asked.
    private static func guesser() throws -> KatakanaGuesser {
        try KatakanaGuesser(data: KatakanaGuesser.encode(.init(
            graphones: [
                .init(letters: "", kana: "", unigram: 0, backoff: 0.1),
                .init(letters: "", kana: "", unigram: 0.2, backoff: 0),
                .init(letters: "bl", kana: "ブ", unigram: 0.3, backoff: 0.1),
                .init(letters: "og", kana: "ログ", unigram: 0.3, backoff: 0.1),
                .init(letters: "og", kana: "ログー", unigram: 0.1, backoff: 0.1),
            ],
            unigramBackoff: 0.01, bigrams: [], trigrams: [], secondOrderBackoffs: [(previous: 0, last: 0, value: 0.2)]
        )))
    }

    /// Steps into the list and commits a row, as Japanese composition picks.
    private func pick(row: Int, in session: InputSession) {
        for _ in 0...row { _ = session.handle(Key.tab) }
        _ = session.handle(Key.enter)
    }

    private func candidates(_ session: InputSession) -> [String] {
        session.display.candidates?.candidates.map(\.text) ?? []
    }

    @Test func aDictionaryMatchLeadsTheList() throws {
        let session = try foreignSession()
        type("computer", into: session)
        #expect(candidates(session).prefix(3) == ["コンピューター", "コンピュータ", "こんぷてr"])
    }

    @Test func spaceStillConvertsTheKana() throws {
        let session = try foreignSession()
        type("computer", into: session)
        _ = session.handle(Key.space)
        #expect(client.markedText == "こんぷてr")
    }

    @Test func choosingItCommitsAndTeachesTheSpelling() throws {
        let session = try foreignSession()
        type("computer", into: session)
        pick(row: 1, in: session)
        #expect(client.document == "コンピュータ")
        #expect(store.lookup("computer", mode: .japanese).map(\.text) == ["コンピュータ"])
    }

    @Test func aWordThatIsAlsoJapaneseStaysBehindItsConversions() throws {
        let session = try foreignSession()
        type("take", into: session)
        let list = candidates(session)
        #expect(list.first == "竹")
        let katakana = try #require(list.firstIndex(of: "テーク"))
        #expect(katakana >= 2)
        #expect(katakana < list.firstIndex(of: "岳")!)
    }

    @Test func aVeryShortSpellingDoesNotLead() throws {
        let session = try foreignSession()
        type("tv", into: session)
        #expect(candidates(session).first == "tv")
        #expect(candidates(session).contains("テレビ"))
    }

    @Test func aGuessIsOfferedButNeverFirst() throws {
        let session = try foreignSession()
        type("blog", into: session)
        let list = candidates(session)
        #expect(list.first == "ぶぉg")
        let guess = try #require(list.firstIndex(of: "ブログ"))
        #expect(guess < 7)
        #expect(list.contains("ブログー"))
        #expect(list.firstIndex(of: "ブログー")! > guess)
    }

    @Test func aChosenGuessComesBackAfterTheFirstConversion() throws {
        let session = try foreignSession()
        type("blog", into: session)
        let row = try #require(candidates(session).firstIndex(of: "ブログ"))
        pick(row: row, in: session)
        #expect(client.document == "ブログ")
        type("blog", into: session)
        #expect(candidates(session).prefix(2) == ["ぶぉg", "ブログ"])
    }

    @Test func romajiGetsNoGuess() throws {
        let session = try foreignSession()
        type("nihongo", into: session)
        #expect(!(session.display.candidates?.candidates.contains {
            if case .foreignWord = $0.source { true } else { false }
        } ?? false))
    }

    @Test func aWordAddedByHandUnderASpellingIsOffered() throws {
        let session = try foreignSession()
        #expect(store.addUserWord(reading: "kubernetes", text: "クバネティス", mode: .japanese))
        japanese.table["kubernetes"] = ["くべrねてs"]
        type("kubernetes", into: session)
        #expect(candidates(session).contains("クバネティス"))
    }

    @Test func undoTakesTheWordBackAndRetypesTheLetters() throws {
        let session = try foreignSession()
        type("computer", into: session)
        pick(row: 0, in: session)
        #expect(client.document == "コンピューター")
        #expect(session.handle(Key.undo))
        #expect(client.document.isEmpty)
        #expect(client.markedText == "computer")
        #expect(store.lookup("computer", mode: .japanese).isEmpty)
    }

    @Test func theSwitchTurnsItOff() throws {
        let session = try foreignSession { $0.foreignWordKatakana = false }
        type("computer", into: session)
        #expect(!candidates(session).contains("コンピューター"))
    }

    @Test func chineseModeOffersNoKatakana() throws {
        let session = try foreignSession()
        session.setMode(.chinese)
        type("computer", into: session)
        #expect(!candidates(session).contains("コンピューター"))
    }
}
