import CRime
import Foundation
import SuguCore

/// Process-wide librime state: directories, deployment, sessions.
///
/// librime keeps global state, so there is one runtime per process. All
/// calls happen on the main actor; deployment runs on librime's maintenance
/// thread and is awaited without blocking the main thread.
@MainActor
public final class RimeRuntime {
    public struct Directories: Sendable {
        /// Bundled, read-only data: default config, algebra, OpenCC tables,
        /// and prebuilt tables in `build/`.
        public var shared: URL
        /// Per-user data: the generated schema, grammar model, staging.
        public var user: URL

        public init(shared: URL, user: URL) {
            self.shared = shared
            self.user = user
        }
    }

    public enum Error: Swift.Error, Equatable {
        case deploymentFailed
        case sessionUnavailable
    }

    public let directories: Directories
    public private(set) var schema: RimeSchema?
    /// How many times librime's sessions were ended, so a session id from
    /// before is known to be gone.
    private(set) var deployments = 0
    private let strings = CStringPool()
    private var isInitialized = false
    private var deployment: Task<Void, any Swift.Error>?
    /// Set when data the schema imports changed under the same schema.
    private var isStale = false

    public init(directories: Directories) {
        self.directories = directories
    }

    public var api: RimeApi { RimeAPI.shared.api }

    /// Writes the schema for `schema` and (re)deploys when it changed. Safe
    /// to call repeatedly; concurrent calls share one deployment.
    public func prepare(_ schema: RimeSchema, version: String) async throws {
        if let deployment { try await deployment.value }
        if isInitialized, self.schema == schema, !isStale { return }
        let task = Task { try await deploy(schema, version: version) }
        deployment = task
        defer { deployment = nil }
        try await task.value
    }

    /// Removes librime's compiled copy of the user data, so the next
    /// deployment builds it again from the sources.
    public func discardBuild() {
        guard deployment == nil else { return }
        try? FileManager.default.removeItem(at: directories.user.appendingPathComponent("build"))
    }

    /// Has the next `prepare` deploy again, for dictionary tables replaced
    /// under the same schema; librime rebuilds what changed.
    public func setNeedsDeployment() {
        isStale = true
    }

    /// True once a deployment succeeded and none is running.
    public var isReady: Bool { isInitialized && deployment == nil && schema != nil && !isStale }

    private func deploy(_ schema: RimeSchema, version: String) async throws {
        isStale = false
        try FileManager.default.createDirectory(at: directories.user, withIntermediateDirectories: true)
        let schemaURL = directories.user.appendingPathComponent("\(RimeSchema.schemaID).schema.yaml")
        let yaml = schema.yaml(version: version)
        if (try? String(contentsOf: schemaURL, encoding: .utf8)) != yaml {
            try yaml.write(to: schemaURL, atomically: true, encoding: .utf8)
            // librime compares source timestamps in whole seconds, so a
            // schema rewritten within a second of the last build would be
            // taken as unchanged. Dropping the compiled copy forces a rebuild.
            try? FileManager.default.removeItem(at: directories.user.appendingPathComponent("build/\(RimeSchema.schemaID).schema.yaml"))
        }
        try RimeUserDictionary.ensureExists(in: directories.user)
        if !isInitialized {
            var traits = makeTraits(version: version)
            api.setup?(&traits)
            api.initialize?(&traits)
            isInitialized = true
        }
        api.cleanup_all_sessions?()
        deployments += 1
        // The sessions are gone and the build is being replaced: not ready
        // again until this deployment succeeds.
        self.schema = nil
        let succeeded = try await maintain()
        // librime reports a failed build step (disk full, an unwritable
        // folder) only in its log; the compiled schema is the evidence.
        let compiled = directories.user.appendingPathComponent("build/\(RimeSchema.schemaID).schema.yaml")
        guard succeeded, FileManager.default.fileExists(atPath: compiled.path) else { throw Error.deploymentFailed }
        self.schema = schema
    }

    /// How long a deployment may run before it counts as failed; a full
    /// rebuild of a large dictionary takes about a minute.
    static let deploymentLimit = Duration.seconds(300)

    /// Runs librime's maintenance and waits for it without holding a
    /// thread: one that never ends fails the deployment after
    /// `deploymentLimit`, and the engine hub tries again later, rather than
    /// leave Chinese waiting for good.
    private func maintain() async throws -> Bool {
        guard api.start_maintenance?(1) ?? 0 != 0 else { return (api.is_maintenance_mode?() ?? 0) == 0 }
        let deadline = ContinuousClock.now + Self.deploymentLimit
        while api.is_maintenance_mode?() ?? 0 != 0 {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        // The thread has finished; this only releases it.
        api.join_maintenance_thread?()
        return true
    }

    private func makeTraits(version: String) -> RimeTraits {
        var traits = RimeTraits()
        traits.data_size = RimeAPI.dataSize(of: RimeTraits.self)
        traits.shared_data_dir = strings.make(directories.shared.path)
        traits.user_data_dir = strings.make(directories.user.path)
        traits.prebuilt_data_dir = strings.make(directories.shared.appendingPathComponent("build").path)
        traits.staging_dir = strings.make(directories.user.appendingPathComponent("build").path)
        traits.distribution_name = strings.make("Sugu")
        traits.distribution_code_name = strings.make("sugu")
        traits.distribution_version = strings.make(version)
        traits.app_name = strings.make("rime.sugu")
        traits.min_log_level = 2
        traits.log_dir = strings.make("")
        let modules = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: 3)
        modules[0] = strings.make("default")
        modules[1] = strings.make("octagram")
        modules[2] = nil
        traits.modules = modules
        return traits
    }

    /// A new librime session on the Sugu schema.
    func makeSession() throws -> RimeSessionId {
        guard isReady else { throw Error.sessionUnavailable }
        let id = api.create_session?() ?? 0
        guard id != 0 else { throw Error.sessionUnavailable }
        guard api.select_schema?(id, RimeSchema.schemaID) ?? 0 != 0 else {
            _ = api.destroy_session?(id)
            throw Error.sessionUnavailable
        }
        return id
    }
}
