import Foundation
import Observation

/// Key-value storage for settings: `UserDefaults` in the app, in-memory in tests.
protocol SettingsStore: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: SettingsStore {}

final class InMemorySettingsStore: SettingsStore {
    private var values: [String: Any] = [:]
    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

/// User preferences, persisted in `UserDefaults`.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: SettingsStore

    private enum Key {
        static let hotKey = "settings.hotKey"
        static let pasteAfterCopy = "settings.pasteAfterCopy"
        static let closePopoverAfterCopy = "settings.closePopoverAfterCopy"
        static let favoritesFirst = "settings.favoritesFirst"
        static let popoverSort = "settings.popoverSort"
        static let librarySort = "settings.librarySort"
        static let automaticBackups = "settings.automaticBackups"
        static let backupRetention = "settings.backupRetention"
        static let maxVersions = "settings.maxVersionsPerPrompt"
        static let rememberValues = "settings.rememberVariableValues"
        static let monospacedEditor = "settings.monospacedEditor"
        static let hasShownWelcome = "settings.hasShownWelcome"
    }

    /// Global shortcut that toggles the popover. `nil` disables it.
    var hotKey: KeyCombo? {
        didSet {
            if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
                defaults.set(data, forKey: Key.hotKey)
            } else {
                defaults.set(Data(), forKey: Key.hotKey)
            }
        }
    }

    /// After copying from the popover, paste into the app that was frontmost (needs Accessibility).
    var pasteAfterCopy: Bool { didSet { defaults.set(pasteAfterCopy, forKey: Key.pasteAfterCopy) } }
    var closePopoverAfterCopy: Bool { didSet { defaults.set(closePopoverAfterCopy, forKey: Key.closePopoverAfterCopy) } }
    var favoritesFirst: Bool { didSet { defaults.set(favoritesFirst, forKey: Key.favoritesFirst) } }
    var popoverSort: PromptSortOrder { didSet { defaults.set(popoverSort.rawValue, forKey: Key.popoverSort) } }
    var librarySort: PromptSortOrder { didSet { defaults.set(librarySort.rawValue, forKey: Key.librarySort) } }
    var automaticBackups: Bool { didSet { defaults.set(automaticBackups, forKey: Key.automaticBackups) } }
    var backupRetention: Int { didSet { defaults.set(backupRetention, forKey: Key.backupRetention) } }
    var maxVersionsPerPrompt: Int { didSet { defaults.set(maxVersionsPerPrompt, forKey: Key.maxVersions) } }
    var rememberVariableValues: Bool { didSet { defaults.set(rememberVariableValues, forKey: Key.rememberValues) } }
    var monospacedEditor: Bool { didSet { defaults.set(monospacedEditor, forKey: Key.monospacedEditor) } }
    var hasShownWelcome: Bool { didSet { defaults.set(hasShownWelcome, forKey: Key.hasShownWelcome) } }

    init(defaults: SettingsStore = UserDefaults.standard) {
        self.defaults = defaults
        if let data = defaults.object(forKey: Key.hotKey) as? Data {
            hotKey = data.isEmpty ? nil : try? JSONDecoder().decode(KeyCombo.self, from: data)
        } else {
            hotKey = .defaultCombo
        }
        pasteAfterCopy = defaults.object(forKey: Key.pasteAfterCopy) as? Bool ?? false
        closePopoverAfterCopy = defaults.object(forKey: Key.closePopoverAfterCopy) as? Bool ?? true
        favoritesFirst = defaults.object(forKey: Key.favoritesFirst) as? Bool ?? true
        popoverSort = (defaults.object(forKey: Key.popoverSort) as? String).flatMap(PromptSortOrder.init(rawValue:)) ?? .smart
        librarySort = (defaults.object(forKey: Key.librarySort) as? String).flatMap(PromptSortOrder.init(rawValue:)) ?? .recentlyUpdated
        automaticBackups = defaults.object(forKey: Key.automaticBackups) as? Bool ?? true
        backupRetention = defaults.object(forKey: Key.backupRetention) as? Int ?? 14
        maxVersionsPerPrompt = defaults.object(forKey: Key.maxVersions) as? Int ?? 50
        rememberVariableValues = defaults.object(forKey: Key.rememberValues) as? Bool ?? true
        monospacedEditor = defaults.object(forKey: Key.monospacedEditor) as? Bool ?? false
        hasShownWelcome = defaults.object(forKey: Key.hasShownWelcome) as? Bool ?? false
    }
}
