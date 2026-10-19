import Foundation
import Testing
@testable import SuguCore

struct ComputedCandidatesTests {
    let computed = ComputedCandidates(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
    // 2026-10-20 12:35 JST, a Tuesday.
    let now = Date(timeIntervalSince1970: 1_792_467_300)

    @Test func chineseDates() {
        let texts = computed.candidates(for: "jintian", mode: .chinese, now: now).map(\.text)
        #expect(texts.contains("2026年10月20日"))
        #expect(texts.contains("2026-10-20"))
        #expect(texts.contains("二〇二六年十月二十日"))
        let tomorrow = computed.candidates(for: "mingtian", mode: .chinese, now: now).map(\.text)
        #expect(tomorrow.contains("2026年10月21日"))
    }

    @Test func chineseNumberPrefix() {
        let texts = computed.candidates(for: "v1234", mode: .chinese, now: now).map(\.text)
        #expect(texts.prefix(2) == ["一千二百三十四", "壹仟贰佰叁拾肆"])
        #expect(computed.candidates(for: "v3*4", mode: .chinese, now: now).first?.text == "12")
    }

    @Test func japaneseDates() {
        let texts = computed.candidates(for: "きょう", mode: .japanese, now: now).map(\.text)
        #expect(texts.contains("2026年10月20日"))
        #expect(texts.contains("令和8年10月20日"))
        #expect(texts.contains("10月20日(火)"))
    }

    @Test func japaneseArithmetic() {
        #expect(computed.candidates(for: "12+30", mode: .japanese, now: now).first?.text == "42")
    }

    @Test func ordinaryReadingsProduceNothing() {
        #expect(computed.candidates(for: "nihao", mode: .chinese, now: now).isEmpty)
        #expect(computed.candidates(for: "にほんご", mode: .japanese, now: now).isEmpty)
    }
}
