import AppKit
import UniformTypeIdentifiers

/// Import, export, backup, and restore flows using native open/save panels and alerts.
enum DataTransfer {
    // MARK: Import

    static func importPrompts(app: AppModel, window: NSWindow?) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Import Prompts"
        panel.message = "Choose PromptVault archives or JSON files containing prompts."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        run(panel, window: window) { urls in
            var total = ImportSummary()
            var failures: [String] = []
            for url in urls {
                do {
                    let data = try Data(contentsOf: url)
                    let archive = try PromptArchiveCodec.decode(data)
                    let summary = app.library.importArchive(archive, mode: .merge)
                    total.promptsAdded += summary.promptsAdded
                    total.promptsUpdated += summary.promptsUpdated
                    total.promptsSkipped += summary.promptsSkipped
                    total.foldersAdded += summary.foldersAdded
                } catch {
                    failures.append("\(url.lastPathComponent): \(describe(error))")
                }
            }
            if failures.isEmpty {
                showAlert(title: "Import Complete", message: total.message, window: window)
            } else {
                let succeeded = urls.count - failures.count
                let prefix = succeeded > 0 ? total.message + "\n\n" : ""
                showAlert(title: "Some Files Couldn’t Be Imported", message: prefix + failures.joined(separator: "\n"), style: .warning, window: window)
            }
        }
    }

    // MARK: Export

    static func exportAll(app: AppModel, window: NSWindow?) {
        export(prompts: nil, app: app, window: window)
    }

    /// Exports `prompts` (or the whole library when `nil`) to a JSON archive.
    static func export(prompts: [Prompt]?, app: AppModel, window: NSWindow?) {
        NSApp.activate()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let date = Date.now.formatted(.iso8601.year().month().day())
        if let prompts, prompts.count == 1, let only = prompts.first {
            panel.title = "Export Prompt"
            panel.nameFieldStringValue = "\(sanitize(only.displayTitle)).json"
        } else if let prompts {
            panel.title = "Export \(prompts.count) Prompts"
            panel.nameFieldStringValue = "PromptVault Export \(date).json"
        } else {
            panel.title = "Export All Prompts"
            panel.nameFieldStringValue = "PromptVault Library \(date).json"
        }
        run(panel, window: window) { url in
            do {
                let archive = app.library.makeArchive(of: prompts, generator: AppInfo.generator)
                try PromptArchiveCodec.encode(archive).write(to: url, options: .atomic)
                let count = archive.prompts.count
                app.showToast(Toast(message: "Exported \(count) prompt\(count == 1 ? "" : "s")"), in: .library)
            } catch {
                showAlert(title: "Export Failed", message: describe(error), style: .warning, window: window)
            }
        }
    }

    // MARK: Backup & restore

    static func backUpNow(app: AppModel, window: NSWindow?) {
        do {
            let url = try app.backups.createBackup(from: app.library, keep: app.settings.backupRetention)
            let alert = NSAlert()
            alert.messageText = "Backup Created"
            alert.informativeText = "Saved “\(url.lastPathComponent)” in your backups folder."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show in Finder")
            present(alert, window: window) { response in
                if response == .alertSecondButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        } catch {
            showAlert(title: "Backup Failed", message: describe(error), style: .warning, window: window)
        }
    }

    /// Replaces the library with a backup. A safety backup of the current library is made first.
    static func restoreFromBackup(app: AppModel, window: NSWindow?) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Restore from Backup"
        panel.message = "Choose a backup to restore. Your current library will be replaced."
        panel.prompt = "Restore"
        panel.allowedContentTypes = [.json]
        panel.directoryURL = app.backups.directory
        panel.allowsMultipleSelection = false
        run(panel, window: window) { urls in
            guard let url = urls.first else { return }
            let archive: PromptArchive
            do {
                archive = try PromptArchiveCodec.decode(Data(contentsOf: url))
            } catch {
                showAlert(title: "Couldn’t Read Backup", message: describe(error), style: .warning, window: window)
                return
            }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Replace your library with this backup?"
            alert.informativeText = "“\(url.lastPathComponent)” contains \(archive.prompts.count) prompts and \(archive.folders.count) folders. "
                + "Your current \(app.library.prompts.count) prompts will be replaced. A backup of your current library will be saved first."
            alert.addButton(withTitle: "Restore")
            alert.addButton(withTitle: "Cancel")
            present(alert, window: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                do {
                    if !app.library.prompts.isEmpty {
                        try app.backups.createBackup(from: app.library, keep: max(app.settings.backupRetention, 1) + 1)
                    }
                } catch {
                    showAlert(title: "Restore Cancelled", message: "Couldn’t back up the current library first: \(describe(error))", style: .warning, window: window)
                    return
                }
                app.libraryState.commitEditor(to: app.library)
                app.libraryState.selection = []
                app.libraryState.syncEditor(with: app.library)
                let summary = app.library.importArchive(archive, mode: .replace)
                app.libraryState.scope = .all
                showAlert(title: "Library Restored", message: summary.message, window: window)
            }
        }
    }

    static func revealDataFolder(app: AppModel) {
        NSWorkspace.shared.activateFileViewerSelecting([app.paths.storeURL])
    }

    static func revealBackups(app: AppModel) {
        try? FileManager.default.createDirectory(at: app.backups.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(app.backups.directory)
    }

    // MARK: Helpers

    private static func run(_ panel: NSOpenPanel, window: NSWindow?, completion: @escaping ([URL]) -> Void) {
        if let window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK { completion(panel.urls) }
            }
        } else if panel.runModal() == .OK {
            completion(panel.urls)
        }
    }

    private static func run(_ panel: NSSavePanel, window: NSWindow?, completion: @escaping (URL) -> Void) {
        if let window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { completion(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    static func showAlert(title: String, message: String, style: NSAlert.Style = .informational, window: NSWindow?) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        present(alert, window: window) { _ in }
    }

    private static func present(_ alert: NSAlert, window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            NSApp.activate()
            completion(alert.runModal())
        }
    }

    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription { return description }
        if error is DecodingError { return "The file contains JSON that doesn’t match the PromptVault format." }
        return error.localizedDescription
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }
}
