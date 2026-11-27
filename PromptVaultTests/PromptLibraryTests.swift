import Foundation
import SwiftData
import Testing
@testable import PromptVault

@MainActor
struct PromptLibraryTests {
    let container: ModelContainer
    let library: PromptLibrary

    init() throws {
        container = try Persistence.makeContainer(storeURL: nil)
        library = PromptLibrary(context: ModelContext(container))
    }

    @Test func createsAndQueriesPrompts() {
        let folder = library.createFolder(named: "Work")
        library.createPrompt(title: "B prompt", content: "x", folder: folder)
        library.createPrompt(title: "A prompt", content: "y", isFavorite: true)
        #expect(library.prompts.count == 2)
        #expect(library.prompts(in: .all, sortedBy: .alphabetical).map(\.title) == ["A prompt", "B prompt"])
        #expect(library.prompts(in: .favorites).map(\.title) == ["A prompt"])
        #expect(library.prompts(in: .uncategorized).map(\.title) == ["A prompt"])
        #expect(library.prompts(in: .folder(folder.id)).map(\.title) == ["B prompt"])
    }

    @Test func folderScopeIncludesSubfolders() {
        let parent = library.createFolder(named: "Coding")
        let child = library.createFolder(named: "Review", parent: parent)
        library.createPrompt(title: "Nested", content: "x", folder: child)
        #expect(library.prompts(in: .folder(parent.id)).map(\.title) == ["Nested"])
        #expect(library.counts().folders[parent.id] == 1)
        #expect(child.pathString == "Coding / Review")
    }

    @Test func savingTextChangesCreatesVersions() throws {
        let prompt = library.createPrompt(title: "Original", content: "v1")
        var draft = PromptDraft(prompt)
        draft.content = "v2"
        library.update(prompt, with: draft)
        draft.title = "Renamed"
        library.update(prompt, with: draft)
        // Saving with no changes must not add a version.
        library.update(prompt, with: draft)

        #expect(prompt.content == "v2")
        #expect(prompt.title == "Renamed")
        let versions = prompt.sortedVersions
        #expect(versions.count == 2)
        #expect(versions.map(\.content).sorted() == ["v1", "v2"])

        let oldest = try #require(versions.first { $0.content == "v1" })
        library.restore(oldest)
        #expect(prompt.content == "v1")
        #expect(prompt.title == "Original")
        #expect(prompt.sortedVersions.count == 3, "Restoring keeps the replaced state as a version")
    }

    @Test func versionHistoryIsCapped() {
        library.maxVersionsPerPrompt = 3
        let prompt = library.createPrompt(title: "T", content: "0")
        for index in 1...6 {
            var draft = PromptDraft(prompt)
            draft.content = "\(index)"
            library.update(prompt, with: draft)
        }
        #expect(prompt.sortedVersions.count == 3)
        #expect(prompt.sortedVersions.first?.content == "5")
    }

    @Test func variableMetadataIsPrunedToContent() {
        let prompt = library.createPrompt(
            title: "T", content: "{{a}} {{b}}",
            variables: [PromptVariable(name: "a", defaultValue: "x"), PromptVariable(name: "zzz")]
        )
        #expect(prompt.storedVariables.map(\.name) == ["a", "b"])
        var draft = PromptDraft(prompt)
        draft.content = "{{b}} only"
        library.update(prompt, with: draft)
        #expect(prompt.variables.map(\.name) == ["b"])
    }

    @Test func duplicateAndTemplates() {
        let template = library.createPrompt(title: "Email", content: "Hi {{name}}", tags: ["x"], isTemplate: true,
                                            variables: [PromptVariable(name: "name", defaultValue: "there")])
        let copy = library.duplicate(template)
        #expect(copy.title == "Email Copy")
        #expect(copy.isTemplate)
        #expect(copy.id != template.id)
        let fromTemplate = library.createPrompt(fromTemplate: template)
        #expect(!fromTemplate.isTemplate)
        #expect(fromTemplate.variables.first?.defaultValue == "there")
        #expect(library.prompts(in: .templates).count == 2)
    }

    @Test func deletingFolderUncategorizesPrompts() {
        let parent = library.createFolder(named: "Parent")
        let child = library.createFolder(named: "Child", parent: parent)
        let prompt = library.createPrompt(title: "Inside", content: "x", folder: child)
        library.delete(parent)
        #expect(library.folders.isEmpty)
        #expect(prompt.folder == nil)
        #expect(library.prompts.count == 1)
        #expect(library.prompts(in: .uncategorized).count == 1)
    }

