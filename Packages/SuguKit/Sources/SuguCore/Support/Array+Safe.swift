extension Array {
    /// The element at `index`, or nil when it is out of range.
    package subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
