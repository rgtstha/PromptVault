import SwiftUI

/// Shared top bar for popover sub-screens.
private struct PopoverNavBar<Trailing: View>: View {
    let title: String
    let backTitle: String
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(backTitle)
                }
                .font(.system(size: 12, weight: .medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .help("Back (Esc)")

            Spacer()
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer()
            trailing
        }
        .frame(height: 22)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

struct PopoverPreviewScreen: View {
    @Environment(AppModel.self) private var app
    let prompt: Prompt

    var body: some View {
        let variableCount = prompt.variables.count
        VStack(spacing: 0) {
            PopoverNavBar(title: "", backTitle: "Prompts", onBack: back) {
                HStack(spacing: 12) {
                    Button {
                        app.library.toggleFavorite(prompt)
                    } label: {
                        Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(prompt.isFavorite ? Design.favorite : .secondary)
                    }
                    .help(prompt.isFavorite ? "Remove from Favorites (⇧⌘F)" : "Add to Favorites (⇧⌘F)")
                    .accessibilityLabel(prompt.isFavorite ? "Remove from favorites" : "Add to favorites")

                    Button {
                        app.popover.route = .edit(prompt.id)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Edit (⌘E)")
                    .accessibilityLabel("Edit")

                    Menu {
                        PromptContextMenu(
                            prompt: prompt, context: .popover,
                            onEdit: { app.popover.route = .edit(prompt.id) },
                            onDelete: { app.popover.pendingDeletion = prompt }
                        )
                        Divider()
                        Button("Open in Library") {
                            app.actions.closePopoverForAppUI()
                            app.actions.openLibrary(prompt.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("More actions")
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        PromptGlyph(prompt: prompt, size: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(prompt.displayTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if !prompt.summary.isEmpty {
                                Text(prompt.summary)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    metadata

                    Text(Highlighter.placeholders(in: prompt.content))
                        .font(app.settings.monospacedEditor ? .system(size: 12, design: .monospaced) : .system(size: 12.5))
                        .lineSpacing(2.5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                                .fill(Color.primary.opacity(0.045))
                        )

                    stats
                }
                .padding(14)
            }

            Divider()
            HStack(spacing: 10) {
                if variableCount > 0 {
                    Label("\(variableCount) variable\(variableCount == 1 ? "" : "s") to fill in", systemImage: "curlybraces")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Esc to go back")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    app.use(prompt, from: .popover)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text(variableCount > 0 ? "Fill In & Copy" : "Copy")
                        Text("↩").foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var metadata: some View {
        FlowLayout(spacing: 5, lineSpacing: 5) {
            if let folder = prompt.folder {
                Label(folder.pathString, systemImage: folder.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    .foregroundStyle(Color.accentColor)
            }
            if prompt.isTemplate {
                Label("Template", systemImage: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.purple.opacity(0.13)))
                    .foregroundStyle(.purple)
            }
            ForEach(prompt.tags, id: \.self) { tag in
                TagChip(name: tag)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 4) {
            Text(prompt.usageCount == 0 ? "Never used" : "Used \(prompt.usageCount) time\(prompt.usageCount == 1 ? "" : "s")")
            if let lastUsed = prompt.lastUsedAt {
                Text("·")
                Text("last \(lastUsed.relativeDescription)")
            }
            Text("·")
            Text("updated \(prompt.updatedAt.relativeDescription)")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }

    private func back() {
        app.popover.selectedID = prompt.id
        app.popover.route = .list
    }
}

// MARK: - Fill in variables

struct PopoverFillScreen: View {
    @Environment(AppModel.self) private var app
    let prompt: Prompt

    var body: some View {
        VStack(spacing: 0) {
            PopoverNavBar(title: prompt.displayTitle, backTitle: "Back", onBack: {
                app.popover.selectedID = prompt.id
                app.popover.route = .list
            }) {
                Color.clear.frame(width: 40, height: 1)
            }
            Divider()
            VariableFillForm(prompt: prompt, compact: true, submitRequest: app.popover.fillSubmitRequest) { values in
                app.deliver(prompt, values: values, context: .popover)
            }
        }
    }
}

// MARK: - Quick editor

struct PopoverEditorScreen: View {
    @Environment(AppModel.self) private var app
    let prompt: Prompt?

    @State private var draft: PromptDraft
    @State private var tags: [String]
    @State private var folderID: UUID?
    @State private var isFavorite: Bool
    @State private var isTemplate: Bool
    @State private var showVariables = false
    @State private var confirmDiscard = false
    @FocusState private var titleFocused: Bool

    private let initialDraft: PromptDraft
    private let initialTags: [String]
    private let initialFolderID: UUID?

    init(prompt: Prompt?, seed: NewPromptSeed?) {
        self.prompt = prompt
        let draft: PromptDraft
        if let prompt {
            draft = PromptDraft(prompt)
            initialTags = prompt.tags
            initialFolderID = prompt.folder?.id
            _isFavorite = State(initialValue: prompt.isFavorite)
            _isTemplate = State(initialValue: prompt.isTemplate)
        } else {
            draft = PromptDraft(
                title: seed?.title ?? "", content: seed?.content ?? "",
                summary: seed?.summary ?? "", variables: seed?.variables ?? []
            )
            initialTags = seed?.tags ?? []
            initialFolderID = seed?.folderID
            _isFavorite = State(initialValue: false)
            _isTemplate = State(initialValue: false)
        }
        initialDraft = draft
        _draft = State(initialValue: draft)
        _tags = State(initialValue: initialTags)
        _folderID = State(initialValue: initialFolderID)
    }

    private var isDirty: Bool {
        draft != initialDraft || tags != initialTags || folderID != initialFolderID
            || isFavorite != (prompt?.isFavorite ?? false) || isTemplate != (prompt?.isTemplate ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: cancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("Cancel (Esc)")
                Spacer()
                Text(prompt == nil ? "New Prompt" : "Edit Prompt")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draft.isEmpty)
                    .help("Save (⌘S)")
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .semibold))
                        .focused($titleFocused)
                    TextField("Short description (optional)", text: $draft.summary, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    PromptTextEditor(
                        text: $draft.content,
                        monospaced: app.settings.monospacedEditor,
                        fontSize: 12.5,
                        placeholder: "Write your prompt… use {{variable}} for fill-in fields"
                    )
                    .frame(height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )

                    Text("Tip: **{{name}}** adds a fill-in field. **{{clipboard}}**, **{{date}}** and **{{time}}** fill themselves in.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)

                    let variables = draft.resolvedVariables
                    if !variables.isEmpty {
                        DisclosureGroup(isExpanded: $showVariables) {
                            VariablesEditor(draft: $draft, compact: true)
                                .padding(.top, 6)
                        } label: {
                            Text("Variables (\(variables.count)) — defaults & hints")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }

                    HStack(spacing: 12) {
                        FolderPicker(folderID: $folderID, showsLabel: false)
                        Spacer()
                        Toggle("Favorite", isOn: $isFavorite)
                        Toggle("Template", isOn: $isTemplate)
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                    TagEditor(tags: $tags, suggestions: app.library.allTags.map(\.name))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.045))
                        )

                    if let prompt {
                        Button("Open in Library for version history…") {
                            save()
                            app.actions.closePopoverForAppUI()
                            app.actions.openLibrary(prompt.id)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(14)
            }

            if confirmDiscard {
                Divider()
                HStack {
                    Text("Discard unsaved changes?")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Keep Editing") { confirmDiscard = false }
                    Button("Discard", role: .destructive) { leave() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                .controlSize(.small)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.orange.opacity(0.08))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: confirmDiscard)
        .onAppear {
            if prompt == nil || draft.title.isEmpty { titleFocused = true }
        }
        .onChange(of: app.popover.editorSaveRequest) { _, _ in save() }
        .onChange(of: app.popover.editorCancelRequest) { _, _ in
            if confirmDiscard { confirmDiscard = false } else { cancel() }
        }
    }

    private func cancel() {
        if isDirty { confirmDiscard = true } else { leave() }
    }

    private func leave() {
        app.popover.newPromptSeed = nil
        if let prompt {
            app.popover.route = .preview(prompt.id)
        } else {
            app.popover.route = .list
        }
    }

    private func save() {
        guard !draft.isEmpty else { return }
        let library = app.library
        let folder = folderID.flatMap { library.folder(id: $0) }
        if let prompt {
            library.update(prompt, with: draft)
            library.setTags(tags, for: prompt)
            if prompt.folder?.id != folderID { library.move([prompt], to: folder) }
            if prompt.isFavorite != isFavorite { library.setFavorite([prompt], isFavorite) }
            if prompt.isTemplate != isTemplate { library.setTemplate([prompt], isTemplate) }
            app.popover.route = .preview(prompt.id)
        } else {
            var title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { title = PromptRecord.fallbackTitle(for: draft.content) }
            let created = library.createPrompt(
                title: title, content: draft.content, summary: draft.summary, tags: tags, folder: folder,
                isFavorite: isFavorite, isTemplate: isTemplate, variables: draft.variables
            )
            app.popover.newPromptSeed = nil
            app.popover.searchText = ""
            app.popover.selectedID = created.id
            app.popover.route = .list
            app.showToast(Toast(message: "Saved “\(created.displayTitle)”"), in: .popover)
        }
    }
}
