import Testing
import SuguCore
@testable import SuguInput

struct CandidateListTests {
    func list(_ count: Int, pageSize: Int = 3) -> CandidateList {
        var list = CandidateList()
        list.candidates = (0..<count).map { Candidate(text: "\($0)", source: .engine(index: $0)) }
        list.pageSize = pageSize
        return list
    }

    @Test func highlightMovesWithinTheList() {
        var list = list(5)
        #expect(list.index(movingHighlightBy: 1) == 0)
        #expect(list.index(movingHighlightBy: -1) == 0)
        list.setHighlight(4)
        #expect(list.page == 1)
        #expect(list.index(movingHighlightBy: 1) == 4)
        #expect(list.index(movingHighlightBy: -2) == 2)
    }

    @Test func pagesTurnWithinTheList() {
        var list = list(7)
        #expect(list.page(turnedBy: -1) == nil)
        #expect(list.page(turnedBy: 1) == 1)
        #expect(list.page(turnedBy: 5) == 2)
        list.page = 2
        #expect(list.page(turnedBy: 1) == nil)
    }

    @Test func rowsMapToTheCurrentPage() {
        var list = list(7)
        list.setHighlight(4)
        #expect(list.index(onPage: 0) == 3)
        #expect(list.index(onPage: 3) == nil)
        list.page = 2
        #expect(list.index(onPage: 0) == 6)
        #expect(list.index(onPage: 1) == nil)
    }

    @Test func currentPageShowsItsRowsAndHighlight() {
        var list = list(7)
        list.setHighlight(4)
        let page = list.currentPage
        #expect(page.rows.map(\.text) == ["3", "4", "5"])
        #expect(page.highlight == 1)
        #expect(page.hasPrevious && page.hasNext)
        list.page = 2
        #expect(list.currentPage.rows.map(\.text) == ["6"])
        #expect(list.currentPage.highlight == nil)
        #expect(!list.currentPage.hasNext)
    }

    @Test func clearingEmptiesEverything() {
        var list = list(4)
        list.setHighlight(3)
        list.clear()
        #expect(list.isEmpty && list.highlight == nil && list.page == 0)
        #expect(list.index(movingHighlightBy: 1) == nil)
        #expect(list.currentPage.rows.isEmpty)
    }
}
