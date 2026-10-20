import Foundation
import Testing
import SuguCore
import SuguLearning
@testable import SuguDictionaries

private func temporaryFile(_ name: String, _ data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

private func utf16(_ text: String) -> Data {
    Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!
}

@Suite struct ImporterTests {
    @Test func googleJapaneseInput() throws {
        let url = try temporaryFile("dictionary.txt", Data("すぐ\tSugu\t固有名詞\t\nとうきょう\t東京\t地名\t\n".utf8))
        #expect(DictionaryFormat.detect(url) == .googleJapaneseInput)
        #expect(try DictionaryImporter.read(url) == [
            DictionaryEntry(mode: .japanese, reading: "すぐ", text: "Sugu"),
            DictionaryEntry(mode: .japanese, reading: "とうきょう", text: "東京"),
        ])
    }

    @Test func atokUTF16() throws {
        let url = try temporaryFile("atok.txt", utf16("!!ATOK_TANGO_TEXT_HEADER_1\r\nカタカナ\t片仮名\t名詞*\r\n"))
        #expect(DictionaryFormat.detect(url) == .atok)
        #expect(try DictionaryImporter.read(url) == [DictionaryEntry(mode: .japanese, reading: "かたかな", text: "片仮名")])
    }

    @Test func sogouText() throws {
        let url = try temporaryFile("sogou.txt", Data("'ni'hao 你好\n'shu'ru'fa 输入法\n".utf8))
        #expect(DictionaryFormat.detect(url) == .sogouText)
        #expect(try DictionaryImporter.read(url).map(\.reading) == ["nihao", "shurufa"])
    }

    /// GBK text also decodes as Shift_JIS, into half-width katakana.
    @Test func sogouTextInGBK() throws {
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let data = try #require("'bei'jing 北京\n'shang'hai 上海\n".data(using: gbk))
        #expect(String(data: data, encoding: .shiftJIS) != nil)
        let url = try temporaryFile("sogou.txt", data)
        #expect(DictionaryFormat.detect(url) == .sogouText)
        #expect(try DictionaryImporter.read(url).map(\.text) == ["北京", "上海"])
        #expect(TextDecoding.string(from: data) == "'bei'jing 北京\n'shang'hai 上海\n")
    }

    /// The first bytes, read to tell the format, may end inside a character.
    @Test func formatIsToldFromAPrefixCutMidCharacter() throws {
        var body = ""
        while body.utf8.count < 5_000 { body += "あいうえお\t五十音\t名詞\r\n" }
        for padding in 0..<4 {
            let text = "!!ATOK_TANGO_TEXT_HEADER_1" + String(repeating: " ", count: padding) + "\r\n" + body
            let data = try #require(text.data(using: .shiftJIS))
            #expect(DictionaryFormat.detect(try temporaryFile("atok.txt", data)) == .atok)
        }
        let utf8 = Data(String(repeating: "東", count: 2_000).utf8)
        #expect(TextDecoding.string(from: utf8.prefix(4_096), prefix: true) != nil)
        // A whole file cut inside a character loses its last line.
        #expect(TextDecoding.string(from: Data("北京\n上海".utf8).dropLast(1)) == "北京")
    }

    @Test func rimeDictionary() throws {
        let yaml = "---\nname: test\nversion: \"1\"\n...\n速贵\tsu gui\t10\n# comment\n输入法\tshu ru fa\n"
        let url = try temporaryFile("test.dict.yaml", Data(yaml.utf8))
        #expect(try DictionaryImporter.read(url) == [
            DictionaryEntry(mode: .chinese, reading: "sugui", text: "速贵"),
            DictionaryEntry(mode: .chinese, reading: "shurufa", text: "输入法"),
        ])
    }

    @Test func textReplacements() throws {
        let items: [[String: String]] = [["shortcut": "omw", "phrase": "On my way!"], ["shortcut": "めあど", "phrase": "sugu@example.com"], ["shortcut": "@@", "phrase": "x"]]
        let data = try PropertyListSerialization.data(fromPropertyList: items, format: .xml, options: 0)
        let url = try temporaryFile("Text Substitutions.plist", data)
        #expect(try DictionaryImporter.read(url) == [
            DictionaryEntry(mode: .chinese, reading: "omw", text: "On my way!"),
            DictionaryEntry(mode: .japanese, reading: "めあど", text: "sugu@example.com"),
        ])
    }

    @Test func sogouCell() throws {
        // Header, syllable table (ni = 0, hao = 1), one group with two words.
        var bytes = [UInt8](repeating: 0, count: 0x2628)
        bytes.replaceSubrange(0..<8, with: [0x40, 0x15, 0x00, 0x00, 0x44, 0x43, 0x53, 0x01])
        var table: [UInt8] = [0x9D, 0x01, 0x00, 0x00]
        func u16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
        func string(_ value: String) -> [UInt8] { Array(value.data(using: .utf16LittleEndian)!) }
        for (index, syllable) in ["ni", "hao"].enumerated() {
            table += u16(index) + u16(string(syllable).count) + string(syllable)
        }
        bytes.replaceSubrange(0x1540..<(0x1540 + table.count), with: table)
        bytes += u16(2) + u16(4) + u16(0) + u16(1)
        for word in ["你好", "拟好"] {
            bytes += u16(string(word).count) + string(word) + u16(4) + [1, 0, 0, 0]
        }
        let url = try temporaryFile("words.scel", Data(bytes))
        #expect(try DictionaryImporter.read(url) == [
            DictionaryEntry(mode: .chinese, reading: "nihao", text: "你好"),
            DictionaryEntry(mode: .chinese, reading: "nihao", text: "拟好"),
        ])
    }
}

