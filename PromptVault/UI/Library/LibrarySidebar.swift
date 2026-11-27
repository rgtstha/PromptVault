import SwiftUI

struct LibrarySidebar: View {
    @Environment(AppModel.self) private var app
    @State private var dropTarget: LibraryScope?

    var body: some View {
        let counts = app.library.counts()
        let tags = app.library.allTags

        List(selection: selection) {
            Section("Library") {
                ForEach(LibraryScope.smartCollections, id: \.self) { scope in
                    Label(scope.title, systemImage: scope.symbolName)
                        .badge(counts.count(for: scope))
                        .tag(scope)
                        .modifier(DropHighlight(isTargeted: dropTarget == scope))
                        .dropDestination(for: String.self) { items, _ in
                            handleDrop(items, onto: scope)
                        } isTargeted: { targeted in
                            updateDropTarget(scope, targeted)
                        }
                }
            }

            Section {
                if app.library.rootFolders.isEmpty {
                    Text("No folders yet")
                        .foregroundStyle(.tertiary)
                        .font(.callout)
                }
                OutlineGroup(app.library.rootFolders, children: \.childrenOrNil) { folder in
                    FolderRow(folder: folder, count: counts.folders[folder.id] ?? 0, isDropTarget: dropTarget == .folder(folder.id))
                        .tag(LibraryScope.folder(folder.id))
                        .draggable("folder:\(folder.id.uuidString)")
                        .dropDestination(for: String.self) { items, _ in
                            handleDrop(items, onto: .folder(folder.id))
                        } isTargeted: { targeted in
                            updateDropTarget(.folder(folder.id), targeted)
                        }
                }
            } header: {
                HStack {
                    Text("Folders")
                    Spacer()
                    Button {
                        app.createFolderInLibrary()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Folder (⇧⌘N)")
                    .accessibilityLabel("New folder")
                }
            }

            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags) { tag in
                        Label(tag.name, systemImage: "number")
                            .badge(tag.count)
                            .modifier(DropHighlight(isTargeted: dropTarget == .tag(tag.name)))
                            .tag(LibraryScope.tag(tag.name))
                            .dropDestination(for: String.self) { items, _ in
                                handleDrop(items, onto: .tag(tag.name))
                            } isTargeted: { targeted in
                                updateDropTarget(.tag(tag.name), targeted)
                            }
                            .contextMenu {
                                Button("Manage Tags…") { app.libraryState.showTagManager = true }
                                Divider()
                                Button("Remove Tag from All Prompts", role: .destructive) {
                                    if app.libraryState.scope == .tag(tag.name) { app.libraryState.scope = .all }
                                    app.library.deleteTag(tag.name)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    app.createFolderInLibrary()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Spacer()
                Button {
                    app.libraryState.showTagManager = true
                } label: {
                    Image(systemName: "number")
                }
                .help("Manage Tags")
                .accessibilityLabel("Manage tags")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var selection: Binding<LibraryScope?> {
        Binding(
            get: { app.libraryState.scope },
            set: { newValue in
                if let newValue { app.libraryState.scope = newValue }
            }
        )
    }

    private func updateDropTarget(_ scope: LibraryScope, _ targeted: Bool) {
        if targeted { dropTarget = scope } else if dropTarget == scope { dropTarget = nil }
    }

    /// Handles prompts dropped onto collections/folders and folders dropped onto folders.
    private func handleDrop(_ items: [String], onto scope: LibraryScope) -> Bool {
        let library = app.library
        var handled = false
        var promptIDs: Set<UUID> = []
        for item in items {
            if item.hasPrefix("prompt:"), let id = UUID(uuidString: String(item.dropFirst(7))) {
                promptIDs.insert(id)
            } else if item.hasPrefix("folder:"), let id = UUID(uuidString: String(item.dropFirst(7))),
                      let folder = library.folder(id: id) {
                switch scope {
                case .folder(let targetID):
                    handled = library.move(folder, to: library.folder(id: targetID)) || handled
                case .all, .uncategorized:
                    handled = library.move(folder, to: nil) || handled
                default:
                    break
                }
            }
        }
        // Dragging one selected prompt moves the whole selection.
        if let first = promptIDs.first, promptIDs.count == 1, app.libraryState.selection.contains(first) {
            promptIDs = app.libraryState.selection
        }
        let prompts = promptIDs.compactMap { library.prompt(id: $0) }
        guard !prompts.isEmpty else { return handled }
        switch scope {
        case .folder(let id):
            library.move(prompts, to: library.folder(id: id))
        case .uncategorized:
            library.move(prompts, to: nil)
        case .favorites:
            library.setFavorite(prompts, true)
        case .templates:
            library.setTemplate(prompts, true)
        case .tag(let tag):
            library.addTag(tag, to: prompts)
        case .all, .recent:
            return handled
        }
        return true
    }
}

private struct FolderRow: View {
    @Environment(AppModel.self) private var app
    let folder: Folder
    let count: Int
    let isDropTarget: Bool

    var body: some View {
        Label(folder.name, systemImage: folder.symbolName)
            .badge(count)
            .modifier(DropHighlight(isTargeted: isDropTarget))
            .contextMenu {
                Button("New Prompt in Folder") {
                    app.libraryState.scope = .folder(folder.id)
                    app.createPromptInLibrary()
                }
                Button("New Subfolder") { app.createFolderInLibrary(parent: folder) }
                Divider()
                Button("Rename…") { app.libraryState.folderBeingRenamed = folder }
                Menu("Icon") {
                    ForEach(Folder.symbolChoices, id: \.self) { symbol in
                        Button {
                            app.library.setSymbol(symbol, for: folder)
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                }
                if folder.parent != nil {
                    Button("Move to Top Level") { app.library.move(folder, to: nil) }
                }
                Button("Export Folder…") {
                    let prompts = app.library.prompts(in: .folder(folder.id))
                    DataTransfer.export(prompts: prompts, app: app, window: NSApp.keyWindow)
                }
                .disabled(count == 0)
                Divider()
                Button("Delete Folder…", role: .destructive) {
                    app.libraryState.folderPendingDeletion = folder
                }
            }
    }
}

private struct DropHighlight: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
            )
    }
}
