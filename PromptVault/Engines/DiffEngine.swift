import Foundation

/// Word-level text diff used by the version history comparison view.
nonisolated enum DiffEngine {
    enum Kind: Sendable { case equal, inserted, removed }

    struct Segment: Hashable, Sendable {
        var kind: Kind
        var text: String
    }

    struct Stats: Equatable, Sendable {
        var insertedWords: Int
        var removedWords: Int
        var isEmpty: Bool { insertedWords == 0 && removedWords == 0 }
    }

    /// Above this many tokens per side the diff falls back to whole lines to stay fast.
    static let tokenLimit = 12_000

    static func diff(old: String, new: String) -> [Segment] {
        if old == new { return old.isEmpty ? [] : [Segment(kind: .equal, text: old)] }
        var oldTokens = tokenize(old)
        var newTokens = tokenize(new)
        if oldTokens.count > tokenLimit || newTokens.count > tokenLimit {
            oldTokens = lines(old)
            newTokens = lines(new)
        }
        return merge(old: oldTokens, new: newTokens)
    }

    static func stats(for segments: [Segment]) -> Stats {
        var stats = Stats(insertedWords: 0, removedWords: 0)
        for segment in segments {
            let words = segment.text.split(whereSeparator: { $0.isWhitespace }).count
            switch segment.kind {
            case .inserted: stats.insertedWords += max(words, segment.text.isEmpty ? 0 : 1)
            case .removed: stats.removedWords += max(words, segment.text.isEmpty ? 0 : 1)
            case .equal: break
            }
        }
        return stats
    }

    /// Splits text into words, runs of whitespace, and individual punctuation characters.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentClass = 0 // 0 none, 1 word, 2 whitespace

        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
            currentClass = 0
        }

        for character in text {
            let characterClass: Int
            if character.isLetter || character.isNumber || character == "_" {
                characterClass = 1
            } else if character.isWhitespace {
                characterClass = 2
            } else {
                characterClass = 3
            }
            if characterClass == 3 {
                flush()
                tokens.append(String(character))
                continue
            }
            if characterClass != currentClass { flush() }
            current.append(character)
            currentClass = characterClass
        }
        flush()
        return tokens
    }

    private static func lines(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character.isNewline {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func merge(old: [String], new: [String]) -> [Segment] {
        let difference = new.difference(from: old)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var segments: [Segment] = []
        func append(_ kind: Kind, _ text: String) {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].text += text
            } else {
                segments.append(Segment(kind: kind, text: text))
            }
        }

        var i = 0
        var j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) {
                append(.removed, old[i])
                i += 1
            } else if j < new.count, inserted.contains(j) {
                append(.inserted, new[j])
                j += 1
            } else if i < old.count, j < new.count {
                append(.equal, new[j])
                i += 1
                j += 1
            } else if i < old.count {
                append(.removed, old[i])
                i += 1
            } else {
                append(.inserted, new[j])
                j += 1
            }
        }
        return segments
    }
}
