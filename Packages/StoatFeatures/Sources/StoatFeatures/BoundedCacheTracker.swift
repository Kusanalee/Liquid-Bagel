// LRU byte-tracking helper for @ObservationIgnored use inside @Observable classes.
// Uses a monotone UInt64 clock (same technique as ImageMemoryCache actor) to track
// access order without requiring an ordered collection.
struct BoundedCacheTracker<Key: Hashable & Sendable>: Sendable {
    private struct Entry: Sendable { var byteCount: Int; var lastAccess: UInt64 }
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    let maxBytes: Int
    private(set) var totalBytes: Int = 0

    init(maxBytes: Int) { self.maxBytes = max(1, maxBytes) }

    var count: Int { entries.count }

    // Insert or overwrite a key. Returns the set of keys that must be removed from
    // the backing dictionary to bring total bytes under the cap.
    mutating func insert(key: Key, byteCount: Int, protecting protected: Set<Key> = []) -> Set<Key> {
        if let existing = entries[key] { totalBytes -= existing.byteCount }
        clock &+= 1
        entries[key] = Entry(byteCount: byteCount, lastAccess: clock)
        totalBytes += byteCount
        return evictIfNeeded(protecting: protected)
    }

    // Record a read hit so the entry's clock advances (making it less evictable).
    mutating func recordAccess(for key: Key) {
        guard entries[key] != nil else { return }
        clock &+= 1
        entries[key]!.lastAccess = clock
    }

    mutating func remove(key: Key) {
        guard let e = entries.removeValue(forKey: key) else { return }
        totalBytes -= e.byteCount
    }

    mutating func removeAll() {
        entries.removeAll()
        totalBytes = 0
        clock = 0
    }

    private mutating func evictIfNeeded(protecting protected: Set<Key>) -> Set<Key> {
        var evicted = Set<Key>()
        while totalBytes > maxBytes {
            guard let oldest = entries
                .filter({ !protected.contains($0.key) })
                .min(by: { $0.value.lastAccess < $1.value.lastAccess })
            else { break }
            entries.removeValue(forKey: oldest.key)
            totalBytes -= oldest.value.byteCount
            evicted.insert(oldest.key)
        }
        return evicted
    }
}
