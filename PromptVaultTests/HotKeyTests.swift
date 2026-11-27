import AppKit
import Carbon.HIToolbox
import Testing
@testable import PromptVault

@MainActor
struct HotKeyTests {
    @Test func defaultComboDisplaysAndValidates() {
        let combo = KeyCombo.defaultCombo
        #expect(combo.displayString == "⌃⌥P")
        #expect(combo.isValidGlobalShortcut)
        #expect(!KeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: [.shift]).isValidGlobalShortcut)
        #expect(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: []).isValidGlobalShortcut)
        #expect(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.command, .shift]).displayString == "⇧⌘Space")
    }

    @Test func comboSurvivesSettingsRoundTrip() {
        let defaults = InMemorySettingsStore()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.hotKey == .defaultCombo, "Default shortcut on first launch")
        let custom = KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command, .option])
        settings.hotKey = custom
        #expect(AppSettings(defaults: defaults).hotKey == custom)
        settings.hotKey = nil
        #expect(AppSettings(defaults: defaults).hotKey == nil, "Clearing the shortcut persists")
    }

    @Test func registersAndUnregistersSystemHotKey() {
        let center = HotKeyCenter.shared
        // An unusual combination that is very unlikely to be taken by another app.
        let combo = KeyCombo(keyCode: UInt32(kVK_F19), modifiers: [.control, .option, .shift, .command])
        #expect(center.register(combo))
        #expect(center.registeredCombo == combo)
        center.unregister()
        #expect(center.registeredCombo == nil)
    }
}
