import Foundation
import Testing
@testable import PromptVault

struct TemplateEngineTests {
    @Test func detectsVariablesInOrderWithoutDuplicates() {
        let text = "You are an expert {{role}}. Build a {{ project_type }} with {{technology}} — again {{role}}."
        #expect(TemplateEngine.variableNames(in: text) == ["role", "project_type", "technology"])
    }

    @Test func ignoresBuiltInsAndInvalidNames() {
        let text = "{{clipboard}} {{Date}} {{#each items}} {{ }} {{9lives}} {{name}}"
        #expect(TemplateEngine.variableNames(in: text) == ["name"])
        #expect(TemplateEngine.usesBuiltIns(text))
    }

    @Test func supportsSpacesAndUnicodeInNames() {
        let text = "Hello {{first name}} and {{prénom}}"
        #expect(TemplateEngine.variableNames(in: text) == ["first name", "prénom"])
    }

    @Test func rendersValuesAndLeavesUnknownPlaceholders() {
        let text = "A {{x}} and {{y}} and {{x}}"
        let result = TemplateEngine.render(text, values: ["x": "1"])
        #expect(result == "A 1 and {{y}} and 1")
    }

    @Test func rendersBuiltIns() {
        let date = ISO8601DateFormatter().date(from: "2026-03-04T10:30:00Z")!
        let builtIns = BuiltInValues(
            clipboard: "copied text", now: date,
            locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!
        )
        let result = TemplateEngine.render("{{clipboard}} | {{year}} | {{weekday}}", values: [:], builtIns: builtIns)
        #expect(result == "copied text | 2026 | Wednesday")
    }

    @Test func escapedPlaceholdersAreLiteral() {
        let text = #"Use \{{name}} in Handlebars, hi {{name}}"#
        #expect(TemplateEngine.variableNames(in: text) == ["name"])
        #expect(TemplateEngine.render(text, values: ["name": "Ana"]) == "Use {{name}} in Handlebars, hi Ana")
    }

    @Test func replacementValuesAreInsertedVerbatim() {
        // Values containing regex template characters or braces must not be interpreted.
        let result = TemplateEngine.render("x={{v}}", values: ["v": "$1 \\{{w}} {{v}}"])
        #expect(result == "x=$1 \\{{w}} {{v}}")
    }

    @Test func resolveMergesMetadataAndDropsOrphans() {
        let stored = [
            PromptVariable(name: "tone", defaultValue: "warm", description: "Voice", isRequired: false),
            PromptVariable(name: "orphan", defaultValue: "gone"),
        ]
        let resolved = TemplateEngine.resolveVariables(in: "{{text}} in a {{tone}} tone", stored: stored)
        #expect(resolved.map(\.name) == ["text", "tone"])
        #expect(resolved[0] == PromptVariable(name: "text"))
        #expect(resolved[1].defaultValue == "warm")
        #expect(resolved[1].isRequired == false)
    }

    @Test func missingRequiredHonorsDefaultsAndOptional() {
        let variables = [
            PromptVariable(name: "a"),
            PromptVariable(name: "b", defaultValue: "fallback"),
            PromptVariable(name: "c", isRequired: false),
        ]
        #expect(TemplateEngine.missingRequired(variables, values: [:]) == ["a"])
        #expect(TemplateEngine.missingRequired(variables, values: ["a": "  "]) == ["a"])
        #expect(TemplateEngine.missingRequired(variables, values: ["a": "ok", "b": ""]) == ["b"])
        #expect(TemplateEngine.missingRequired(variables, values: ["a": "ok"]).isEmpty)
    }
}
