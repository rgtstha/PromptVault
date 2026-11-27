import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var app: AppModel?
    private var statusController: StatusItemController?
    private var libraryWindow: LibraryWindowController?
    private var settingsWindow: SettingsWindowController?

    /// Unit tests run inside the app; skip UI and the real data store in that case.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.build()
        launch(paths: .resolve())
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let app else { return }
        app.libraryState.commitEditor(to: app.library, leaving: true)
        app.library.save()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Re-opening the app (e.g. from Finder or Spotlight) shows the library.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLibrary(selecting: nil)
        return true
    }

    // MARK: Startup

    private func launch(paths: AppPaths) {
        do {
            configure(try AppModel.bootstrap(paths: paths))
        } catch {
            handleStoreFailure(error, paths: paths)
        }
    }

    private func handleStoreFailure(_ error: Error, paths: AppPaths) {
        Log.data.fault("Couldn't open the library: \(error.localizedDescription, privacy: .public)")
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "PromptVault couldn’t open your library"
        alert.informativeText = """
        \(error.localizedDescription)

        You can set the unreadable library aside and start fresh — the old file is kept next to it \
        so it can be recovered — or restore from a backup afterwards.
        """
        alert.addButton(withTitle: "Start Fresh")
        alert.addButton(withTitle: "Quit")
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }
        do {
            try Persistence.quarantineStore(at: paths.storeURL)
            configure(try AppModel.bootstrap(paths: paths))
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            NSApp.terminate(nil)
        }
    }

    private func configure(_ model: AppModel) {
        app = model
        let status = StatusItemController(app: model)
        statusController = status
        status.hasOtherVisibleWindows = { [weak self] in self?.hasVisibleWindows ?? false }
        status.contextMenuProvider = { MainMenu.statusItemMenu() }

        model.actions = AppActions(
            showPopover: { [weak status] in status?.show() },
            closePopover: { [weak status] in status?.close() },
            closePopoverForAppUI: { [weak status] in status?.close(returningFocus: false) },
            openLibrary: { [weak self] id in self?.showLibrary(selecting: id) },
            openSettings: { [weak self] in self?.showSettingsWindow() },
            flashStatusItem: { [weak status] in status?.flash() },
            pasteIntoPreviousApp: { [weak status] in status?.pasteIntoPreviousApp() },
            hotKeyChanged: { combo in HotKeyCenter.shared.register(combo) }
        )

        HotKeyCenter.shared.onPress = { [weak status] in status?.toggle() }
        model.hotKeyUnavailable = !HotKeyCenter.shared.register(model.settings.hotKey)
        if let combo = model.settings.hotKey {
            if model.hotKeyUnavailable {
                Log.app.error("Global shortcut \(combo.displayString, privacy: .public) is unavailable")
            } else {
                Log.app.notice("Registered global shortcut \(combo.displayString, privacy: .public)")
            }
        }

        // Build the search index while idle so the first keystroke is instant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak model] in
            model?.library.warmSearchIndex()
        }

        // Defer the daily backup so it never slows down launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak model] in
            model?.performAutomaticBackupIfNeeded()
        }

        // First launch: show where the app lives.
        if !model.settings.hasShownWelcome {
            model.settings.hasShownWelcome = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak status] in status?.show() }
        }
    }

    // MARK: Windows

    private var hasVisibleWindows: Bool {
        libraryWindow?.window?.isVisible == true || settingsWindow?.window?.isVisible == true
    }

    private func updateActivationPolicy() {
        if !hasVisibleWindows { NSApp.setActivationPolicy(.accessory) }
    }

    private func showLibrary(selecting promptID: UUID?) {
        guard let app else { return }
        if libraryWindow == nil {
            let controller = LibraryWindowController(app: app)
            controller.onClose = { [weak self] in self?.updateActivationPolicy() }
            libraryWindow = controller
        }
        if let promptID, let prompt = app.library.prompt(id: promptID) {
            let state = app.libraryState
            let visible = app.library.prompts(in: state.scope, matching: state.searchText).contains { $0.id == promptID }
            if !visible {
                state.scope = .all
                state.searchText = ""
            }
            state.select(prompt, library: app.library)
        }
        libraryWindow?.show()
    }

    private func showSettingsWindow() {
        guard let app else { return }
        if settingsWindow == nil {
            let controller = SettingsWindowController(app: app)
            controller.onClose = { [weak self] in self?.updateActivationPolicy() }
            settingsWindow = controller
        }
        settingsWindow?.show()
    }

    private var frontWindow: NSWindow? {
        libraryWindow?.window?.isKeyWindow == true ? libraryWindow?.window : nil
    }

    // MARK: Menu actions

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Your personal library of AI prompts.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    @objc func showSettings(_ sender: Any?) { showSettingsWindow() }

    @objc func showPopover(_ sender: Any?) {
        DispatchQueue.main.async { [weak self] in self?.statusController?.show() }
    }

    @objc func showLibraryWindow(_ sender: Any?) { showLibrary(selecting: nil) }

    @objc func newPrompt(_ sender: Any?) {
        showLibrary(selecting: nil)
        app?.createPromptInLibrary()
    }

    @objc func newFolder(_ sender: Any?) {
        showLibrary(selecting: nil)
        app?.createFolderInLibrary()
    }

    @objc func findPrompts(_ sender: Any?) {
        showLibrary(selecting: nil)
        app?.libraryState.searchFocusRequest += 1
    }

    @objc func importPrompts(_ sender: Any?) {
        guard let app else { return }
        DataTransfer.importPrompts(app: app, window: frontWindow)
    }

    @objc func exportAll(_ sender: Any?) {
        guard let app else { return }
        DataTransfer.exportAll(app: app, window: frontWindow)
    }

    @objc func exportSelected(_ sender: Any?) {
        guard let app else { return }
        let prompts = app.libraryState.selection.compactMap { app.library.prompt(id: $0) }
        guard !prompts.isEmpty else { return }
        app.libraryState.commitEditor(to: app.library)
        DataTransfer.export(prompts: prompts, app: app, window: frontWindow)
    }

    @objc func backUpNow(_ sender: Any?) {
        guard let app else { return }
        DataTransfer.backUpNow(app: app, window: frontWindow)
    }

    @objc func restoreBackup(_ sender: Any?) {
        guard let app else { return }
        DataTransfer.restoreFromBackup(app: app, window: frontWindow)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let app else { return false }
        if menuItem.action == #selector(exportSelected(_:)) {
            return libraryWindow?.window?.isVisible == true && !app.libraryState.selection.isEmpty
        }
        return true
    }
}
