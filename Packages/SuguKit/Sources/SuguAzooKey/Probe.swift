internal import KanaKanjiConverterModuleWithDefaultDictionary

public func azooKeyProbe() -> String {
    let converter = KanaKanjiConverter.withDefaultDictionary()
    var text = ComposingText()
    text.insertAtCursorPosition("にほんご", inputStyle: .direct)
    _ = converter
    return text.convertTarget
}
