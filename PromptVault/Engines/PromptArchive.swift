import Foundation

/// The documented, portable JSON format used for export, import, and backups.
/// See `docs/JSON-FORMAT.md`.
nonisolated struct PromptArchive: Codable, Sendable {
    static let formatIdentifier = "promptvault.archive"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var generator: String?
    var folders: [FolderRecord]
    var prompts: [PromptRecord]

    init(exportedAt: Date = .now, generator: String? = nil, folders: [FolderRecord], prompts: [PromptRecord]) {
        self.format = Self.formatIdentifier
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.generator = generator
        self.folders = folders
        self.prompts = prompts
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, exportedAt, generator, folders, prompts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? Self.formatIdentifier
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        generator = try container.decodeIfPresent(String.self, forKey: .generator)
        folders = try container.decodeIfPresent([FolderRecord].self, forKey: .folders) ?? []
        prompts = try container.decodeIfPresent([PromptRecord].self, forKey: .prompts) ?? []
    }
}

nonisolated struct FolderRecord: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var symbol: String
    var parentId: UUID?
    var sortIndex: Int

    init(id: UUID, name: String, symbol: String, parentId: UUID?, sortIndex: Int) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.parentId = parentId
        self.sortIndex = sortIndex
    }

    private enum CodingKeys: String, CodingKey { case id, name, symbol, parentId, sortIndex }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "folder"
        parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
        sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
    }
}

nonisolated struct PromptRecord: Codable, Hashable, Sendable {
    var id: UUID?
    var title: String
    var content: String
    var description: String
    /// Reference to a folder in the archive's `folders` array.
    var folderId: UUID?
    /// Human-readable folder path such as `"Coding / Code Review"`. Used when `folderId` is
    /// absent or unknown, which makes hand-written files easy to import.
    var folder: String?
    var tags: [String]
    var isFavorite: Bool
    var isTemplate: Bool
    var variables: [PromptVariable]
    var createdAt: Date?
    var updatedAt: Date?
    var usageCount: Int
    var lastUsedAt: Date?
    var versions: [VersionRecord]

    init(
        id: UUID?, title: String, content: String, description: String, folderId: UUID?, folder: String?,
        tags: [String], isFavorite: Bool, isTemplate: Bool, variables: [PromptVariable],
        createdAt: Date?, updatedAt: Date?, usageCount: Int, lastUsedAt: Date?, versions: [VersionRecord]
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.description = description
        self.folderId = folderId
        self.folder = folder
        self.tags = tags
        self.isFavorite = isFavorite
        self.isTemplate = isTemplate
        self.variables = variables
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
        self.versions = versions
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, description, folderId, folder, tags, isFavorite, isTemplate
        case variables, createdAt, updatedAt, usageCount, lastUsedAt, versions
        // Accepted aliases for hand-written files
        case prompt, text, name, summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(UUID.self, forKey: .id)
        content = try container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .prompt)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? ""
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        title = decodedTitle ?? PromptRecord.fallbackTitle(for: content)
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .summary)
            ?? ""
        folderId = try? container.decodeIfPresent(UUID.self, forKey: .folderId)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isTemplate = try container.decodeIfPresent(Bool.self, forKey: .isTemplate) ?? false
        variables = try container.decodeIfPresent([PromptVariable].self, forKey: .variables) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        versions = try container.decodeIfPresent([VersionRecord].self, forKey: .versions) ?? []
        if title.isEmpty && content.isEmpty {
            throw DecodingError.dataCorruptedError(
                forKey: .content, in: container,
                debugDescription: "A prompt needs at least a title or content."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(folderId, forKey: .folderId)
        try container.encodeIfPresent(folder, forKey: .folder)
        try container.encode(tags, forKey: .tags)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(isTemplate, forKey: .isTemplate)
        try container.encode(variables, forKey: .variables)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(usageCount, forKey: .usageCount)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(versions, forKey: .versions)
    }

    static func fallbackTitle(for content: String) -> String {
        let firstLine = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 60 ? String(trimmed.prefix(57)) + "…" : trimmed
    }
}

nonisolated struct VersionRecord: Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var content: String
    var description: String
    var variables: [PromptVariable]
    var savedAt: Date

    init(id: UUID, title: String, content: String, description: String, variables: [PromptVariable], savedAt: Date) {
        self.id = id
        self.title = title
        self.content = content
        self.description = description
        self.variables = variables
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey { case id, title, content, description, variables, savedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        variables = try container.decodeIfPresent([PromptVariable].self, forKey: .variables) ?? []
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .now
    }
}

nonisolated enum PromptArchiveError: LocalizedError, Equatable {
    case unrecognizedFormat
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            "The file isn’t a PromptVault archive or a JSON list of prompts."
        case .unsupportedVersion(let version):
            "This archive was created by a newer version of PromptVault (format version \(version))."
        }
    }
}

nonisolated enum PromptArchiveCodec {
    static func encode(_ archive: PromptArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Decodes a full archive, a bare JSON array of prompts, or a single prompt object.
    static func decode(_ data: Data) throws -> PromptArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDate)

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw PromptArchiveError.unrecognizedFormat
        }

        if let object = json as? [String: Any] {
            if object["prompts"] != nil || object["format"] != nil {
                let archive = try decoder.decode(PromptArchive.self, from: data)
                if archive.version > PromptArchive.currentVersion {
                    throw PromptArchiveError.unsupportedVersion(archive.version)
                }
                return archive
            }
            if object["content"] != nil || object["prompt"] != nil || object["text"] != nil {
                let record = try decoder.decode(PromptRecord.self, from: data)
                return PromptArchive(folders: [], prompts: [record])
            }
            throw PromptArchiveError.unrecognizedFormat
        }

        if json is [Any] {
            let records = try decoder.decode([PromptRecord].self, from: data)
            return PromptArchive(folders: [], prompts: records)
        }

        throw PromptArchiveError.unrecognizedFormat
    }

    @Sendable private static func decodeDate(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: seconds)
        }
        let string = try container.decode(String.self)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        if let date = dateOnly.date(from: string) { return date }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
    }
}