/// A clock tests move forward by hand; sync files keep whole seconds.
private final class ManualClock: @unchecked Sendable {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance() { now += 60 }
}

@MainActor
@Suite struct SyncTests {
    private func store(_ clock: @escaping @Sendable () -> Date = Date.init) throws -> LearnedStore {
        try LearnedStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/learned.sqlite"), clock: clock)
    }

    /// A file cut short, as a partial copy on a network share, adds no
    /// word from its last line.
    @Test func incompleteLinesAreSkipped() throws {
        let source = try store()
        source.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        source.addUserWord(reading: "kuai", text: "快", mode: .chinese)
        let data = SuguDictionaryFile.encode(source.allWords())
        let cut = data.prefix(data.count - 30)
        #expect(SuguDictionaryFile.decode(cut).count == 1)
        #expect(SuguDictionaryFile.decode(Data("chinese\tsugu\t速贵\tuser\n".utf8)).isEmpty)
    }

    @Test func roundTripKeepsDetail() throws {
        let source = try store()
        source.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        source.learn(Commit(text: "東京", reading: "とうきょう"), mode: .japanese)
        let words = SuguDictionaryFile.decode(SuguDictionaryFile.encode(source.allWords()))
        #expect(Set(words.map(\.text)) == ["速贵", "東京"])
        #expect(words.first { $0.text == "東京" }?.kind == .learned)
        #expect(words.first { $0.text == "速贵" }?.kind == .user)
    }

    @Test func pullsOtherMacsAndSkipsWhatWasDeleted() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let laptop = try store()
        laptop.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        laptop.learn(Commit(text: "東京", reading: "とうきょう"), mode: .japanese)
        try await SyncFolder(folder: folder, deviceID: "laptop", store: laptop).export(includeLearned: false)

        let desktop = try store()
        let sync = SyncFolder(folder: folder, deviceID: "desktop", store: desktop)
        #expect(try await sync.pull(includeLearned: true) == 1)
        #expect(desktop.lookup("sugu", mode: .chinese).map(\.text) == ["速贵"])
        // Learned words stay home unless the user opts in.
        #expect(desktop.lookup("とうきょう", mode: .japanese).isEmpty)

        desktop.deleteAll()
        #expect(try await sync.pull(includeLearned: true) == 0)
        #expect(desktop.count == 0)
    }

    @Test func deletionsSpreadAndEchoesStayDeleted() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clock = ManualClock()
        let laptop = try store { clock.now }
        let desktop = try store { clock.now }
        let laptopSync = SyncFolder(folder: folder, deviceID: "laptop", store: laptop)
        let desktopSync = SyncFolder(folder: folder, deviceID: "desktop", store: desktop)
        laptop.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        try await laptopSync.export(includeLearned: false)
        try await desktopSync.pull(includeLearned: false)
        try await desktopSync.export(includeLearned: false)

        // The desktop's file still has the word; deleting it on the laptop
        // must not let that copy bring it back.
        clock.advance()
        laptop.deleteAll()
        try await laptopSync.pull(includeLearned: false)
        #expect(laptop.count == 0)

        // The deletion reaches the desktop.
        try await laptopSync.export(includeLearned: false)
        #expect(try await desktopSync.pull(includeLearned: false) == 1)
        #expect(desktop.count == 0)

        // Adding the word again on purpose brings it back.
        clock.advance()
        laptop.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        try await laptopSync.export(includeLearned: false)
        try await desktopSync.pull(includeLearned: false)
        #expect(desktop.lookup("sugu", mode: .chinese).map(\.text) == ["速贵"])
    }

    @Test func pinsSyncWithoutNewerUse() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let laptop = try store()
        let desktop = try store()
        let laptopSync = SyncFolder(folder: folder, deviceID: "laptop", store: laptop)
        let desktopSync = SyncFolder(folder: folder, deviceID: "desktop", store: desktop)
        laptop.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        try await laptopSync.export(includeLearned: false)
        try await desktopSync.pull(includeLearned: false)

        let id = try #require(laptop.allWords().first?.id)
        laptop.setPinned(true, id: id)
        try await laptopSync.export(includeLearned: false)
        try await desktopSync.pull(includeLearned: false)
        #expect(desktop.allWords().first?.pinned == true)
    }

    @Test func unreadableFilesDoNotStopTheOthers() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("broken.sugudict"), withIntermediateDirectories: true)
        let laptop = try store()
        laptop.addUserWord(reading: "sugu", text: "速贵", mode: .chinese)
        try await SyncFolder(folder: folder, deviceID: "laptop", store: laptop).export(includeLearned: false)

        let desktop = try store()
        let sync = SyncFolder(folder: folder, deviceID: "desktop", store: desktop)
        let snapshot = try await sync.read()
        #expect(snapshot.unreadable == ["broken.sugudict"])
        #expect(try sync.merge(snapshot, includeLearned: false) == 1)
    }
}
