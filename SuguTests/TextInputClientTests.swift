import AppKit
import InputMethodKit
import Testing

/// A text field as InputMethodKit presents it: UTF-16 offsets throughout.
private final class FakeTextInput: NSObject, IMKTextInput {
    let text: NSMutableString
    var selection: NSRange
    var marked = NSRange(location: NSNotFound, length: 0)
    var exposesText = true

    init(_ text: String, caret: Int? = nil) {
        self.text = NSMutableString(string: text)
        selection = NSRange(location: caret ?? self.text.length, length: 0)
    }

    func insertText(_ string: Any!, replacementRange: NSRange) {
        let inserted = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        let range = replacementRange.location == NSNotFound ? selection : replacementRange
        text.replaceCharacters(in: range, with: inserted)
        selection = NSRange(location: range.location + (inserted as NSString).length, length: 0)
        marked = NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {}
    func selectedRange() -> NSRange { exposesText ? selection : NSRange(location: NSNotFound, length: NSNotFound) }
    func markedRange() -> NSRange { marked }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        guard exposesText, NSMaxRange(range) <= text.length else { return nil }
        return NSAttributedString(string: text.substring(with: range))
    }
    func length() -> Int { exposesText ? text.length : NSNotFound }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { 0 }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! { [:] }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "com.example.editor" }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "fake" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { text.substring(with: range) }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}

@MainActor
@Suite struct TextInputClientTests {
    private func adapter(_ field: FakeTextInput) -> TextInputClient {
        TextInputClient(client: field, controller: IMKInputController())
    }

    @Test func readsWholeCharactersBeforeTheCaret() {
        let field = FakeTextInput("ab😀c")
        let client = adapter(field)
        #expect(client.textBeforeCaret(limit: 2) == "😀c")
        #expect(client.textBeforeCaret(limit: 1) == "c")
        #expect(client.textBeforeCaret(limit: 10) == "ab😀c")
    }

    @Test func readsBeforeMarkedTextAndAfterTheSelection() {
        let field = FakeTextInput("今日は😀晴れ", caret: 3)
        field.marked = NSRange(location: 3, length: 2)
        field.selection = NSRange(location: 4, length: 0)
        let client = adapter(field)
        // Marked text is not the document's yet.
        #expect(client.textBeforeCaret(limit: 5) == "今日は")
        field.marked = NSRange(location: NSNotFound, length: 0)
        field.selection = NSRange(location: 1, length: 2)
        #expect(client.textAfterCaret(limit: 2) == "😀晴")
        #expect(client.textAfterCaret(limit: 10) == "😀晴れ")
        #expect(client.selectedText() == "日は")
    }

    @Test func deletesWholeCharactersBeforeTheCaret() {
        let field = FakeTextInput("ab😀c")
        let client = adapter(field)
        #expect(client.deleteBeforeCaret(count: 2))
        #expect(field.text as String == "ab")
        #expect(!client.deleteBeforeCaret(count: 3))
        #expect(field.text as String == "ab")
    }

    @Test func fieldsThatHideTheirTextGiveNothing() {
        let field = FakeTextInput("secret")
        field.exposesText = false
        let client = adapter(field)
        #expect(client.textBeforeCaret(limit: 3) == nil)
        #expect(client.textAfterCaret(limit: 3) == nil)
        #expect(!client.deleteBeforeCaret(count: 1))
        #expect(client.selectedText() == nil)
    }
}
