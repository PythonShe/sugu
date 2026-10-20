import AppKit
import SuguCore
import SuguInput
import Testing

@MainActor
@Suite struct CandidateViewTests {
    @Test func voiceOverSeesEachCandidateAndThePageButtons() throws {
        let view = CandidateView()
        view.pageLabels = ("Previous Page", "Next Page")
        var selected: Int?, turned: Int?
        view.onSelect = { selected = $0 }
        view.onTurnPage = { turned = $0 }
        let candidates = [Candidate(text: "北京", annotation: "běijīng", source: .engine(index: 0)), Candidate(text: "背景", source: .engine(index: 0))]
        _ = view.update(CandidatePresentation(candidates: candidates, highlightedIndex: 1, hasNextPage: true), style: .init(layout: .vertical, fontSize: 16))

        let children = try #require(view.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(children.compactMap { $0.accessibilityLabel() } == ["1 北京 běijīng", "2 背景", "Previous Page", "Next Page"])
        #expect(children.map { $0.isAccessibilityEnabled() } == [true, true, false, true])
        #expect((view.accessibilitySelectedChildren() as? [NSAccessibilityElement])?.first === children[1])
        _ = children[0].accessibilityPerformPress()
        _ = children[3].accessibilityPerformPress()
        #expect(selected == 0)
        #expect(turned == 1)
    }
}
