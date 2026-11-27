import AppKit
import Carbon.HIToolbox
import SwiftData
import Testing
@testable import PromptVault

/// Creates an app model backed by an in-memory store and a throwaway defaults suite.
@MainActor
func makeTestAppModel(seed: Bool = true) throws -> (app: AppModel, cleanup: () -> Void) {
    let paths = AppPaths(dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("PromptVaultTests-\(UUID().uuidString)"))
    let app = AppModel(paths: paths, container: try Persistence.makeContainer(storeURL: nil), settings: AppSettings(defaults: InMemorySettingsStore()))
    if seed { app.library.seedSampleContent() }
    return (app, {
        try? FileManager.default.removeItem(at: paths.dataDirectory)
    })
}

@MainActor
private func key(_ keyCode: Int, _ characters: String = "", _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: UInt16(keyCode)
    )!
}

/// Exercises the popover keyboard router without touching the clipboard.
@MainActor
struct PopoverKeyRoutingTests {
    @Test func arrowsAndControlKeysMoveSelection() throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        let results = app.popover.results
        #expect(app.popover.effectiveSelection(in: results) == results[0].id)

        #expect(app.handlePopoverKeyDown(key(kVK_DownArrow)))
        #expect(app.popover.selectedID == results[1].id)
        #expect(app.handlePopoverKeyDown(key(kVK_ANSI_N, "n", .control)))
        #expect(app.popover.selectedID == results[2].id)
        #expect(app.handlePopoverKeyDown(key(kVK_UpArrow)))
        #expect(app.popover.selectedID == results[1].id)
        // Can't move past the top.
        for _ in 0..<5 { _ = app.handlePopoverKeyDown(key(kVK_UpArrow)) }
        #expect(app.popover.selectedID == results[0].id)
    }

    @Test func tabPreviewsAndEscapeReturnsWithSelectionKept() throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        _ = app.handlePopoverKeyDown(key(kVK_DownArrow))
        let selected = try #require(app.popover.selectedID)

        #expect(app.handlePopoverKeyDown(key(kVK_Tab, "\t")))
        #expect(app.popover.route == .preview(selected))
        #expect(app.handlePopoverKeyDown(key(kVK_Escape, "\u{1b}")))
        #expect(app.popover.route == .list)
        #expect(app.popover.selectedID == selected)
    }

    @Test func editAndNewShortcutsOpenTheEditor() throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        let selected = try #require(app.popover.selectedPrompt)

        #expect(app.handlePopoverKeyDown(key(kVK_ANSI_E, "e", .command)))
        #expect(app.popover.route == .edit(selected.id))
        let cancelRequests = app.popover.editorCancelRequest
        #expect(app.handlePopoverKeyDown(key(kVK_Escape, "\u{1b}")))
        #expect(app.popover.editorCancelRequest == cancelRequests + 1, "Esc asks the editor to cancel (it confirms if dirty)")
        let saveRequests = app.popover.editorSaveRequest
        #expect(app.handlePopoverKeyDown(key(kVK_ANSI_S, "s", .command)))
        #expect(app.popover.editorSaveRequest == saveRequests + 1)
        // Plain typing in the editor is never intercepted.
        #expect(!app.handlePopoverKeyDown(key(kVK_ANSI_A, "a")))
        #expect(!app.handlePopoverKeyDown(key(kVK_Return, "\r")))

        app.popover.route = .list
        #expect(app.handlePopoverKeyDown(key(kVK_ANSI_N, "n", .command)))
        #expect(app.popover.route == .edit(nil))
    }

    @Test func returnOnPromptWithVariablesOpensForm() throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        app.popover.searchText = "Expert Project Kickoff"
        let target = try #require(app.popover.selectedPrompt)
        #expect(target.hasUserVariables)

        #expect(app.handlePopoverKeyDown(key(kVK_Return, "\r")))
        #expect(app.popover.route == .fill(target.id))
        let submits = app.popover.fillSubmitRequest
        #expect(app.handlePopoverKeyDown(key(kVK_Return, "\r", .command)))
        #expect(app.popover.fillSubmitRequest == submits + 1)
        #expect(!app.handlePopoverKeyDown(key(kVK_Return, "\r")), "Plain Return belongs to the form fields")
        #expect(app.handlePopoverKeyDown(key(kVK_Escape, "\u{1b}")))
        #expect(app.popover.route == .list)

        // ⌘1 uses the first result the same way.
        #expect(app.handlePopoverKeyDown(key(kVK_ANSI_1, "1", .command)))
        #expect(app.popover.route == .fill(target.id))
    }

    @Test func scopeCyclingFavoriteAndDelete() throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        #expect(app.handlePopoverKeyDown(key(kVK_ANSI_RightBracket, "]", .command)))
        #expect(app.popover.scope == .favorites)
        #expect(app.handlePopoverKeyDown(key(kVK_ANSI_LeftBracket, "[", .command)))
        #expect(app.popover.scope == .all)

        let prompt = try #require(app.popover.selectedPrompt)
        let wasFavorite = prompt.isFavorite
        #expect(app.handlePopoverKeyDown(key(kVK_ANSI_F, "f", [.command, .shift])))
        #expect(prompt.isFavorite != wasFavorite)

        let count = app.library.prompts.count
        #expect(app.handlePopoverKeyDown(key(kVK_Delete, "\u{7f}", .command)))
        #expect(app.popover.pendingDeletion?.id == prompt.id)
        #expect(app.handlePopoverKeyDown(key(kVK_Escape, "\u{1b}")))
        #expect(app.popover.pendingDeletion == nil)
        #expect(app.library.prompts.count == count, "Escape cancels deletion")

        _ = app.handlePopoverKeyDown(key(kVK_Delete, "\u{7f}", .command))
        #expect(app.handlePopoverKeyDown(key(kVK_Return, "\r")))
        #expect(app.library.prompts.count == count - 1)
        #expect(app.library.prompt(id: prompt.id) == nil)
    }

    @Test func escapeClearsSearchThenCloses() throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        var closed = false
        app.actions.closePopover = { closed = true }
        app.popover.searchText = "code"
        #expect(app.handlePopoverKeyDown(key(kVK_Escape, "\u{1b}")))
        #expect(app.popover.searchText.isEmpty)
        #expect(!closed)
        #expect(app.handlePopoverKeyDown(key(kVK_Escape, "\u{1b}")))
        #expect(closed)
    }

    @Test func typingIsNotIntercepted() throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        for (code, character) in [(kVK_ANSI_A, "a"), (kVK_Space, " "), (kVK_LeftArrow, ""), (kVK_ANSI_C, "c")] {
            #expect(!app.handlePopoverKeyDown(key(code, character)))
        }
        #expect(!app.handlePopoverKeyDown(key(kVK_ANSI_A, "a", .command)), "⌘A selects text in the search field")
    }

    @Test func prepareForDisplayResetsTransientState() throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        let folder = app.library.createFolder(named: "Temp")
        app.popover.scope = .folder(folder.id)
        app.popover.searchText = "x"
        app.popover.route = .edit(nil)
        app.library.delete(folder)
        app.popover.prepareForDisplay()
        #expect(app.popover.route == .list)
        #expect(app.popover.searchText.isEmpty)
        #expect(app.popover.scope == .all, "A deleted folder scope falls back to All")
    }
}

