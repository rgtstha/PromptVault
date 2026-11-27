import SwiftUI

struct PopoverListScreen: View {
    @Environment(AppModel.self) private var app
    @FocusState private var searchFocused: Bool
    @State private var hoveredID: UUID?

    var body: some View {
        @Bindable var popover = app.popover
        let results = popover.results
        let selectedID = popover.effectiveSelection(in: results)

        VStack(spacing: 0) {
            header(searchText: $popover.searchText)
            ScopeBar()
            Divider()
            if results.isEmpty {
                emptyState
            } else {
                resultList(results, selectedID: selectedID)
            }
            Divider()
            PopoverFooter(resultCount: results.count)
        }
        .onAppear { searchFocused = true }
        .onChange(of: popover.searchFocusRequest) { _, _ in
            searchFocused = false
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    // MARK: Header

    private func header(searchText: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            TextField("Search PromptVault", text: searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .accessibilityLabel("Search prompts")
            if !searchText.wrappedValue.isEmpty {
                Button {
                    searchText.wrappedValue = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            NewPromptMenu()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: List

    private func resultList(_ results: [Prompt], selectedID: UUID?) -> some View {
        let query = app.popover.searchText
        let scope = app.popover.scope
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, prompt in
                        PopoverPromptRow(
                            prompt: prompt,
                            index: index,
                            isSelected: prompt.id == selectedID,
                            isHovered: prompt.id == hoveredID,
                            query: query,
                            showFolder: !isScope(scope, folderOf: prompt),
                            showLastUsed: scope == .recent
                        ) {
                            app.use(prompt, from: .popover)
                        }
                        .id(prompt.id)
                        .onHover { inside in
                            if inside { hoveredID = prompt.id } else if hoveredID == prompt.id { hoveredID = nil }
                        }
                        .onTapGesture {
                            app.popover.selectedID = prompt.id
                            app.popover.route = .preview(prompt.id)
                        }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            app.use(prompt, from: .popover)
                        })
                        .contextMenu {
                            PromptContextMenu(
                                prompt: prompt, context: .popover,
                                onEdit: { app.popover.route = .edit(prompt.id) },
                                onDelete: { app.popover.pendingDeletion = prompt }
                            )
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func isScope(_ scope: LibraryScope, folderOf prompt: Prompt) -> Bool {
        if case .folder(let id) = scope { return prompt.folder?.id == id }
        return false
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
        let popover = app.popover
        if app.library.prompts.isEmpty {
            EmptyStateView(
                symbol: "text.bubble",
                title: "No prompts yet",
                message: "Save the prompts you use most and copy them in a keystroke.",
                actionTitle: "Create Your First Prompt"
            ) { popover.startNewPrompt() }
        } else if !popover.searchText.isEmpty {
            EmptyStateView(
                symbol: "magnifyingglass",
                title: "No matches",
                message: "Nothing matches “\(popover.searchText)”\(popover.scope == .all ? "" : " in \(scopeName(popover.scope))").",
                actionTitle: popover.scope == .all ? "Create “\(popover.searchText)”" : "Search All Prompts"
            ) {
                if popover.scope == .all {
                    popover.startNewPrompt(seed: NewPromptSeed(title: popover.searchText))
                } else {
                    popover.scope = .all
                }
            }
        } else {
            switch popover.scope {
            case .favorites:
                EmptyStateView(symbol: "star", title: "No favorites", message: "Star prompts you reach for often. Select a prompt and press ⇧⌘F.")
            case .recent:
                EmptyStateView(symbol: "clock", title: "Nothing used yet", message: "Prompts you copy will show up here.")
            case .templates:
                EmptyStateView(symbol: "doc.on.doc", title: "No templates", message: "Save a prompt as a template to reuse it as a starting point.")
            default:
                EmptyStateView(
                    symbol: "folder", title: "Empty", message: "There are no prompts here yet.",
                    actionTitle: "New Prompt"
                ) { popover.startNewPrompt(seed: NewPromptSeed(folderID: app.currentFolderID)) }
            }
        }
    }

    private func scopeName(_ scope: LibraryScope) -> String {
        if case .folder(let id) = scope { return app.library.folder(id: id)?.name ?? "this folder" }
        return scope.title
    }
}

// MARK: - Row

struct PopoverPromptRow: View {
    let prompt: Prompt
    let index: Int
    let isSelected: Bool
    let isHovered: Bool
    let query: String
    let showFolder: Bool
    let showLastUsed: Bool
    let onCopy: () -> Void

    var body: some View {
        let variableCount = TemplateEngine.variableNames(in: prompt.content).count
        HStack(spacing: 10) {
            PromptGlyph(prompt: prompt, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(Highlighter.searchMatches(in: prompt.displayTitle, query: query))
                        .font(.system(size: 13, weight: .medium))
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
                }
                HStack(spacing: 6) {
                    Text(prompt.subtitle)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if showLastUsed, let lastUsed = prompt.lastUsedAt {
                        Text(lastUsed.relativeDescription)
                            .layoutPriority(1)
                    } else if showFolder, let folder = prompt.folder {
                        Label(folder.name, systemImage: folder.symbolName)
                            .labelStyle(.titleAndIcon)
                            .imageScale(.small)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isSelected {
                KeyCap("↩")
                    .transition(.opacity)
            } else if index < 9 && isHovered {
                KeyCap("⌘\(index + 1)")
            }
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelected || isHovered ? Color.accentColor : Color.secondary.opacity(0.55))
            .help(variableCount > 0 ? "Fill in variables and copy" : "Copy to clipboard")
            .accessibilityLabel("Copy \(prompt.displayTitle)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Design.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : (isHovered ? Color.primary.opacity(0.05) : .clear))
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityHint("Opens a preview. Press Return to copy.")
    }
}

// MARK: - Scope bar

private struct ScopeBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let popover = app.popover
        let counts = app.library.counts()
        let rootFolders = app.library.rootFolders
        let selectedNested = nestedSelection(rootFolders: rootFolders)

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(.all, title: "All", symbol: "tray.full", count: counts.all)
                    chip(.favorites, title: "Favorites", symbol: "star.fill", count: counts.favorites)
                    chip(.recent, title: "Recent", symbol: "clock", count: nil)
                    if counts.templates > 0 {
                        chip(.templates, title: "Templates", symbol: "doc.on.doc", count: counts.templates)
                    }
                    if let selectedNested {
                        chip(selectedNested.scope, title: selectedNested.title, symbol: selectedNested.symbol, count: nil)
                    }
                    ForEach(rootFolders) { folder in
                        chip(.folder(folder.id), title: folder.name, symbol: folder.symbolName, count: counts.folders[folder.id])
                    }
                    moreMenu(counts: counts)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            }
            .onChange(of: popover.scope) { _, scope in
                withAnimation { proxy.scrollTo(scope, anchor: .center) }
            }
        }
    }

    private func chip(_ scope: LibraryScope, title: String, symbol: String, count: Int?) -> some View {
        let isSelected = app.popover.scope == scope
        return Button {
            app.popover.scope = scope
            app.popover.selectedID = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .lineLimit(1)
                if let count, count > 0 {
                    Text("\(count)")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06)))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .id(scope)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func moreMenu(counts: ScopeCounts) -> some View {
        Menu {
            Section("Folders") {
                Button {
                    app.popover.scope = .uncategorized
                } label: {
                    Label("Uncategorized (\(counts.uncategorized))", systemImage: "tray")
                }
                ForEach(app.library.flattenedFolders()) { node in
                    Button {
                        app.popover.scope = .folder(node.folder.id)
                    } label: {
                        Label(String(repeating: "   ", count: node.depth) + node.folder.name, systemImage: node.folder.symbolName)
                    }
                }
            }
            let tags = app.library.allTags
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags) { tag in
                        Button("#\(tag.name) (\(tag.count))") { app.popover.scope = .tag(tag.name) }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("All folders and tags (⌘[ and ⌘] to switch)")
    }

    /// A chip for the current scope when it isn't otherwise visible (nested folder, tag, uncategorized).
    private func nestedSelection(rootFolders: [Folder]) -> (scope: LibraryScope, title: String, symbol: String)? {
        switch app.popover.scope {
        case .folder(let id):
            guard !rootFolders.contains(where: { $0.id == id }), let folder = app.library.folder(id: id) else { return nil }
            return (.folder(id), folder.name, folder.symbolName)
        case .tag(let tag):
            return (.tag(tag), "#\(tag)", "number")
        case .uncategorized:
            return (.uncategorized, "Uncategorized", "tray")
        default:
            return nil
        }
    }
}

// MARK: - New prompt menu

private struct NewPromptMenu: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let templates = app.library.prompts(in: .templates, sortedBy: .alphabetical)
        Menu {
            Button {
                app.popover.startNewPrompt(seed: NewPromptSeed(folderID: app.currentFolderID))
            } label: {
                Label("New Prompt", systemImage: "square.and.pencil")
            }
            Button {
                let clipboard = Clipboard.currentString()
                app.popover.startNewPrompt(seed: NewPromptSeed(
                    title: PromptRecord.fallbackTitle(for: clipboard), content: clipboard, folderID: app.currentFolderID
                ))
            } label: {
                Label("New from Clipboard", systemImage: "doc.on.clipboard")
            }
            .disabled(Clipboard.currentString().isEmpty)
            if !templates.isEmpty {
                Menu {
                    ForEach(templates) { template in
                        Button(template.displayTitle) {
                            app.popover.startNewPrompt(seed: NewPromptSeed(
                                title: template.displayTitle, content: template.content, summary: template.summary,
                                tags: template.tags, folderID: template.folder?.id, variables: template.variables
                            ))
                        }
                    }
                } label: {
                    Label("New from Template", systemImage: "doc.on.doc")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
        } primaryAction: {
            app.popover.startNewPrompt(seed: NewPromptSeed(folderID: app.currentFolderID))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("New prompt (⌘N)")
        .accessibilityLabel("New prompt")
    }
}

// MARK: - Footer

private struct PopoverFooter: View {
    @Environment(AppModel.self) private var app
    let resultCount: Int

    var body: some View {
        @Bindable var settings = app.settings
        HStack(spacing: 8) {
            Button {
                let id = app.popover.selectedPrompt?.id
                app.actions.closePopoverForAppUI()
                app.actions.openLibrary(id)
            } label: {
                Label("Open Library", systemImage: "books.vertical")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open the full library (⌘L)")

            Spacer()

            HStack(spacing: 4) {
                KeyCap("↩")
                Text("copy")
                KeyCap("⇥")
                Text("preview")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)

            Spacer()

            Menu {
                Picker("Sort By", selection: $settings.popoverSort) {
                    ForEach(PromptSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                Toggle("Show Favorites First", isOn: $settings.favoritesFirst)
                Divider()
                Button("Import Prompts…") {
                    app.actions.closePopoverForAppUI()
                    DataTransfer.importPrompts(app: app, window: nil)
                }
                Button("Settings…") {
                    app.actions.closePopoverForAppUI()
                    app.actions.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                Divider()
                Button("Quit PromptVault") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Options")
            .accessibilityLabel("Options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
