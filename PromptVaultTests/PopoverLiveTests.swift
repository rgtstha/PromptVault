import AppKit
import Carbon.HIToolbox
import Testing
@testable import PromptVault

/// Drives the real status item + popover through the AppKit event path. Opt-in because it puts
/// an item in the menu bar and briefly takes focus: run with
/// `TEST_RUNNER_PROMPTVAULT_UI_TESTS=1 xcodebuild … test -only-testing:PromptVaultTests/PopoverLiveTests`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PROMPTVAULT_UI_TESTS"] != nil), .serialized)
struct PopoverLiveTests {
    @Test func focusTypingNavigationPasteAndCopy() async throws {
        let (app, cleanup) = try makeTestAppModel()
        defer { cleanup() }
        let previousMenu = NSApp.mainMenu
        NSApp.mainMenu = MainMenu.build()
        defer { NSApp.mainMenu = previousMenu }

        let savedClipboard = ClipboardSnapshot()
        defer { savedClipboard.restore() }

        let status = StatusItemController(app: app)
        app.actions.closePopover = { [weak status] in status?.close() }
        app.actions.closePopoverForAppUI = { [weak status] in status?.close(returningFocus: false) }
        // Let the menu bar place the new status item before anchoring a popover to it.
        try await Task.sleep(for: .milliseconds(600))

        // 1. The search field has focus on the first AND second open, and typing reaches it.
        for attempt in 1...2 {
            status.show()
            try await Task.sleep(for: .milliseconds(800))
            // macOS may refuse activation that isn't triggered by real user input (posted test
            // events don't count), e.g. while you are typing in another app during the run.
            #expect(NSApp.isActive, "app activates when the popover opens (open \(attempt)); frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
            let window = try #require(status.popoverWindow, "popover window exists (open \(attempt))")
            #expect(window.isKeyWindow, "popover is key (open \(attempt))")
            #expect(window.firstResponder is NSTextView, "search field focused (open \(attempt))")

            for character in "e" { try await type(String(character), in: window) }
            #expect(app.popover.searchText == "e", "typed text reaches search (open \(attempt))")

            let results = app.popover.results
            try #require(results.count >= 2)
            try await press(kVK_DownArrow, in: window)
            #expect(app.popover.selectedID == results[1].id, "↓ moves selection (open \(attempt))")

            status.close()
            // The window hides immediately; `isShown` flips once the close animation finishes.
            for _ in 1...20 where status.isShown {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(!window.isVisible)
            #expect(!status.isShown)
        }

        // 2. ⌘V pastes into the popover's search field (needs the Edit menu key equivalents).
        Clipboard.copy("Socratic")
        status.show()
        try await Task.sleep(for: .milliseconds(800))
        let window = try #require(status.popoverWindow)
        try await press(kVK_ANSI_V, characters: "v", flags: .command, in: window)
        #expect(app.popover.searchText == "Socratic", "⌘V pastes into search")

        // 3. Return copies the selected prompt (no variables) and records usage.
        let target = try #require(app.popover.selectedPrompt)
        #expect(target.title == "Socratic Tutor")
        let usesBefore = target.usageCount
        try await press(kVK_Return, characters: "\r", in: window)
        try await Task.sleep(for: .milliseconds(400))
        #expect(Clipboard.currentString() == target.content, "Return copies the prompt text")
        #expect(target.usageCount == usesBefore + 1)
        #expect(!status.isShown, "popover closes after copying (default setting)")
    }

    // MARK: Event helpers

    private func type(_ characters: String, in window: NSWindow) async throws {
        let code: Int = switch characters {
        case "c": kVK_ANSI_C
        case "o": kVK_ANSI_O
        case "d": kVK_ANSI_D
        case "e": kVK_ANSI_E
        default: 0
        }
        try await press(code, characters: characters, in: window)
    }

    private func press(_ keyCode: Int, characters: String = "", flags: NSEvent.ModifierFlags = [], in window: NSWindow) async throws {
        let specialCharacters: String = switch keyCode {
        case kVK_DownArrow: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case kVK_UpArrow: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        default: characters
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: specialCharacters,
                charactersIgnoringModifiers: specialCharacters, isARepeat: false, keyCode: UInt16(keyCode)
            )!
            NSApp.postEvent(event, atStart: false)
        }
        try await Task.sleep(for: .milliseconds(150))
    }
}

/// Saves every item and type on the general pasteboard and puts them back afterwards.
@MainActor
private struct ClipboardSnapshot {
    private let items: [NSPasteboardItem]

    init() {
        items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
