import Foundation
import Testing
import SuguCore
import SuguLM
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
        // As before versions: without the columns a later step adds.
        try database.execute("ALTER TABLE words DROP COLUMN shown; ALTER TABLE words DROP COLUMN script; PRAGMA user_version = 0")
        let store = try makeStore()
        var version = 0
        try SQLiteDatabase(url: url).query("PRAGMA user_version") { version = Int($0.int(0)) }
        #expect(version == 3)
        #expect(store.lookup("きょう", mode: .japanese).map(\.text) == ["今日"])
    }

    /// A store from before n-grams gains their tables and keeps its words.
    @Test func aStoreBeforeNGramsGainsThem() throws {
        do {
            let store = try makeStore()
            store.learn(Commit(text: "今日", reading: "きょう"), mode: .japanese)
        }
        try SQLiteDatabase(url: url).execute("""
            DROP TABLE ngrams; DROP TABLE ngram_events;
            ALTER TABLE words DROP COLUMN shown; ALTER TABLE words DROP COLUMN script; PRAGMA user_version = 1
            """)
        let store = try makeStore()
        var commit = Commit(text: "描く", reading: "かく")
        commit.context = "絵を"
        store.learn(commit, mode: .japanese)
        #expect(store.lookup("きょう", mode: .japanese).map(\.text) == ["今日"])
        #expect(store.personalNGrams(for: .japanese).count(of: "を描") == 1)
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
    @Test func enteredReadingsDropApostrophes() async throws {
        let store = try makeStore()
        _ = try await store.importUserWords([(reading: "zhou'an", text: "周安", mode: .chinese)])
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

    @Test func importCountsOnlyNewWords() async throws {
        let store = try makeStore()
        store.addUserWord(reading: "sugu", text: "速具", mode: .chinese)
        let added = try await store.importUserWords([
            ("sugu", "速具", .chinese), ("すぐ", "直ぐ", .japanese),
        ])
        #expect(added == 1)
        #expect(store.count == 2)
    }

    /// A rolled-back write leaves memory as SQLite has it: here another
    /// process already stored one of the words.
    @Test func failedWriteLeavesMemoryAsStored() throws {
        let store = try makeStore()
        let other = try makeStore()
        other.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        let words = ["新词", "速贵"].map {
            LearnedWord(id: 0, mode: .chinese, reading: "sugu", text: $0, kind: .user, count: 0, pinned: false, firstUsed: clock.now, lastUsed: clock.now)
        }
        #expect(throws: (any Error).self) { try store.merge(words) }
        #expect(store.lookup("sugu", mode: .chinese).map(\.text) == ["速贵"])
        store.addUserWord(reading: "kuai", text: "快", mode: .chinese)
        #expect(Set(try makeStore().allWords().map(\.text)) == ["速贵", "快"])
    }

    /// A Sugu file the user imports brings back what Delete All removed.
    @Test func restoringBringsBackDeletedWords() async throws {
        let store = try makeStore()
        store.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        let backup = store.allWords()
        clock.advance(hours: 1)
        store.deleteAll()
        #expect(try store.merge(backup) == 0)
        #expect(try await store.restore(backup) == 1)
        #expect(store.allDeletions().isEmpty)
        // As used now, so a deletion another Mac still carries keeps it.
        #expect(store.allWords().first?.lastUsed == clock.now)
    }

    /// Other Macs' learned words that expiry would delete are not taken.
    @Test func mergeSkipsWhatExpiryDeletes() throws {
        let store = try makeStore()
        store.expire(olderThan: 30)
        let old = clock.now.addingTimeInterval(-40 * 86_400)
        func word(_ text: String, _ kind: LearnedWord.Kind, pinned: Bool = false) -> LearnedWord {
            LearnedWord(id: 0, mode: .chinese, reading: "ci", text: text, kind: kind, count: 1, pinned: pinned, firstUsed: old, lastUsed: old)
        }
        #expect(try store.merge([word("词", .learned), word("辞", .learned, pinned: true), word("此", .user)]) == 2)
        #expect(Set(store.allWords().map(\.text)) == ["辞", "此"])
        #expect(store.expiringCount(olderThan: 30) == 0)
    }

    /// An undone commit is remembered as deleted, for sync.
    @Test func unlearningRemembersTheDeletion() throws {
        let store = try makeStore()
        let commit = Commit(text: "你好", reading: "nihao")
        store.learn(commit, mode: .chinese)
        store.unlearn(commit, mode: .chinese)
        #expect(store.allDeletions().map(\.text) == ["你好"])
        store.learn(commit, mode: .chinese)
        #expect(store.allDeletions().isEmpty)
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

/// Chinese words are one word in any script, stored in Simplified and
/// shown in the script being typed (D-094).
@MainActor
struct LearnedStoreScriptTests {
    let clock = TestClock()
    let forms = TestChineseForms()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sugu-tests-\(UUID().uuidString)")
        .appendingPathComponent("learned.sqlite")

    func makeStore() throws -> LearnedStore {
        let clock = clock
        let store = try LearnedStore(url: url, clock: { clock.now })
        store.chineseForms = forms
        return store
    }

    @Test func aWordTypedInEitherScriptIsOneWord() throws {
        let store = try makeStore()
        store.learn(Commit(text: "學習", reading: "xuexi"), mode: .chinese, script: .traditional)
        clock.advance(hours: 1)
        store.learn(Commit(text: "学习", reading: "xuexi"), mode: .chinese, script: .simplified)
        let words = store.lookup("xuexi", mode: .chinese)
        #expect(words.map(\.text) == ["学习"])
        #expect(words.first?.count == 2)
        #expect(words.first?.shown == "学习")
        #expect(words.first?.script == .simplified)
    }

    /// The bug this design fixes: a word typed in Traditional is offered in
    /// Simplified when Simplified is typed, and the other way round.
    @Test func aWordIsShownInTheScriptInUse() throws {
        let store = try makeStore()
        store.learn(Commit(text: "臺灣", reading: "taiwan"), mode: .chinese, script: .traditional)
        let word = try #require(store.lookup("taiwan", mode: .chinese).first)
        #expect(word.text == "台湾")
        #expect(store.text(of: word, in: .simplified) == "台湾")
        #expect(store.text(of: word, in: .traditional) == "臺灣")
        #expect(store.text(of: word, in: .traditionalTaiwan) == "臺灣")
    }

    /// One Simplified character can stand for two Traditional ones (发: 發
    /// or 髮): the script typed in keeps the form chosen.
    @Test func theScriptTypedInKeepsTheFormChosen() throws {
        let store = try makeStore()
        store.learn(Commit(text: "頭髮", reading: "toufa"), mode: .chinese, script: .traditional)
        let word = try #require(store.lookup("toufa", mode: .chinese).first)
        #expect(store.text(of: word, in: .traditional) == "頭髮")
        #expect(store.text(of: word, in: .simplified) == "头发")
        #expect(try LearnedStore(url: url).lookup("toufa", mode: .chinese).first?.shown == "頭髮")
    }

    @Test func undoingAndForgettingFindTheWordInAnyScript() throws {
        let store = try makeStore()
        store.learn(Commit(text: "學習", reading: "xuexi"), mode: .chinese, script: .traditional)
        store.learn(Commit(text: "臺灣", reading: "taiwan"), mode: .chinese, script: .traditional)
        store.unlearn(Commit(text: "学习", reading: "xuexi"), mode: .chinese)
        #expect(store.lookup("xuexi", mode: .chinese).isEmpty)
        #expect(store.words(showing: "台湾", mode: .chinese).map(\.shown) == ["臺灣"])
        #expect(store.reading(for: "台湾", mode: .chinese) == "taiwan")
    }

    /// A file from an older Sugu or another Mac has words as typed; they
    /// merge with the same word here, and so do its deletions.
    @Test func mergedWordsAndDeletionsMeetInSimplified() throws {
        let store = try makeStore()
        store.learn(Commit(text: "学习", reading: "xuexi"), mode: .chinese, script: .simplified)
        let old = clock.now.addingTimeInterval(-86_400)
        let incoming = LearnedWord(id: 0, mode: .chinese, reading: "xuexi", text: "學習", kind: .learned, count: 5, pinned: true, firstUsed: old, lastUsed: old)
        try store.merge([incoming])
        let word = try #require(store.lookup("xuexi", mode: .chinese).first)
        #expect(store.lookup("xuexi", mode: .chinese).count == 1)
        #expect(word.count == 5 && word.pinned)
        // The later use here keeps its form.
        #expect(word.shown == "学习")
        try store.applyDeletions([WordDeletion(mode: .chinese, reading: "xuexi", text: "學習", kind: .learned, deletedAt: clock.now)])
        #expect(store.lookup("xuexi", mode: .chinese).isEmpty)
    }

    @Test func japaneseIsStoredAsTyped() throws {
        let store = try makeStore()
        store.learn(Commit(text: "学習", reading: "がくしゅう"), mode: .japanese, script: .traditional)
        let word = try #require(store.lookup("がくしゅう", mode: .japanese).first)
        #expect(word.text == "学習" && word.script == nil)
        #expect(store.text(of: word, in: .simplified) == "学習")
    }
}

/// A few characters of OpenCC's tables, enough for the tests.
@MainActor
final class TestChineseForms: ChineseForms {
    static let traditional: [Character: Character] = ["學": "学", "習": "习", "臺": "台", "灣": "湾", "異": "异", "議": "议", "頭": "头", "髮": "发", "發": "发"]
    static let simplified: [Character: Character] = ["学": "學", "习": "習", "台": "臺", "湾": "灣", "异": "異", "议": "議", "头": "頭", "发": "發"]

    func simplified(_ text: String) -> String? {
        String(text.map { Self.traditional[$0] ?? $0 })
    }

    func text(_ text: String, in script: ChineseScript) -> String? {
        let simplified = String(text.map { Self.traditional[$0] ?? $0 })
        return script == .simplified ? simplified : String(simplified.map { Self.simplified[$0] ?? $0 })
    }
}

/// The user's n-grams (D-079).
@MainActor
struct LearnedStoreNGramTests {
    let clock = TestClock()
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sugu-tests-\(UUID().uuidString)")
        .appendingPathComponent("learned.sqlite")

    func makeStore() throws -> LearnedStore {
        let clock = clock
        return try LearnedStore(url: url, clock: { clock.now })
    }

    private func commit(_ text: String, after context: String?) -> Commit {
        var commit = Commit(text: text, reading: text)
        commit.context = context
        return commit
    }

    @Test func learnsTheCommitsNGramsAfterItsContextAndKeepsThem() throws {
        let store = try makeStore()
        store.learn(commit("描きました", after: "絵を"), mode: .japanese)
        let grams = store.personalNGrams(for: .japanese)
        #expect(grams.count(of: "を描") == 1)
        #expect(grams.count(of: "絵を描き") == 1)
        #expect(grams.count(of: "絵を") == 0)
        #expect(store.personalNGrams(for: .chinese).isEmpty)
        let reopened = try makeStore()
        #expect(reopened.personalNGrams(for: .japanese).count(of: "を描") == 1)
        #expect(reopened.hasNGrams)
    }

    @Test func aCommitWithoutContextOrInEnglishTeachesNoNGrams() throws {
        let store = try makeStore()
        store.learn(commit("描きました", after: nil), mode: .japanese)
        store.learn(commit("hello", after: "say "), mode: .english)
        #expect(store.personalNGrams(for: .japanese).isEmpty)
        #expect(store.personalNGrams(for: .english).isEmpty)
        #expect(!store.hasNGrams)
    }

    @Test func undoTakesBackOneUse() throws {
        let store = try makeStore()
        store.learn(commit("异议", after: "任何"), mode: .chinese)
        store.learn(commit("异议", after: "任何"), mode: .chinese)
        store.unlearn(commit("异议", after: "任何"), mode: .chinese)
        #expect(store.personalNGrams(for: .chinese).count(of: "何异议") == 1)
        store.unlearn(commit("异议", after: "任何"), mode: .chinese)
        #expect(store.personalNGrams(for: .chinese).isEmpty)
        #expect(try makeStore().personalNGrams(for: .chinese).isEmpty)
    }

    @Test func forgetLastHourDeleteAllAndExpiryReachTheNGrams() throws {
        let store = try makeStore()
        store.learn(commit("异议", after: "任何"), mode: .chinese)
        clock.advance(hours: 3)
        store.learn(commit("异议", after: "任何"), mode: .chinese)
        store.learn(commit("描く", after: "絵を"), mode: .japanese)
        store.forget()
        #expect(store.personalNGrams(for: .chinese).count(of: "异议") == 1)
        #expect(store.personalNGrams(for: .japanese).isEmpty)
        #expect(try makeStore().personalNGrams(for: .chinese).count(of: "异议") == 1)

        clock.advance(days: 31)
        store.learn(commit("描く", after: "絵を"), mode: .japanese)
        store.expire(olderThan: 30)
        #expect(store.personalNGrams(for: .chinese).isEmpty)
        #expect(store.personalNGrams(for: .japanese).count(of: "を描") == 1)

        store.deleteAll()
        #expect(store.personalNGrams(for: .japanese).isEmpty)
        #expect(!store.hasNGrams)
        #expect(!(try makeStore().hasNGrams))
    }

    /// Text that reads the same is one n-gram; runs too long for the
    /// model are not kept.
    @Test func nGramsAreNormalizedAndBounded() throws {
        let store = try makeStore()
        store.learn(commit("好，", after: ""), mode: .chinese)
        store.learn(commit("好,", after: ""), mode: .chinese)
        store.unlearn(commit("好，", after: ""), mode: .chinese)
        #expect(store.personalNGrams(for: .chinese).count(of: "好,") == 1)
        store.unlearn(commit("好,", after: ""), mode: .chinese)
        #expect(!store.hasNGrams)
        #expect(try makeStore().personalNGrams(for: .chinese).isEmpty)
        store.learn(commit("👍🏽👍🏽👍🏽", after: ""), mode: .chinese)
        #expect(store.personalNGrams(for: .chinese).count(of: "👍🏽") == 3)
        store.unlearn(commit("👍🏽👍🏽👍🏽", after: ""), mode: .chinese)
        #expect(!store.hasNGrams)
    }

    @Test func learnsInTheFormTheModelsRead() throws {
        let store = try makeStore()
        let forms = TestChineseForms()
        store.chineseForms = forms
        store.learn(commit("異議", after: "任何"), mode: .chinese)
        #expect(store.personalNGrams(for: .chinese).count(of: "异议") == 1)
        #expect(store.personalNGrams(for: .chinese).count(of: "異議") == 0)
    }

    @Test func theLeastRecentlyUsedNGramsGoPastTheLimit() throws {
        let store = try makeStore()
        store.maximumNGrams = 10
        store.learn(commit("一二三四五六", after: ""), mode: .chinese)
        clock.advance(hours: 1)
        store.learn(commit("甲乙丙", after: ""), mode: .chinese)
        let grams = store.personalNGrams(for: .chinese)
        #expect(grams.count(of: "甲乙丙") == 1)
        #expect(grams.count(of: "一二") == 0)
        #expect(try makeStore().personalNGrams(for: .chinese).count(of: "一二") == 0)
    }
}
