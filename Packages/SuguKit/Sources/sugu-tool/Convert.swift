import Foundation
import SuguCore
import SuguRime

/// Prints the candidates each reading produces, for quick checks from the
/// terminal.
@MainActor
enum Convert {
    static func run(data: URL, japanese: Bool, readings: [String]) async throws {
        let user = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-convert")
        let runtime = RimeRuntime(directories: .init(shared: data.appendingPathComponent("Rime"), user: user))
        try await runtime.prepare(RimeSchema(), version: "dev")
        let engine = RimeEngine(runtime: runtime)
        for reading in readings {
            let started = Date()
            engine.insert(reading)
            let elapsed = Date().timeIntervalSince(started) * 1000
            let texts = engine.state.candidates.prefix(9).map(\.text).joined(separator: " ")
            print("\(reading) [\(String(format: "%.1f", elapsed)) ms]: \(texts)")
            engine.clear()
        }
    }
}
