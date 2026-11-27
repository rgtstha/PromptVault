import Foundation
import SwiftData

/// A snapshot of a prompt's text, captured each time an edit to the title, description,
/// or content is saved. `savedAt` is when this state was originally saved; `capturedAt` is when
/// it was replaced (the snapshot was taken).
@Model
final class PromptVersion {
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var summary: String = ""
    var variablesData: Data? = nil
    var savedAt: Date = Date()
    var capturedAt: Date = Date()

    var prompt: Prompt?

    init(id: UUID = UUID(), title: String, content: String, summary: String, variablesData: Data?, savedAt: Date, capturedAt: Date = .now) {
        self.id = id
        self.title = title
        self.content = content
        self.summary = summary
        self.variablesData = variablesData
        self.savedAt = savedAt
        self.capturedAt = capturedAt
    }
}
