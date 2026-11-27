import SwiftUI

struct SettingsView: View {
    enum Tab: Hashable { case general, library, about }
    @State private var tab: Tab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            LibrarySettingsTab()
                .tabItem { Label("Library & Data", systemImage: "externaldrive") }
                .tag(Tab.library)
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 540, height: 500)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var app
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var isTrusted = AutoPaster.isTrusted

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                LabeledContent("Open PromptVault") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ShortcutRecorder(combo: settings.hotKey) { combo in
                            app.updateHotKey(combo)
                        }
                        if app.hotKeyUnavailable {
                            Text("That shortcut is in use by another app. Try a different one.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.orange)
                } else if LaunchAtLogin.requiresApproval {
                    Text("Approve PromptVault in System Settings › General › Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Access")
            }

            Section {
                Toggle("Close the menu after copying", isOn: $settings.closePopoverAfterCopy)
                Toggle(isOn: $settings.pasteAfterCopy) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paste into the frontmost app")
                        Text("After copying from the menu bar, PromptVault switches back and presses ⌘V for you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: settings.pasteAfterCopy) { _, enabled in
                    if enabled && !AutoPaster.isTrusted { AutoPaster.requestAccess() }
                    isTrusted = AutoPaster.isTrusted
                }
                if settings.pasteAfterCopy && !isTrusted {
                    HStack {
                        Label("Needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Spacer()
                        Button("Open System Settings") { AutoPaster.openAccessibilitySettings() }
                            .controlSize(.small)
                        Button("Check Again") { isTrusted = AutoPaster.isTrusted }
                            .controlSize(.small)
                    }
                }
                Toggle("Remember values entered for variables", isOn: $settings.rememberVariableValues)
            } header: {
                Text("Copying")
            }

            Section {
                Picker("Sort prompts by", selection: $settings.popoverSort) {
                    ForEach(PromptSortOrder.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show favorites first", isOn: $settings.favoritesFirst)
                Toggle("Use a monospaced font for prompt text", isOn: $settings.monospacedEditor)
            } header: {
                Text("Menu Bar List")
            }
        }
        .formStyle(.grouped)
        .onAppear { isTrusted = AutoPaster.isTrusted }
    }
}

private struct LibrarySettingsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Stepper(value: $settings.maxVersionsPerPrompt, in: 5...500, step: 5) {
                    LabeledContent("Versions kept per prompt", value: "\(settings.maxVersionsPerPrompt)")
                }
                .onChange(of: settings.maxVersionsPerPrompt) { _, _ in app.applyVersionLimit() }
            } header: {
                Text("Version History")
            } footer: {
                Text("A version is saved each time you change a prompt’s title, description, or text. The oldest are removed beyond this limit.")
            }

            Section {
                Toggle("Back up automatically every day", isOn: $settings.automaticBackups)
                Stepper(value: $settings.backupRetention, in: 1...90) {
                    LabeledContent("Backups to keep", value: "\(settings.backupRetention)")
                }
                LabeledContent("Last backup") {
                    Text(app.backups.latestBackupDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Back Up Now") { DataTransfer.backUpNow(app: app, window: NSApp.keyWindow) }
                    Button("Restore from Backup…") { DataTransfer.restoreFromBackup(app: app, window: NSApp.keyWindow) }
                    Spacer()
                    Button("Show Backups") { DataTransfer.revealBackups(app: app) }
                }
            } header: {
                Text("Backups")
            }

            Section {
                HStack {
                    Button("Import…") { DataTransfer.importPrompts(app: app, window: NSApp.keyWindow) }
                    Button("Export All…") { DataTransfer.exportAll(app: app, window: NSApp.keyWindow) }
                    Spacer()
                    Button("Show Data Folder") { DataTransfer.revealDataFolder(app: app) }
                }
                LabeledContent("Location") {
                    Text(app.paths.dataDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            } header: {
                Text("Your Data")
            } footer: {
                Text("Everything is stored on this Mac — no account or internet connection needed. Exports use an open JSON format you can read, edit, and move between devices.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("PromptVault")
                .font(.system(size: 22, weight: .bold))
            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .foregroundStyle(.secondary)
            Text("Your personal library of AI prompts — one keystroke away.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
