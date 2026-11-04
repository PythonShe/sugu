import Foundation
import SuguCore

/// Compiles the foreign-word data into `Data/Lexicon`: the dictionary from
/// UniDic, CLDR and Wikidata, and the guesser trained from the same pairs.
enum BuildLoanwords {
    struct Source {
        /// Pairs in the order their words should be preferred.
        var dictionary: [(key: String, kana: String)]
        var training: [(key: String, kana: String)]
    }

    static let maximumWords = 3

    // MARK: Pairs

    /// Katakana as stored: no separators, nothing but kana and the long mark.
    static func cleanKana(_ raw: String) -> String? {
        let kana = raw.filter { !"・=＝ ".contains($0) }
        let plain = kana.unicodeScalars.allSatisfy { (0x30A1...0x30FA).contains($0.value) || $0.value == 0x30FC }
        return !kana.isEmpty && plain ? kana : nil
    }

    private static let spelledLetters = ["エー", "ビー", "シー", "ディー", "デー", "イー", "エフ", "ジー", "エイチ", "アイ", "ジェー", "ジェイ", "ケー", "ケイ", "エル", "エム", "エヌ", "オー", "ピー", "キュー", "アール", "エス", "ティー", "ユー", "ブイ", "ダブリュー", "ダブル", "エックス", "ワイ", "ゼット", "ゼッド", "トリプル", "ツー", "スリー", "フォー", "ファイブ", "ワン", "ゼロ"]

    /// Whether katakana just names letters and numbers one by one, as an
    /// acronym's reading does; such pairs say nothing about a word.
    static func spellsLetters(_ kana: String) -> Bool {
        var reachable: Set<Substring> = [Substring(kana)]
        while let rest = reachable.popFirst() {
            if rest.isEmpty { return true }
            for letter in spelledLetters where rest.hasPrefix(letter) {
                reachable.insert(rest.dropFirst(letter.count))
            }
        }
        return false
    }

    static func clean(spelling: String, kana raw: String) -> (key: String, kana: String)? {
        guard let kana = cleanKana(raw), let key = LoanwordSpelling.key(spelling), key.count >= 2,
              !spelling.contains(where: \.isNumber), spelling.filter({ $0 == " " }).count <= 2 else { return nil }
        if key.count <= 8, spellsLetters(kana) { return nil }
        return (key, kana)
    }

