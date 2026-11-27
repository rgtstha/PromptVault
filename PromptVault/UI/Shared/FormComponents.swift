import SwiftUI

/// Token-style tag editor with suggestions from existing tags.
struct TagEditor: View {
    @Binding var tags: [String]
    var suggestions: [String] = []
    var placeholder = "Add tag"

    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var matchingSuggestions: [String] {
        let typed = input.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let current = Set(tags.map { $0.lowercased() })
        return suggestions
            .filter { !current.contains($0.lowercased()) }
            .filter { typed.isEmpty || $0.lowercased().hasPrefix(typed) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(name: tag) { tags.removeAll { $0 == tag } }
                }
                TextField(placeholder, text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(minWidth: 70, maxWidth: 140)
                    .focused($isFocused)
                    .onSubmit(commitInput)
                    .onChange(of: input) { _, newValue in
                        if newValue.contains(",") { commitInput() }
                    }
                    .onKeyPress(.delete) {
                        guard input.isEmpty, !tags.isEmpty else { return .ignored }
                        tags.removeLast()
                        return .handled
                    }
            }
            if isFocused && !matchingSuggestions.isEmpty {
                HStack(spacing: 4) {
                    Text("Suggestions:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    ForEach(matchingSuggestions, id: \.self) { suggestion in
                        Button("#\(suggestion)") {
                            tags = PromptLibrary.normalizeTags(tags + [suggestion])
                            input = ""
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    private func commitInput() {
        let pieces = input.split(separator: ",").map(String.init)
        input = ""
        guard !pieces.isEmpty else { return }
        tags = PromptLibrary.normalizeTags(tags + pieces)
    }
}

/// Menu-style picker for a prompt's folder (`nil` = Uncategorized).
struct FolderPicker: View {
    @Environment(AppModel.self) private var app
    @Binding var folderID: UUID?
    var showsLabel = true

    var body: some View {
        Picker(selection: $folderID) {
            Label("Uncategorized", systemImage: "tray").tag(UUID?.none)
            if !app.library.folders.isEmpty {
                Divider()
            }
            ForEach(app.library.flattenedFolders()) { node in
                Label {
                    Text(String(repeating: "      ", count: node.depth) + node.folder.name)
                } icon: {
                    Image(systemName: node.folder.symbolName)
                }
                .tag(Optional(node.folder.id))
            }
        } label: {
            if showsLabel { Text("Folder") }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// "Move to" menu content listing every folder.
struct MoveToFolderMenu: View {
    @Environment(AppModel.self) private var app
    let prompts: [Prompt]

    var body: some View {
        Menu {
            Button {
                app.library.move(prompts, to: nil)
            } label: {
                Label("Uncategorized", systemImage: "tray")
            }
            Divider()
            ForEach(app.library.flattenedFolders()) { node in
                Button {
                    app.library.move(prompts, to: node.folder)
                } label: {
                    Label(String(repeating: "   ", count: node.depth) + node.folder.name, systemImage: node.folder.symbolName)
                }
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }
    }
}

/// Edits defaults, descriptions, and required flags for the variables found in a prompt.
struct VariablesEditor: View {
    @Binding var draft: PromptDraft
    var compact = false

    var body: some View {
        let variables = draft.resolvedVariables
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            ForEach(variables) { variable in
                VariableMetadataRow(variable: variable, compact: compact) { updated in
                    draft.setVariable(updated)
                }
            }
        }
    }
}

private struct VariableMetadataRow: View {
    let variable: PromptVariable
    var compact: Bool
    let onChange: (PromptVariable) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("{{\(variable.name)}}")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Toggle("Required", isOn: binding(\.isRequired))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }
            if compact {
                TextField("Default value", text: binding(\.defaultValue))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                TextField("Hint shown when filling in", text: binding(\.description))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            } else {
                HStack(spacing: 8) {
                    TextField("Default value", text: binding(\.defaultValue))
                        .textFieldStyle(.roundedBorder)
                    TextField("Hint shown when filling in", text: binding(\.description))
                        .textFieldStyle(.roundedBorder)
                }
                .font(.system(size: 12))
            }
        }
        .padding(compact ? 8 : 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PromptVariable, Value>) -> Binding<Value> {
        Binding(
            get: { variable[keyPath: keyPath] },
            set: { newValue in
                var updated = variable
                updated[keyPath: keyPath] = newValue
                onChange(updated)
            }
        )
    }
}

/// The fill-in form shown before copying a prompt that has variables.
struct VariableFillForm: View {
    @Environment(AppModel.self) private var app
    let prompt: Prompt
    var compact = true
    /// Incremented externally (⌘↩) to submit.
    var submitRequest = 0
    let onSubmit: ([String: String]) -> Void

    @State private var values: [String: String] = [:]
    @State private var showPreview = false
    @State private var attemptedSubmit = false
    @State private var didSubmit = false
    @FocusState private var focusedField: String?

    private var variables: [PromptVariable] { prompt.variables }

    private var missing: [String] {
        TemplateEngine.missingRequired(variables, values: values)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(variables) { variable in
                        fieldView(for: variable)
                    }
                    if TemplateEngine.usesBuiltIns(prompt.content) {
                        Label("Built-in values like {{clipboard}} and {{date}} are filled in automatically.", systemImage: "wand.and.stars")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    DisclosureGroup(isExpanded: $showPreview) {
                        Text(previewText)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                            .padding(.top, 6)
                    } label: {
                        Text("Preview")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .padding(compact ? 14 : 20)
            }

            Divider()
            HStack(spacing: 10) {
                if attemptedSubmit && !missing.isEmpty {
                    Label("Fill in \(missing.count == 1 ? "1 required field" : "\(missing.count) required fields")", systemImage: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else {
                    Button("Reset to Defaults") { resetToDefaults() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    submit()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, 10)
        }
        .onAppear {
            loadInitialValues()
            focusedField = variables.first(where: { (values[$0.name] ?? "").isEmpty })?.name ?? variables.first?.name
        }
        .onChange(of: submitRequest) { _, _ in submit() }
    }

    @ViewBuilder
    private func fieldView(for variable: PromptVariable) -> some View {
        let isMissing = attemptedSubmit && missing.contains(variable.name)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(variable.name.replacingOccurrences(of: "_", with: " ").capitalizedFirstLetter)
                    .font(.system(size: 12, weight: .semibold))
                if variable.isRequired {
                    Text("*").foregroundStyle(.secondary).accessibilityLabel("required")
                } else {
                    Text("optional").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            TextField(
                variable.defaultValue.isEmpty ? "Enter \(variable.name.replacingOccurrences(of: "_", with: " "))…" : variable.defaultValue,
                text: Binding(get: { values[variable.name] ?? "" }, set: { values[variable.name] = $0 }),
                axis: .vertical
            )
            .lineLimit(1...6)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: variable.name)
            .onSubmit(submit)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.orange, lineWidth: isMissing ? 1.5 : 0)
            )
            if !variable.description.isEmpty {
                Text(variable.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewText: AttributedString {
        let rendered = app.render(prompt, values: effectiveValues)
        return Highlighter.placeholders(in: rendered)
    }

    /// Values with empty fields replaced by defaults.
    private var effectiveValues: [String: String] {
        var result: [String: String] = [:]
        for variable in variables {
            let value = values[variable.name] ?? ""
            result[variable.name] = value.isEmpty ? variable.defaultValue : value
        }
        return result
    }

    private func loadInitialValues() {
        let remembered = app.settings.rememberVariableValues ? prompt.lastVariableValues : [:]
        var initial: [String: String] = [:]
        for variable in variables {
            initial[variable.name] = remembered[variable.name] ?? variable.defaultValue
        }
        values = initial
    }

    private func resetToDefaults() {
        values = Dictionary(uniqueKeysWithValues: variables.map { ($0.name, $0.defaultValue) })
    }

    private func submit() {
        guard !didSubmit else { return }
        attemptedSubmit = true
        if let first = missing.first {
            focusedField = first
            NSSound.beep()
            return
        }
        didSubmit = true
        onSubmit(effectiveValues)
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
