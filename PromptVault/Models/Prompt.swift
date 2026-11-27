import Foundation
import SwiftData

/// A saved AI prompt.
///
/// Every stored property has a default value and every relationship is optional so the
/// schema stays compatible with a future CloudKit-backed `ModelConfiguration`.
@Model
final class Prompt {
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    /// The short description shown in lists. Named `summary` to avoid clashing with
    /// `CustomStringConvertible.description`; exported as `"description"` in JSON.
    var summary: String = ""
    var tags: [String] = []
    var isFavorite: Bool = false
    /// Templates are blueprints that new prompts can be created from.
    var isTemplate: Bool = false
    /// JSON-encoded `[PromptVariable]` metadata (defaults, descriptions, required flags).
    var variablesData: Data? = nil
    /// JSON-encoded `[String: String]` of the values used the last time the prompt was filled in.
    var lastVariableValuesData: Data? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var usageCount: Int = 0
    var lastUsedAt: Date? = nil

    @Relationship(deleteRule: .nullify, inverse: \Folder.prompts)
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \PromptVersion.prompt)
    var versions: [PromptVersion]? = []

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        summary: String = "",
        tags: [String] = [],
        isFavorite: Bool = false,
        isTemplate: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.summary = summary
        self.tags = tags
        self.isFavorite = isFavorite
        self.isTemplate = isTemplate
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Prompt {
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Prompt" : trimmed
    }

    /// Variable metadata, merged with the placeholders that actually appear in `content`.
    var variables: [PromptVariable] {
        get { TemplateEngine.resolveVariables(in: content, stored: storedVariables) }
        set { storedVariables = newValue }
    }

    /// The raw stored variable metadata (may contain entries for placeholders no longer in the content).
    var storedVariables: [PromptVariable] {
        get {
            guard let variablesData else { return [] }
            return (try? JSONDecoder().decode([PromptVariable].self, from: variablesData)) ?? []
        }
        set {
            variablesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    var lastVariableValues: [String: String] {
        get {
            guard let lastVariableValuesData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: lastVariableValuesData)) ?? [:]
        }
        set {
            lastVariableValuesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    /// True for a freshly created prompt that has no text, tags, or usage.
    var isBlank: Bool {
        title.isEmpty && content.isEmpty && summary.isEmpty && tags.isEmpty
            && usageCount == 0 && (versions ?? []).isEmpty
    }

    /// Whether using the prompt requires the user to fill in a form.
    var hasUserVariables: Bool {
        !TemplateEngine.variableNames(in: content).isEmpty
    }

    /// Versions, newest first.
    var sortedVersions: [PromptVersion] {
        (versions ?? []).sorted { $0.savedAt > $1.savedAt }
    }

    /// Text shown under the title in lists: the description, or the start of the content.
    var subtitle: String {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty { return trimmedSummary }
        let collapsed = content
            .prefix(220)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }
}
