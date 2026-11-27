import SwiftUI

struct LibraryDetailColumn: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let state = app.libraryState
        if let session = state.editor, let prompt = app.library.prompt(id: session.promptID) {
            PromptEditorView(prompt: prompt, session: session)
                .id(prompt.id)
        } else if state.selection.count > 1 {
            MultiSelectionView(prompts: state.selection.compactMap { app.library.prompt(id: $0) })
        } else {
            InsightsView()
        }
    }
}

/// Full editor for one prompt. Text fields edit a draft (saved with ⌘S, or automatically when
/// switching prompts or closing the window); organization fields apply immediately.
struct PromptEditorView: View {
    @Environment(AppModel.self) private var app
    let prompt: Prompt
    @Bindable var session: PromptEditorSession
    @FocusState private var titleFocused: Bool

    var body: some View {
        @Bindable var state = app.libraryState
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                organization
                contentSection
                if !session.draft.resolvedVariables.isEmpty {
                    variablesSection
                }
                statsSection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar { toolbarContent }
        .inspector(isPresented: $state.showHistory) {
            VersionHistoryView(prompt: prompt, session: session)
                .inspectorColumnWidth(min: 280, ideal: 330, max: 480)
        }
        .onChange(of: prompt.updatedAt) { _, _ in session.refreshIfUnmodified(from: prompt) }
        .onChange(of: state.titleFocusRequest) { _, _ in titleFocused = true }
        .onAppear {
            if prompt.title.isEmpty && prompt.content.isEmpty { titleFocused = true }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Untitled Prompt", text: $session.draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .bold))
                .focused($titleFocused)
                .accessibilityLabel("Title")
            TextField("Add a short description", text: $session.draft.summary, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1...3)
                .accessibilityLabel("Description")
        }
    }

