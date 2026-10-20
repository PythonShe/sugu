import Foundation
import SuguDownloads
import SuguRime

/// Optional data the user can download from settings. Each item is pinned
/// to a file and checksum reviewed for this release; nothing is fetched
/// without the user asking.
@MainActor
public final class ModelLibrary {
    public enum Item: String, CaseIterable, Sendable {
        /// wanxiang grammar model for librime-octagram (CC-BY-4.0).
        case grammarModel
        /// rime-ice dictionary (GPL-3.0), an alternative Chinese dictionary.
        case rimeIce
        /// Zenzai neural model for Japanese conversion (CC-BY-SA-4.0).
        case zenzaiModel

        public var download: Download {
            switch self {
            case .grammarModel:
                Download(
                    url: URL(string: "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram")!,
                    sha256: "9eedac1d836f3fdafb61b162035c8937253aedc106be40b2b957d9ab64e9ed89",
                    size: 398_497_836
                )
            case .rimeIce:
                Download(
                    url: URL(string: "https://github.com/iDvel/rime-ice/releases/download/2026.06.30/cn_dicts.zip")!,
                    sha256: "4e19619920f901cf900a33142ac0d10586787cdaf577a5b106da2cc078a84720",
                    size: 14_715_121
                )
            case .zenzaiModel:
                Download(
                    url: URL(string: "https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/ddf6e44b2e05ab7ea9a3e31559c5e7948761365c/ggml-model-Q5_K_M.gguf")!,
                    sha256: "4de930c06bef8c263aa1aa40684af206db4ce1b96375b3b8ed0ea508e0b14f6c",
                    size: 73_871_968
                )
            }
        }

        public var license: String {
            switch self {
            case .grammarModel: "CC-BY-4.0"
            case .rimeIce: "GPL-3.0"
            case .zenzaiModel: "CC-BY-SA-4.0"
            }
        }

        public var homepage: URL {
            switch self {
            case .grammarModel: URL(string: "https://github.com/amzxyz/rime-wanxiang-data")!
            case .rimeIce: URL(string: "https://github.com/iDvel/rime-ice")!
            case .zenzaiModel: URL(string: "https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf")!
            }
        }

        /// The release name shown with the item.
        public var version: String {
            switch self {
            case .grammarModel: "LTS"
            case .rimeIce: "2026.06.30"
            case .zenzaiModel: "zenz-v3.1-small"
            }
        }
    }

    public enum State: Equatable, Sendable {
        case notInstalled
        case downloading(Double)
        case installing
        case installed
        case failed(Failure)
    }

    /// Why an install failed; the settings window words it.
    public enum Failure: Equatable, Sendable {
        case checksumMismatch
        case server(status: Int)
        case extraction
        case other(String)
    }

    public private(set) var states: [Item: State] = [:]
    /// Called on every state change, including progress.
    public var onChange: ((Item) -> Void)?

    private let engines: EngineHub
    private var tasks: [Item: Task<Void, Never>] = [:]
    /// Items whose removal waits for a cancelled download to unwind.
    private var removing: Set<Item> = []

    public init(engines: EngineHub) {
        self.engines = engines
        for item in Item.allCases {
            states[item] = isInstalled(item) ? .installed : .notInstalled
        }
    }

    public func state(of item: Item) -> State { states[item] ?? .notInstalled }

    public func isInstalled(_ item: Item) -> Bool {
        switch item {
        case .grammarModel: engines.isGrammarModelInstalled
        case .rimeIce: engines.isRimeIceInstalled
        case .zenzaiModel: engines.isZenzaiModelInstalled
        }
    }

    public func install(_ item: Item) {
        guard tasks[item] == nil, !removing.contains(item) else { return }
        set(item, .downloading(0))
        tasks[item] = Task {
            do {
                try await perform(item)
                set(item, .installed)
                engines.modelsDidChange()
            } catch where Self.isCancellation(error) {
                // A cancel can arrive after the files were moved in.
                let installed = isInstalled(item)
                set(item, installed ? .installed : .notInstalled)
                if installed { engines.modelsDidChange() }
            } catch {
                set(item, .failed(Self.failure(for: error)))
            }
            tasks[item] = nil
        }
    }

    public func cancel(_ item: Item) {
        tasks[item]?.cancel()
    }

    /// Removes an installed item. A download still running is cancelled
    /// and allowed to finish unwinding first, so it cannot move files back
    /// in after they were deleted.
    public func remove(_ item: Item) {
        let running = tasks[item]
        running?.cancel()
        removing.insert(item)
        Task {
            await running?.value
            deleteFiles(of: item)
            removing.remove(item)
            set(item, .notInstalled)
            engines.modelsDidChange()
        }
    }

    private func deleteFiles(of item: Item) {
        let fm = FileManager.default
        let locations = engines.locations
        switch item {
        case .grammarModel:
            try? fm.removeItem(at: locations.grammarModel)
        case .rimeIce:
            try? fm.removeItem(at: locations.rimeIceManifest)
            try? fm.removeItem(at: locations.rimeIceTables)
        case .zenzaiModel:
            try? fm.removeItem(at: locations.zenzaiModel)
        }
    }

    private func perform(_ item: Item) async throws {
        let locations = engines.locations
        let progress: @MainActor @Sendable (Double) -> Void = { [weak self] fraction in
            self?.set(item, .downloading(fraction))
        }
        switch item {
        case .grammarModel:
            try await Downloader.fetch(item.download, to: locations.grammarModel, progress: progress)
        case .zenzaiModel:
            try await Downloader.fetch(item.download, to: locations.zenzaiModel, progress: progress)
        case .rimeIce:
            let fm = FileManager.default
            let work = locations.models.appendingPathComponent("rime-ice-install", isDirectory: true)
            try? fm.removeItem(at: work)
            defer { try? fm.removeItem(at: work) }
            let archive = work.appendingPathComponent("cn_dicts.zip")
            try await Downloader.fetch(item.download, to: archive, progress: progress)
            set(item, .installing)
            let extracted = work.appendingPathComponent("extracted", isDirectory: true)
            try await ZipArchive.extract(archive, to: extracted)
            try Task.checkCancellation()
            try? fm.removeItem(at: locations.rimeIceTables)
            try fm.createDirectory(at: locations.rimeIceTables, withIntermediateDirectories: true)
            for table in RimeSchema.rimeIceTables {
                let name = "\(table).dict.yaml"
                try fm.moveItem(at: extracted.appendingPathComponent("cn_dicts/\(name)"), to: locations.rimeIceTables.appendingPathComponent(name))
            }
            try RimeSchema.rimeIceManifest(version: item.version)
                .write(to: locations.rimeIceManifest, atomically: true, encoding: .utf8)
        }
        try Task.checkCancellation()
    }

    private func set(_ item: Item, _ state: State) {
        guard states[item] != state else { return }
        states[item] = state
        onChange?(item)
    }

    /// A cancelled download surfaces as URLSession's own error, not as
    /// `CancellationError`.
    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func failure(for error: any Error) -> Failure {
        switch error {
        case DownloadError.checksumMismatch: .checksumMismatch
        case DownloadError.server(let status): .server(status: status)
        case DownloadError.extractionFailed: .extraction
        default: .other(error.localizedDescription)
        }
    }
}
