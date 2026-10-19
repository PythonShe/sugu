import Foundation
import SuguCore
import SuguLearning

/// Keeps dictionaries in step through a folder the user picks (iCloud
/// Drive, a shared disk). Each Mac writes only its own file and reads the
/// others', so two Macs never write the same file.
@MainActor
public final class SyncFolder {
    public static let fileExtension = "sugudict"

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

    private var ownFile: URL {
        folder.appendingPathComponent("\(deviceID).\(Self.fileExtension)")
    }

    /// Writes this Mac's words: user words always, learned words only when
    /// the user opted in.
    public func export(includeLearned: Bool) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let words = store.allWords().filter { includeLearned || $0.kind == .user }
        try SuguDictionaryFile.encode(words).write(to: ownFile, options: .atomic)
    }

    /// Merges what other Macs wrote since the last pull. Returns how many
    /// words were new.
    @discardableResult
    public func pull(includeLearned: Bool) throws -> Int {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == Self.fileExtension && $0.lastPathComponent != ownFile.lastPathComponent }
        var added = 0
        for file in files {
            let name = file.lastPathComponent
            let words = SuguDictionaryFile.decode(try Data(contentsOf: file)).filter { includeLearned || $0.kind == .user }
            added += try store.merge(words, since: watermarks[name])
            if let newest = words.map(\.lastUsed).max() {
                watermarks[name] = max(watermarks[name] ?? newest, newest)
            }
        }
        return added
    }
}
