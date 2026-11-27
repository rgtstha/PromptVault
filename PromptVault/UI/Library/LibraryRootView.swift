import SwiftUI

/// The full management window: sidebar (collections, folders, tags) · prompt list · editor.
struct LibraryRootView: View {
    @Environment(AppModel.self) private var app
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var renameText = ""

    var body: some View {
        @Bindable var state = app.libraryState
        let library = app.library

        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } content: {
            PromptListColumn()
                .navigationSplitViewColumnWidth(min: 270, ideal: 330, max: 520)
        } detail: {
            LibraryDetailColumn()
        }
        .frame(minWidth: 880, minHeight: 540)
        .navigationTitle(windowTitle)
        .navigationSubtitle(windowSubtitle)
        .onAppear { state.syncEditor(with: library) }
        .onChange(of: state.selection) { _, _ in state.syncEditor(with: library) }
        .onChange(of: library.prompts.count) { _, _ in
            // Drop selections of prompts that no longer exist (deleted elsewhere).
            let existing = Set(library.prompts.map(\.id))
            let stale = state.selection.subtracting(existing)
            if !stale.isEmpty { state.removeFromSelection(stale) }
        }
        .sheet(item: fillingPrompt) { prompt in
            LibraryFillSheet(prompt: prompt)
        }
        .sheet(isPresented: $state.showTagManager) {
            TagManagerView()
        }
        .alert("Rename Folder", isPresented: renamingBinding) {
            TextField("Folder name", text: $renameText)
            Button("Rename") {
                if let folder = state.folderBeingRenamed { library.rename(folder, to: renameText) }
                state.folderBeingRenamed = nil
            }
            Button("Cancel", role: .cancel) { state.folderBeingRenamed = nil }
        }
        .onChange(of: state.folderBeingRenamed) { _, folder in
            renameText = folder?.name ?? ""
        }
        .confirmationDialog(
            "Delete “\(state.folderPendingDeletion?.name ?? "")”?",
            isPresented: folderDeletionBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = state.folderPendingDeletion {
                    let removedIDs = Set(folder.selfAndDescendants.map(\.id))
                    if case .folder(let id) = state.scope, removedIDs.contains(id) { state.scope = .all }
                    library.delete(folder)
                }
                state.folderPendingDeletion = nil
            }
        } message: {
            Text(folderDeletionMessage)
        }
        .confirmationDialog(
            promptDeletionTitle,
            isPresented: promptDeletionBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let doomed = state.promptsPendingDeletion
                state.removeFromSelection(Set(doomed.map(\.id)))
                library.delete(doomed)
                state.promptsPendingDeletion = []
            }
        } message: {
            Text("Version history will be deleted too. This can’t be undone.")
        }
        .alert("Something Went Wrong", isPresented: errorBinding) {
            Button("OK") { library.lastError = nil }
        } message: {
            Text(library.lastError?.message ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = app.libraryToast {
                ToastView(toast: toast)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: app.libraryToast)
    }

    // MARK: Title

    private var windowTitle: String {
        switch app.libraryState.scope {
        case .folder(let id): app.library.folder(id: id)?.name ?? "Folder"
        default: app.libraryState.scope.title
        }
    }

    private var windowSubtitle: String {
        let state = app.libraryState
        let count = app.library.prompts(in: state.scope, matching: state.searchText).count
        return state.searchText.isEmpty
            ? "\(count) prompt\(count == 1 ? "" : "s")"
            : "\(count) result\(count == 1 ? "" : "s")"
    }

    // MARK: Bindings

    private var fillingPrompt: Binding<Prompt?> {
        Binding(
            get: { app.libraryState.fillingPromptID.flatMap { app.library.prompt(id: $0) } },
            set: { app.libraryState.fillingPromptID = $0?.id }
        )
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { app.libraryState.folderBeingRenamed != nil },
                set: { if !$0 { app.libraryState.folderBeingRenamed = nil } })
    }

    private var folderDeletionBinding: Binding<Bool> {
        Binding(get: { app.libraryState.folderPendingDeletion != nil },
                set: { if !$0 { app.libraryState.folderPendingDeletion = nil } })
    }

    private var promptDeletionBinding: Binding<Bool> {
        Binding(get: { !app.libraryState.promptsPendingDeletion.isEmpty },
                set: { if !$0 { app.libraryState.promptsPendingDeletion = [] } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { app.library.lastError != nil }, set: { if !$0 { app.library.lastError = nil } })
    }

    private var folderDeletionMessage: String {
        guard let folder = app.libraryState.folderPendingDeletion else { return "" }
        let all = folder.selfAndDescendants
        let promptCount = all.reduce(0) { $0 + ($1.prompts?.count ?? 0) }
        var message = promptCount == 0
            ? "The folder is empty."
            : "\(promptCount) prompt\(promptCount == 1 ? "" : "s") inside will be moved to Uncategorized."
        if all.count > 1 {
            message += " \(all.count - 1) subfolder\(all.count == 2 ? "" : "s") will also be deleted."
        }
        return message
    }

    private var promptDeletionTitle: String {
        let doomed = app.libraryState.promptsPendingDeletion
        if doomed.count == 1, let only = doomed.first { return "Delete “\(only.displayTitle)”?" }
        return "Delete \(doomed.count) prompts?"
    }
}

/// Variable form presented as a sheet when copying from the library.
private struct LibraryFillSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let prompt: Prompt

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fill In Variables")
                        .font(.headline)
                    Text(prompt.displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            VariableFillForm(prompt: prompt, compact: false) { values in
                app.deliver(prompt, values: values, context: .library)
                dismiss()
            }
        }
        .frame(width: 520, height: 520)
    }
}

extension AppModel {
    /// Creates a prompt in the library's current folder/collection and opens it for editing.
    func createPromptInLibrary(title: String = "", content: String = "") {
        let state = libraryState
        state.commitEditor(to: library)
        var folder: Folder?
        var tags: [String] = []
        switch state.scope {
        case .folder(let id): folder = library.folder(id: id)
        case .tag(let tag): tags = [tag]
        case .recent: state.scope = .all
        default: break
        }
        let prompt = library.createPrompt(
            title: title, content: content, tags: tags, folder: folder,
            isFavorite: state.scope == .favorites, isTemplate: state.scope == .templates
        )
        state.searchText = ""
        state.select(prompt, library: library)
        state.titleFocusRequest += 1
    }

    func createFolderInLibrary(parent: Folder? = nil) {
        let folder = library.createFolder(named: "New Folder", parent: parent)
        libraryState.scope = .folder(folder.id)
        libraryState.folderBeingRenamed = folder
    }
}
