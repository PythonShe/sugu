import CryptoKit
import Foundation
import SuguCore
import SuguLearning

/// Keeps dictionaries in step through a folder the user picks (iCloud
/// Drive, a shared disk). Each Mac writes only its own file and reads the
/// others', so two Macs never write the same file. Files carry deletions as
/// well as words, so a word deleted on one Mac goes on every Mac and is not
/// brought back by another Mac's older copy. A pull merges whole files, and
/// the store decides what to take (`LearnedStore.merge`); a file merged
/// before and unchanged since is skipped, and so is one no Mac has written
/// for longer than deletions are kept (a retired Mac's), which could
/// otherwise bring back words whose deletions have lapsed.
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
    /// The checksum of each other Mac's file as last merged.
    public private(set) var merged: [String: String]
    private let store: LearnedStore

    public init(folder: URL, deviceID: String, store: LearnedStore, merged: [String: String] = [:]) {
        self.folder = folder
        self.deviceID = deviceID
        self.store = store
        self.merged = merged
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
            // The folder is the user's; when it is gone (an unmounted disk),
            // fail rather than create a stand-in on this Mac.
            guard FileManager.default.fileExists(atPath: folder.path) else { throw CocoaError(.fileNoSuchFile) }
            try Self.coordinatedWrite(data, to: file)
        }.value
    }

    /// Other Macs' files, read off the main actor.
    public struct Snapshot: Sendable {
        fileprivate var files: [(name: String, data: Data, digest: String)]
        /// Files that exist but could not be read this time.
        public var unreadable: [String]
    }

    /// Merges what other Macs wrote. Returns how many words were added or
    /// deleted.
    @discardableResult
    public func pull(includeLearned: Bool) async throws -> Int {
        try merge(await read(), includeLearned: includeLearned)
    }

    /// Reads other Macs' files. A file that cannot be read is skipped and
    /// listed, so one bad file does not stop the others.
    public func read() async throws -> Snapshot {
        let folder = folder
        let ownName = ownName
        let oldest = Date().addingTimeInterval(-LearnedStore.deletionRetention)
        return try await Task.detached(priority: .utility) {
            try Self.readOtherFiles(in: folder, excluding: ownName, writtenSince: oldest)
        }.value
    }

    /// Merges files read with `read()` into the store.
    @discardableResult
    public func merge(_ snapshot: Snapshot, includeLearned: Bool) throws -> Int {
        var changed = 0
        for (name, data, digest) in snapshot.files where merged[name] != digest {
            let contents = SuguDictionaryFile.decodeContents(data)
            let words = contents.words.filter { includeLearned || $0.kind == .user }
            let deletions = contents.deletions.filter { includeLearned || $0.kind == .user }
            changed += try store.applyDeletions(deletions)
            changed += try store.merge(words)
            merged[name] = digest
        }
        // Files gone from the folder are forgotten.
        let present = Set(snapshot.files.map(\.name) + snapshot.unreadable)
        merged = merged.filter { present.contains($0.key) }
        return changed
    }

    // MARK: File access (off the main actor)

    /// Other Macs' files that are on this disk. Files a cloud provider has
    /// not downloaded yet are requested and read on a later pull.
    nonisolated private static func readOtherFiles(in folder: URL, excluding ownName: String, writtenSince oldest: Date) throws -> Snapshot {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .contentModificationDateKey]
        let entries = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
        var result = Snapshot(files: [], unreadable: [])
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
            if let modified = values?.contentModificationDate, modified < oldest { continue }
            if let data = try? coordinatedRead(entry) {
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                result.files.append((name, data, digest))
            } else {
                result.unreadable.append(name)
            }
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
