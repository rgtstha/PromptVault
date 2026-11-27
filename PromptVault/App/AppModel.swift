import AppKit
import Observation
import SwiftData

/// Window/popover operations implemented by the AppKit layer (`AppDelegate`).
struct AppActions {
    var showPopover: () -> Void = {}
    var closePopover: () -> Void = {}
    /// Closes the popover without returning focus to the previous app (PromptVault UI follows).
    var closePopoverForAppUI: () -> Void = {}
    var openLibrary: (_ promptID: UUID?) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var flashStatusItem: () -> Void = {}
    var pasteIntoPreviousApp: () -> Void = {}
    var hotKeyChanged: (_ combo: KeyCombo?) -> Bool = { _ in true }
}

enum UseContext {
    case popover
    case library
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var symbol = "checkmark.circle.fill"
    var isError = false
}

/// Root dependency container shared by the popover, library window, and settings.
@Observable
final class AppModel {
    let paths: AppPaths
    let container: ModelContainer
    let library: PromptLibrary
    let settings: AppSettings
    let backups: BackupService
    let popover: PopoverModel
    let libraryState: LibraryState

    var popoverToast: Toast?
    var libraryToast: Toast?
    /// Set when the configured global shortcut couldn't be registered.
    var hotKeyUnavailable = false

    @ObservationIgnored var actions = AppActions()

    init(paths: AppPaths, container: ModelContainer, settings: AppSettings = AppSettings()) {
        self.paths = paths
        self.container = container
        self.settings = settings
        self.library = PromptLibrary(context: container.mainContext)
        self.library.maxVersionsPerPrompt = settings.maxVersionsPerPrompt
        self.backups = BackupService(directory: paths.backupsDirectory)
        self.popover = PopoverModel(library: library, settings: settings)
        self.libraryState = LibraryState()
    }

    /// Opens the on-disk store, seeding sample content when the store is brand new.
    static func bootstrap(paths: AppPaths = .resolve()) throws -> AppModel {
        try paths.createDirectories()
        let isNewStore = !FileManager.default.fileExists(atPath: paths.storeURL.path)
        let container = try Persistence.makeContainer(storeURL: paths.storeURL)
        let model = AppModel(paths: paths, container: container)
        if isNewStore {
            model.library.seedSampleContent()
            Log.data.notice("Created a new library with sample content at \(paths.storeURL.path, privacy: .private)")
        }
        Log.data.notice("Opened library: \(model.library.prompts.count) prompts, \(model.library.folders.count) folders")
        return model
    }

    // MARK: - Using prompts

    /// Starts using a prompt: copies it straight away, or asks for variable values first.
    func use(_ prompt: Prompt, from context: UseContext) {
        guard prompt.hasUserVariables else {
            deliver(prompt, values: [:], context: context)
            return
        }
        switch context {
        case .popover:
            popover.route = .fill(prompt.id)
        case .library:
            libraryState.fillingPromptID = prompt.id
        }
    }

    func builtInValues() -> BuiltInValues {
        BuiltInValues(clipboard: Clipboard.currentString())
    }

    func render(_ prompt: Prompt, values: [String: String]) -> String {
        TemplateEngine.render(prompt.content, values: values, builtIns: builtInValues())
    }

    /// Copies the final text, records usage, then closes/pastes according to settings.
    func deliver(_ prompt: Prompt, values: [String: String], context: UseContext) {
        let text = render(prompt, values: values)
        guard Clipboard.copy(text) else {
            showToast(Toast(message: "Couldn’t write to the clipboard", symbol: "exclamationmark.triangle.fill", isError: true), in: context)
            return
        }
        library.recordUse(of: prompt, variableValues: values, rememberValues: settings.rememberVariableValues)
        actions.flashStatusItem()

        switch context {
        case .popover:
            if settings.pasteAfterCopy && AutoPaster.isTrusted {
                actions.closePopover()
                actions.pasteIntoPreviousApp()
            } else if settings.closePopoverAfterCopy {
                actions.closePopover()
            } else {
                popover.route = .list
                showToast(Toast(message: "Copied “\(prompt.displayTitle)”"), in: .popover)
            }
        case .library:
            showToast(Toast(message: "Copied “\(prompt.displayTitle)” to the clipboard"), in: .library)
        }
    }

    /// Copies the prompt text exactly as written, without filling variables.
    func copyTemplateText(_ prompt: Prompt, context: UseContext) {
        Clipboard.copy(prompt.content)
        showToast(Toast(message: "Copied template text"), in: context)
    }

    func showToast(_ toast: Toast, in context: UseContext) {
        switch context {
        case .popover: popoverToast = toast
        case .library: libraryToast = toast
        }
        let id = toast.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(toast.isError ? 3 : 1.6))
            guard let self else { return }
            if self.popoverToast?.id == id { self.popoverToast = nil }
            if self.libraryToast?.id == id { self.libraryToast = nil }
        }
    }

    // MARK: - Settings side effects

    func updateHotKey(_ combo: KeyCombo?) {
        settings.hotKey = combo
        hotKeyUnavailable = !actions.hotKeyChanged(combo)
    }

    func applyVersionLimit() {
        library.maxVersionsPerPrompt = settings.maxVersionsPerPrompt
    }

    func performAutomaticBackupIfNeeded() {
        guard settings.automaticBackups else { return }
        backups.performAutomaticBackupIfNeeded(library: library, keep: settings.backupRetention)
    }
}
