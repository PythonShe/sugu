/// Symbols by the names Japanese input methods offer them under (やじるし
/// → → ← ↑ ↓), which AzooKey's dictionary does not: written by Sugu. Names
/// that are everyday words on their own (から, おなじ, かける) are left out.
public enum JapaneseSymbolNames {
    public static func symbols(for reading: String) -> [String] {
        table[reading] ?? []
    }

    private static let table: [String: [String]] = [
        "やじるし": ["→", "←", "↑", "↓", "⇒", "⇔"],
        "まる": ["○", "●", "◎"],
        "さんかく": ["△", "▲", "▽", "▼"],
        "しかく": ["□", "■", "◇", "◆"],
        "ほし": ["★", "☆"],
        "こめ": ["※"],
        "ゆうびん": ["〒"],
        "おんぷ": ["♪", "♬"],
        "ばつ": ["×"],
        "かっこ": ["【】", "『』", "〈〉", "《》", "［］"],
        "せっし": ["℃"],
        "ふとうごう": ["≠", "≦", "≧", "＜", "＞"],
        "にあいこーる": ["≒"],
        "るーと": ["√"],
        "むげん": ["∞"],
        "ぱーみる": ["‰"],
        "ゆえに": ["∴"],
        "なぜならば": ["∵"],
        "せくしょん": ["§"],
        "だがー": ["†", "‡"],
        "あるふぁ": ["α"], "べーた": ["β"], "がんま": ["γ"], "でるた": ["δ", "Δ"],
        "しぐま": ["σ", "Σ"], "ぱい": ["π"], "らむだ": ["λ"], "おめが": ["ω", "Ω"],
    ]
}
