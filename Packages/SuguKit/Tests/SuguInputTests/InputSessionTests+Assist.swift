import Foundation
import Testing
import SuguCore
import SuguLearning
@testable import SuguInput

/// Apple's language models: revisions of the selection and model
/// candidates.
extension InputSessionTests {
    @Test func aRevisedSelectionStaysUntilAResultIsChosen() async throws {
        let session = makeSession { $0.languageModel = .onDevice }
        let assistant = FakeAssistant()
        assistant.results = ["Hello, world", "你好，世界"]
        session.assistant = assistant
        session.setMode(.english)
        client.selection = "你好，世界"
        session.revise(selectionWith: .translate(to: .english))
        #expect(client.markedText == "你好，世界")
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.display.candidates?.candidates.map(\.text) == ["你好，世界", "Hello, world"])
        #expect(session.handle(Key.escape))
        #expect(client.document == "你好，世界")

        session.revise(selectionWith: .translate(to: .english))
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.handle(Key.char("2")))
        #expect(client.document == "你好，世界Hello, world")
    }

    @Test func selectionCommandsNeedTheirLevelAndSwitch() {
        let session = makeSession { $0.languageModel = .onDevice; $0.modelForSelection = false }
        session.assistant = FakeAssistant()
        client.selection = "text"
        #expect(!session.canReviseSelection)
        let off = makeSession()
        off.assistant = FakeAssistant()
        #expect(!off.canReviseSelection)
    }

    @Test func longCompositionsGetModelCandidatesAfterTheBest() async throws {
        let session = makeSession { $0.languageModel = .privateCloudCompute; $0.modelForConversion = true; $0.modelForTranslation = true }
        let assistant = FakeAssistant()
        assistant.suggestions = CompositionSuggestions(conversions: ["你好世界！", "你好世界"], translations: [.english: "Hello world", .japanese: "こんにちは世界"])
        session.assistant = assistant
        type("nihaoshijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.count == 1)
        #expect(assistant.requests.first?.translations == [.japanese, .english])
        #expect(session.display.candidates?.candidates.map(\.text).prefix(4) == ["你好世界", "你好世界！", "こんにちは世界", "Hello world"])
        session.selectCandidate(onPage: 1)
        #expect(client.document == "你好世界！")
    }

    @Test func aReadingTypedAgainBeforeThePauseIsStillAsked() async throws {
        let session = makeSession { $0.languageModel = .privateCloudCompute; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        assistant.suggestions = CompositionSuggestions(conversions: ["你好世界！"])
        session.assistant = assistant
        type("nihaoshijie", into: session)
        for _ in 0..<4 { _ = session.handle(Key.backspace) }
        type("ijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.count == 1)
        #expect(session.display.candidates?.candidates.map(\.text).contains("你好世界！") == true)
    }

    @Test func modelCandidatesEndWithTheirComposition() async throws {
        let session = makeSession { $0.languageModel = .privateCloudCompute; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        assistant.suggestions = CompositionSuggestions(conversions: ["你好世界！"])
        session.assistant = assistant
        type("nihaoshijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        session.commitComposition()
        // The same reading elsewhere is asked again, with its own context.
        type("nihaoshijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.count == 2)
        // Turned off, the model's candidates go at once.
        session.preferences.languageModel = .off
        _ = session.handle(Key.backspace)
        type("e", into: session)
        #expect(session.display.candidates?.candidates.map(\.text).contains("你好世界！") == false)
    }

    @Test func aRequestWaitingForThePauseIsDroppedWhenFocusMoves() async throws {
        let session = makeSession { $0.languageModel = .privateCloudCompute; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        session.assistant = assistant
        type("nihaoshijie", into: session)
        session.attach(FakeClient(bundleIdentifier: "com.1password.1password"))
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.isEmpty)
    }

    @Test func passwordManagersNeverReachTheModel() async throws {
        let password = FakeClient(bundleIdentifier: "com.1password.1password")
        let session = makeSession { $0.languageModel = .privateCloudCompute; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        session.assistant = assistant
        session.attach(password)
        for c in "nihaoshijie" { _ = session.handle(Key.char(c)) }
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.isEmpty)
    }

    /// On this Mac only translations are asked for: its conversions were
    /// worse than the engines'.
    @Test func onDeviceCompositionsAskForTranslationsOnly() async throws {
        let session = makeSession { $0.languageModel = .onDevice; $0.modelForConversion = true; $0.modelForTranslation = true }
        let assistant = FakeAssistant()
        session.assistant = assistant
        type("nihaoshijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.map(\.convert) == [false])
        #expect(assistant.requests.first?.translations == [.japanese, .english])
    }

    @Test func onDeviceConversionsAloneAskNothing() async throws {
        let session = makeSession { $0.languageModel = .onDevice; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        session.assistant = assistant
        type("nihaoshijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.isEmpty)
    }
}
