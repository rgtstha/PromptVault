import Foundation

/// A collection of prompts shown in the popover or the library sidebar.
enum LibraryScope: Hashable, Codable, Sendable {
    case all
    case favorites
    case recent
    case templates
    case uncategorized
    case folder(UUID)
    case tag(String)

    static let smartCollections: [LibraryScope] = [.all, .favorites, .recent, .templates, .uncategorized]

    var title: String {
        switch self {
        case .all: "All Prompts"
        case .favorites: "Favorites"
        case .recent: "Recently Used"
        case .templates: "Templates"
        case .uncategorized: "Uncategorized"
        case .folder: "Folder"
        case .tag(let tag): "#\(tag)"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: "All"
        case .recent: "Recent"
        default: title
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .favorites: "star"
        case .recent: "clock"
        case .templates: "doc.on.doc"
        case .uncategorized: "tray"
        case .folder: "folder"
        case .tag: "number"
        }
    }

    /// The Recently Used collection always sorts by last use.
    var forcedSortOrder: PromptSortOrder? {
        self == .recent ? .recentlyUsed : nil
    }
}

enum PromptSortOrder: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Frequently *and* recently used prompts first (frecency).
    case smart
    case recentlyUsed
    case recentlyUpdated
    case alphabetical
    case mostUsed
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: "Smart (Frequent & Recent)"
        case .recentlyUsed: "Recently Used"
        case .recentlyUpdated: "Recently Updated"
        case .alphabetical: "Alphabetical"
        case .mostUsed: "Most Used"
        case .newest: "Date Created"
        }
    }
}
