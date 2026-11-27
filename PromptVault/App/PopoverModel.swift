import AppKit
import Carbon.HIToolbox
import Observation

enum PopoverRoute: Equatable {
    case list
    case preview(UUID)
    case fill(UUID)
    /// `nil` creates a new prompt.
    case edit(UUID?)
}

/// State for the menu bar popover. Kept outside the view so the AppKit key monitor and the
/// SwiftUI views share one source of truth.
@Observable
final class PopoverModel {
    @ObservationIgnored let library: PromptLibrary
    @ObservationIgnored let settings: AppSettings

    var route: PopoverRoute = .list
    var searchText = ""
    var scope: LibraryScope = .all
    var selectedID: UUID?
    /// Seed for a new prompt (e.g. created from the clipboard or a template).
    var newPromptSeed: NewPromptSeed?
    var pendingDeletion: Prompt?

    /// Incremented to ask views to focus the search field / save / cancel the editor.
    var searchFocusRequest = 0
    var editorSaveRequest = 0
    var editorCancelRequest = 0
    var fillSubmitRequest = 0

    init(library: PromptLibrary, settings: AppSettings) {
        self.library = library
        self.settings = settings
    }

    var results: [Prompt] {
        library.prompts(
            in: scope, matching: searchText,
            sortedBy: settings.popoverSort, favoritesFirst: settings.favoritesFirst
        )
    }

    /// The selected prompt, falling back to the first result.
    func effectiveSelection(in results: [Prompt]) -> UUID? {
        if let selectedID, results.contains(where: { $0.id == selectedID }) { return selectedID }
        return results.first?.id
    }

    var selectedPrompt: Prompt? {
        let results = self.results
        guard let id = effectiveSelection(in: results) else { return nil }
        return results.first { $0.id == id }
    }

    func moveSelection(by delta: Int) {
        let results = self.results
        guard !results.isEmpty else { return }
        let currentIndex = effectiveSelection(in: results).flatMap { id in results.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), results.count - 1)
        selectedID = results[nextIndex].id
    }

    /// Scopes shown as chips, in order (used for ⌘[ / ⌘] cycling).
    var scopeCycle: [LibraryScope] {
        [.all, .favorites, .recent, .templates] + library.flattenedFolders().map { .folder($0.folder.id) }
    }

    func cycleScope(by delta: Int) {
        let cycle = scopeCycle
        let index = cycle.firstIndex(of: scope) ?? 0
        scope = cycle[(index + delta + cycle.count) % cycle.count]
        selectedID = nil
    }

    /// Called every time the popover opens.
    func prepareForDisplay() {
        route = .list
        searchText = ""
        selectedID = nil
        pendingDeletion = nil
        if case .folder(let id) = scope, library.folder(id: id) == nil { scope = .all }
        if case .tag(let tag) = scope, !library.allTags.contains(where: { $0.name == tag }) { scope = .all }
        searchFocusRequest += 1
    }

    func startNewPrompt(seed: NewPromptSeed? = nil) {
        newPromptSeed = seed
        route = .edit(nil)
    }
}

struct NewPromptSeed: Equatable {
    var title = ""
    var content = ""
    var summary = ""
    var tags: [String] = []
    var folderID: UUID?
    var variables: [PromptVariable] = []
}

// MARK: - Keyboard handling

extension AppModel {
    /// Handles a key press while the popover is key. Returns `true` if the event was consumed.
    func handlePopoverKeyDown(_ event: NSEvent) -> Bool {
        // Let input methods (Japanese, Chinese, …) commit/compose with Return and arrows.
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = Int(event.keyCode)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if let pending = popover.pendingDeletion {
            switch keyCode {
            case kVK_Escape:
                popover.pendingDeletion = nil
                return true
            case kVK_Return, kVK_ANSI_KeypadEnter:
                library.delete([pending])
                popover.pendingDeletion = nil
                popover.route = .list
                return true
            default:
                return false
            }
        }

        switch popover.route {
        case .list:
            return handleListKey(keyCode: keyCode, flags: flags, characters: characters)
        case .preview(let id):
            return handlePreviewKey(promptID: id, keyCode: keyCode, flags: flags, characters: characters)
        case .fill(let id):
            if keyCode == kVK_Escape {
                popover.route = .list
                popover.selectedID = id
                return true
            }
            if flags == .command, keyCode == kVK_Return {
                popover.fillSubmitRequest += 1
                return true
            }
            return false
        case .edit:
            if keyCode == kVK_Escape {
                popover.editorCancelRequest += 1
                return true
            }
            if flags == .command, characters == "s" || keyCode == kVK_Return {
                popover.editorSaveRequest += 1
                return true
            }
            return false
        }
    }

