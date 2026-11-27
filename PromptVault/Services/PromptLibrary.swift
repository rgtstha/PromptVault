import Foundation
import Observation
import SwiftData

/// The single source of truth for prompts and folders. All mutations go through this type so
/// that versioning, timestamps, and persistence are handled consistently.
///
/// Prompts are kept in memory and filtered/searched there, which keeps search instantaneous
/// for collections of many thousands of prompts.
@Observable
final class PromptLibrary {
    let context: ModelContext

    /// Maximum number of saved versions kept per prompt (oldest are pruned).
    var maxVersionsPerPrompt = 50

    private(set) var prompts: [Prompt] = []
    private(set) var folders: [Folder] = []

    /// The most recent persistence error, surfaced to the UI.
    var lastError: LibraryError?

    /// Incremented after every change. Query results and counts are cached per revision, and
    /// views that read them re-render when it changes.
    private(set) var revision = 0

    /// Search documents keyed by prompt instance (the strong reference keeps the identifier
    /// unique). Every mutation that changes searchable text invalidates its entries explicitly —
    /// all mutations go through this type — so typing never re-reads SwiftData properties.
    @ObservationIgnored private var searchIndex: [ObjectIdentifier: (prompt: Prompt, document: SearchDocument)] = [:]
    @ObservationIgnored private var queryCache: [QueryKey: [Prompt]] = [:]
    @ObservationIgnored private var queryCacheRevision = -1
    @ObservationIgnored private var cachedCounts: (revision: Int, counts: ScopeCounts)?

