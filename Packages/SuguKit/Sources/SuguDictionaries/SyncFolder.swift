import Foundation
import SuguCore
import SuguLearning

/// Keeps dictionaries in step through a folder the user picks (iCloud
/// Drive, a shared disk). Each Mac writes only its own file and reads the
/// others', so two Macs never write the same file. Files carry deletions as
/// well as words, so a word deleted on one Mac goes on every Mac and is not
/// brought back by another Mac's older copy.
///
/// File access runs off the main actor and is coordinated, because a
/// cloud folder can block while it downloads; only merging into the store
/// runs on the main actor.
@MainActor
public final class SyncFolder {
    nonisolated public static let fileExtension = "sugudict"

    public let folder: URL
    /// Identifies this Mac's file. Random, not derived from hardware.
    public let deviceID: String
    /// Newest use already taken from each other Mac's file, so words
    /// deleted here are not brought back by an older copy.
    public private(set) var watermarks: [String: Date]
    private let store: LearnedStore

    public init(folder: URL, deviceID: String, store: LearnedStore, watermarks: [String: Date] = [:]) {
        self.folder = folder
        self.deviceID = deviceID
        self.store = store
        self.watermarks = watermarks
    }

    private var ownName: String { "\(deviceID).\(Self.fileExtension)" }

    /// Writes this Mac's words and deletions: user words always, learned
    /// words only when the user opted in.
    public func export(includeLearned: Bool) async throws {
        let words = store.allWords().filter { includeLearned || $0.kind == .user }
        let deletions = store.allDeletions().filter { includeLearned || $0.kind == .user }
        let data = SuguDictionaryFile.encode(words, deletions: deletions)
        let file = folder.appendingPathComponent(ownName)
        let folder = folder
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Self.coordinatedWrite(data, to: file)
        }.value
    }

    /// Merges what other Macs wrote since the last pull. Returns how many
    /// words were added or deleted.
    @discardableResult
    public func pull(includeLearned: Bool) async throws -> Int {
        let folder = folder
        let ownName = ownName
        let files = try await Task.detached(priority: .utility) {
            try Self.readOtherFiles(in: folder, excluding: ownName)
        }.value
        var changed = 0
        for (name, data) in files {
            let contents = SuguDictionaryFile.decodeContents(data)
            let words = contents.words.filter { includeLearned || $0.kind == .user }
            let deletions = contents.deletions.filter { includeLearned || $0.kind == .user }
            changed += try store.applyDeletions(deletions)
            changed += try store.merge(words, since: watermarks[name])
            if let newest = words.map(\.lastUsed).max() {
                watermarks[name] = max(watermarks[name] ?? newest, newest)
            }
        }
        return changed
    }

    // MARK: File access (off the main actor)

    /// Other Macs' files that are on this disk. Files a cloud provider has
    /// not downloaded yet are requested and read on a later pull.
    nonisolated private static func readOtherFiles(in folder: URL, excluding ownName: String) throws -> [(String, Data)] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        let entries = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        var result: [(String, Data)] = []
        for entry in entries {
            let name = entry.lastPathComponent
            // Older iCloud Drive keeps an evicted file as ".name.icloud".
            if name.hasPrefix("."), name.hasSuffix(".\(fileExtension).icloud") {
                let real = folder.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                try? fm.startDownloadingUbiquitousItem(at: real)
                continue
            }
            guard entry.pathExtension == fileExtension, name != ownName else { continue }
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isUbiquitousItem == true, values?.ubiquitousItemDownloadingStatus != .current {
                try? fm.startDownloadingUbiquitousItem(at: entry)
                continue
            }
            result.append((name, try coordinatedRead(entry)))
        }
        return result
    }

    nonisolated private static func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    nonisolated private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, any Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}
