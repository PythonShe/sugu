import Foundation
import Testing
import SuguCore
import SuguDictionaries
import SuguLearning

final class SyncTestClock: @unchecked Sendable {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
}

@MainActor
@Suite struct DictionarySyncTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-sync-\(UUID().uuidString)", isDirectory: true)
    let defaults = UserDefaults(suiteName: "sugu-sync-tests-\(UUID().uuidString)")!
    let clock = SyncTestClock()

    private func store() throws -> LearnedStore {
        try LearnedStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/learned.sqlite"))
    }

    private func sync(_ store: LearnedStore, folder: URL? = nil) -> DictionarySync {
        let preferences = PreferencesStore(defaults: defaults)
        preferences.update { $0.syncFolderPath = (folder ?? self.folder).path }
        let clock = clock
        return DictionarySync(store: store, preferences: preferences, defaults: defaults, exportDelay: .zero, now: { clock.now })
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".\(SyncFolder.fileExtension)") }
    }

    @Test func syncMergesOtherMacsAndWritesThisOne() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let other = try store()
        other.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        try await SyncFolder(folder: folder, deviceID: "other", store: other).export(includeLearned: false)

        let mine = try store()
        let sync = sync(mine)
        await sync.syncNow()?.value
        #expect(mine.lookup("sugu", mode: .chinese).map(\.text) == ["速贵"])
        #expect(try files().count == 2)
        #expect(sync.lastSync == clock.now)
        #expect(sync.lastError == nil)
        // Not due again until the pull interval has passed.
        #expect(sync.pullIfDue() == nil)
        clock.now += DictionarySync.pullInterval
        #expect(sync.pullIfDue() != nil)
    }

    @Test func failuresBackOff() async throws {
        let sync = sync(try store(), folder: folder.appendingPathComponent("missing"))
        await sync.syncNow()?.value
        #expect(sync.lastError != nil)
        #expect(sync.pullIfDue() == nil)
        clock.now += DictionarySync.pullInterval
        await sync.pullIfDue()?.value
        // The second failure waits twice as long.
        clock.now += DictionarySync.pullInterval
        #expect(sync.pullIfDue() == nil)
        clock.now += DictionarySync.pullInterval
        #expect(sync.pullIfDue() != nil)
    }

    @Test func changesAreWrittenAfterAPause() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mine = try store()
        let sync = sync(mine)
        mine.addUserWord(reading: "sugu", text: "すぐ", mode: .japanese)
        await sync.storeDidChange()?.value
        #expect(try files().count == 1)
        #expect(sync.lastError == nil)
    }
}