    private struct QueryKey: Hashable {
        let scope: LibraryScope
        let text: String
        let order: PromptSortOrder
        let favoritesFirst: Bool
    }

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        do {
            prompts = try context.fetch(FetchDescriptor<Prompt>())
            folders = try context.fetch(FetchDescriptor<Folder>())
        } catch {
            report("Couldn’t load your prompts", error)
        }
        let live = Set(prompts.map(ObjectIdentifier.init))
        searchIndex = searchIndex.filter { live.contains($0.key) }
        revision &+= 1
    }

    /// Builds the search index ahead of the first search (call when idle after launch).
    func warmSearchIndex() {
        for prompt in prompts { _ = document(for: prompt) }
    }

    private func invalidateSearch<S: Sequence>(_ prompts: S) where S.Element == Prompt {
        for prompt in prompts { searchIndex[ObjectIdentifier(prompt)] = nil }
    }

    private func invalidateSearch(inFolder folder: Folder) {
        invalidateSearch(folder.selfAndDescendants.flatMap { $0.prompts ?? [] })
    }

    // MARK: - Lookup

    func prompt(id: UUID) -> Prompt? { prompts.first { $0.id == id } }

    func folder(id: UUID) -> Folder? { folders.first { $0.id == id } }

    var rootFolders: [Folder] {
        folders.filter { $0.parent == nil }.sorted(by: Folder.displayOrder)
    }

    /// Depth-first list of all folders, for pickers and menus.
    func flattenedFolders(excluding excluded: Folder? = nil) -> [FolderNode] {
        var result: [FolderNode] = []
        func visit(_ folder: Folder, depth: Int) {
            if let excluded, folder.id == excluded.id { return }
            result.append(FolderNode(folder: folder, depth: depth))
            for child in folder.sortedChildren { visit(child, depth: depth + 1) }
        }
        for root in rootFolders { visit(root, depth: 0) }
        return result
    }

    var allTags: [TagSummary] {
        counts().tags
            .map { TagSummary(name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Querying

    /// Prompts in `scope` matching `searchText`, ordered by relevance when searching and by
    /// `order` otherwise.
    func prompts(
        in scope: LibraryScope,
        matching searchText: String = "",
        sortedBy order: PromptSortOrder = .smart,
        favoritesFirst: Bool = false
    ) -> [Prompt] {
        let currentRevision = revision
        if queryCacheRevision != currentRevision {
            queryCache.removeAll(keepingCapacity: true)
            queryCacheRevision = currentRevision
        }
        let key = QueryKey(scope: scope, text: searchText, order: order, favoritesFirst: favoritesFirst)
        if let cached = queryCache[key] { return cached }
        let results = computePrompts(in: scope, matching: searchText, sortedBy: order, favoritesFirst: favoritesFirst)
        if queryCache.count > 32 { queryCache.removeAll(keepingCapacity: true) }
        queryCache[key] = results
        return results
    }

    private func computePrompts(
        in scope: LibraryScope,
        matching searchText: String,
        sortedBy order: PromptSortOrder,
        favoritesFirst: Bool
    ) -> [Prompt] {
        let candidates = filter(prompts, by: scope)
        let effectiveOrder = scope.forcedSortOrder ?? order
        let now = Date.now
        let query = SearchQuery(searchText)

        if !query.isEmpty {
            var scored: [(prompt: Prompt, score: Double)] = []
            scored.reserveCapacity(candidates.count)
            for prompt in candidates {
                guard let score = SearchEngine.score(document(for: prompt), query: query) else { continue }
                let boost = (prompt.isFavorite ? 4 : 0) + min(8, log2(Double(prompt.usageCount) + 1) * 2)
                scored.append((prompt, score + boost))
            }
            let tieBreak = Self.comparator(for: effectiveOrder, now: now)
            scored.sort { $0.score != $1.score ? $0.score > $1.score : tieBreak($0.prompt, $1.prompt) }
            return scored.map(\.prompt)
        }

        var sorted = Self.sort(candidates, by: effectiveOrder, now: now)
        if favoritesFirst && scope != .favorites && scope != .recent {
            sorted = sorted.filter(\.isFavorite) + sorted.filter { !$0.isFavorite }
        }
        return sorted
    }

    private func filter(_ prompts: [Prompt], by scope: LibraryScope) -> [Prompt] {
        switch scope {
        case .all:
            return prompts
        case .favorites:
            return prompts.filter(\.isFavorite)
        case .recent:
            return prompts.filter { $0.lastUsedAt != nil }
        case .templates:
            return prompts.filter(\.isTemplate)
        case .uncategorized:
            return prompts.filter { $0.folder == nil }
        case .folder(let id):
            guard let folder = folder(id: id) else { return [] }
            let ids = Set(folder.selfAndDescendants.map(\.id))
            return prompts.filter { prompt in prompt.folder.map { ids.contains($0.id) } ?? false }
        case .tag(let tag):
            return prompts.filter { prompt in prompt.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        }
    }

    private func document(for prompt: Prompt) -> SearchDocument {
        let key = ObjectIdentifier(prompt)
        if let entry = searchIndex[key] { return entry.document }
        let document = SearchDocument(
            title: prompt.title, summary: prompt.summary, content: prompt.content,
            tags: prompt.tags, folder: prompt.folder?.pathString ?? ""
        )
        searchIndex[key] = (prompt, document)
        return document
    }

    /// Frecency: usage count decayed by time since last use (14-day half-life).
    static func frecency(of prompt: Prompt, now: Date) -> Double {
        guard let lastUsed = prompt.lastUsedAt, prompt.usageCount > 0 else { return 0 }
        let days = max(0, now.timeIntervalSince(lastUsed) / 86_400)
        return Double(prompt.usageCount) * pow(0.5, days / 14)
    }

    static func sort(_ prompts: [Prompt], by order: PromptSortOrder, now: Date = .now) -> [Prompt] {
        if order == .smart {
            // Decorate-sort-undecorate so frecency is computed once per prompt.
            return prompts
                .map { (prompt: $0, score: frecency(of: $0, now: now)) }
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.prompt.updatedAt > rhs.prompt.updatedAt
                }
                .map(\.prompt)
        }
        return prompts.sorted(by: comparator(for: order, now: now))
    }

    static func comparator(for order: PromptSortOrder, now: Date) -> (Prompt, Prompt) -> Bool {
        switch order {
        case .smart:
            return { lhs, rhs in
                let l = frecency(of: lhs, now: now), r = frecency(of: rhs, now: now)
                return l != r ? l > r : lhs.updatedAt > rhs.updatedAt
            }
        case .recentlyUsed:
            return { lhs, rhs in
                switch (lhs.lastUsedAt, rhs.lastUsedAt) {
                case let (l?, r?) where l != r: return l > r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.updatedAt > rhs.updatedAt
                }
            }
        case .recentlyUpdated:
            return { $0.updatedAt > $1.updatedAt }
        case .alphabetical:
            return { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        case .mostUsed:
            return { lhs, rhs in
                if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
                return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
            }
        case .newest:
            return { $0.createdAt > $1.createdAt }
        }
    }

    /// Prompt counts for every sidebar collection (cached until the next change).
    func counts() -> ScopeCounts {
        let currentRevision = revision
        if let cachedCounts, cachedCounts.revision == currentRevision { return cachedCounts.counts }
        var counts = ScopeCounts()
        var tagNames: [String: String] = [:] // lowercased -> display name
        for prompt in prompts {
            counts.all += 1
            if prompt.isFavorite { counts.favorites += 1 }
            if prompt.lastUsedAt != nil { counts.recent += 1 }
            if prompt.isTemplate { counts.templates += 1 }
            for tag in prompt.tags {
                let key = tag.lowercased()
                let name = tagNames[key] ?? tag
                tagNames[key] = name
                counts.tags[name, default: 0] += 1
            }
        }
        // Folder totals include subfolders; computed per folder rather than per prompt.
        var filed = 0
        for folder in folders {
            let direct = folder.prompts?.count ?? 0
            guard direct > 0 else { continue }
            filed += direct
            for ancestor in folder.path { counts.folders[ancestor.id, default: 0] += direct }
        }
        counts.uncategorized = counts.all - filed
        cachedCounts = (currentRevision, counts)
        return counts
    }

    func count(for scope: LibraryScope) -> Int {
        filter(prompts, by: scope).count
    }

    var totalUses: Int { prompts.reduce(0) { $0 + $1.usageCount } }

    func mostUsed(limit: Int) -> [Prompt] {
        Array(Self.sort(prompts.filter { $0.usageCount > 0 }, by: .mostUsed).prefix(limit))
    }

    func recentlyUsed(limit: Int) -> [Prompt] {
        Array(Self.sort(prompts.filter { $0.lastUsedAt != nil }, by: .recentlyUsed).prefix(limit))
    }

    // MARK: - Prompts

    @discardableResult
    func createPrompt(
        title: String,
        content: String,
        summary: String = "",
        tags: [String] = [],
        folder: Folder? = nil,
        isFavorite: Bool = false,
        isTemplate: Bool = false,
        variables: [PromptVariable] = []
    ) -> Prompt {
        let prompt = Prompt(
            title: title, content: content, summary: summary,
            tags: Self.normalizeTags(tags), isFavorite: isFavorite, isTemplate: isTemplate
        )
        context.insert(prompt)
        prompt.folder = folder
        prompt.storedVariables = TemplateEngine.resolveVariables(in: content, stored: variables)
        commit(reload: true)
        return prompt
    }

    /// Automatic saves within this interval of the previous save are treated as one editing
    /// session and don't create additional versions.
    static let autosaveCoalescingInterval: TimeInterval = 5 * 60

    /// Saves text edits. A version of the previous state is kept whenever the title,
    /// description, or content changes.
    ///
    /// - Parameter coalescing: Pass `true` for automatic saves (switching prompts, leaving the
    ///   window). If a version was captured within `autosaveCoalescingInterval`, the edit belongs to
    ///   the same session and no extra version is created, so frequent autosaves can't push real
    ///   history out.
    func update(_ prompt: Prompt, with draft: PromptDraft, coalescing: Bool = false) {
        let newVariables = TemplateEngine.resolveVariables(in: draft.content, stored: draft.variables)
        let textChanged = prompt.title != draft.title
            || prompt.content != draft.content
            || prompt.summary != draft.summary
        let variablesChanged = prompt.storedVariables != newVariables
        guard textChanged || variablesChanged else { return }

        let lastCapture = (prompt.versions ?? []).map(\.capturedAt).max()
        let withinSession = coalescing
            && lastCapture.map { Date.now.timeIntervalSince($0) < Self.autosaveCoalescingInterval } ?? false
        if textChanged && !withinSession { snapshotVersion(of: prompt) }
        invalidateSearch([prompt])
        prompt.title = draft.title
        prompt.content = draft.content
        prompt.summary = draft.summary
        prompt.storedVariables = newVariables
        prompt.updatedAt = .now
        trimVersions(of: prompt)
        commit()
    }

    func delete(_ prompts: [Prompt]) {
        guard !prompts.isEmpty else { return }
        invalidateSearch(prompts)
        for prompt in prompts {
            context.delete(prompt)
        }
        commit(reload: true)
    }

    @discardableResult
    func duplicate(_ prompt: Prompt) -> Prompt {
        let copy = Prompt(
            title: "\(prompt.displayTitle) Copy", content: prompt.content, summary: prompt.summary,
            tags: prompt.tags, isFavorite: false, isTemplate: prompt.isTemplate
        )
        context.insert(copy)
        copy.folder = prompt.folder
        copy.variablesData = prompt.variablesData
        commit(reload: true)
        return copy
    }

    /// Creates a regular prompt from a template.
    @discardableResult
    func createPrompt(fromTemplate template: Prompt) -> Prompt {
        let prompt = Prompt(
            title: template.displayTitle, content: template.content, summary: template.summary,
            tags: template.tags, isFavorite: false, isTemplate: false
        )
        context.insert(prompt)
        prompt.folder = template.folder
        prompt.variablesData = template.variablesData
        commit(reload: true)
        return prompt
    }

    func toggleFavorite(_ prompt: Prompt) {
        setFavorite([prompt], !prompt.isFavorite)
    }

    func setFavorite(_ prompts: [Prompt], _ isFavorite: Bool) {
        for prompt in prompts { prompt.isFavorite = isFavorite }
        commit()
    }

    func setTemplate(_ prompts: [Prompt], _ isTemplate: Bool) {
        for prompt in prompts { prompt.isTemplate = isTemplate }
        commit()
    }

    func move(_ prompts: [Prompt], to folder: Folder?) {
        invalidateSearch(prompts)
        for prompt in prompts { prompt.folder = folder }
        commit()
    }

    func setTags(_ tags: [String], for prompt: Prompt) {
        let normalized = Self.normalizeTags(tags)
        guard normalized != prompt.tags else { return }
        invalidateSearch([prompt])
        prompt.tags = normalized
        prompt.updatedAt = .now
        commit()
    }

    func addTag(_ tag: String, to prompts: [Prompt]) {
        invalidateSearch(prompts)
        for prompt in prompts {
            let normalized = Self.normalizeTags(prompt.tags + [tag])
            if normalized != prompt.tags {
                prompt.tags = normalized
                prompt.updatedAt = .now
            }
        }
        commit()
    }

    /// Records that a prompt was copied/used.
    func recordUse(of prompt: Prompt, variableValues: [String: String] = [:], rememberValues: Bool = true) {
        prompt.usageCount += 1
        prompt.lastUsedAt = .now
        if rememberValues && !variableValues.isEmpty {
            prompt.lastVariableValues = variableValues.mapValues { String($0.prefix(4_000)) }
        }
        commit()
    }

    func resetUsage(of prompt: Prompt) {
        prompt.usageCount = 0
        prompt.lastUsedAt = nil
        commit()
    }

    // MARK: - Versions

    private func snapshotVersion(of prompt: Prompt) {
        if prompt.title.isEmpty && prompt.content.isEmpty { return }
        let version = PromptVersion(
            title: prompt.title, content: prompt.content, summary: prompt.summary,
            variablesData: prompt.variablesData, savedAt: prompt.updatedAt
        )
        context.insert(version)
        version.prompt = prompt
    }

    private func trimVersions(of prompt: Prompt) {
        let versions = prompt.sortedVersions
        guard versions.count > maxVersionsPerPrompt else { return }
        for version in versions.dropFirst(maxVersionsPerPrompt) {
            context.delete(version)
        }
    }

    /// Restores a previous version. The current state is itself saved as a version first,
    /// so restoring is always reversible.
    func restore(_ version: PromptVersion) {
        guard let prompt = version.prompt else { return }
        let unchanged = prompt.title == version.title
            && prompt.content == version.content
            && prompt.summary == version.summary
        guard !unchanged else { return }
        invalidateSearch([prompt])
        snapshotVersion(of: prompt)
        prompt.title = version.title
        prompt.content = version.content
        prompt.summary = version.summary
        prompt.storedVariables = TemplateEngine.resolveVariables(
            in: version.content,
            stored: Self.decodeVariables(version.variablesData) + prompt.storedVariables
        )
        prompt.updatedAt = .now
        trimVersions(of: prompt)
        commit()
    }

    func deleteVersion(_ version: PromptVersion) {
        context.delete(version)
        commit()
    }

    func clearHistory(of prompt: Prompt) {
        for version in prompt.versions ?? [] { context.delete(version) }
        commit()
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(named name: String, parent: Folder? = nil, symbolName: String = "folder") -> Folder {
        let siblings = parent?.sortedChildren ?? rootFolders
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(
            name: Self.uniqueName(base.isEmpty ? "New Folder" : base, among: siblings.map(\.name)),
            symbolName: symbolName,
            sortIndex: (siblings.map(\.sortIndex).max() ?? -1) + 1
        )
        context.insert(folder)
        folder.parent = parent
        commit(reload: true)
        return folder
    }

    func rename(_ folder: Folder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        invalidateSearch(inFolder: folder)
        folder.name = trimmed
        commit()
    }

    func setSymbol(_ symbolName: String, for folder: Folder) {
        folder.symbolName = symbolName
        commit()
    }

    /// Moves a folder under a new parent (`nil` = top level). Returns `false` if the move would
    /// create a cycle.
    @discardableResult
    func move(_ folder: Folder, to parent: Folder?) -> Bool {
        if let parent, parent.id == folder.id || parent.isDescendant(of: folder) { return false }
        guard folder.parent?.id != parent?.id else { return true }
        let siblings = parent?.sortedChildren ?? rootFolders
        invalidateSearch(inFolder: folder)
        folder.parent = parent
        folder.sortIndex = (siblings.map(\.sortIndex).max() ?? -1) + 1
        commit(reload: true)
        return true
    }

    /// Deletes a folder and its subfolders. Prompts inside them become Uncategorized.
    func delete(_ folder: Folder) {
        let doomed = folder.selfAndDescendants
        invalidateSearch(inFolder: folder)
        for item in doomed {
            for prompt in item.prompts ?? [] { prompt.folder = nil }
        }
        for item in doomed.sorted(by: { $0.depth > $1.depth }) {
            context.delete(item)
        }
        commit(reload: true)
    }

    // MARK: - Tags

    func renameTag(_ oldName: String, to newName: String) {
        let replacement = Self.normalizeTags([newName]).first
        for prompt in prompts where prompt.tags.contains(where: { $0.caseInsensitiveCompare(oldName) == .orderedSame }) {
            var tags = prompt.tags.compactMap { tag -> String? in
                tag.caseInsensitiveCompare(oldName) == .orderedSame ? replacement : tag
            }
            tags = Self.normalizeTags(tags)
            invalidateSearch([prompt])
            prompt.tags = tags
            prompt.updatedAt = .now
        }
        commit()
    }

    func deleteTag(_ name: String) {
        renameTag(name, to: "")
    }

    /// Trims, strips leading `#`, replaces inner whitespace with `-`, and removes
    /// case-insensitive duplicates (keeping the first spelling).
    static func normalizeTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in tags {
            var tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            while tag.hasPrefix("#") { tag.removeFirst() }
            tag = tag.split(whereSeparator: \.isWhitespace).joined(separator: "-")
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    static func uniqueName(_ base: String, among existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }

    // MARK: - Import / Export

    /// Builds an archive of `subset` (or the whole library) including the folders they need.
    func makeArchive(of subset: [Prompt]? = nil, includeHistory: Bool = true, generator: String? = nil) -> PromptArchive {
        let chosen = subset ?? prompts
        let chosenFolders: [Folder]
        if subset == nil {
            chosenFolders = folders
        } else {
            var needed: [UUID: Folder] = [:]
            for prompt in chosen {
                for folder in prompt.folder?.path ?? [] { needed[folder.id] = folder }
            }
            chosenFolders = Array(needed.values)
        }

        let folderRecords = chosenFolders
            .sorted { $0.depth != $1.depth ? $0.depth < $1.depth : Folder.displayOrder($0, $1) }
            .map { FolderRecord(id: $0.id, name: $0.name, symbol: $0.symbolName, parentId: $0.parent?.id, sortIndex: $0.sortIndex) }

        let promptRecords = chosen
            .sorted { $0.createdAt < $1.createdAt }
            .map { prompt in
                PromptRecord(
                    id: prompt.id, title: prompt.title, content: prompt.content, description: prompt.summary,
                    folderId: prompt.folder?.id, folder: prompt.folder?.pathString,
                    tags: prompt.tags, isFavorite: prompt.isFavorite, isTemplate: prompt.isTemplate,
                    variables: prompt.variables, createdAt: prompt.createdAt, updatedAt: prompt.updatedAt,
                    usageCount: prompt.usageCount, lastUsedAt: prompt.lastUsedAt,
                    versions: includeHistory ? prompt.sortedVersions.map { version in
                        VersionRecord(
                            id: version.id, title: version.title, content: version.content,
                            description: version.summary, variables: Self.decodeVariables(version.variablesData),
                            savedAt: version.savedAt
                        )
                    } : []
                )
            }
        return PromptArchive(generator: generator, folders: folderRecords, prompts: promptRecords)
    }

    /// Imports an archive.
    /// - `.merge` keeps existing data: prompts with a matching ID are updated only if the imported
    ///   copy is newer; identical untitled duplicates are skipped.
    /// - `.replace` deletes everything first (used by Restore from Backup).
    @discardableResult
    func importArchive(_ archive: PromptArchive, mode: ImportMode) -> ImportSummary {
        var summary = ImportSummary()

        if mode == .replace {
            for prompt in prompts { context.delete(prompt) }
            for folder in folders { context.delete(folder) }
            searchIndex.removeAll()
            do { try context.save() } catch { report("Couldn’t clear the library", error) }
            reload()
        }

        var localFolders = folders
        var folderMap: [UUID: Folder] = [:]
        let existingFolderIDs = Dictionary(localFolders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func siblings(of parent: Folder?) -> [Folder] {
            localFolders.filter { $0.parent?.id == parent?.id }
        }

        func findOrCreateFolder(named name: String, parent: Folder?, id: UUID = UUID(), symbol: String = "folder", sortIndex: Int? = nil) -> Folder {
            if let match = siblings(of: parent).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return match
            }
            let index = sortIndex ?? ((siblings(of: parent).map(\.sortIndex).max() ?? -1) + 1)
            let folder = Folder(id: id, name: name, symbolName: symbol, sortIndex: index)
            context.insert(folder)
            folder.parent = parent
            localFolders.append(folder)
            summary.foldersAdded += 1
            return folder
        }

        for record in Self.parentFirst(archive.folders) {
            let parent = record.parentId.flatMap { folderMap[$0] }
            if let existing = existingFolderIDs[record.id] {
                folderMap[record.id] = existing
                continue
            }
            folderMap[record.id] = findOrCreateFolder(
                named: record.name, parent: parent, id: record.id, symbol: record.symbol, sortIndex: record.sortIndex
            )
        }

        func resolveFolderPath(_ path: String) -> Folder? {
            let components = path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var parent: Folder?
            for component in components {
                parent = findOrCreateFolder(named: component, parent: parent)
            }
            return parent
        }

        var existingPrompts = Dictionary(prompts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for record in archive.prompts {
            let folder = record.folderId.flatMap { folderMap[$0] } ?? record.folder.flatMap(resolveFolderPath)

            if let id = record.id, let existing = existingPrompts[id] {
                let importedDate = record.updatedAt ?? .distantPast
                guard importedDate > existing.updatedAt else {
                    summary.promptsSkipped += 1
                    continue
                }
                if existing.title != record.title || existing.content != record.content || existing.summary != record.description {
                    snapshotVersion(of: existing)
                }
                existing.title = record.title
                existing.content = record.content
                existing.summary = record.description
                existing.tags = Self.normalizeTags(record.tags)
                existing.isFavorite = record.isFavorite
                existing.isTemplate = record.isTemplate
                existing.storedVariables = TemplateEngine.resolveVariables(in: record.content, stored: record.variables)
                if let folder { existing.folder = folder }
                existing.usageCount = max(existing.usageCount, record.usageCount)
                existing.lastUsedAt = [existing.lastUsedAt, record.lastUsedAt].compactMap { $0 }.max()
                existing.updatedAt = importedDate
                let knownVersionIDs = Set((existing.versions ?? []).map(\.id))
                for versionRecord in record.versions where !knownVersionIDs.contains(versionRecord.id) {
                    insertVersion(versionRecord, into: existing)
                }
                trimVersions(of: existing)
                summary.promptsUpdated += 1
                continue
            }

            if record.id == nil, prompts.contains(where: { $0.title == record.title && $0.content == record.content }) {
                summary.promptsSkipped += 1
                continue
            }

            let createdAt = record.createdAt ?? .now
            let prompt = Prompt(
                id: record.id ?? UUID(), title: record.title, content: record.content, summary: record.description,
                tags: Self.normalizeTags(record.tags), isFavorite: record.isFavorite, isTemplate: record.isTemplate,
                createdAt: createdAt
            )
            prompt.updatedAt = record.updatedAt ?? createdAt
            prompt.usageCount = max(0, record.usageCount)
            prompt.lastUsedAt = record.lastUsedAt
            context.insert(prompt)
            prompt.folder = folder
            prompt.storedVariables = TemplateEngine.resolveVariables(in: record.content, stored: record.variables)
            for versionRecord in record.versions { insertVersion(versionRecord, into: prompt) }
            trimVersions(of: prompt)
            existingPrompts[prompt.id] = prompt
            summary.promptsAdded += 1
        }

        searchIndex.removeAll()
        commit(reload: true)
        return summary
    }

    private func insertVersion(_ record: VersionRecord, into prompt: Prompt) {
        let version = PromptVersion(
            id: record.id, title: record.title, content: record.content, summary: record.description,
            variablesData: record.variables.isEmpty ? nil : try? JSONEncoder().encode(record.variables),
            savedAt: record.savedAt, capturedAt: record.savedAt
        )
        context.insert(version)
        version.prompt = prompt
    }

    /// Orders folder records so parents come before their children. Records whose parent is
    /// missing (or that form a cycle) are treated as top-level.
    static func parentFirst(_ records: [FolderRecord]) -> [FolderRecord] {
        let ids = Set(records.map(\.id))
        var placed: Set<UUID> = []
        var remaining = records
        var ordered: [FolderRecord] = []
        while !remaining.isEmpty {
            let ready = remaining.filter { record in
                guard let parentId = record.parentId, ids.contains(parentId) else { return true }
                return placed.contains(parentId)
            }
            if ready.isEmpty {
                // Cycle: detach the remaining records.
                for var record in remaining {
                    record.parentId = nil
                    ordered.append(record)
                }
                break
            }
            for record in ready { placed.insert(record.id) }
            ordered.append(contentsOf: ready)
            let readyIDs = Set(ready.map(\.id))
            remaining.removeAll { readyIDs.contains($0.id) }
        }
        return ordered
    }

    static func decodeVariables(_ data: Data?) -> [PromptVariable] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([PromptVariable].self, from: data)) ?? []
    }

    // MARK: - Persistence

    func save() {
        guard context.hasChanges else { return }
        commit()
    }

    private func commit(reload shouldReload: Bool = false) {
        do {
            try context.save()
        } catch {
            report("Couldn’t save your changes", error)
        }
        if shouldReload { reload() } else { revision &+= 1 }
    }

    private func report(_ message: String, _ error: Error) {
        Log.data.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        lastError = LibraryError(message: "\(message): \(error.localizedDescription)")
    }
}

// MARK: - Supporting types

struct FolderNode: Identifiable {
    let folder: Folder
    let depth: Int
    var id: UUID { folder.id }
}

struct TagSummary: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name.lowercased() }
}

struct ScopeCounts {
    var all = 0
    var favorites = 0
    var recent = 0
    var templates = 0
    var uncategorized = 0
    var folders: [UUID: Int] = [:]
    var tags: [String: Int] = [:]

    func count(for scope: LibraryScope) -> Int {
        switch scope {
        case .all: all
        case .favorites: favorites
        case .recent: recent
        case .templates: templates
        case .uncategorized: uncategorized
        case .folder(let id): folders[id] ?? 0
        case .tag(let name): tags.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? 0
        }
    }
}

struct LibraryError: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

enum ImportMode: Sendable {
    case merge
    case replace
}

struct ImportSummary: Equatable {
    var promptsAdded = 0
    var promptsUpdated = 0
    var promptsSkipped = 0
    var foldersAdded = 0

    var message: String {
        var parts: [String] = []
        parts.append("\(promptsAdded) prompt\(promptsAdded == 1 ? "" : "s") added")
        if promptsUpdated > 0 { parts.append("\(promptsUpdated) updated") }
        if promptsSkipped > 0 { parts.append("\(promptsSkipped) skipped (already up to date)") }
        if foldersAdded > 0 { parts.append("\(foldersAdded) folder\(foldersAdded == 1 ? "" : "s") created") }
        return parts.joined(separator: ", ") + "."
    }
}

/// Editable copy of a prompt's text fields. The editors work on a draft and save it through
/// `PromptLibrary.update(_:with:)`, which is what creates version history entries.
struct PromptDraft: Equatable {
    var title: String
    var content: String
    var summary: String
    /// Variable metadata. May contain entries for placeholders no longer in `content`;
    /// those are pruned on save.
    var variables: [PromptVariable]

    init(title: String = "", content: String = "", summary: String = "", variables: [PromptVariable] = []) {
        self.title = title
        self.content = content
        self.summary = summary
        self.variables = variables
    }

    init(_ prompt: Prompt) {
        self.init(title: prompt.title, content: prompt.content, summary: prompt.summary, variables: prompt.variables)
    }

    /// Variables for the placeholders currently in `content`.
    var resolvedVariables: [PromptVariable] {
        TemplateEngine.resolveVariables(in: content, stored: variables)
    }

    mutating func setVariable(_ variable: PromptVariable) {
        if let index = variables.firstIndex(where: { $0.name == variable.name }) {
            variables[index] = variable
        } else {
            variables.append(variable)
        }
    }

    /// True when saving would not change anything.
    func matches(_ prompt: Prompt) -> Bool {
        title == prompt.title && content == prompt.content && summary == prompt.summary
            && resolvedVariables == prompt.variables
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
