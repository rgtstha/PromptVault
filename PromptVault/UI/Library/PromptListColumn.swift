import SwiftUI

struct PromptListColumn: View {
    @Environment(AppModel.self) private var app
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var state = app.libraryState
        @Bindable var settings = app.settings
        let prompts = app.library.prompts(in: state.scope, matching: state.searchText, sortedBy: settings.librarySort)

        Group {
            if prompts.isEmpty {
                emptyState
            } else {
                List(selection: $state.selection) {
                    ForEach(prompts) { prompt in
                        LibraryPromptRow(prompt: prompt, query: state.searchText, scope: state.scope)
                            .tag(prompt.id)
                            .draggable("prompt:\(prompt.id.uuidString)")
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    menu(for: ids)
                } primaryAction: { ids in
                    if ids.count == 1, let id = ids.first, let prompt = app.library.prompt(id: id) {
                        app.use(prompt, from: .library)
                    }
                }
                .onDeleteCommand {
                    state.promptsPendingDeletion = selectedPrompts
                }
            }
        }
        .searchable(text: $state.searchText, placement: .toolbar, prompt: "Search prompts or #tag")
        .modifier(SearchFocusModifier(isFocused: $searchFocused))
        .onChange(of: state.searchFocusRequest) { _, _ in searchFocused = true }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Sort By", selection: $settings.librarySort) {
                        ForEach(PromptSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort prompts")
                .disabled(state.scope == .recent)

                Button {
                    app.createPromptInLibrary()
                } label: {
                    Label("New Prompt", systemImage: "square.and.pencil")
                }
                .help("New Prompt (⌘N)")
            }
        }
    }

    private var selectedPrompts: [Prompt] {
        app.libraryState.selection.compactMap { app.library.prompt(id: $0) }
    }

    @ViewBuilder
    private func menu(for ids: Set<UUID>) -> some View {
        let prompts = ids.compactMap { app.library.prompt(id: $0) }
        if prompts.count == 1, let prompt = prompts.first {
            PromptContextMenu(
                prompt: prompt, context: .library,
                onEdit: { app.libraryState.select(prompt, library: app.library) },
                onDelete: { app.libraryState.promptsPendingDeletion = [prompt] }
            )
            Divider()
            Button("Export…") { DataTransfer.export(prompts: [prompt], app: app, window: NSApp.keyWindow) }
        } else if prompts.count > 1 {
            BulkActionsMenu(prompts: prompts)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let state = app.libraryState
        if !state.searchText.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass", title: "No Results",
                message: "No prompts match “\(state.searchText)”. Search looks in titles, descriptions, content, and tags (use #tag to filter).",
                actionTitle: state.scope == .all ? nil : "Search All Prompts"
            ) { state.scope = .all }
        } else if app.library.prompts.isEmpty {
            EmptyStateView(
                symbol: "text.bubble", title: "Your library is empty",
                message: "Create a prompt or import a collection from a JSON file.",
                actionTitle: "New Prompt"
            ) { app.createPromptInLibrary() }
        } else {
            switch state.scope {
            case .favorites:
                EmptyStateView(symbol: "star", title: "No Favorites", message: "Star the prompts you use most — they appear first in the menu bar.")
            case .recent:
                EmptyStateView(symbol: "clock", title: "Nothing Used Yet", message: "Prompts you copy show up here, most recent first.")
            case .templates:
                EmptyStateView(
                    symbol: "doc.on.doc", title: "No Templates",
                    message: "Templates are reusable starting points with predefined variables. Mark any prompt as a template, or create one here.",
                    actionTitle: "New Template"
                ) { app.createPromptInLibrary() }
            case .uncategorized:
                EmptyStateView(symbol: "tray", title: "All Organized", message: "Every prompt is in a folder.")
            default:
                EmptyStateView(
                    symbol: "folder", title: "No Prompts Here", message: "Create a prompt, or drag prompts onto this folder in the sidebar.",
                    actionTitle: "New Prompt"
                ) { app.createPromptInLibrary() }
            }
        }
    }
}

struct BulkActionsMenu: View {
    @Environment(AppModel.self) private var app
    let prompts: [Prompt]

    var body: some View {
        Button("Add \(prompts.count) to Favorites") { app.library.setFavorite(prompts, true) }
        Button("Remove from Favorites") { app.library.setFavorite(prompts, false) }
        MoveToFolderMenu(prompts: prompts)
        Divider()
        Button("Export \(prompts.count) Prompts…") { DataTransfer.export(prompts: prompts, app: app, window: NSApp.keyWindow) }
        Divider()
        Button("Delete \(prompts.count) Prompts…", role: .destructive) {
            app.libraryState.promptsPendingDeletion = prompts
        }
    }
}

struct LibraryPromptRow: View {
    let prompt: Prompt
    let query: String
    let scope: LibraryScope

    var body: some View {
        let variableCount = TemplateEngine.variableNames(in: prompt.content).count
        HStack(alignment: .top, spacing: 10) {
            PromptGlyph(prompt: prompt, size: 28)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(Highlighter.searchMatches(in: prompt.displayTitle, query: query))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if prompt.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Design.favorite)
                            .accessibilityLabel("Favorite")
                    }
                    if variableCount > 0 {
                        VariableBadge(count: variableCount)
                    }
                    Spacer(minLength: 4)
                    Text(trailingDate)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(prompt.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let folder = prompt.folder, scope != .folder(folder.id) {
                        Label(folder.name, systemImage: folder.symbolName)
                            .lineLimit(1)
                    }
                    if !prompt.tags.isEmpty {
                        Text(prompt.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if prompt.usageCount > 0 {
                        Label("\(prompt.usageCount)", systemImage: "doc.on.doc")
                            .help("Copied \(prompt.usageCount) time\(prompt.usageCount == 1 ? "" : "s")")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
                .imageScale(.small)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var trailingDate: String {
        if scope == .recent, let lastUsed = prompt.lastUsedAt { return lastUsed.relativeDescription }
        return prompt.updatedAt.relativeDescription
    }
}
