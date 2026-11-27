import Foundation

/// Metadata for a `{{placeholder}}` inside a prompt.
nonisolated struct PromptVariable: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var defaultValue: String
    var description: String
    var isRequired: Bool

    var id: String { name }

    init(name: String, defaultValue: String = "", description: String = "", isRequired: Bool = true) {
        self.name = name
        self.defaultValue = defaultValue
        self.description = description
        self.isRequired = isRequired
    }

    private enum CodingKeys: String, CodingKey {
        case name, defaultValue, description, isRequired
    }

    /// Lenient decoding so hand-written JSON only needs a `name`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? true
    }
}
