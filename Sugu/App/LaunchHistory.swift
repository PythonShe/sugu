import Foundation

/// Recent launch times, kept to notice a crash loop: macOS starts an input
/// method again at the next key, so a crash at launch or at the first key
/// would repeat at every keystroke in every app.
enum LaunchHistory {
    /// This many launches within `window` count as a loop.
    static let loopCount = 3
    static let window: TimeInterval = 60

    /// Records a launch in `folder`; true when it makes a loop.
    static func recordLaunch(in folder: URL, now: Date = .now) -> Bool {
        let file = folder.appendingPathComponent("launches.json")
        let earlier = (try? JSONDecoder().decode([Date].self, from: Data(contentsOf: file))) ?? []
        let launches = earlier.filter { $0 <= now && now.timeIntervalSince($0) < window } + [now]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(launches).write(to: file, options: .atomic)
        return launches.count >= loopCount
    }
}
