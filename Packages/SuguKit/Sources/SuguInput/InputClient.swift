import SuguCore

/// The document side of the input session: the focused text field, as the
/// shell sees it through InputMethodKit.
@MainActor
public protocol InputClient: AnyObject {
    /// Bundle identifier of the app that owns the field.
    var bundleIdentifier: String? { get }
    /// Inserts committed text, replacing the marked text.
    func commit(_ text: String)
    /// Shows the composition as marked text; empty segments clear it.
    func setMarkedText(_ segments: [CompositionSegment], caret: Int)
    /// Up to `limit` characters left of the caret, or nil when the field
    /// does not expose its text.
    func textBeforeCaret(limit: Int) -> String?
    /// Up to `limit` characters right of the caret (after any selection),
    /// or nil when the field does not expose its text.
    func textAfterCaret(limit: Int) -> String?
    /// Deletes `count` characters left of the caret. Returns false when the
    /// field does not support it.
    func deleteBeforeCaret(count: Int) -> Bool
    /// The selected text, for reconversion; nil when nothing is selected or
    /// the field does not expose it.
    func selectedText() -> String?
}
