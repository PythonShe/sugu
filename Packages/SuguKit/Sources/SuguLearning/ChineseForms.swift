import SuguCore

/// Converts Chinese between scripts for the store, which keeps each word
/// once in Simplified and gives it back in the script being typed (D-094).
@MainActor
public protocol ChineseForms: AnyObject {
    /// Text in any Chinese script, in Simplified; nil when it cannot be
    /// converted.
    func simplified(_ text: String) -> String?
    /// Text in any Chinese script, in `script`; nil when it cannot be
    /// converted.
    func text(_ text: String, in script: ChineseScript) -> String?
}
