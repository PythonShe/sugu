import Foundation
import Testing
@testable import SuguLM

@Suite struct CharacterLanguageModelTests {
    private func model(_ sentences: [String], order: Int = 3, minimumCount: Int = 1) throws -> CharacterLanguageModel {
        var builder = CharacterLanguageModelBuilder(order: order)
        builder.minimumCount = minimumCount
        sentences.forEach { builder.add($0) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-lm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try builder.build().data.write(to: url)
        return try CharacterLanguageModel(contentsOf: url)
    }

    private let corpus = ["雨が降る", "雨が降った", "雪が降る", "雨が止む", "古い本", "本が古い"]

    @Test func seenSequencesScoreAboveUnseenOnes() throws {
        let model = try model(corpus)
        #expect(model.logProbability(of: "雨が降る") > model.logProbability(of: "雨が古る"))
        #expect(model.logProbability(of: "降る", after: "雪が") > model.logProbability(of: "古る", after: "雪が"))
    }

    @Test func probabilitiesOfEachContextSumToOne() throws {
        for minimumCount in [1, 2] {
            let model = try model(corpus + corpus.prefix(3), minimumCount: minimumCount)
            let alphabet = Set(corpus.joined()).map(String.init)
            for history in ["", "雨が", "が", "古"] {
                // Every character seen, plus the mass left for unseen ones.
                let seen = alphabet.map { exp(Double(model.logProbability(of: $0, after: history))) }.reduce(0, +)
                let unseen = exp(Double(model.logProbability(of: "猫", after: history)))
                #expect(abs(seen + unseen - 1) < 0.01, "history \(history): \(seen) + \(unseen)")
            }
        }
    }

    @Test func textIsComparedAfterCompatibilityNormalization() throws {
        let model = try model(["ABC", "ABD"])
        #expect(model.logProbability(of: "ＡＢＣ") == model.logProbability(of: "ABC"))
    }

    @Test func rejectsOtherFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-lm-bad-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a model at all, not at all".utf8).write(to: url)
        #expect(throws: CharacterLanguageModel.ModelError.self) { try CharacterLanguageModel(contentsOf: url) }
    }
}
