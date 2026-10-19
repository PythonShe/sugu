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
    private let strings = CStringPool()
    private var isInitialized = false
    private var deployment: Task<Void, any Swift.Error>?

    public init(directories: Directories) {
        self.directories = directories
    }

    public var api: RimeApi { RimeAPI.shared.api }

    /// Writes the schema for `schema` and (re)deploys when it changed. Safe
    /// to call repeatedly; concurrent calls share one deployment.
    public func prepare(_ schema: RimeSchema, version: String) async throws {
        if let deployment { try await deployment.value }
        if isInitialized, self.schema == schema { return }
        let task = Task { try await deploy(schema, version: version) }
        deployment = task
        defer { deployment = nil }
        try await task.value
    }

    public var isReady: Bool { isInitialized && deployment == nil }

    private func deploy(_ schema: RimeSchema, version: String) async throws {
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
        if !isInitialized {
            var traits = makeTraits(version: version)
            api.setup?(&traits)
            api.initialize?(&traits)
            isInitialized = true
        }
        api.cleanup_all_sessions?()
        let succeeded = await Task.detached(priority: .userInitiated) {
            let api = RimeAPI.shared.api
            guard api.start_maintenance?(1) ?? 0 != 0 else { return (api.is_maintenance_mode?() ?? 0) == 0 }
            api.join_maintenance_thread?()
            return true
        }.value
        guard succeeded else { throw Error.deploymentFailed }
        self.schema = schema
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
        _ = api.select_schema?(id, RimeSchema.schemaID)
        return id
    }
}
