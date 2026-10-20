import Foundation
import Testing
import SuguCore
@testable import SuguLearning

/// A clock the tests move by hand.
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(days: Double = 0, hours: Double = 0) { now += days * 86_400 + hours * 3_600 }
}

@MainActor
struct LearnedStoreTests {
    let clock = TestClock()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sugu-tests-\(UUID().uuidString)")
        .appendingPathComponent("learned.sqlite")

    func makeStore() throws -> LearnedStore {
        let clock = clock
        return try LearnedStore(url: url, clock: { clock.now })
    }

    @Test func learnsWholeCommitAndClauses() throws {
        let store = try makeStore()
        store.learn(Commit(text: "今日は晴れ", reading: "きょうははれ", clauses: [
            .init(reading: "きょうは", text: "今日は"), .init(reading: "はれ", text: "晴れ"),
        ]), mode: .japanese)
        #expect(store.lookup("きょうは", mode: .japanese).map(\.text) == ["今日は"])
        #expect(store.lookup("キョウハハレ", mode: .japanese).map(\.text) == ["今日は晴れ"])
        #expect(store.lookup("きょうは", mode: .chinese).isEmpty)
    }

    @Test func ignoresUnconvertedText() throws {
        let store = try makeStore()
        store.learn(Commit(text: "nihao", reading: "nihao"), mode: .chinese)
        #expect(store.count == 0)
    }

    @Test func rankingPrefersFrequentAndRecent() throws {
        let store = try makeStore()
        store.learn(Commit(text: "拟好", reading: "nihao"), mode: .chinese)
        clock.advance(hours: 1)
        store.learn(Commit(text: "你好", reading: "ni'hao"), mode: .chinese)
        store.learn(Commit(text: "你好", reading: "nihao"), mode: .chinese)
        #expect(store.lookup("NiHao", mode: .chinese).map(\.text) == ["你好", "拟好"])
        let rare = try #require(store.lookup("nihao", mode: .chinese).last)
        store.setPinned(true, id: rare.id)
        #expect(store.lookup("nihao", mode: .chinese).first?.text == "拟好")
    }

    /// A word picked for xi'an is not offered first for xian; words
    /// learned for xian with a character per part still are for xi'an.
    @Test func apostrophesThatSplitDifferentlyStay() throws {
        let store = try makeStore()
        store.learn(Commit(text: "西安", reading: "xi'an"), mode: .chinese)
        #expect(store.lookup("xian", mode: .chinese).isEmpty)
        #expect(store.lookup("Xi'an", mode: .chinese).map(\.text) == ["西安"])
        store.learn(Commit(text: "先", reading: "xian"), mode: .chinese)
        store.learn(Commit(text: "西岸", reading: "xian"), mode: .chinese)
        #expect(Set(store.lookup("xi'an", mode: .chinese).map(\.text)) == ["西安", "西岸"])
        #expect(Set(store.lookup("xian", mode: .chinese).map(\.text)) == ["先", "西岸"])
        #expect(LearnedWord.normalize("fan'gan", mode: .chinese) == "fan'gan")
        #expect(LearnedWord.normalize("zhang''san'", mode: .chinese) == "zhangsan")
    }

    /// Imported pinyin separates every syllable; none of it is kept.
    @Test func enteredReadingsDropApostrophes() throws {
        let store = try makeStore()
        _ = try store.importUserWords([(reading: "zhou'an", text: "周安", mode: .chinese)])
        #expect(store.lookup("zhouan", mode: .chinese).map(\.text) == ["周安"])
    }

    @Test func forgetsTheLastHour() throws {
        let store = try makeStore()
        store.learn(Commit(text: "你好", reading: "nihao"), mode: .chinese)
        clock.advance(hours: 3)
        store.learn(Commit(text: "你好", reading: "nihao"), mode: .chinese)
        store.learn(Commit(text: "拟好", reading: "nihao"), mode: .chinese)
        store.forget(since: 3_600)
        let words = store.lookup("nihao", mode: .chinese)
        #expect(words.map(\.text) == ["你好"])
        #expect(words.first?.count == 1)
    }

    @Test func expiresUnusedLearnedWordsOnly() throws {
        let store = try makeStore()
        store.learn(Commit(text: "旧词", reading: "jiuci"), mode: .chinese)
        store.addUserWord(reading: "sugu", text: "すぐ", mode: .chinese)
        clock.advance(days: 200)
        #expect(store.expire(olderThan: 180) == 1)
        #expect(store.allWords().map(\.text) == ["すぐ"])
    }

    @Test func persistsAcrossLaunches() throws {
        do {
            let store = try makeStore()
            store.learn(Commit(text: "東京", reading: "とうきょう"), mode: .japanese)
        }
        let reopened = try makeStore()
        #expect(reopened.lookup("とうきょう", mode: .japanese).map(\.text) == ["東京"])
    }

    @Test func importCountsOnlyNewWords() throws {
        let store = try makeStore()
        store.addUserWord(reading: "sugu", text: "速具", mode: .chinese)
        let added = try store.importUserWords([
            ("sugu", "速具", .chinese), ("すぐ", "直ぐ", .japanese),
        ])
        #expect(added == 1)
        #expect(store.count == 2)
    }
}
