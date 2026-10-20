import AppKit
import Carbon
import InputMethodKit
import SuguCore
import SuguInput

/// The focused text field as InputMethodKit exposes it.
@MainActor
final class TextInputClient: InputClient {
    let client: any IMKTextInput & NSObjectProtocol
    private weak var controller: IMKInputController?
    /// The marked text Sugu last set; nil when there is none. Clearing
    /// marked text that was never set replaces the selection in some apps.
    private var marked: (segments: [CompositionSegment], caret: Int)?
    /// Where the composition starts on screen, read once per marked text:
    /// moving the highlight through predictions leaves it in place.
    private var markedRect: NSRect?

    private static let notFound = NSRange(location: NSNotFound, length: NSNotFound)

    init(client: any IMKTextInput & NSObjectProtocol, controller: IMKInputController) {
        self.client = client
        self.controller = controller
    }

    func represents(_ other: Any?) -> Bool {
        (other as AnyObject?) === client
    }

    var bundleIdentifier: String? { client.bundleIdentifier() }

    func commit(_ text: String) {
        client.insertText(text, replacementRange: Self.notFound)
        marked = nil
        markedRect = nil
    }

    func setMarkedText(_ segments: [CompositionSegment], caret: Int) {
        if let marked, marked.segments == segments, marked.caret == caret { return }
        guard marked != nil || !segments.isEmpty else { return }
        let marked = NSMutableAttributedString()
        for segment in segments {
            let range = NSRange(location: marked.length, length: (segment.text as NSString).length)
            marked.append(NSAttributedString(string: segment.text, attributes: attributes(for: segment.role, range: range)))
        }
        let joined = segments.map(\.text).joined()
        let caretOffset = joined.prefix(caret).utf16.count
        client.setMarkedText(marked, selectionRange: NSRange(location: caretOffset, length: 0), replacementRange: Self.notFound)
        self.marked = segments.isEmpty ? nil : (segments, caret)
        markedRect = nil
    }

    private func attributes(for role: CompositionSegment.Role, range: NSRange) -> [NSAttributedString.Key: Any] {
        let style = switch role {
        case .input: kTSMHiliteSelectedRawText
        case .converted: kTSMHiliteConvertedText
        case .focused: kTSMHiliteSelectedConvertedText
        }
        guard let marks = controller?.mark(forStyle: style, at: range) else { return [:] }
        var attributes: [NSAttributedString.Key: Any] = [:]
        for (key, value) in marks {
            if let name = key as? String { attributes[NSAttributedString.Key(name)] = value }
        }
        return attributes
    }

    /// End of the committed text: the start of the marked text, or the
    /// caret.
    private var insertionPoint: Int? {
        let marked = client.markedRange()
        if marked.location != NSNotFound, marked.length > 0 { return marked.location }
        let selected = client.selectedRange()
        return selected.location == NSNotFound ? nil : selected.location
    }

    func textBeforeCaret(limit: Int) -> String? {
        guard let end = insertionPoint else { return nil }
        guard end > 0 else { return "" }
        // Characters can take two UTF-16 units; read enough to cover them.
        let start = max(0, end - limit * 2)
        guard let text = client.attributedSubstring(from: NSRange(location: start, length: end - start))?.string else { return nil }
        return String(text.suffix(limit))
    }

    func textAfterCaret(limit: Int) -> String? {
        let selected = client.selectedRange()
        guard selected.location != NSNotFound else { return nil }
        let start = NSMaxRange(selected)
        let end = min(client.length(), start + limit * 2)
        guard end > start else { return "" }
        guard let text = client.attributedSubstring(from: NSRange(location: start, length: end - start))?.string else { return nil }
        return String(text.prefix(limit))
    }

    func deleteBeforeCaret(count: Int) -> Bool {
        guard let end = insertionPoint, let before = textBeforeCaret(limit: count), before.count == count else { return false }
        let length = before.utf16.count
        client.insertText("", replacementRange: NSRange(location: end - length, length: length))
        return true
    }

    func selectedText() -> String? {
        let selected = client.selectedRange()
        guard selected.location != NSNotFound, selected.length > 0 else { return nil }
        return client.attributedSubstring(from: selected)?.string
    }

    /// The rectangle of the composition's first character in screen
    /// coordinates; zero when the field does not report one.
    func compositionRect() -> NSRect {
        if let markedRect { return markedRect }
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        if marked != nil, rect != .zero { markedRect = rect }
        return rect
    }
}
