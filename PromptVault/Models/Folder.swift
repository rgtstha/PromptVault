import Foundation
import SwiftData

/// A user-created folder. Folders can be nested; every prompt belongs to at most one folder
/// (prompts without a folder are "Uncategorized").
@Model
final class Folder {
    var id: UUID = UUID()
    var name: String = ""
    /// SF Symbol name used in the sidebar.
    var symbolName: String = "folder"
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var children: [Folder]? = []

    var prompts: [Prompt]? = []

    init(id: UUID = UUID(), name: String, symbolName: String = "folder", sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.sortIndex = sortIndex
    }
}

extension Folder {
    static let symbolChoices: [String] = [
        "folder", "tray", "archivebox", "doc.text", "pencil", "text.quote",
        "chevron.left.forwardslash.chevron.right", "terminal", "hammer", "ladybug",
        "magnifyingglass", "book", "graduationcap", "lightbulb", "sparkles", "wand.and.stars",
        "brain", "bubble.left.and.bubble.right", "briefcase", "chart.bar", "megaphone",
        "paintbrush", "photo", "globe", "envelope", "person.2", "heart", "star", "bolt", "flag",
    ]

    var sortedChildren: [Folder] {
        (children ?? []).sorted(by: Folder.displayOrder)
    }

    /// `nil` when there are no children, as required by `List(_:children:)` / `OutlineGroup`.
    var childrenOrNil: [Folder]? {
        let sorted = sortedChildren
        return sorted.isEmpty ? nil : sorted
    }

    /// Ancestors from the root down to (and including) this folder.
    var path: [Folder] {
        var result: [Folder] = [self]
        var visited: Set<UUID> = [id]
        var cursor = parent
        while let current = cursor, !visited.contains(current.id) {
            result.insert(current, at: 0)
            visited.insert(current.id)
            cursor = current.parent
        }
        return result
    }

    var pathString: String {
        path.map(\.name).joined(separator: " / ")
    }

    var depth: Int { path.count - 1 }

    /// This folder and every folder nested inside it.
    var selfAndDescendants: [Folder] {
        var result: [Folder] = []
        var stack: [Folder] = [self]
        var visited: Set<UUID> = []
        while let next = stack.popLast() {
            guard visited.insert(next.id).inserted else { continue }
            result.append(next)
            stack.append(contentsOf: next.children ?? [])
        }
        return result
    }

    func isDescendant(of other: Folder) -> Bool {
        var cursor = parent
        var visited: Set<UUID> = []
        while let current = cursor, visited.insert(current.id).inserted {
            if current.id == other.id { return true }
            cursor = current.parent
        }
        return false
    }

    static func displayOrder(_ lhs: Folder, _ rhs: Folder) -> Bool {
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