@MainActor
struct VersionCoalescingTests {
    @Test func explicitSavesAlwaysCreateVersions() throws {
        let (app, cleanup) = try makeTestAppModel(seed: false)
        defer { cleanup() }
        let library = app.library
        let prompt = library.createPrompt(title: "T", content: "v0")
        for index in 1...3 {
            var draft = PromptDraft(prompt)
            draft.content = "v\(index)"
            library.update(prompt, with: draft)
        }
        #expect(prompt.sortedVersions.count == 3)
    }

    @Test func autosavesWithinASessionShareOneVersion() throws {
        let (app, cleanup) = try makeTestAppModel(seed: false)
        defer { cleanup() }
        let library = app.library
        let prompt = library.createPrompt(title: "T", content: "original")
        for index in 1...4 {
            var draft = PromptDraft(prompt)
            draft.content = "autosave \(index)"
            library.update(prompt, with: draft, coalescing: true)
        }
        #expect(prompt.content == "autosave 4")
        #expect(prompt.sortedVersions.map(\.content) == ["original"], "Only the pre-session state is kept")

        // A later session (last capture long ago) records a new version.
        prompt.sortedVersions.first?.capturedAt = .now.addingTimeInterval(-3600)
        var draft = PromptDraft(prompt)
        draft.content = "next session"
        library.update(prompt, with: draft, coalescing: true)
        #expect(prompt.sortedVersions.count == 2)
    }