    private var organization: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                FolderPicker(folderID: Binding(
                    get: { prompt.folder?.id },
                    set: { id in app.library.move([prompt], to: id.flatMap { app.library.folder(id: $0) }) }
                ))
                Toggle(isOn: Binding(get: { prompt.isFavorite }, set: { app.library.setFavorite([prompt], $0) })) {
                    Label("Favorite", systemImage: "star")
                }
                Toggle(isOn: Binding(get: { prompt.isTemplate }, set: { app.library.setTemplate([prompt], $0) })) {
                    Label("Template", systemImage: "doc.on.doc")
                }
                .help("Templates are reusable starting points. Use “New Prompt from Template” to create prompts from them.")
                Spacer()
            }
            .toggleStyle(.button)
            .controlSize(.small)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "number")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TagEditor(
                    tags: Binding(get: { prompt.tags }, set: { app.library.setTags($0, for: prompt) }),
                    suggestions: app.library.allTags.map(\.name)
                )
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Prompt")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(contentStats)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            PromptTextEditor(
                text: $session.draft.content,
                monospaced: app.settings.monospacedEditor,
                fontSize: 13.5,
                placeholder: "Write your prompt. Use {{variable}} for fill-in fields."
            )
            .frame(minHeight: 260, idealHeight: 420)
            .background(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            Text("**{{name}}** creates a fill-in field  ·  **{{clipboard}}**, **{{date}}**, **{{time}}**, **{{weekday}}** fill in automatically  ·  **\\\\{{name}}** stays literal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var variablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variables")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Defaults pre-fill the form shown when you copy this prompt. Optional variables can be left empty.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            VariablesEditor(draft: $session.draft)
        }
    }

    private var statsSection: some View {
        let versions = prompt.versions?.count ?? 0
        return Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                stat("Used", prompt.usageCount == 0 ? "Never" : "\(prompt.usageCount) time\(prompt.usageCount == 1 ? "" : "s")")
                stat("Last used", prompt.lastUsedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
            }
            GridRow {
                stat("Created", prompt.createdAt.formatted(date: .abbreviated, time: .shortened))
                stat("Updated", prompt.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            GridRow {
                stat("Versions", versions == 0 ? "None yet" : "\(versions) saved")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var contentStats: String {
        let content = session.draft.content
        let words = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let variables = session.draft.resolvedVariables.count
        var parts = ["\(words) word\(words == 1 ? "" : "s")", "\(content.count) characters"]
        if variables > 0 { parts.insert("\(variables) variable\(variables == 1 ? "" : "s")", at: 0) }
        return parts.joined(separator: " · ")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if session.hasUnsavedChanges {
                Button {
                    app.libraryState.commitEditor(to: app.library, explicit: true)
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save changes (⌘S). Each save keeps the previous text in Version History.")

                Button {
                    session.draft = session.baseline
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .help("Discard unsaved changes")
            }

            Button {
                save()
                app.use(prompt, from: .library)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help(prompt.hasUserVariables ? "Fill in variables and copy (⇧⌘C)" : "Copy to clipboard (⇧⌘C)")

            Button {
                save()
                app.libraryState.showHistory.toggle()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .keyboardShortcut("y", modifiers: [.command, .option])
            .help("Version History (⌥⌘Y)")

            Menu {
                Button("Duplicate") {
                    save()
                    let copy = app.library.duplicate(prompt)
                    app.libraryState.select(copy, library: app.library)
                }
                if prompt.isTemplate {
                    Button("New Prompt from Template") {
                        let created = app.library.createPrompt(fromTemplate: prompt)
                        app.libraryState.select(created, library: app.library)
                    }
                }
                if prompt.hasUserVariables {
                    Button("Copy Without Filling In") { app.copyTemplateText(prompt, context: .library) }
                }
                Button("Export…") {
                    save()
                    DataTransfer.export(prompts: [prompt], app: app, window: NSApp.keyWindow)
                }
                Divider()
                Button("Reset Usage Statistics") { app.library.resetUsage(of: prompt) }
                    .disabled(prompt.usageCount == 0)
                Divider()
                Button("Delete…", role: .destructive) {
                    app.libraryState.promptsPendingDeletion = [prompt]
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More actions")
        }
    }

    private func save() {
        app.libraryState.commitEditor(to: app.library)
    }
}

// MARK: - Version history

struct VersionHistoryView: View {
    @Environment(AppModel.self) private var app
    let prompt: Prompt
    let session: PromptEditorSession

    enum CompareMode: String, CaseIterable, Identifiable {
        case sinceVersion = "Changes Since"
        case inVersion = "Changes In"
        var id: String { rawValue }
    }

    @State private var selectedID: UUID?
    @State private var mode: CompareMode = .sinceVersion
    @State private var confirmClear = false

    var body: some View {
        let versions = prompt.sortedVersions
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version History")
                        .font(.headline)
                    Text(versions.isEmpty ? "No saved versions" : "\(versions.count) previous version\(versions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !versions.isEmpty {
                    Menu {
                        Button("Clear History…", role: .destructive) { confirmClear = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(14)
            Divider()

            if versions.isEmpty {
                EmptyStateView(
                    symbol: "clock.arrow.circlepath",
                    title: "No Previous Versions",
                    message: "Each time you save a change to the title, description, or text, the previous version is kept here so you can compare or restore it."
                )
            } else {
                List(selection: $selectedID) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        let newer = index == 0 ? (prompt.content, prompt.title) : (versions[index - 1].content, versions[index - 1].title)
                        VersionRow(version: version, nextContent: newer.0)
                            .tag(version.id)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 140, idealHeight: 220, maxHeight: 260)

                Divider()
                if let selectedID, let index = versions.firstIndex(where: { $0.id == selectedID }) {
                    comparison(version: versions[index], previous: versions.indices.contains(index + 1) ? versions[index + 1] : nil)
                } else {
                    Text("Select a version to compare it with the current text.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
            }
        }
        .confirmationDialog("Clear version history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                selectedID = nil
                app.library.clearHistory(of: prompt)
            }
        } message: {
            Text("All \(prompt.versions?.count ?? 0) previous versions of “\(prompt.displayTitle)” will be permanently deleted.")
        }
        .onAppear { selectedID = selectedID ?? versions.first?.id }
    }

    private func comparison(version: PromptVersion, previous: PromptVersion?) -> some View {
        let old: (title: String, content: String)
        let new: (title: String, content: String)
        switch mode {
        case .sinceVersion:
            old = (version.title, version.content)
            new = (prompt.title, prompt.content)
        case .inVersion:
            old = (previous?.title ?? "", previous?.content ?? "")
            new = (version.title, version.content)
        }
        let segments = DiffEngine.diff(old: old.content, new: new.content)
        let stats = DiffEngine.stats(for: segments)

        return VStack(alignment: .leading, spacing: 10) {
            Picker("Compare", selection: $mode) {
                ForEach(CompareMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("“Changes Since” compares this version with the current text. “Changes In” shows what this version changed.")

            HStack(spacing: 8) {
                Label("\(stats.insertedWords) added", systemImage: "plus")
                    .foregroundStyle(.green)
                Label("\(stats.removedWords) removed", systemImage: "minus")
                    .foregroundStyle(.red)
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))
            .labelStyle(.titleAndIcon)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if old.title != new.title {
                        HStack(spacing: 4) {
                            Text("Title:").foregroundStyle(.secondary)
                            Text(old.title.isEmpty ? "—" : old.title).strikethrough().foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption2)
                            Text(new.title)
                        }
                        .font(.system(size: 11.5))
                    }
                    if segments.isEmpty || stats.isEmpty && old.content == new.content {
                        Text(mode == .sinceVersion ? "The text is identical to the current version." : "No text changes in this version.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        DiffText(segments: segments)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))

            HStack {
                Button(role: .destructive) {
                    selectedID = nil
                    app.library.deleteVersion(version)
                } label: {
                    Text("Delete")
                }
                Spacer()
                Button("Restore This Version") {
                    app.libraryState.commitEditor(to: app.library)
                    app.library.restore(version)
                    session.refreshIfUnmodified(from: prompt)
                    selectedID = prompt.sortedVersions.first?.id
                    app.showToast(Toast(message: "Restored version from \(version.savedAt.formatted(date: .abbreviated, time: .shortened))"), in: .library)
                }
                .buttonStyle(.borderedProminent)
                .help("Your current text is saved as a version first, so this can be undone.")
            }
        }
        .padding(14)
    }
}

private struct VersionRow: View {
    let version: PromptVersion
    let nextContent: String

    var body: some View {
        let stats = DiffEngine.stats(for: DiffEngine.diff(old: version.content, new: nextContent))
        VStack(alignment: .leading, spacing: 2) {
            Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 6) {
                Text(version.title.isEmpty ? "Untitled" : version.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !stats.isEmpty {
                    Text("+\(stats.insertedWords) −\(stats.removedWords)")
                        .monospacedDigit()
                        .help("Words changed by the next save")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
