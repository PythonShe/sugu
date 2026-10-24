import Testing
@testable import SuguCore

struct GenerationalCacheTests {
    @Test func keepsWhatWasUsedSinceItLastFilled() {
        var cache = GenerationalCache<Int, String>(limit: 4)
        cache.insert("a", for: 1)
        cache.insert("b", for: 2)
        cache.insert("c", for: 3)
        #expect(cache.value(for: 1) == "a")
        cache.insert("d", for: 4)
        cache.insert("e", for: 5)
        #expect(cache.value(for: 1) == "a")
        #expect(cache.value(for: 2) == nil)
        #expect(cache.count <= 4)
    }

    @Test func neverHoldsMoreThanItsLimit() {
        var cache = GenerationalCache<Int, Int>(limit: 10)
        for key in 0..<1_000 {
            cache.insert(key, for: key)
            _ = cache.value(for: key / 2)
            #expect(cache.count <= 10)
        }
    }
}
