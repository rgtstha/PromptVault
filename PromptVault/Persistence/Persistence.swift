import Foundation
import SwiftData

/// Versioned schema so future model changes can ship with a migration plan.
enum PromptVaultSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Prompt.self, Folder.self, PromptVersion.self] }
}

enum PromptVaultMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PromptVaultSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// File locations. All user data lives in one directory:
/// `~/Library/Application Support/PromptVault/` by default.
///
/// The directory can be overridden (useful for development and testing) with either
/// the `PROMPTVAULT_DATA_DIR` environment variable or the launch argument
/// `-PromptVaultDataDirectory /some/path`.
struct AppPaths: Sendable {
    let dataDirectory: URL

    var storeURL: URL { dataDirectory.appendingPathComponent("PromptVault.store") }
    var backupsDirectory: URL { dataDirectory.appendingPathComponent("Backups", isDirectory: true) }

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        defaults: UserDefaults = .standard) -> AppPaths {
        if let override = environment["PROMPTVAULT_DATA_DIR"], !override.isEmpty {
            return AppPaths(dataDirectory: URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true))
        }
        if let override = defaults.string(forKey: "PromptVaultDataDirectory"), !override.isEmpty {
            return AppPaths(dataDirectory: URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(dataDirectory: support.appendingPathComponent("PromptVault", isDirectory: true))
    }

    func createDirectories() throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }
}

enum Persistence {
    static var schema: Schema { Schema(versionedSchema: PromptVaultSchemaV1.self) }

    /// Opens (or creates) the on-disk store. Pass `nil` for an in-memory store.
    static func makeContainer(storeURL: URL?) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: PromptVaultMigrationPlan.self, configurations: [configuration])
    }

    /// Moves an unreadable store (and its SQLite sidecar files) aside so a fresh one can be created.
    /// Returns the location of the moved store.
    @discardableResult
    static func quarantineStore(at storeURL: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: .now)
        let directory = storeURL.deletingLastPathComponent()
        let base = storeURL.deletingPathExtension().lastPathComponent
        let destination = directory.appendingPathComponent("\(base)-unreadable-\(stamp).store")
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: URL(fileURLWithPath: destination.path + suffix))
        }
        return destination
    }
}
