import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

/// Thin wrapper around the general pasteboard.
enum Clipboard {
    @discardableResult
    static func copy(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    static func currentString() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }
}

/// Pastes into the previously active app by synthesizing ⌘V. Requires Accessibility permission.
enum AutoPaster {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt asking the user to grant Accessibility access.
    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Activates `application` and sends ⌘V to it once it is frontmost.
    static func paste(into application: NSRunningApplication?) {
        guard isTrusted else { return }
        application?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            postCommandV()
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Writes JSON backups of the whole library and prunes old ones.
final class BackupService {
    let directory: URL
    private var cachedLatestBackup: Date?
    private var hasScanned = false

    init(directory: URL) {
        self.directory = directory
    }

    static let fileExtension = "json"
    private static let prefix = "PromptVault Backup "

    func backups() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == Self.fileExtension && $0.lastPathComponent.hasPrefix(Self.prefix) }
            .sorted { modificationDate(of: $0) > modificationDate(of: $1) }
    }

    var latestBackupDate: Date? {
        if !hasScanned {
            cachedLatestBackup = backups().first.map(modificationDate(of:))
            hasScanned = true
        }
        return cachedLatestBackup
    }

    @discardableResult
    func createBackup(from library: PromptLibrary, keep: Int) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = directory.appendingPathComponent("\(Self.prefix)\(formatter.string(from: .now)).\(Self.fileExtension)")
        let data = try PromptArchiveCodec.encode(library.makeArchive(generator: AppInfo.generator))
        try data.write(to: url, options: .atomic)
        cachedLatestBackup = .now
        hasScanned = true
        prune(keep: keep)
        Log.data.notice("Wrote backup \(url.lastPathComponent, privacy: .public)")
        return url
    }

    /// Creates a backup when the last one is older than `interval` and the library isn't empty.
    func performAutomaticBackupIfNeeded(library: PromptLibrary, keep: Int, interval: TimeInterval = 24 * 60 * 60) {
        guard !library.prompts.isEmpty else { return }
        if let latest = latestBackupDate, Date.now.timeIntervalSince(latest) < interval { return }
        do {
            try createBackup(from: library, keep: keep)
        } catch {
            Log.data.error("Automatic backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func prune(keep: Int) {
        let all = backups()
        guard all.count > keep, keep > 0 else { return }
        for url in all.dropFirst(keep) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var generator: String { "PromptVault \(version)" }
}
