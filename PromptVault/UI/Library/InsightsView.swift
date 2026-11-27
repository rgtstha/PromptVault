import SwiftUI

/// Shown when nothing is selected: library stats, most/recently used prompts, and tips.
struct InsightsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let library = app.library
        let counts = library.counts()
        let mostUsed = library.mostUsed(limit: 6)
        let recent = library.recentlyUsed(limit: 6)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overview")
                        .font(.system(size: 26, weight: .bold))
                    Text("Select a prompt to edit it, or double-click to copy.")
                        .foregroundStyle(.secondary)
                }

                // KPI row
                HStack(spacing: 12) {
                    StatTile(label: "Prompts", value: counts.all, symbol: "text.bubble")
                    StatTile(label: "Favorites", value: counts.favorites, symbol: "star")
                    StatTile(label: "Templates", value: counts.templates, symbol: "doc.on.doc")
                    StatTile(label: "Total copies", value: library.totalUses, symbol: "doc.on.clipboard")
                }

                HStack(alignment: .top, spacing: 14) {
                    InsightCard(title: "Most used") {
                        if mostUsed.isEmpty {
                            placeholder("Copy a prompt to start tracking usage.")
                        } else {
                            let maximum = mostUsed.map(\.usageCount).max() ?? 1
                            ForEach(mostUsed) { prompt in
                                UsageMeterRow(prompt: prompt, maximum: maximum) { open(prompt) }
                            }
                        }
                    }
                    InsightCard(title: "Recently used") {
                        if recent.isEmpty {
                            placeholder("Nothing used yet.")
                        } else {
                            ForEach(recent) { prompt in
                                Button { open(prompt) } label: {
                                    HStack {
                                        Text(prompt.displayTitle)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(prompt.lastUsedAt?.relativeDescription ?? "")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 12))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                InsightCard(title: "Keyboard") {
                    VStack(alignment: .leading, spacing: 7) {
                        shortcutRow(app.settings.hotKey?.displayString ?? "Not set", "Open PromptVault from anywhere")
                        shortcutRow("↑ ↓  ↩", "Choose and copy a prompt in the menu bar")
                        shortcutRow("⌘1 – ⌘9", "Copy one of the first nine results")
                        shortcutRow("⇥", "Preview the selected prompt")
                        shortcutRow("⌘E  ⌘D  ⇧⌘F", "Edit, duplicate, favorite")
                        shortcutRow("⌘[  ⌘]", "Switch collection in the menu bar")
                        shortcutRow("#tag", "Filter search by tag")
                    }
                }

                HStack {
                    Button {
                        app.createPromptInLibrary()
                    } label: {
                        Label("New Prompt", systemImage: "square.and.pencil")
                    }
                    Button {
                        DataTransfer.importPrompts(app: app, window: NSApp.keyWindow)
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func open(_ prompt: Prompt) {
        app.libraryState.searchText = ""
        if case .folder = app.libraryState.scope { app.libraryState.scope = .all }
        app.libraryState.select(prompt, library: app.library)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func shortcutRow(_ keys: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .frame(width: 110, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

/// KPI tile: sentence-case label, a semibold value with compact formatting, and an icon.
private struct StatTile: View {
    let label: String
    let value: Int
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text(value, format: .number.notation(.compactName))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct InsightCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Design.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

/// Ranked meter-list row: name, a single-hue bar on a lighter track of the same hue, and the figure.
/// Text stays in text colors; the bar alone carries the accent hue.
private struct UsageMeterRow: View {
    let prompt: Prompt
    let maximum: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(prompt.displayTitle)
                        .lineLimit(1)
                    Spacer()
                    Text(prompt.usageCount, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                GeometryReader { proxy in
                    let fraction = maximum > 0 ? CGFloat(prompt.usageCount) / CGFloat(maximum) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.accentColor.opacity(0.15))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(6, proxy.size.width * fraction))
                    }
                }
                .frame(height: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(prompt.displayTitle): copied \(prompt.usageCount) time\(prompt.usageCount == 1 ? "" : "s")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(prompt.displayTitle), copied \(prompt.usageCount) times")
        .accessibilityAddTraits(.isButton)
    }
}

struct MultiSelectionView: View {
    @Environment(AppModel.self) private var app
    let prompts: [Prompt]
    @State private var newTag = ""

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(0..<min(3, prompts.count), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12 + Double(index) * 0.06))
                        .frame(width: 64, height: 78)
                        .rotationEffect(.degrees(Double(index - 1) * 7))
                }
                Image(systemName: "text.bubble")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 100)
            Text("\(prompts.count) Prompts Selected")
                .font(.title2.weight(.semibold))

            VStack(spacing: 10) {
                HStack {
                    Button("Add to Favorites") { app.library.setFavorite(prompts, true) }
                    Button("Remove from Favorites") { app.library.setFavorite(prompts, false) }
                }
                HStack {
                    Menu("Move to Folder") {
                        Button("Uncategorized") { app.library.move(prompts, to: nil) }
                        Divider()
                        ForEach(app.library.flattenedFolders()) { node in
                            Button(String(repeating: "   ", count: node.depth) + node.folder.name) {
                                app.library.move(prompts, to: node.folder)
                            }
                        }
                    }
                    .fixedSize()
                    Button("Export…") { DataTransfer.export(prompts: prompts, app: app, window: NSApp.keyWindow) }
                }
                HStack {
                    TextField("Add tag to all", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                        .onSubmit(addTag)
                    Button("Add Tag", action: addTag)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Delete \(prompts.count) Prompts…", role: .destructive) {
                    app.libraryState.promptsPendingDeletion = prompts
                }
                .padding(.top, 6)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        app.library.addTag(tag, to: prompts)
        newTag = ""
    }
}

struct TagManagerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var edits: [String: String] = [:]
    @State private var pendingDelete: TagSummary?

    var body: some View {
        let tags = app.library.allTags
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Tags")
                        .font(.headline)
                    Text("Rename a tag to merge it with another. Tags are independent of folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            Divider()
            if tags.isEmpty {
                EmptyStateView(symbol: "number", title: "No Tags", message: "Add tags to prompts in the editor to group them across folders.")
            } else {
                List {
                    ForEach(tags) { tag in
                        HStack(spacing: 10) {
                            Image(systemName: "number")
                                .foregroundStyle(.secondary)
                            TextField("Tag", text: Binding(
                                get: { edits[tag.id] ?? tag.name },
                                set: { edits[tag.id] = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .onSubmit { commit(tag) }
                            Spacer()
                            Text("\(tag.count) prompt\(tag.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Button {
                                pendingDelete = tag
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Remove this tag from all prompts")
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") {
                    for tag in tags { commit(tag) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 440, height: 480)
        .confirmationDialog("Remove “#\(pendingDelete?.name ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Tag", role: .destructive) {
                if let tag = pendingDelete {
                    if app.libraryState.scope == .tag(tag.name) { app.libraryState.scope = .all }
                    app.library.deleteTag(tag.name)
                }
                pendingDelete = nil
            }
        } message: {
            Text("The tag will be removed from \(pendingDelete?.count ?? 0) prompts. The prompts themselves are kept.")
        }
    }

    private func commit(_ tag: TagSummary) {
        guard let newName = edits[tag.id]?.trimmingCharacters(in: .whitespaces), !newName.isEmpty, newName != tag.name else { return }
        if app.libraryState.scope == .tag(tag.name) {
            app.libraryState.scope = .tag(PromptLibrary.normalizeTags([newName]).first ?? newName)
        }
        app.library.renameTag(tag.name, to: newName)
        edits[tag.id] = nil
    }
}
