import Foundation
import SuguCore
import SuguAzooKey
import SuguRime

/// Prints the candidates each reading produces, for quick checks from the
/// terminal.
@MainActor
enum Convert {
    static func run(data: URL, user: URL?, schema: RimeSchema, japanese: Bool, readings: [String]) async throws {
        if japanese {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-convert-ja")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            var started = Date()
            let engine = AzooKeyEngine(configuration: .init(workingDirectory: work))
            print("loaded converter in \(milliseconds(since: started)) ms")
            for reading in readings {
                started = Date()
                engine.insert(reading)
                let typing = milliseconds(since: started)
                let predictions = engine.state.candidates.prefix(5).map(\.text).joined(separator: " ")
                started = Date()
                engine.convert()
                let conversion = milliseconds(since: started)
                let shown = engine.state.segments.map { $0.role == .focused ? "[\($0.text)]" : $0.text }.joined()
                let candidates = engine.state.candidates.prefix(6).map(\.text).joined(separator: " ")
                print("\(reading) → \(shown)  {\(candidates)}  typing \(typing) ms, convert \(conversion) ms; predictions: \(predictions)")
                engine.clear()
            }
            return
        }
        let user = user ?? FileManager.default.temporaryDirectory.appendingPathComponent("sugu-convert")
        let runtime = RimeRuntime(directories: .init(shared: data.appendingPathComponent("Rime"), user: user))
        let started = Date()
        try await runtime.prepare(schema, version: "dev")
        print("deployed in \(milliseconds(since: started)) ms")
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

    private static func milliseconds(since date: Date) -> String {
        String(format: "%.1f", Date().timeIntervalSince(date) * 1000)
    }
}
