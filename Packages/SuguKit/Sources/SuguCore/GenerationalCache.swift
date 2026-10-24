/// A cache of at most `limit` entries that, when full, forgets only those
/// not used since it last filled, rather than everything at once. It keeps
/// two generations and drops the older when the newer fills; an entry used
/// from the older moves to the newer. Unlike a least-recently-used list,
/// it adds nothing per entry.
public struct GenerationalCache<Key: Hashable, Value> {
    private var recent: [Key: Value] = [:]
    private var older: [Key: Value] = [:]
    private let generation: Int

    public init(limit: Int) {
        generation = max(1, limit / 2)
    }

    public var count: Int { recent.count + older.count }

    public mutating func value(for key: Key) -> Value? {
        if let value = recent[key] { return value }
        guard let value = older.removeValue(forKey: key) else { return nil }
        insert(value, for: key)
        return value
    }

    public mutating func insert(_ value: Value, for key: Key) {
        if recent.count >= generation {
            older = recent
            recent = [:]
        }
        recent[key] = value
    }

    public mutating func removeAll() {
        recent = [:]
        older = [:]
    }
}
