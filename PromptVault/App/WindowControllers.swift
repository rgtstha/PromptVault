import AppKit
import SwiftUI

/// The resizable library (management) window.
final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    private let app: AppModel
    var onClose: () -> Void = {}

    init(app: AppModel) {
        self.app = app
        let hosting = NSHostingController(rootView: LibraryRootView().environment(app))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: hosting)
        window.title = "PromptVault"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setContentSize(NSSize(width: 1140, height: 740))
        window.center()
        window.setFrameAutosaveName("PromptVaultLibraryWindow")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Persist in-progress edits whenever the user leaves the window.
        app.libraryState.commitEditor(to: app.library)
    }

    func windowWillClose(_ notification: Notification) {
        app.libraryState.commitEditor(to: app.library, leaving: true)
        DispatchQueue.main.async { [weak self] in self?.onClose() }
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: () -> Void = {}

    init(app: AppModel) {
        let hosting = NSHostingController(rootView: SettingsView().environment(app))
        let window = NSWindow(contentViewController: hosting)
        window.title = "PromptVault Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onClose() }
    }
}
