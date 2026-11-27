import OSLog

/// Unified logging. View with: `log stream --predicate 'subsystem == "app.promptvault.PromptVault"'`
nonisolated enum Log {
    static let app = Logger(subsystem: "app.promptvault.PromptVault", category: "app")
    static let data = Logger(subsystem: "app.promptvault.PromptVault", category: "data")
}
