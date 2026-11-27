import SwiftUI

/// Root of the menu bar popover. Routes between list, preview, fill-in form, and editor.
struct PopoverRootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let popover = app.popover
        ZStack {
            switch popover.route {
            case .list:
                PopoverListScreen()
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
            case .preview(let id):
                if let prompt = app.library.prompt(id: id) {
                    PopoverPreviewScreen(prompt: prompt)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    missingPrompt
                }
            case .fill(let id):
                if let prompt = app.library.prompt(id: id) {
                    PopoverFillScreen(prompt: prompt)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    missingPrompt
                }
            case .edit(let id):
                PopoverEditorScreen(prompt: id.flatMap { app.library.prompt(id: $0) }, seed: popover.newPromptSeed)
                    .id(id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: Design.popoverSize.width, height: Design.popoverSize.height)
        .animation(.snappy(duration: 0.22), value: popover.route)
        .overlay(alignment: .bottom) {
            if let toast = app.popoverToast {
                ToastView(toast: toast)
                    .padding(.bottom, 52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: app.popoverToast)
        .overlay {
            if let pending = popover.pendingDeletion {
                DeleteConfirmationOverlay(prompt: pending)
            }
        }
    }

    private var missingPrompt: some View {
        EmptyStateView(symbol: "questionmark.folder", title: "Prompt not found", message: "It may have been deleted.", actionTitle: "Back to List") {
            app.popover.route = .list
        }
    }
}

private struct DeleteConfirmationOverlay: View {
    @Environment(AppModel.self) private var app
    let prompt: Prompt

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .onTapGesture { app.popover.pendingDeletion = nil }
            VStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 22))
                    .foregroundStyle(.red)
                Text("Delete “\(prompt.displayTitle)”?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Its version history will be deleted too. This can’t be undone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Cancel") { app.popover.pendingDeletion = nil }
                    Button("Delete", role: .destructive) {
                        app.library.delete([prompt])
                        app.popover.pendingDeletion = nil
                        app.popover.route = .list
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(width: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 6)
        }
        .transition(.opacity)
    }
}

/// Context menu actions shared by popover and library rows.
struct PromptContextMenu: View {
    @Environment(AppModel.self) private var app
    let prompt: Prompt
    let context: UseContext
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button {
            app.use(prompt, from: context)
        } label: {
            Label(prompt.hasUserVariables ? "Fill In & Copy" : "Copy", systemImage: "doc.on.doc")
        }
        if prompt.hasUserVariables {
            Button {
                app.copyTemplateText(prompt, context: context)
            } label: {
                Label("Copy Without Filling In", systemImage: "curlybraces")
            }
        }
        Button {
            onEdit()
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            let copy = app.library.duplicate(prompt)
            if context == .popover { app.popover.selectedID = copy.id }
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        if prompt.isTemplate {
            Button {
                let created = app.library.createPrompt(fromTemplate: prompt)
                switch context {
                case .popover: app.popover.route = .edit(created.id)
                case .library: app.libraryState.select(created, library: app.library)
                }
            } label: {
                Label("New Prompt from Template", systemImage: "doc.badge.plus")
            }
        }
        Divider()
        Button {
            app.library.toggleFavorite(prompt)
        } label: {
            Label(prompt.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: prompt.isFavorite ? "star.slash" : "star")
        }
        Button {
            app.library.setTemplate([prompt], !prompt.isTemplate)
        } label: {
            Label(prompt.isTemplate ? "Convert to Regular Prompt" : "Save as Template", systemImage: "doc.on.doc")
        }
        MoveToFolderMenu(prompts: [prompt])
        Divider()
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete…", systemImage: "trash")
        }
    }
}