    /// Fields of a CSV line, with quotes as UniDic uses them.
    static func fields(_ line: Substring) -> [Substring] {
        guard line.contains("\"") else { return line.split(separator: ",", omittingEmptySubsequences: false) }
        var result: [Substring] = []
        var start = line.startIndex
        var quoted = false
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == "\"" { quoted.toggle() } else if line[index] == ",", !quoted {
                result.append(line[start..<index])
                start = line.index(after: index)
            }
            index = line.index(after: index)
        }
        result.append(line[start...])
        return result
    }

    /// UniDic's lemmas name their source spelling (`アルバイト-Arbeit`). Also
    /// returns the readings of native words, to tell which spellings are
    /// ordinary romaji too.
    static func uniDic(_ url: URL) throws -> (pairs: [(key: String, kana: String)], native: Set<String>) {
        let text = try String(contentsOf: url, encoding: .utf8)
        var seen = Set<String>()
        var pairs: [(key: String, kana: String)] = []
        var native = Set<String>()
        text.enumerateLines { line, _ in
            let columns = fields(Substring(line))
            guard columns.count >= 18 else { return }
            let lForm = String(columns[10]), lemma = columns[11], origin = columns[16], part = columns[4]
            if ["和", "漢", "混"].contains(origin), !["記号", "補助記号", "空白"].contains(part),
               lForm.unicodeScalars.allSatisfy({ (0x30A1...0x30FA).contains($0.value) || $0.value == 0x30FC }) {
                native.insert(WidthConversion.hiragana(lForm))
            }
            guard seen.insert(String(lemma)).inserted, let dash = lemma.firstIndex(of: "-") else { return }
            let head = String(lemma[..<dash])
            var spelling = String(lemma[lemma.index(after: dash)...])
            for opening in ["(", "（"] {
                if let range = spelling.range(of: opening) { spelling = String(spelling[..<range.lowerBound]) }
            }
            guard spelling.contains(where: { $0.isLetter && $0.isASCII || ("À"..."ɏ").contains($0) }) else { return }
            if let pair = clean(spelling: spelling, kana: cleanKana(head) != nil ? head : lForm) { pairs.append(pair) }
        }
        return (pairs, native)
    }

    /// Languages, territories and cities: CLDR gives each a Japanese name and
    /// names in other languages (Germany, Deutschland → ドイツ).
    static func cldr(_ directory: URL) throws -> [(key: String, kana: String)] {
        func names(_ language: String) throws -> [String: String] {
            let document = try XMLDocument(contentsOf: directory.appendingPathComponent("\(language).xml"), options: [])
            var result: [String: String] = [:]
            for (path, prefix) in [("//languages/language[not(@alt)]", "L"), ("//territories/territory[not(@alt)]", "T")] {
                for case let element as XMLElement in try document.nodes(forXPath: path) {
                    if let type = element.attribute(forName: "type")?.stringValue, let value = element.stringValue { result[prefix + type] = value }
                }
            }
            for case let element as XMLElement in try document.nodes(forXPath: "//timeZoneNames/zone") {
                if let type = element.attribute(forName: "type")?.stringValue,
                   let city = element.elements(forName: "exemplarCity").first?.stringValue { result["C" + type] = city }
            }
            return result
        }
        let japanese = try names("ja")
        var pairs: [(key: String, kana: String)] = []
        for language in ["en", "de", "fr", "es", "it", "pt", "nl"] {
            let other = try names(language)
            for (id, name) in other.sorted(by: { $0.key < $1.key }) {
                if let kana = japanese[id], let pair = clean(spelling: name, kana: kana) { pairs.append(pair) }
            }
        }
        for (id, kana) in japanese.sorted(by: { $0.key < $1.key }) where id.hasPrefix("C") {
            let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? ""
            if let pair = clean(spelling: city, kana: kana) { pairs.append(pair) }
        }
        return pairs
    }

    /// `scripts/refresh-wikidata-loanwords.py`'s extract: key, katakana, the
    /// item's sitelinks, and how many labels the pair came from when it was
    /// taken out of a longer name (0 for a whole label). All of it trains the
    /// guesser; only notable items reach the dictionary.
    static func wikidata(_ url: URL) throws -> (dictionary: [(key: String, kana: String)], training: [(key: String, kana: String)]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        var dictionary: [(key: String, kana: String)] = []
        var training: [(key: String, kana: String)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t")
            guard columns.count == 4, let sitelinks = Int(columns[2]), let tokens = Int(columns[3]),
                  let pair = clean(spelling: String(columns[0]), kana: String(columns[1])) else { continue }
            training.append(pair)
            guard pair.key.count >= 3, sitelinks >= 50, tokens == 0 || tokens >= 5 else { continue }
            // A name that reads as romaji only stays when it is that reading.
            if let kana = RomajiReading(pair.key).kana, WidthConversion.katakana(kana) != pair.kana { continue }
            dictionary.append(pair)
        }
        return (dictionary, training)
    }

    // MARK: Compiling

    /// Collects pairs into entries, words in the order the pairs came.
    static func entries(_ pairs: [(key: String, kana: String)], native: Set<String>, keep: (String, String, Int) -> Bool = { _, _, _ in true }) -> [LoanwordTable.Entry] {
        var words: [String: [String]] = [:]
        for pair in pairs where !(words[pair.key]?.contains(pair.kana) ?? false) {
            guard keep(pair.key, pair.kana, words[pair.key]?.count ?? 0) else { continue }
            words[pair.key, default: []].append(pair.kana)
        }
        return words.keys.sorted().map { key in
            let reading = RomajiReading(key).kana
            return LoanwordTable.Entry(key: key, words: Array(words[key]!.prefix(maximumWords)), alsoJapanese: reading.map(native.contains) ?? false)
        }
    }

    static func run(uniDic uniDicURL: URL, cldr cldrDirectory: URL, wikidata wikidataURL: URL, output: URL, excludingFromTraining: URL?, minimumTrigram: Int) async throws {
        let (uniDicPairs, native) = try uniDic(uniDicURL)
        let cldrPairs = try cldr(cldrDirectory)
        let (wikidataWords, wikidataTraining) = try wikidata(wikidataURL)
        print("pairs: UniDic \(uniDicPairs.count), CLDR \(cldrPairs.count), Wikidata \(wikidataWords.count) of \(wikidataTraining.count); \(native.count) native readings")

        let excluded = try excludingFromTraining.map { url in
            Set(try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map { String($0.split(separator: "\t")[0]) })
        } ?? []
        var trainer = GraphoneTrainer()
        var seen = Set<String>()
        var pairs: [GraphoneTrainer.Pair] = []
        var curatedCount = 0
        for (index, pair) in (uniDicPairs + cldrPairs + wikidataTraining).enumerated() {
            guard pair.key.count <= KatakanaGuesser.maximumLength, pair.key.utf8.allSatisfy({ (0x61...0x7A).contains($0) }),
                  !excluded.contains(pair.key), seen.insert(pair.key + "\t" + pair.kana).inserted else { continue }
            pairs.append(trainer.pair(key: pair.key, kana: pair.kana))
            if index < uniDicPairs.count + cldrPairs.count { curatedCount += 1 }
        }
        // Common words (UniDic, CLDR) count twice, so the far more numerous
        // Wikidata names do not swamp their patterns.
        pairs += pairs[0..<curatedCount]
        // A fixed subsample, spread over the sources by a stride.
        let sample = pairs.count <= GraphoneTrainer.emSample ? pairs : stride(from: 0, to: pairs.count, by: pairs.count / GraphoneTrainer.emSample).map { pairs[$0] }
        print("training on \(pairs.count) pairs, EM on \(sample.count)")
        let table = await trainer.train(sample)
        let logTable = table.mapValues { log($0) }
        let aligned = await trainer.alignments(pairs, logTable: logTable)
        let model = trainer.model(from: aligned.sequences, minimumTrigram: minimumTrigram)
        print("model: \(model.graphones.count) graphones, \(model.bigrams.count) bigrams, \(model.trigrams.count) trigrams")

        // Wikidata pairs that barely align are translations (assepoester,
        // シンデレラ), and so are second words that do not (cafe, コーヒー).
        var checker = trainer
        func aligns(_ key: String, _ kana: String) -> Bool {
            guard key.utf8.allSatisfy({ (0x61...0x7A).contains($0) }) else { return true }
            let pair = checker.pair(key: key, kana: kana)
            guard let result = trainer.align(pair, logTable: logTable) else { return false }
            return result.score >= aligned.noiseFloor
        }
        let curated = Set((uniDicPairs + cldrPairs).map { $0.key + "\t" + $0.kana })
        var dropped = 0
        let table2 = entries(uniDicPairs + cldrPairs + wikidataWords, native: native) { key, kana, position in
            if position == 0, curated.contains(key + "\t" + kana) { return true }
            if aligns(key, kana) { return true }
            dropped += 1
            return false
        }
        print("dictionary: \(table2.count) keys, \(table2.filter(\.alsoJapanese).count) also Japanese, \(dropped) pairs dropped as translations")

        let fm = FileManager.default
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let dictionaryData = LoanwordTable.encode(table2)
        try dictionaryData.write(to: output.appendingPathComponent(ForeignWords.bundledDictionaryFile))
        let modelData = KatakanaGuesser.encode(model)
        try modelData.write(to: output.appendingPathComponent(ForeignWords.guesserFile))
        print("wrote \(dictionaryData.count) bytes of dictionary, \(modelData.count) bytes of guesser")
    }

    // MARK: The download

    /// How much a spelling and katakana sound alike, from 0 to 1, comparing
    /// coarse consonant classes. Keeps a gloss that is a transliteration
    /// (`keyboard`, キーボード) from one that is a translation (`joyously`,
    /// イソイソ).
    static func soundsAlike(spelling: String, kana: String) -> Double {
        func consonants(_ text: String) -> [Character] {
            var folded = text
            for (from, to) in [("ph", "f"), ("ck", "k"), ("qu", "k"), ("sch", "s"), ("sh", "s"), ("ch", "s"), ("th", "s"), ("ts", "s"), ("tz", "s"), ("dg", "j")] {
                folded = folded.replacingOccurrences(of: from, with: to)
            }
            let classes: [Character: Character] = ["r": "R", "l": "R", "b": "B", "v": "B", "w": "B", "f": "H", "h": "H", "k": "K", "c": "K", "q": "K", "g": "K", "x": "K", "s": "S", "z": "S", "j": "S", "t": "T", "d": "T", "m": "M", "n": "N", "p": "P"]
            var result: [Character] = []
            for character in folded {
                if let group = classes[character], result.last != group { result.append(group) }
            }
            return result
        }
        let romaji = kana.applyingTransform(.latinToKatakana, reverse: true)?.folding(options: .diacriticInsensitive, locale: nil).lowercased() ?? ""
        let left = consonants(spelling), right = consonants(romaji)
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        var row = Array(0...right.count)
        for (i, l) in left.enumerated() {
            var current = [i + 1]
            for (j, r) in right.enumerated() {
                current.append(min(row[j + 1] + 1, current[j] + 1, row[j] + (l == r ? 0 : 1)))
            }
            row = current
        }
        return 1 - Double(row[right.count]) / Double(max(left.count, right.count))
    }

    /// Words of JMdict entries written only in katakana: their named source,
    /// then their glosses that sound like them.
    private final class JMdictReader: NSObject, XMLParserDelegate {
        var sources: [(key: String, kana: String)] = []
        var glosses: [(key: String, kana: String)] = []
        private var kana: [String] = []
        private var hasKanji = false
        private var text = ""
        private var entrySources: [String] = []
        private var entryGlosses: [String] = []
        private var keepsGloss = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "entry":
                kana = []
                hasKanji = false
                entrySources = []
                entryGlosses = []
            case "keb": hasKanji = true
            case "gloss": keepsGloss = attributes["g_type"] == nil
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "reb": if let clean = cleanKana(text) { kana.append(clean) }
            case "lsource": if !text.isEmpty { entrySources.append(text) }
            case "gloss": if keepsGloss { entryGlosses.append(text) }
            case "entry":
                guard !kana.isEmpty, !hasKanji else { return }
                for word in kana {
                    for source in entrySources {
                        if let pair = clean(spelling: source, kana: word) { sources.append(pair) }
                    }
                    for gloss in entryGlosses {
                        let plain = gloss.replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                        guard plain.split(separator: " ").count <= 3, let pair = clean(spelling: plain, kana: word),
                              soundsAlike(spelling: pair.key, kana: word) >= 0.6 else { continue }
                        glosses.append(pair)
                    }
                }
            default: break
            }
        }
    }

    /// Katakana headwords of Wiktionary's Japanese section, by the term their
    /// etymology says they were borrowed from.
    static func wiktionary(_ url: URL) throws -> [(key: String, kana: String)] {
        let borrowed: Set<String> = ["bor", "bor+", "der", "der+", "lbor", "slbor", "obor", "ubor", "psm"]
        var pairs: [(key: String, kana: String)] = []
        let text = try String(contentsOf: url, encoding: .utf8)
        text.enumerateLines { line, _ in
            guard line.contains("etymology_templates"), let data = line.data(using: .utf8),
                  let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let word = entry["word"] as? String, let kana = cleanKana(word),
                  let templates = entry["etymology_templates"] as? [[String: Any]] else { return }
            for template in templates {
                guard let name = template["name"] as? String, borrowed.contains(name),
                      let args = template["args"] as? [String: Any], args["1"] as? String == "ja" else { continue }
                for field in ["3", "tr"] {
                    guard var term = args[field] as? String, !term.isEmpty else { continue }
                    if let hash = term.firstIndex(of: "#") { term = String(term[..<hash]) }
                    if let pair = clean(spelling: term, kana: kana) {
                        pairs.append(pair)
                        break
                    }
                }
            }
        }
        return pairs
    }

    /// Compiles the optional download from JMdict and Wiktionary, which are
    /// share-alike and so stay out of the app.
    static func buildDownload(jmdict: URL, wiktionary wiktionaryURL: URL, uniDic uniDicURL: URL, output: URL) throws {
        let reader = JMdictReader()
        guard let parser = XMLParser(contentsOf: jmdict) else { throw ToolError.unreadable(jmdict.path) }
        parser.delegate = reader
        guard parser.parse() else { throw parser.parserError ?? ToolError.unreadable(jmdict.path) }
        let wiktionaryPairs = try wiktionary(wiktionaryURL)
        let native = try uniDic(uniDicURL).native
        print("pairs: JMdict sources \(reader.sources.count), glosses \(reader.glosses.count), Wiktionary \(wiktionaryPairs.count)")
        let entries = entries(reader.sources + wiktionaryPairs + reader.glosses, native: native)
        let data = LoanwordTable.encode(entries)
        try data.write(to: output)
        print("wrote \(entries.count) keys, \(data.count) bytes")
    }

    enum ToolError: Error {
        case unreadable(String)
    }

    // MARK: Checking

    /// Prints how often the guesser finds the katakana of `pairs`, a TSV of
    /// spelling and katakana, for tuning against data that stays out of the
    /// build.
    static func checkGuesser(model: URL, pairs: URL, showing: Int, beam: Int) throws {
        let guesser = try KatakanaGuesser(contentsOf: model)
        var total = 0, top1 = 0, top5 = 0, none = 0
        var shown = 0
        var slowest = 0.0
        let started = Date()
        for line in try String(contentsOf: pairs, encoding: .utf8).split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t")
            guard columns.count >= 2, let key = LoanwordSpelling.key(String(columns[0])) else { continue }
            let accepted = columns[1].split(separator: " ").map(String.init)
            total += 1
            let began = Date()
            let guesses = guesser.guesses(for: key, beam: beam).map(\.text)
            slowest = max(slowest, Date().timeIntervalSince(began))
            if guesses.isEmpty { none += 1 }
            if let first = guesses.first, accepted.contains(first) { top1 += 1 }
            if guesses.contains(where: accepted.contains) { top5 += 1 }
            if shown < showing {
                print("\(key)\t\(accepted.joined(separator: " "))\t\(guesses.joined(separator: " "))")
                shown += 1
            }
        }
        func percent(_ count: Int) -> String { String(format: "%.1f%%", 100 * Double(count) / Double(max(total, 1))) }
        print("\(total) words: top-1 \(percent(top1)), top-5 \(percent(top5)), no guess \(percent(none)); \(String(format: "%.0f", Date().timeIntervalSince(started) / Double(max(total, 1)) * 1e6)) us mean, \(String(format: "%.0f", slowest * 1e6)) us slowest")
    }
}
