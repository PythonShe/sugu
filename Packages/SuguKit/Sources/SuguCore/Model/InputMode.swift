/// The language state inside Sugu's single input source. Decides which
/// engine, if any, receives keystrokes.
public enum InputMode: String, CaseIterable, Codable, Sendable {
    case chinese
    case japanese
    case english

    /// The next mode in the toggle cycle, skipping modes the user turned off.
    public func next(enabled: [InputMode]) -> InputMode {
        let cycle = InputMode.allCases.filter { enabled.contains($0) || $0 == .english }
        guard let index = cycle.firstIndex(of: self) else { return cycle.first ?? .english }
        return cycle[(index + 1) % cycle.count]
    }
}
