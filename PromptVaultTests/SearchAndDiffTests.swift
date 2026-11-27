import Foundation
import Testing
@testable import PromptVault

struct SearchEngineTests {
    private func doc(_ title: String, summary: String = "", content: String = "", tags: [String] = [], folder: String = "") -> SearchDocument {
        SearchDocument(title: title, summary: summary, content: content, tags: tags, folder: folder)
    }

    @Test func parsesTermsAndTagFilters() {
        let query = SearchQuery("  Code  #Review #swift  bugs ")
        #expect(query.terms == ["code", "bugs"])
        #expect(query.tagFilters == ["review", "swift"])
    }

    @Test func requiresEveryTerm() {
        let document = doc("Code Review", content: "find bugs")
        #expect(SearchEngine.score(document, query: SearchQuery("code bugs")) != nil)
        #expect(SearchEngine.score(document, query: SearchQuery("code missing")) == nil)
    }

    @Test func ranksTitleAboveContent() throws {
        let titleMatch = try #require(SearchEngine.score(doc("Email writer"), query: SearchQuery("email")))
        let contentMatch = try #require(SearchEngine.score(doc("Other", content: "write an email"), query: SearchQuery("email")))
        #expect(titleMatch > contentMatch)
    }

    @Test func isCaseAndDiacriticInsensitive() {
        #expect(SearchEngine.score(doc("Résumé Builder"), query: SearchQuery("resume")) != nil)
    }

    @Test func tagFiltersUsePrefixMatching() {
        let document = doc("Anything", tags: ["marketing", "email"])
        #expect(SearchEngine.score(document, query: SearchQuery("#mark")) != nil)
        #expect(SearchEngine.score(document, query: SearchQuery("#sales")) == nil)
    }

    @Test func fuzzySubsequenceMatchesTitles() {
        #expect(SearchEngine.score(doc("Conventional Commit Message"), query: SearchQuery("cncm")) != nil)
        #expect(SearchEngine.isSubsequence("abc", of: "a_b_c"))
        #expect(!SearchEngine.isSubsequence("acb", of: "abc"))
    }

    @Test func searchesTenThousandDocumentsQuickly() {
        let filler = String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 20)
        let documents = (0..<10_000).map { index in
            doc("Prompt \(index)", summary: "Summary \(index)", content: filler + " unique\(index)", tags: ["tag\(index % 50)"])
        }
        let query = SearchQuery("unique9999")
        let clock = ContinuousClock()
        var matches = 0
        let elapsed = clock.measure {
            for document in documents where SearchEngine.score(document, query: query) != nil { matches += 1 }
        }
        #expect(matches == 1)
        // Generous bound (debug build, shared CI machines); typically a few milliseconds.
        #expect(elapsed < .milliseconds(500), "Search took \(elapsed)")
    }
}

struct DiffEngineTests {
    @Test func identicalTextIsOneEqualSegment() {
        #expect(DiffEngine.diff(old: "same text", new: "same text") == [.init(kind: .equal, text: "same text")])
    }

    @Test func detectsWordInsertionsAndRemovals() {
        let segments = DiffEngine.diff(old: "The quick brown fox", new: "The slow brown fox jumps")
        let removed = segments.filter { $0.kind == .removed }.map(\.text).joined()
        let inserted = segments.filter { $0.kind == .inserted }.map(\.text).joined()
        #expect(removed.contains("quick"))
        #expect(inserted.contains("slow"))
        #expect(inserted.contains("jumps"))
        let stats = DiffEngine.stats(for: segments)
        #expect(stats.removedWords == 1)
        #expect(stats.insertedWords == 2)
    }

    @Test func reconstructsBothSides() {
        let old = "Line one\nLine two, with punctuation!\n{{var}}"
        let new = "Line one\nLine 2 — with more punctuation?\n{{var}} end"
        let segments = DiffEngine.diff(old: old, new: new)
        let rebuiltOld = segments.filter { $0.kind != .inserted }.map(\.text).joined()
        let rebuiltNew = segments.filter { $0.kind != .removed }.map(\.text).joined()
        #expect(rebuiltOld == old)
        #expect(rebuiltNew == new)
    }

    @Test func tokenizerSplitsWordsSpacesAndPunctuation() {
        #expect(DiffEngine.tokenize("Hi, there  you!") == ["Hi", ",", " ", "there", "  ", "you", "!"])
    }
}

struct PromptArchiveCodecTests {
    @Test func decodesBareArrayWithAliasesAndDefaults() throws {
        let json = """
        [
          {"title": "One", "content": "Hello {{name}}"},
          {"name": "Two", "prompt": "Second", "summary": "desc", "tags": ["a"], "folder": "Work / Email"},
          {"text": "Untitled first line\\nmore"}
        ]
        """
        let archive = try PromptArchiveCodec.decode(Data(json.utf8))
        #expect(archive.prompts.count == 3)
        #expect(archive.prompts[1].title == "Two")
        #expect(archive.prompts[1].content == "Second")
        #expect(archive.prompts[1].description == "desc")
        #expect(archive.prompts[1].folder == "Work / Email")
        #expect(archive.prompts[2].title == "Untitled first line")
        #expect(archive.prompts[0].isFavorite == false)
    }

    @Test func decodesSinglePromptObject() throws {
        let archive = try PromptArchiveCodec.decode(Data(#"{"title":"Solo","content":"x","createdAt":"2025-01-02"}"#.utf8))
        #expect(archive.prompts.map(\.title) == ["Solo"])
        #expect(archive.prompts[0].createdAt != nil)
    }

    @Test func rejectsUnrelatedJSONAndNewerVersions() {
        #expect(throws: PromptArchiveError.unrecognizedFormat) {
            try PromptArchiveCodec.decode(Data(#"{"hello":"world"}"#.utf8))
        }
        #expect(throws: PromptArchiveError.unrecognizedFormat) {
            try PromptArchiveCodec.decode(Data("not json".utf8))
        }
        #expect(throws: PromptArchiveError.unsupportedVersion(99)) {
            try PromptArchiveCodec.decode(Data(#"{"format":"promptvault.archive","version":99,"prompts":[]}"#.utf8))
        }
    }

    @Test func encodesAndDecodesRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let record = PromptRecord(
            id: UUID(), title: "T", content: "C {{v}}", description: "D", folderId: nil, folder: nil,
            tags: ["x"], isFavorite: true, isTemplate: true,
            variables: [PromptVariable(name: "v", defaultValue: "d", description: "desc", isRequired: false)],
            createdAt: date, updatedAt: date, usageCount: 3, lastUsedAt: date,
            versions: [VersionRecord(id: UUID(), title: "old", content: "old", description: "", variables: [], savedAt: date)]
        )
        let archive = PromptArchive(exportedAt: date, generator: "test", folders: [], prompts: [record])
        let data = try PromptArchiveCodec.encode(archive)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"description\" : \"D\""))
        #expect(text.contains("\"format\" : \"promptvault.archive\""))
        let decoded = try PromptArchiveCodec.decode(data)
        #expect(decoded.prompts == [record])
    }
}
