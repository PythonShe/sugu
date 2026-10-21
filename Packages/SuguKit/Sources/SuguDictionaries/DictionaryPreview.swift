import Foundation
import SuguCore
import SuguLearning

/// A dictionary file read and ready to import: what it is and what it
/// holds, shown before anything is added.
public struct DictionaryPreview: Sendable {
    public var url: URL
    public var format: DictionaryFormat
    /// The words to add, in the file's order.
    public var entries: [DictionaryEntry]
    /// Sugu's own file, restored with its counts, pins and dates.
    public var restoredWords: [LearnedWord]?

    public init(url: URL, format: DictionaryFormat, entries: [DictionaryEntry], restoredWords: [LearnedWord]? = nil) {
        self.url = url
        self.format = format
        self.entries = entries
        self.restoredWords = restoredWords
    }

    /// Reads `url`, off the main actor.
    public static func read(_ url: URL) async throws -> DictionaryPreview {
        try await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let format = DictionaryFormat.detect(url) else { throw DictionaryImporter.Error.unrecognizedFormat }
            if format == .sugu {
                let words = SuguDictionaryFile.decode(try Data(contentsOf: url))
                guard words.count <= DictionaryImporter.maximumEntries else { throw DictionaryImporter.Error.tooLarge }
                guard !words.isEmpty else { throw DictionaryImporter.Error.unreadable }
                return DictionaryPreview(url: url, format: format, entries: words.map { DictionaryEntry(mode: $0.mode, reading: $0.reading, text: $0.shown) },
                                         restoredWords: words)
            }
            let entries = try DictionaryImporter.read(url, format: format)
            guard !entries.isEmpty else { throw DictionaryImporter.Error.unreadable }
            return DictionaryPreview(url: url, format: format, entries: entries)
        }.value
    }

    /// How many of the words the store does not have yet.
    @MainActor
    public func newCount(in store: LearnedStore) -> Int {
        entries.count { !store.contains(reading: $0.reading, text: $0.text, mode: $0.mode) }
    }

    /// Adds the words to the store; returns how many were new. Sugu's own
    /// file brings back its words even when they were deleted here.
    @MainActor
    public func importWords(into store: LearnedStore) async throws -> Int {
        if let restoredWords { return try await store.restore(restoredWords) }
        return try await store.importUserWords(entries.map { ($0.reading, $0.text, $0.mode) })
    }
}
