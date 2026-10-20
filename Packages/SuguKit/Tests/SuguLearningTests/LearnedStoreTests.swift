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
        return try LearnedStore(url: url, syllabary: Self.syllabary, clock: { clock.now })
    }

    static let syllabary = PinyinSyllabary(["xi", "xia", "xian", "an", "n", "qu", "fan", "fang", "gan", "a"])

    @Test func learnsWholeCommitAndClauses() throws {
        let store = try makeStore()
        store.learn(Commit(text: "今日は晴れ", reading: "きょうははれ", clauses: [
            .init(reading: "きょうは", text: "今日は"), .init(reading: "はれ", text: "晴れ"),
        ]), mode: .japanese)
        #expect(store.lookup("きょうは", mode: .japanese).map(\.text) == ["今日は"])
        #expect(store.lookup("キョウハハレ", mode: .japanese).map(\.text) == ["今日は晴れ"])
        #expect(store.lookup("きょうは", mode: .chinese).isEmpty)
    }

    /// A commit holding text typed as is teaches only its clauses.
    @Test func learnsOnlyClausesOfACommitThatIsNoWord() throws {
        let store = try makeStore()
        store.learn(Commit(text: "事，好", reading: "shi4，hao3", clauses: [.init(reading: "shi4", text: "事")], mayBeWord: false), mode: .chinese)
        #expect(store.lookup("shi4", mode: .chinese).map(\.text) == ["事"])
        #expect(store.count == 1)
    }

    /// The store records its schema version, and a store made before
    /// versions existed is brought to it with its words.
    @Test func storeCarriesItsSchemaVersion() throws {
        do {
            let store = try makeStore()
            store.learn(Commit(text: "今日", reading: "きょう"), mode: .japanese)
        }
        let database = try SQLiteDatabase(url: url)
        try database.execute("PRAGMA user_version = 0")
        let store = try makeStore()
        var version = 0
        try SQLiteDatabase(url: url).query("PRAGMA user_version") { version = Int($0.int(0)) }
        #expect(version == 1)
        #expect(store.lookup("きょう", mode: .japanese).map(\.text) == ["今日"])
    }

    @Test func emojiAreNotLearned() throws {
        let store = try makeStore()
        store.learn(Commit(text: "👍", reading: "tongyi"), mode: .chinese)
        store.learn(Commit(text: "❤️", reading: "hongxin"), mode: .chinese)
        #expect(store.count == 0)
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
        #expect(store.lookup("xi'an", mode: .chinese).first?.text == "西安")
    }

    /// A word stored without an apostrophe is found for one typed with it
    /// only when its letters can have been split there and nowhere else.
    @Test func apostropheLookupsKeepTheirSplit() throws {
        let store = try makeStore()
        store.learn(Commit(text: "先去", reading: "xianqu"), mode: .chinese)
        store.learn(Commit(text: "方案", reading: "fangan"), mode: .chinese)
        store.learn(Commit(text: "西岸", reading: "xian"), mode: .chinese)
        #expect(store.lookup("xi'anqu", mode: .chinese).isEmpty)
        #expect(store.lookup("fan'gan", mode: .chinese).isEmpty)
        #expect(store.lookup("xi'an", mode: .chinese).map(\.text) == ["西岸"])
        #expect(PinyinSyllabary(["xi", "xia", "an", "n"]).splits(of: "xian", count: 2) == [[2]])
        #expect(Set(Self.syllabary.splits(of: "fangan", count: 2)) == [[3], [4]])
        #expect(Self.syllabary.splits(of: "xianqu", count: 3) == [[2, 4]])
        #expect(Self.syllabary.splits(of: "xianqu", count: 4).isEmpty)
        #expect(LearnedWord.normalize("zhang''san'", mode: .chinese) == "zhangsan")
    }

    /// Imported pinyin separates every syllable; none of it is kept.
    @Test func enteredReadingsDropApostrophes() throws {
        let store = try makeStore()
        _ = try store.importUserWords([(reading: "zhou'an", text: "周安", mode: .chinese)])
        #expect(store.lookup("zhouan", mode: .chinese).map(\.text) == ["周安"])
    }

    /// A damaged store is set aside and a fresh one opened, so learning
    /// goes on; a sound one is left alone.
    @Test func damagedStoreIsSetAside() throws {
        try makeStore().learn(Commit(text: "你好", reading: "nihao"), mode: .chinese)
        #expect(try makeStore().lookup("nihao", mode: .chinese).count == 1)
        let directory = url.deletingLastPathComponent()
        try Data(repeating: 0x5A, count: 8_192).write(to: url)
        let store = try makeStore()
        #expect(store.lookup("nihao", mode: .chinese).isEmpty)
        store.learn(Commit(text: "世界", reading: "shijie"), mode: .chinese)
        #expect(try makeStore().lookup("shijie", mode: .chinese).count == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("learned.sqlite.damaged-") && !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm") })
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

/// Another process holding the file (a second Sugu during an update).
@MainActor
struct LearnedStoreLockTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sugu-tests-\(UUID().uuidString)")
        .appendingPathComponent("learned.sqlite")

    /// Holds a write lock on the store's file for `seconds`.
    func holdLock(for seconds: Double) throws {
        nonisolated(unsafe) let other = try SQLiteDatabase(url: url)
        try other.execute("BEGIN IMMEDIATE")
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            try? other.execute("COMMIT")
        }
    }

    @Test func learnsWhileTheFileIsHeldBriefly() throws {
        let store = try LearnedStore(url: url)
        try holdLock(for: 0.1)
        store.learn(Commit(text: "你好", reading: "nihao"), mode: .chinese)
        let reopened = try LearnedStore(url: url)
        #expect(reopened.lookup("nihao", mode: .chinese).map(\.text) == ["你好"])
    }

    @Test func keepsWorkingAfterTheFileWasHeldTooLong() throws {
        let store = try LearnedStore(url: url)
        try holdLock(for: 0.5)
        store.learn(Commit(text: "你好", reading: "nihao"), mode: .chinese)
        Thread.sleep(forTimeInterval: 0.5)
        store.learn(Commit(text: "世界", reading: "shijie"), mode: .chinese)
        let reopened = try LearnedStore(url: url)
        #expect(reopened.lookup("shijie", mode: .chinese).map(\.text) == ["世界"])
    }
}