    @Test func movingFolderPreventsCycles() {
        let a = library.createFolder(named: "A")
        let b = library.createFolder(named: "B", parent: a)
        #expect(library.move(a, to: b) == false)
        #expect(library.move(b, to: nil))
        #expect(b.parent == nil)
    }

    @Test func folderNamesAreUniqueAmongSiblings() {
        library.createFolder(named: "Ideas")
        let second = library.createFolder(named: "ideas")
        #expect(second.name == "ideas 2")
    }

    @Test func tagNormalizationRenameAndDelete() {
        let prompt = library.createPrompt(title: "T", content: "x", tags: ["#Swift", "swift", " machine learning ", ""])
        #expect(prompt.tags == ["Swift", "machine-learning"])
        library.renameTag("swift", to: "ios")
        #expect(prompt.tags == ["ios", "machine-learning"])
        library.deleteTag("machine-learning")
        #expect(prompt.tags == ["ios"])
        #expect(library.allTags.map(\.name) == ["ios"])
    }

    @Test func recordUseUpdatesStatsAndSmartSort() {
        let a = library.createPrompt(title: "A", content: "x")
        let b = library.createPrompt(title: "B", content: "y")
        library.recordUse(of: b, variableValues: ["v": "1"])
        library.recordUse(of: b)
        library.recordUse(of: a)
        #expect(b.usageCount == 2)
        #expect(b.lastVariableValues == ["v": "1"])
        #expect(library.prompts(in: .all, sortedBy: .smart).first?.title == "B")
        #expect(library.prompts(in: .all, sortedBy: .mostUsed).map(\.title) == ["B", "A"])
        #expect(library.prompts(in: .recent).first?.title == "A", "Recently Used always sorts by last use")
        #expect(library.totalUses == 3)
    }

    @Test func searchFindsByTitleTagsAndContent() {
        library.createPrompt(title: "Code Review", content: "find bugs", tags: ["quality"])
        library.createPrompt(title: "Email", content: "write a code of conduct email")
        library.createPrompt(title: "Other", content: "nothing")
        #expect(library.prompts(in: .all, matching: "code").map(\.title) == ["Code Review", "Email"])
        #expect(library.prompts(in: .all, matching: "#qual").map(\.title) == ["Code Review"])
        #expect(library.prompts(in: .all, matching: "conduct email").map(\.title) == ["Email"])
    }

    @Test func searchCacheRefreshesAfterEdit() {
        let prompt = library.createPrompt(title: "Alpha", content: "x")
        #expect(library.prompts(in: .all, matching: "beta").isEmpty)
        var draft = PromptDraft(prompt)
        draft.title = "Beta"
        library.update(prompt, with: draft)
        #expect(library.prompts(in: .all, matching: "beta").count == 1)
    }

    @Test func exportImportRoundTripIntoEmptyLibrary() throws {
        let folder = library.createFolder(named: "Coding")
        let child = library.createFolder(named: "Review", parent: folder)
        let prompt = library.createPrompt(title: "P", content: "{{x}}", tags: ["t"], folder: child, isFavorite: true,
                                          variables: [PromptVariable(name: "x", defaultValue: "d")])
        var draft = PromptDraft(prompt)
        draft.content = "{{x}} v2"
        library.update(prompt, with: draft)
        library.recordUse(of: prompt)

        let data = try PromptArchiveCodec.encode(library.makeArchive())
        let other = PromptLibrary(context: ModelContext(try Persistence.makeContainer(storeURL: nil)))
        let summary = other.importArchive(try PromptArchiveCodec.decode(data), mode: .merge)

        #expect(summary.promptsAdded == 1)
        #expect(summary.foldersAdded == 2)
        let imported = try #require(other.prompts.first)
        #expect(imported.id == prompt.id)
        #expect(imported.content == "{{x}} v2")
        #expect(imported.folder?.pathString == "Coding / Review")
        #expect(imported.isFavorite)
        #expect(imported.usageCount == 1)
        #expect(imported.variables.first?.defaultValue == "d")
        #expect(imported.sortedVersions.map(\.content) == ["{{x}}"])
    }

    @Test func mergeImportSkipsOlderAndUpdatesNewer() throws {
        let prompt = library.createPrompt(title: "P", content: "local")
        var archive = library.makeArchive()

        // Same updatedAt -> skipped.
        var summary = library.importArchive(archive, mode: .merge)
        #expect(summary.promptsSkipped == 1)
        #expect(library.prompts.count == 1)

        // Newer imported copy -> updated, and the local text is kept as a version.
        archive.prompts[0].content = "remote"
        archive.prompts[0].updatedAt = prompt.updatedAt.addingTimeInterval(60)
        summary = library.importArchive(archive, mode: .merge)
        #expect(summary.promptsUpdated == 1)
        #expect(prompt.content == "remote")
        #expect(prompt.sortedVersions.first?.content == "local")
    }

