import AppKit
import SuguCore
import SuguInput

/// Times what the candidate window does on each keystroke — laying out a
/// page and drawing it — offscreen, against the draw budget in CLAUDE.md.
/// Shows nothing and touches no settings or stores:
///   Sugu.app/Contents/MacOS/Sugu --measure-draw
@MainActor
enum DrawMeasurement {
    static let budget = 16.0
    static let rounds = 40

    /// Prints the timings; returns whether p99 is within the budget.
    static func run() -> Bool {
        _ = NSApplication.shared
        let view = CandidateView(frame: .zero)
        let styles = [
            CandidateView.Style(layout: .vertical, fontSize: 16),
            CandidateView.Style(layout: .horizontal, fontSize: 16),
            CandidateView.Style(layout: .vertical, fontSize: 28),
        ]
        var times: [Double] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: appearance)
            for style in styles {
                for _ in 0..<rounds {
                    for page in pages {
                        let start = ContinuousClock.now
                        let size = view.update(page, style: style)
                        view.frame = NSRect(origin: .zero, size: size)
                        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                            view.cacheDisplay(in: view.bounds, to: rep)
                        }
                        let elapsed = start.duration(to: .now).components
                        times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
                    }
                }
            }
        }
        times.sort()
        func percentile(_ p: Double) -> Double { times[min(times.count - 1, Int(Double(times.count) * p))] }
        let p99 = percentile(0.99)
        let verdict = p99 < budget ? "pass" : "FAIL"
        print(String(format: "Candidate window (%d draws): p50 %.2f ms  p99 %.2f ms  max %.2f ms (< %.0f) — %@",
                     times.count, percentile(0.5), p99, times.last ?? 0, budget, verdict))
        return p99 < budget
    }

    /// Full pages as each language produces them: short words with
    /// readings, long sentence candidates, Latin text, and a candidate too
    /// long to show whole.
    private static var pages: [CandidatePresentation] {
        let chinese = ["我", "爱", "北京", "天安门", "我爱北京天安门", "卧", "握", "沃", "窝", "喔"]
        let readings = ["wǒ", "ài", "běijīng", "tiān'ānmén", nil, "wò", "wò", "wò", "wō", "ō"]
        let japanese = ["今日はいい天気ですね", "今日は良い天気ですね", "京は異以天気ですね", "きょうはいいてんきですね",
                        "今日は", "強は", "京は", "教は", "凶は", "共は"]
        return [
            CandidatePresentation(
                candidates: zip(chinese, readings).map { Candidate(text: $0, annotation: $1, source: .engine(index: 0)) },
                highlightedIndex: 0, hasNextPage: true),
            CandidatePresentation(
                candidates: japanese.map { Candidate(text: $0, source: .engine(index: 0)) },
                highlightedIndex: 3, page: 1, hasPreviousPage: true, hasNextPage: true),
            CandidatePresentation(
                candidates: ["github", "GitHub", "ギットハブ"].map { Candidate(text: $0, source: .latin) },
                highlightedIndex: nil, isPrediction: true),
            CandidatePresentation(
                candidates: [String(repeating: "今日はいい天気ですね", count: 6), "今日は"].map { Candidate(text: $0, source: .engine(index: 0)) },
                highlightedIndex: 0),
        ]
    }
}