    private func handleListKey(keyCode: Int, flags: NSEvent.ModifierFlags, characters: String) -> Bool {
        switch keyCode {
        case kVK_DownArrow where flags.isEmpty || flags == .shift:
            popover.moveSelection(by: 1)
            return true
        case kVK_UpArrow where flags.isEmpty || flags == .shift:
            popover.moveSelection(by: -1)
            return true
        case kVK_PageDown:
            popover.moveSelection(by: 8)
            return true
        case kVK_PageUp:
            popover.moveSelection(by: -8)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let prompt = popover.selectedPrompt {
                if flags.contains(.option) {
                    copyTemplateText(prompt, context: .popover)
                } else {
                    use(prompt, from: .popover)
                }
            }
            return true
        case kVK_Tab where flags.isEmpty:
            if let prompt = popover.selectedPrompt { popover.route = .preview(prompt.id) }
            return true
        case kVK_Escape:
            if !popover.searchText.isEmpty {
                popover.searchText = ""
                popover.selectedID = nil
            } else {
                actions.closePopover()
            }
            return true
        default:
            break
        }

        if flags == .control {
            switch characters {
            case "n": popover.moveSelection(by: 1); return true
            case "p": popover.moveSelection(by: -1); return true
            default: break
            }
        }

        if flags == .command {
            if let digit = Int(characters), (1...9).contains(digit) {
                let results = popover.results
                if digit <= results.count { use(results[digit - 1], from: .popover) }
                return true
            }
            switch characters {
            case "e":
                if let prompt = popover.selectedPrompt { popover.route = .edit(prompt.id) }
                return true
            case "d":
                if let prompt = popover.selectedPrompt { popover.selectedID = library.duplicate(prompt).id }
                return true
            case "n":
                popover.startNewPrompt(seed: NewPromptSeed(folderID: currentFolderID))
                return true
            case "o", "l":
                let id = popover.selectedPrompt?.id
                actions.closePopoverForAppUI()
                actions.openLibrary(id)
                return true
            case "[":
                popover.cycleScope(by: -1)
                return true
            case "]":
                popover.cycleScope(by: 1)
                return true
            case "c":
                // ⌘C copies the selected prompt unless text is selected in the search field.
                if !firstResponderHasSelectedText, let prompt = popover.selectedPrompt {
                    use(prompt, from: .popover)
                    return true
                }
                return false
            default:
                break
            }
            if keyCode == kVK_Delete, let prompt = popover.selectedPrompt {
                popover.pendingDeletion = prompt
                return true
            }
        }

        if flags == [.command, .shift], characters == "f", let prompt = popover.selectedPrompt {
            // Keep the selection on this prompt even if "favorites first" moves it.
            popover.selectedID = prompt.id
            library.toggleFavorite(prompt)
            return true
        }
        return false
    }

    private func handlePreviewKey(promptID: UUID, keyCode: Int, flags: NSEvent.ModifierFlags, characters: String) -> Bool {
        guard let prompt = library.prompt(id: promptID) else {
            popover.route = .list
            return true
        }
        switch keyCode {
        case kVK_Escape:
            popover.route = .list
            popover.selectedID = promptID
            return true
        case kVK_LeftArrow where flags.isEmpty:
            popover.route = .list
            popover.selectedID = promptID
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if flags.contains(.option) { copyTemplateText(prompt, context: .popover) } else { use(prompt, from: .popover) }
            return true
        default:
            break
        }
        if flags == .command {
            switch characters {
            case "e": popover.route = .edit(promptID); return true
            case "d": popover.route = .preview(library.duplicate(prompt).id); return true
            case "c" where !firstResponderHasSelectedText: use(prompt, from: .popover); return true
            default: break
            }
            if keyCode == kVK_Delete {
                popover.pendingDeletion = prompt
                return true
            }
        }
        if flags == [.command, .shift], characters == "f" {
            library.toggleFavorite(prompt)
            return true
        }
        return false
    }

    var currentFolderID: UUID? {
        if case .folder(let id) = popover.scope { return id }
        return nil
    }

    private var firstResponderHasSelectedText: Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return textView.selectedRange().length > 0
    }
}
