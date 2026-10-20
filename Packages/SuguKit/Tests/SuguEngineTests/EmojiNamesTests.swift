import Foundation
import Testing
import SuguRime

struct EmojiNamesTests {
    private let annotations = Data("""
    <ldml><annotations>
        <annotation cp="😊">害羞 | 微笑 | 脸</annotation>
        <annotation cp="😊" type="tts">羞涩微笑</annotation>
        <annotation cp="☺">微笑 | 脸 | smile</annotation>
        <annotation cp="☺" type="tts">微笑</annotation>
        <annotation cp="🙆‍♂">好的 | 手势</annotation>
        <annotation cp="#⃣">井号</annotation>
    </annotations></ldml>
    """.utf8)

    @Test func wordsOfferTheEmojiTheyName() {
        let lines = EmojiNames.table(fromAnnotations: [annotations]).split(separator: "\n")
        // The name first, then keywords; single characters and Latin words
        // offer nothing.
        #expect(lines.contains("微笑\t微笑 ☺️"))
        #expect(lines.contains("羞涩微笑\t羞涩微笑 😊"))
        #expect(!lines.contains { $0.hasPrefix("脸\t") || $0.hasPrefix("smile\t") })
    }

    /// Symbols CLDR does not name come first, in both scripts.
    @Test func symbolsByTheirNames() {
        let arrows = Data("<ldml><annotations><annotation cp=\"←\">箭头 | 左</annotation></annotations></ldml>".utf8)
        let lines = EmojiNames.table(fromAnnotations: [arrows]).split(separator: "\n")
        #expect(lines.contains("箭头\t箭头 → ← ↑ ↓"))
        #expect(lines.contains("箭頭\t箭頭 → ← ↑ ↓"))
        #expect(lines.contains("摄氏度\t摄氏度 ℃"))
    }

    @Test func emojiAreFullyQualified() {
        let table = EmojiNames.table(fromAnnotations: [annotations])
        #expect(table.contains("好的\t好的 🙆‍♂️"))
        #expect(table.contains("井号\t井号 #️⃣"))
    }
}