    @Test func importResolvesFolderPathsAndSkipsIdenticalHandWrittenDuplicates() throws {
        let json = #"[{"title":"Hand","content":"written","folder":"Work / Email"}]"#
        let archive = try PromptArchiveCodec.decode(Data(json.utf8))
        let first = library.importArchive(archive, mode: .merge)
        let second = library.importArchive(archive, mode: .merge)
        #expect(first.promptsAdded == 1)
        #expect(first.foldersAdded == 2)
        #expect(second.promptsAdded == 0)
        #expect(second.promptsSkipped == 1)
        #expect(library.folders.count == 2)
        #expect(library.prompts.first?.folder?.pathString == "Work / Email")
    }

    @Test func replaceImportRestoresExactly() throws {
        library.createPrompt(title: "Keep", content: "a")
        let backup = library.makeArchive()
        library.createPrompt(title: "Extra", content: "b")
        library.createFolder(named: "Temp")
        let summary = library.importArchive(backup, mode: .replace)
        #expect(summary.promptsAdded == 1)
        #expect(library.prompts.map(\.title) == ["Keep"])
        #expect(library.folders.isEmpty)
    }

    @Test func seedDataIsValid() {
        library.seedSampleContent()
        #expect(library.prompts.count >= 8)
        #expect(library.folders.count == 4)
        #expect(library.prompts.contains { $0.isTemplate })
        #expect(library.prompts.contains { TemplateEngine.usesBuiltIns($0.content) })
        for prompt in library.prompts {
            #expect(!prompt.title.isEmpty)
            // Every stored variable corresponds to a placeholder in the content.
            #expect(prompt.storedVariables.map(\.name) == TemplateEngine.variableNames(in: prompt.content))
        }
    }
}

/// Exercises a real on-disk SQLite store, which can surface schema problems in-memory stores hide.
@MainActor
struct PersistenceTests {
    @Test func dataSurvivesReopeningTheStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PromptVaultTests-\(UUID().uuidString)")
        let paths = AppPaths(dataDirectory: directory)
        try paths.createDirectories()
        defer { try? FileManager.default.removeItem(at: directory) }

        let promptID: UUID
        do {
            let library = PromptLibrary(context: ModelContext(try Persistence.makeContainer(storeURL: paths.storeURL)))
            let parent = library.createFolder(named: "Parent", symbolName: "star")
            let child = library.createFolder(named: "Child", parent: parent)
            let prompt = library.createPrompt(title: "Persisted", content: "{{a}} text", tags: ["one", "two"], folder: child,
                                              variables: [PromptVariable(name: "a", defaultValue: "x", description: "d", isRequired: false)])
            var draft = PromptDraft(prompt)
            draft.content = "{{a}} edited"
            library.update(prompt, with: draft)
            library.recordUse(of: prompt, variableValues: ["a": "value"])
            promptID = prompt.id
        }

        let reopened = PromptLibrary(context: ModelContext(try Persistence.makeContainer(storeURL: paths.storeURL)))
        let prompt = try #require(reopened.prompt(id: promptID))
        #expect(prompt.content == "{{a}} edited")
        #expect(prompt.tags == ["one", "two"])
        #expect(prompt.folder?.pathString == "Parent / Child")
        #expect(prompt.folder?.parent?.symbolName == "star")
        #expect(prompt.variables == [PromptVariable(name: "a", defaultValue: "x", description: "d", isRequired: false)])
        #expect(prompt.lastVariableValues == ["a": "value"])
        #expect(prompt.usageCount == 1)
        #expect(prompt.sortedVersions.map(\.content) == ["{{a}} text"])
    }

    @Test func quarantineMovesStoreFilesAside() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PromptVaultTests-\(UUID().uuidString)")
        let paths = AppPaths(dataDirectory: directory)
        try paths.createDirectories()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("garbage".utf8).write(to: paths.storeURL)

        let moved = try Persistence.quarantineStore(at: paths.storeURL)
        #expect(!FileManager.default.fileExists(atPath: paths.storeURL.path))
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test func dataDirectoryOverride() {
        let paths = AppPaths.resolve(environment: ["PROMPTVAULT_DATA_DIR": "/tmp/pv-test"], defaults: .standard)
        #expect(paths.storeURL.path == "/tmp/pv-test/PromptVault.store")
    }
}
