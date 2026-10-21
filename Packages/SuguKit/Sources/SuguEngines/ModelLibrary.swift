import Foundation
import os
import SuguCore
import SuguDownloads
import SuguRime

/// Where `ModelLibrary` installs files, and who reloads them afterwards.
@MainActor
public protocol ModelHost: AnyObject {
    var locations: EngineHub.Locations { get }
    func modelDidChange(_ item: ModelLibrary.Item)
}

extension EngineHub: ModelHost {}

/// Optional data the user can download from settings. Each item is pinned
/// to a file and checksum reviewed for this release. rime-ice and the
/// grammar model also follow their upstream releases once a file has been
/// public for `minimumReleaseAge`, checked against GitHub's checksum
/// (D-093); Zenzai's model must suit the AzooKey built in, so it moves
/// with Sugu. Nothing is downloaded without the user asking.
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
                // Upstream republishes its LTS file under the same name, so
                // the reviewed copy is served from Sugu's site, by checksum.
                Download(
                    url: URL(string: "https://sugu.zheng-she.com/models/wanxiang-lts-zh-hans-9eedac1d.gram")!,
                    fallback: URL(string: "https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram")!,
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

        /// The release name shown with the item.
        public var version: String {
            switch self {
            case .grammarModel: "LTS"
            case .rimeIce: "2026.06.30"
            case .zenzaiModel: "zenz-v3.1-small"
            }
        }

        /// The file reviewed for this release of Sugu.
        public var pinned: Release { Release(version: version, download: download) }

        /// Whether the item follows its upstream releases.
        public var followsUpstream: Bool { self != .zenzaiModel }

        /// The newest upstream release old enough to offer, if the item
        /// follows upstream.
        public func latestRelease() async throws -> Release? {
            switch self {
            case .grammarModel:
                // Republished under the same tag; dated by its file.
                try await GitHubReleases.newest("wanxiang-lts-zh-hans.gram", in: "amzxyz/rime-wanxiang-data", tag: "LTS", minimumAge: ModelLibrary.minimumReleaseAge)
            case .rimeIce:
                // Dated releases only, not the nightly build.
                try await GitHubReleases.newest("cn_dicts.zip", in: "iDvel/rime-ice", versions: /\d{4}\.\d{2}\.\d{2}/, minimumAge: ModelLibrary.minimumReleaseAge)
            case .zenzaiModel:
                nil
            }
        }
    }

    /// How long an upstream file must have been public before it is
    /// offered: time for a bad or tampered release to be noticed and
    /// withdrawn first.
    public static let minimumReleaseAge: TimeInterval = 14 * 86_400
    /// Upstream is asked at most this often.
    static let checkInterval: TimeInterval = 86_400

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
        case notEnoughSpace
        case other(String)
    }

    public private(set) var states: [Item: State] = [:]
    /// Newer releases of installed items, found by `checkForUpdates`.
    public private(set) var updates: [Item: Release] = [:]
    /// Called on every state change, including progress.
    public var onChange: ((Item) -> Void)?

    private let engines: any ModelHost
    /// The pinned release and the upstream lookup; tests substitute both.
    private let pinned: (Item) -> Release
    private let latest: @MainActor (Item) async throws -> Release?
    private var tasks: [Item: Task<Void, Never>] = [:]
    /// Items whose removal waits for a cancelled download to unwind.
    private var removing: Set<Item> = []
    private var lastCheck: Date?
    private var checking: Task<Void, Never>?

    /// What each item was installed from, by file checksum.
    private struct Installed: Codable {
        var version: String
        var sha256: String
    }

    private var installed: [String: Installed]

    public init(
        engines: any ModelHost,
        pinned: @escaping (Item) -> Release = \.pinned,
        latest: @escaping @MainActor (Item) async throws -> Release? = { try await $0.latestRelease() }
    ) {
        self.engines = engines
        self.pinned = pinned
        self.latest = latest
        let record = engines.locations.models.appendingPathComponent("installed.json")
        installed = (try? JSONDecoder().decode([String: Installed].self, from: Data(contentsOf: record))) ?? [:]
        for item in Item.allCases {
            states[item] = isInstalled(item) ? .installed : .notInstalled
        }
    }

    public func state(of item: Item) -> State { states[item] ?? .notInstalled }

    /// The release an installed item came from. Installs from before the
    /// record could only be the pinned file.
    private func installedRelease(of item: Item) -> Installed? {
        guard isInstalled(item) else { return nil }
        return installed[item.rawValue] ?? Installed(version: pinned(item).version, sha256: pinned(item).download.sha256)
    }

    private func record(_ item: Item, _ release: Release?) {
        installed[item.rawValue] = release.map { Installed(version: $0.version, sha256: $0.download.sha256) }
        let url = engines.locations.models.appendingPathComponent("installed.json")
        try? FileManager.default.createDirectory(at: engines.locations.models, withIntermediateDirectories: true)
        try? JSONEncoder().encode(installed).write(to: url, options: .atomic)
    }

    /// Looks for newer releases of the installed items, at most once a day.
    public func checkForUpdates(now: Date = .now) {
        guard checking == nil, lastCheck.map({ now.timeIntervalSince($0) >= Self.checkInterval }) ?? true else { return }
        lastCheck = now
        checking = Task {
            for item in Item.allCases where isInstalled(item) {
                let offer = item.followsUpstream ? try? await latest(item) : pinned(item)
                // Installed again or removed while upstream answered.
                guard tasks[item] == nil, let current = installedRelease(of: item) else { continue }
                let update = offer.flatMap { $0.download.sha256 == current.sha256 ? nil : $0 }
                guard updates[item] != update else { continue }
                updates[item] = update
                onChange?(item)
            }
            checking = nil
        }
    }

    public func isInstalled(_ item: Item) -> Bool {
        switch item {
        case .grammarModel: engines.locations.hasGrammarModel
        case .rimeIce: engines.locations.hasRimeIce
        case .zenzaiModel: engines.locations.hasZenzaiModel
        }
    }

    /// Installs an item, or its update when one was found: the newest
    /// upstream release old enough, or the pinned file when upstream is
    /// out of reach.
    public func install(_ item: Item) {
        guard tasks[item] == nil, !removing.contains(item) else { return }
        set(item, .downloading(0))
        tasks[item] = Task {
            do {
                let release = if let update = updates[item] { update } else { (try? await latest(item)) ?? pinned(item) }
                try Task.checkCancellation()
                try await perform(item, release)
                updates[item] = nil
                set(item, .installed)
                engines.modelDidChange(item)
            } catch where Self.isCancellation(error) {
                // A cancel can arrive after the files were moved in.
                let installed = isInstalled(item)
                set(item, installed ? .installed : .notInstalled)
                if installed { engines.modelDidChange(item) }
            } catch {
                Log.downloads.error("\(String(describing: item), privacy: .public) failed: \(String(describing: error), privacy: .public)")
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
            record(item, nil)
            updates[item] = nil
            removing.remove(item)
            set(item, .notInstalled)
            engines.modelDidChange(item)
        }
    }

    private func deleteFiles(of item: Item) {
        let fm = FileManager.default
        let locations = engines.locations
        switch item {
        case .grammarModel:
            for file in locations.grammarModels { try? fm.removeItem(at: file) }
        case .rimeIce:
            try? fm.removeItem(at: locations.rimeIceManifest)
            try? fm.removeItem(at: locations.rimeIceTables)
        case .zenzaiModel:
            try? fm.removeItem(at: locations.zenzaiModel)
        }
    }

    private func perform(_ item: Item, _ release: Release) async throws {
        let locations = engines.locations
        let progress: @MainActor @Sendable (Double) -> Void = { [weak self] fraction in
            self?.set(item, .downloading(fraction))
        }
        switch item {
        case .grammarModel:
            // A name of its own (octagram keeps the model it loaded); the
            // previous file goes once this one is in place.
            let previous = locations.grammarModels
            let file = locations.grammarModel(named: "\(RimeSchema.grammarLanguage)-\(release.download.sha256.prefix(8))")
            try await Downloader.fetch(release.download, to: file, progress: progress)
            for old in previous where old != file { try? FileManager.default.removeItem(at: old) }
        case .zenzaiModel:
            try await Downloader.fetch(release.download, to: locations.zenzaiModel, progress: progress)
        case .rimeIce:
            let fm = FileManager.default
            let work = locations.models.appendingPathComponent("rime-ice-install", isDirectory: true)
            try? fm.removeItem(at: work)
            defer { try? fm.removeItem(at: work) }
            let archive = work.appendingPathComponent("cn_dicts.zip")
            try await Downloader.fetch(release.download, to: archive, progress: progress)
            set(item, .installing)
            let extracted = work.appendingPathComponent("extracted", isDirectory: true)
            try await ZipArchive.extract(archive, to: extracted)
            try Task.checkCancellation()
            // The tables are gathered beside the old ones and swapped in at
            // once; without its manifest the dictionary counts as missing,
            // so a failure part way leaves none rather than half of one.
            let tables = work.appendingPathComponent("tables", isDirectory: true)
            try fm.createDirectory(at: tables, withIntermediateDirectories: true)
            for table in RimeSchema.rimeIceTables {
                let name = "\(table).dict.yaml"
                try fm.moveItem(at: extracted.appendingPathComponent("cn_dicts/\(name)"), to: tables.appendingPathComponent(name))
            }
            try? fm.removeItem(at: locations.rimeIceManifest)
            if fm.fileExists(atPath: locations.rimeIceTables.path) {
                _ = try fm.replaceItemAt(locations.rimeIceTables, withItemAt: tables)
            } else {
                try fm.createDirectory(at: locations.rimeIceTables.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: tables, to: locations.rimeIceTables)
            }
            try RimeSchema.rimeIceManifest(version: release.version)
                .write(to: locations.rimeIceManifest, atomically: true, encoding: .utf8)
        }
        record(item, release)
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
        case DownloadError.notEnoughSpace: .notEnoughSpace
        default: .other(error.localizedDescription)
        }
    }
}
