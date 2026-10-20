import Foundation
import Testing
import SuguAzooKey
import SuguCore
import SuguRime

/// End-to-end checks against the real engines and the data built by
/// `scripts/build-data.sh`. Skipped when `Data/` has not been built.
private let dataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data")
private let hasData = FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("Rime/build/sugu.table.bin").path)

/// librime keeps process-wide state, so every test shares one runtime.
@MainActor
private enum Shared {
    static let user = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-engine-tests-\(getpid())")
    static let runtime = RimeRuntime(directories: .init(shared: dataDirectory.appendingPathComponent("Rime"), user: user))
}

@MainActor
@Suite(.serialized, .enabled(if: hasData))
struct RimeEngineTests {
    private func first(_ reading: String, schema: RimeSchema = RimeSchema(), script: ChineseScript = .simplified) async throws -> String? {
        try await Shared.runtime.prepare(schema, version: "test")
        let engine = RimeEngine(runtime: Shared.runtime, script: script)
        engine.insert(reading)
        defer { engine.clear() }
        return engine.state.candidates.first?.text
    }

    @Test func fullPinyin() async throws {
        #expect(try await first("nihao") == "你好")
        #expect(try await first("woaibeijingtiananmen") == "我爱北京天安门")
    }

    /// A user schema must survive deployment; librime trashes user copies
    /// that are older than a shared copy.
    @Test func doublePinyinSchemaIsApplied() async throws {
        #expect(try await first("nihc", schema: RimeSchema(scheme: .xiaohe)) == "你好")
        #expect(FileManager.default.fileExists(atPath: Shared.user.appendingPathComponent("sugu.schema.yaml").path))
    }

    @Test func fuzzyPinyin() async throws {
        #expect(try await first("zongguo", schema: RimeSchema(fuzzy: [.zZh])) == "中国")
    }

    @Test func traditionalScript() async throws {
        #expect(try await first("zhongguo", script: .traditional) == "中國")
    }

    @Test func japaneseKanjiForms() async throws {
        #expect(try await first("dongjing", script: .japanese) == "東京")
        #expect(try await first("hengbin", script: .japanese) == "横浜")
    }

    @Test func scriptConverterNormalizesThroughSimplified() throws {
        let openCC = dataDirectory.appendingPathComponent("Rime/opencc")
        let simplified = try #require(ScriptConverter.toScript(.simplified, openCC: openCC))
        #expect(simplified.convert("東京") == "东京")
        #expect(simplified.convert("横浜") == "横滨")
        let japanese = try #require(ScriptConverter.toScript(.japanese, openCC: openCC))
        #expect(japanese.convert("横滨") == "横浜")
        let traditional = try #require(ScriptConverter.toScript(.traditional, openCC: openCC))
        #expect(traditional.convert("中国") == "中國")
    }
}

@MainActor
@Suite struct AzooKeyEngineTests {
    @Test func firstDisplayIsBestSentence() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-azookey-tests")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let engine = AzooKeyEngine(configuration: .init(workingDirectory: work))
        engine.insert("kyouhaiitenkidesune")
        #expect(engine.state.segments.map(\.text).joined() == "きょうはいいてんきですね")
        _ = engine.convert()
        #expect(engine.state.segments.map(\.text).joined() == "今日はいい天気ですね")
        #expect(engine.state.segments.first?.role == .focused)
    }
}
