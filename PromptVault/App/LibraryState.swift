import Foundation
import Observation

/// UI state for the library window. Lives in `AppModel` so it survives the window being
/// closed and can be driven from the popover and menu bar.
@Observable
final class LibraryState {
    var scope: LibraryScope = .all
    var selection: Set<UUID> = []
    var searchText = ""
    var showHistory = false
    var fillingPromptID: UUID?
    var showTagManager = false
    var folderBeingRenamed: Folder?
    var folderPendingDeletion: Folder?
    var promptsPendingDeletion: [Prompt] = []
    /// Incremented to focus the search field or the title of a new prompt.
    var searchFocusRequest = 0
    var titleFocusRequest = 0

    /// Draft for the prompt currently open in the editor.
    private(set) var editor: PromptEditorSession?

    /// Keeps the editor in sync with the selection, saving the previous draft first.
    func syncEditor(with library: PromptLibrary) {
        let targetID = selection.count == 1 ? selection.first : nil
        guard editor?.promptID != targetID else { return }
        commitEditor(to: library, leaving: true)
        if let targetID, let prompt = library.prompt(id: targetID) {
            editor = PromptEditorSession(prompt: prompt)
        } else {
            editor = nil
        }
    }

    /// Saves pending edits (if any). Safe to call at any time, e.g. when the window closes.
    /// A prompt left completely empty (a "New Prompt" the user never typed into) is discarded
    /// when leaving it. Automatic saves are coalesced into editing sessions for version history;
    /// pass `explicit: true` for a deliberate save (⌘S) to always record a version.
    func commitEditor(to library: PromptLibrary, leaving: Bool = false, explicit: Bool = false) {
        guard let editor, let prompt = library.prompt(id: editor.promptID) else { return }
        if leaving && editor.draft.isEmpty && editor.draft.summary.isEmpty && prompt.isBlank {
            self.editor = nil
            selection.remove(prompt.id)
            library.delete([prompt])
            return
        }
        if !editor.draft.matches(prompt) {
            library.update(prompt, with: editor.draft, coalescing: !explicit)
        }
        editor.baseline = PromptDraft(prompt)
        editor.draft = editor.baseline
    }

    func select(_ prompt: Prompt, library: PromptLibrary) {
        selection = [prompt.id]
        syncEditor(with: library)
    }

    func removeFromSelection(_ ids: Set<UUID>) {
        selection.subtract(ids)
        if let editor, ids.contains(editor.promptID) { self.editor = nil }
    }
}

/// An in-progress edit of one prompt's text fields.
@Observable
final class PromptEditorSession {
    let promptID: UUID
    var draft: PromptDraft
    /// The prompt's state when the draft was loaded or last saved.
    var baseline: PromptDraft

    init(prompt: Prompt) {
        let initial = PromptDraft(prompt)
        promptID = prompt.id
        draft = initial
        baseline = initial
    }

    var hasUnsavedChanges: Bool { draft != baseline }

    /// Picks up changes made elsewhere (popover, version restore, import) when there are no
    /// local edits that would be overwritten.
    func refreshIfUnmodified(from prompt: Prompt) {
        let current = PromptDraft(prompt)
        guard current != baseline else { return }
        if !hasUnsavedChanges { draft = current }
        baseline = current
    }
}
