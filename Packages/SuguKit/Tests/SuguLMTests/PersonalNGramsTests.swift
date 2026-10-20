import Foundation
import Testing
@testable import SuguLM

@MainActor
@Suite struct PersonalNGramsTests {
    private func base(_ sentences: [String]) throws -> CharacterLanguageModel {
        var builder = CharacterLanguageModelBuilder()
        builder.minimumCount = 1
        sentences.forEach { builder.add($0) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-lm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try builder.build().data.write(to: url)
        return try CharacterLanguageModel(contentsOf: url)
    }

    private let corpus = ["这没有意义。", "有意义的事。", "意义很大。", "我有异议。"]

    @Test func gramsEndInTheTextAndReachIntoTheContext() {
        #expect(PersonalNGrams.grams(of: "异议", after: "任何", order: 3) == ["何异", "任何异", "异议", "何异议"])
        #expect(PersonalNGrams.grams(of: "议", after: "", order: 3).isEmpty)
        #expect(PersonalNGrams.grams(of: "异议", after: "没有任何", order: 3) == ["何异", "任何异", "异议", "何异议"])
    }

    @Test func countsComeAndGo() {
        let grams = PersonalNGrams(order: 3)
        grams.add("异议", count: 2)
        #expect(grams.count(of: "异议") == 2)
        grams.add("异议", count: -5)
        #expect(grams.count(of: "异议") == 0)
        #expect(grams.isEmpty)
        grams.add("异", count: 1)
        #expect(grams.isEmpty)
    }

    @Test func withoutTheUsersNGramsTheBaseScores() throws {
        let base = try base(corpus)
        let empty = BlendedLanguageModel(base: base, personal: PersonalNGrams())
        let off = BlendedLanguageModel(base: base)
        for (text, history) in [("没有意义", ""), ("异议", "没有任何")] {
            #expect(empty.logProbability(of: text, after: history) == base.logProbability(of: text, after: history))
            #expect(off.logProbability(of: text, after: history) == base.logProbability(of: text, after: history))
        }
    }

    /// Once the user typed 任何异议, it reads as more natural after 任何
    /// than the corpus's 意义, and nowhere else changes.
    @Test func theUsersContinuationsGainAfterTheirContext() throws {
        let base = try base(corpus)
        let personal = PersonalNGrams()
        let model = BlendedLanguageModel(base: base, personal: personal)
        #expect(model.logProbability(of: "意义", after: "没有任何") > model.logProbability(of: "异议", after: "没有任何"))
        let version = model.version
        for gram in PersonalNGrams.grams(of: "任何异议", after: "") { personal.add(gram, count: 1) }
        #expect(model.version != version)
        #expect(model.logProbability(of: "异议", after: "没有任何") > model.logProbability(of: "意义", after: "没有任何"))
        #expect(model.logProbability(of: "意义", after: "很有") == base.logProbability(of: "意义", after: "很有"))
        // An alternative loses at most what the user's weight takes.
        let lost = base.logProbability(of: "意", after: "没有任何") - model.logProbability(of: "意", after: "没有任何")
        #expect(lost > 0 && lost <= -log(1 - PersonalNGrams.maximumWeight))
    }
}
