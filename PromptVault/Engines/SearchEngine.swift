import Foundation

/// A parsed search string. Plain words must all match (AND); `#tag` tokens filter by tag.
nonisolated struct SearchQuery: Equatable, Sendable {
    var terms: [String]
    var tagFilters: [String]
    fileprivate let termBytes: [[UInt8]]
    fileprivate let tagBytes: [[UInt8]]

    init(_ raw: String) {
        var terms: [String] = []
        var tags: [String] = []
        for token in raw.split(whereSeparator: \.isWhitespace) {
            if token.hasPrefix("#") {
                let tag = SearchEngine.normalize(String(token.dropFirst()))
                if !tag.isEmpty { tags.append(tag) }
            } else {
                let term = SearchEngine.normalize(String(token))
                if !term.isEmpty { terms.append(term) }
            }
        }
        self.terms = terms
        self.tagFilters = tags
        self.termBytes = terms.map { Array($0.utf8) }
        self.tagBytes = tags.map { Array($0.utf8) }
    }

    var isEmpty: Bool { terms.isEmpty && tagFilters.isEmpty }

    static func == (lhs: SearchQuery, rhs: SearchQuery) -> Bool {
        lhs.terms == rhs.terms && lhs.tagFilters == rhs.tagFilters
    }
}

/// Pre-normalized searchable text for one prompt, stored as folded UTF-8 bytes so matching
/// can use `memmem`. Build once and cache.
nonisolated struct SearchDocument: Sendable {
    fileprivate let title: [UInt8]
    fileprivate let summary: [UInt8]
    fileprivate let content: [UInt8]
    fileprivate let tags: [[UInt8]]
    fileprivate let folder: [UInt8]

    init(title: String, summary: String, content: String, tags: [String], folder: String) {
        self.title = Array(SearchEngine.normalize(title).utf8)
        self.summary = Array(SearchEngine.normalize(summary).utf8)
        self.content = Array(SearchEngine.normalize(content).utf8)
        self.tags = tags.map { Array(SearchEngine.normalize($0).utf8) }
        self.folder = Array(SearchEngine.normalize(folder).utf8)
    }
}

nonisolated enum SearchEngine {
    /// Case-, diacritic-, and width-insensitive normalization.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Relevance score, or `nil` when the document doesn't match every term and tag filter.
    static func score(_ document: SearchDocument, query: SearchQuery) -> Double? {
        for tag in query.tagBytes where !document.tags.contains(where: { $0.starts(with: tag) }) {
            return nil
        }
        var total = query.tagBytes.isEmpty ? 0.0 : 1.0
        for term in query.termBytes {
            guard let termScore = score(term: term, in: document) else { return nil }
            total += termScore
        }
        return total
    }

    private static func score(term: [UInt8], in document: SearchDocument) -> Double? {
        var best = 0.0
        let title = document.title
        if title == term {
            best = 100
        } else if title.starts(with: term) {
            best = 60
        } else if containsWordPrefix(title, term) {
            best = 40
        } else if find(term, in: title) != nil {
            best = 25
        }

        for tag in document.tags {
            if tag == term { best = max(best, 30) } else if tag.starts(with: term) { best = max(best, 20) }
        }

        if best < 12 {
            if containsWordPrefix(document.summary, term) {
                best = max(best, 12)
            } else if find(term, in: document.summary) != nil {
                best = max(best, 9)
            }
        }
        if best < 10, find(term, in: document.folder) != nil { best = max(best, 10) }
        if best < 4, find(term, in: document.content) != nil { best = max(best, 4) }
        if best == 0, term.count >= 2, isSubsequence(term, of: title) { best = 3 }

        return best > 0 ? best : nil
    }

    // MARK: - Byte-level primitives

    /// Offset of the first occurrence of `needle` in `haystack` at or after `start`.
    static func find(_ needle: [UInt8], in haystack: [UInt8], from start: Int = 0) -> Int? {
        guard !needle.isEmpty, start >= 0, haystack.count - start >= needle.count else { return nil }
        return haystack.withUnsafeBytes { hay -> Int? in
            needle.withUnsafeBytes { pin -> Int? in
                guard let hayBase = hay.baseAddress, let pinBase = pin.baseAddress,
                      let hit = memmem(hayBase + start, hay.count - start, pinBase, pin.count) else { return nil }
                return hayBase.distance(to: UnsafeRawPointer(hit))
            }
        }
    }

    /// True when `needle` occurs at the start of a word in `haystack`.
    static func containsWordPrefix(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        var start = 0
        while let offset = find(needle, in: haystack, from: start) {
            if offset == 0 || !isWordByte(haystack[offset - 1]) { return true }
            start = offset + 1
        }
        return false
    }

    /// ASCII letters/digits, plus any non-ASCII byte (part of a multi-byte letter).
    private static func isWordByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), 0x80...0xFF:
            return true
        default:
            return false
        }
    }

    /// Fuzzy match: every byte of `needle` appears in `haystack` in order.
    static func isSubsequence(_ needle: [UInt8], of haystack: [UInt8]) -> Bool {
        var index = needle.startIndex
        guard index < needle.endIndex else { return true }
        for byte in haystack where byte == needle[index] {
            index += 1
            if index == needle.endIndex { return true }
        }
        return false
    }

    // MARK: - String conveniences

    static func containsWordPrefix(_ haystack: String, _ needle: String) -> Bool {
        containsWordPrefix(Array(normalize(haystack).utf8), Array(normalize(needle).utf8))
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        isSubsequence(Array(normalize(needle).utf8), of: Array(normalize(haystack).utf8))
    }
}