    @Test func tagEditsDontHideTextHistory() throws {
        let (app, cleanup) = try makeTestAppModel(seed: false)
        defer { cleanup() }
        let library = app.library
        let prompt = library.createPrompt(title: "T", content: "before")
        library.setTags(["new"], for: prompt) // bumps updatedAt
        var draft = PromptDraft(prompt)
        draft.content = "after"
        library.update(prompt, with: draft, coalescing: true)
        #expect(prompt.sortedVersions.map(\.content) == ["before"])
    }

    @Test func libraryEditorCommitsCoalesceUnlessExplicit() throws {
        let (app, cleanup) = try makeTestAppModel(seed: false)
        defer { cleanup() }
        let library = app.library
        let state = app.libraryState
        let prompt = library.createPrompt(title: "T", content: "a")
        state.select(prompt, library: library)
        let session = try #require(state.editor)

        session.draft.content = "b"
        state.commitEditor(to: library)            // autosave
        session.draft.content = "c"
        state.commitEditor(to: library)            // autosave, same session
        #expect(prompt.sortedVersions.count == 1)
        session.draft.content = "d"
        state.commitEditor(to: library, explicit: true) // ⌘S
        #expect(prompt.sortedVersions.count == 2)
        #expect(prompt.content == "d")
    }

    @Test func blankNewPromptIsDiscardedWhenLeft() throws {
        let (app, cleanup) = try makeTestAppModel(seed: false)
        defer { cleanup() }
        let keep = app.library.createPrompt(title: "Keep", content: "x")
        app.createPromptInLibrary()
        #expect(app.library.prompts.count == 2)
        app.libraryState.select(keep, library: app.library)
        #expect(app.library.prompts.count == 1, "The untouched new prompt is removed")
    }
}

/// End-to-end timing through `PromptLibrary` (not just the engine) at 10,000 prompts.
@MainActor
struct LibraryPerformanceTests {
    @Test func tenThousandPromptLibraryStaysInteractive() throws {
        let (app, cleanup) = try makeTestAppModel(seed: false)
        defer { cleanup() }
        let library = app.library
        let filler = String(repeating: "Explain the trade-offs clearly and give concrete examples. ", count: 12)
        let folders = (0..<20).map { FolderRecord(id: UUID(), name: "Folder \($0)", symbol: "folder", parentId: nil, sortIndex: $0) }
        let records = (0..<10_000).map { index in
            PromptRecord(
                id: UUID(), title: "Prompt \(index)", content: filler + " marker\(index) {{topic}}",
                description: "Description \(index)", folderId: folders[index % 20].id, folder: nil,
                tags: ["tag\(index % 40)"], isFavorite: index % 17 == 0, isTemplate: false, variables: [],
                createdAt: .now, updatedAt: .now, usageCount: index % 23, lastUsedAt: index % 23 == 0 ? nil : .now,
                versions: []
            )
        }
        let importStart = ContinuousClock.now
        library.importArchive(PromptArchive(folders: folders, prompts: records), mode: .merge)
        let importTime = ContinuousClock.now - importStart
        #expect(library.prompts.count == 10_000)

        let clock = ContinuousClock()
        var results: [Prompt] = []
        let coldSearch = clock.measure { results = library.prompts(in: .all, matching: "marker9999") }
        #expect(results.count == 1)
        let warmSearch = clock.measure { results = library.prompts(in: .all, matching: "prompt 42") }
        #expect(!results.isEmpty)
        let smartSort = clock.measure { results = library.prompts(in: .all, sortedBy: .smart, favoritesFirst: true) }
        #expect(results.count == 10_000)
        let folderScope = clock.measure { results = library.prompts(in: .folder(folders[3].id)) }
        #expect(results.count == 500)
        let counts = clock.measure { _ = library.counts() }

        print("""
        [perf] import \(importTime) · cold search \(coldSearch) · warm search \(warmSearch) · \
        smart sort \(smartSort) · folder scope \(folderScope) · counts \(counts)
        """)
        // Generous bounds for unoptimized debug builds on shared machines.
        #expect(warmSearch < .milliseconds(150))
        #expect(smartSort < .milliseconds(250))
        #expect(counts < .milliseconds(250))
    }
}
