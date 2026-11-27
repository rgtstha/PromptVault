import Foundation

/// Parses and renders `{{variable}}` placeholders.
///
/// Syntax:
/// - `{{name}}` — a user variable. Names start with a letter or underscore and may contain
///   letters, digits, spaces, `_`, `-` and `.` (surrounding whitespace is ignored).
/// - Built-in variables are filled automatically: `{{clipboard}}`, `{{date}}`, `{{time}}`,
///   `{{datetime}}`, `{{weekday}}`, `{{year}}`.
/// - `\{{name}}` is an escaped placeholder and is rendered literally as `{{name}}`.
nonisolated enum TemplateEngine {
    struct Placeholder: Hashable, Sendable {
        let name: String
        /// Range of the whole `{{…}}` token in the source string.
        let range: Range<String.Index>
        let isBuiltIn: Bool
    }

    static let builtInNames: [String] = ["clipboard", "date", "time", "datetime", "weekday", "year"]

    private static let namePattern = #"[\p{L}_][\p{L}\p{N}_\-. ]*?"#
    private static let placeholderRegex = try! NSRegularExpression(
        pattern: #"(?<!\\)\{\{\s*("# + namePattern + #")\s*\}\}"#
    )
    private static let escapedRegex = try! NSRegularExpression(
        pattern: #"\\(\{\{\s*"# + namePattern + #"\s*\}\})"#
    )

    static func isBuiltIn(_ name: String) -> Bool {
        builtInNames.contains(name.lowercased())
    }

    /// Every placeholder occurrence, in order of appearance.
    static func placeholders(in text: String) -> [Placeholder] {
        guard text.contains("{{") else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        return placeholderRegex.matches(in: text, range: nsRange).compactMap { match in
            guard let whole = Range(match.range, in: text),
                  let nameRange = Range(match.range(at: 1), in: text) else { return nil }
            let name = text[nameRange].trimmingCharacters(in: .whitespaces)
            return Placeholder(name: name, range: whole, isBuiltIn: isBuiltIn(name))
        }
    }

    /// Unique user-variable names (built-ins excluded), in order of first appearance.
    static func variableNames(in text: String) -> [String] {
        var seen: Set<String> = []
        return placeholders(in: text).compactMap { placeholder in
            guard !placeholder.isBuiltIn, seen.insert(placeholder.name).inserted else { return nil }
            return placeholder.name
        }
    }

    static func usesBuiltIns(_ text: String) -> Bool {
        placeholders(in: text).contains(where: \.isBuiltIn)
    }

    /// Merges the placeholders present in `content` with stored metadata. Variables keep the
    /// order in which they first appear; placeholders without metadata get defaults.
    static func resolveVariables(in content: String, stored: [PromptVariable]) -> [PromptVariable] {
        let metadata = Dictionary(stored.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return variableNames(in: content).map { metadata[$0] ?? PromptVariable(name: $0) }
    }

    /// Names of required variables whose value is empty (after applying defaults).
    static func missingRequired(_ variables: [PromptVariable], values: [String: String]) -> [String] {
        variables.compactMap { variable in
            guard variable.isRequired else { return nil }
            let value = values[variable.name] ?? variable.defaultValue
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? variable.name : nil
        }
    }

    /// Replaces placeholders with values. User variables missing from `values` are left as-is;
    /// built-ins are resolved from `builtIns`.
    /// Escapes (`\{{x}}`) are only processed in the template text, never inside inserted values.
    static func render(_ text: String, values: [String: String], builtIns: BuiltInValues = .init()) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var cursor = text.startIndex
        for placeholder in placeholders(in: text) {
            result += unescape(String(text[cursor..<placeholder.range.lowerBound]))
            let replacement: String?
            if placeholder.isBuiltIn {
                replacement = values[placeholder.name] ?? builtIns.value(for: placeholder.name)
            } else {
                replacement = values[placeholder.name]
            }
            result += replacement ?? String(text[placeholder.range])
            cursor = placeholder.range.upperBound
        }
        result += unescape(String(text[cursor...]))
        return result
    }

    private static func unescape(_ text: String) -> String {
        guard text.contains("\\{{") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return escapedRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }
}

/// Values for built-in variables, captured at the moment a prompt is used.
nonisolated struct BuiltInValues: Sendable {
    var clipboard: String
    var now: Date
    var locale: Locale
    var timeZone: TimeZone

    init(clipboard: String = "", now: Date = .now, locale: Locale = .current, timeZone: TimeZone = .current) {
        self.clipboard = clipboard
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
    }

    func value(for name: String) -> String? {
        switch name.lowercased() {
        case "clipboard":
            return clipboard
        case "date":
            return format(dateStyle: .long, timeStyle: .none)
        case "time":
            return format(dateStyle: .none, timeStyle: .short)
        case "datetime":
            return format(dateStyle: .long, timeStyle: .short)
        case "weekday":
            return format(template: "EEEE")
        case "year":
            return format(template: "yyyy")
        default:
            return nil
        }
    }

    private func format(dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: now)
    }

    private func format(template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: now)
    }
}
