import AppKit
import SwiftUI

/// Owns the menu bar item and its popover, including keyboard routing while the popover is open.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let app: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var keyMonitor: Any?
    private var lastCloseTime: Date = .distantPast
    private var flashTask: Task<Void, Never>?
    private var returnFocusOnClose = true

    /// The app that was frontmost before the popover opened; focus returns there afterwards.
    private(set) var previousApp: NSRunningApplication?

    var hasOtherVisibleWindows: () -> Bool = { false }
    var contextMenuProvider: () -> NSMenu = { NSMenu() }

    init(app: AppModel) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.image(named: "text.bubble")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "PromptVault"
            button.setAccessibilityLabel("PromptVault")
        }

        let hosting = NSHostingController(rootView: PopoverRootView().environment(app))
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = Design.popoverSize
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private static func image(named symbol: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PromptVault")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    var isShown: Bool { popover.isShown }

    // MARK: Showing & hiding

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
            return
        }
        // A transient popover closes on mouse-down outside it, which includes the status
        // item itself; don't immediately reopen it on the matching mouse-up.
        if !popover.isShown && Date.now.timeIntervalSince(lastCloseTime) < 0.3 { return }
        toggle()
    }

    func toggle() {
        popover.isShown ? close() : show()
    }

    func show() {
        guard let button = statusItem.button, !popover.isShown else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = frontmost
        }
        app.popover.prepareForDisplay()
        returnFocusOnClose = true
        Self.forceActivate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installKeyMonitor()
    }

    /// Closes the popover. Pass `returningFocus: false` when PromptVault is about to show its own
    /// UI (library window, settings, an open panel) so focus isn't handed back to the previous app.
    /// Cooperative activation (`NSApp.activate()`) can be declined for a menu bar popover opened
    /// from the global shortcut, leaving it visible but unable to receive typing (verified by
    /// `PopoverLiveTests`). Forced activation is still required for this case; it is called
    /// through a protocol because the API is deprecated without a replacement for menu bar apps.
    static func forceActivate() {
        (NSApp as ForcedActivating).activate(ignoringOtherApps: true)
    }

        func close(returningFocus: Bool = true) {
        guard popover.isShown else { return }
        returnFocusOnClose = returningFocus
        popover.performClose(nil)
    }

    /// The popover's window, while shown (used by tests).
    var popoverWindow: NSWindow? { popover.contentViewController?.view.window }

    func popoverDidShow(_ notification: Notification) {
        // Focus is requested again once the window is on screen; requesting it only before
        // showing doesn't reliably focus the field on the second and later opens.
        app.popover.searchFocusRequest += 1
    }

    func popoverDidClose(_ notification: Notification) {
        lastCloseTime = .now
        removeKeyMonitor()
        app.popover.route = .list
        app.popover.pendingDeletion = nil
        // Return focus to where the user came from, unless PromptVault is showing its own UI.
        if returnFocusOnClose && NSApp.modalWindow == nil && NSApp.isActive && !hasOtherVisibleWindows() {
            previousApp?.activate()
        }
        returnFocusOnClose = true
        app.performAutomaticBackupIfNeeded()
    }

    private func showContextMenu() {
        close()
        guard let button = statusItem.button else { return }
        let menu = contextMenuProvider()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown,
                  let popoverWindow = self.popover.contentViewController?.view.window,
                  event.window === popoverWindow else { return event }
            return self.app.handlePopoverKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: Feedback & paste

    /// Briefly shows a checkmark in the menu bar to confirm a copy.
    func flash() {
        guard let button = statusItem.button else { return }
        button.image = Self.image(named: "checkmark.circle.fill")
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak button] in
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            button?.image = Self.image(named: "text.bubble")
        }
    }

    func pasteIntoPreviousApp() {
        let target = previousApp
        DispatchQueue.main.async {
            AutoPaster.paste(into: target)
        }
    }
}

private protocol ForcedActivating {
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: ForcedActivating {}
