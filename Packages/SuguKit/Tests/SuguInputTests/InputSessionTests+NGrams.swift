import Foundation
import Testing
import SuguCore
import SuguLearning
import SuguLM
@testable import SuguInput

/// The user's n-grams (D-079): learned from commits, after the text Sugu
/// typed before them.
extension InputSessionTests {
    @Test func commitsAreLearnedAfterWhatSuguTypedBefore() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.space)
        type("nihao", into: session)
        _ = session.handle(Key.space)
        let grams = store.personalNGrams(for: .chinese)
        #expect(grams.count(of: "你好") == 2)
        #expect(grams.count(of: "好你") == 1)
        #expect(grams.count(of: "你好你好") == 1)
    }

    @Test func theCaretMovingEndsTheContext() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.space)
        session.caretMayHaveMoved()
        type("nihao", into: session)
        _ = session.handle(Key.space)
        #expect(store.personalNGrams(for: .chinese).count(of: "好你") == 0)
        _ = session.handle(Key.down)
        type("nihao", into: session)
        _ = session.handle(Key.space)
        #expect(store.personalNGrams(for: .chinese).count(of: "好你") == 0)
    }

    @Test func undoTakesBackTheNGrams() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.space)
        #expect(session.handle(Key.undo))
        #expect(!store.hasNGrams)
        _ = session.handle(Key.space)
        #expect(store.personalNGrams(for: .chinese).count(of: "你好") == 1)
    }

    @Test func nGramsAreNotLearnedWhenTurnedOff() {
        let session = makeSession { $0.learnsPhrases = false }
        type("nihao", into: session)
        _ = session.handle(Key.space)
        #expect(!store.hasNGrams)
    }

    @Test func nGramsAreNotLearnedWhereWordsAreNot() {
        let session = makeSession()
        session.attach(FakeClient(bundleIdentifier: "com.1password.1password"))
        type("nihao", into: session)
        _ = session.handle(Key.space)
        #expect(!store.hasNGrams)
    }
}
