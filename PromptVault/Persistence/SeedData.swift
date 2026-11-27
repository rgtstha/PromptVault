import Foundation

/// Starter content created the first time a brand-new library is opened, so the app
/// demonstrates folders, tags, favorites, variables, built-ins, and templates out of the box.
extension PromptLibrary {
    func seedSampleContent() {
        let writing = createFolder(named: "Writing", symbolName: "pencil")
        let coding = createFolder(named: "Coding", symbolName: "chevron.left.forwardslash.chevron.right")
        let review = createFolder(named: "Code Review", parent: coding, symbolName: "ladybug")
        let research = createFolder(named: "Research", symbolName: "magnifyingglass")

        createPrompt(
            title: "Expert Project Kickoff",
            content: """
            You are an expert {{role}}. Help me build a {{project_type}} application using {{technology}}.

            Start by asking me up to five clarifying questions. Then propose:
            1. A high-level architecture
            2. The key data models
            3. A step-by-step implementation plan with milestones
            """,
            summary: "Template that turns an assistant into a domain expert for a new project.",
            tags: ["planning", "architecture"],
            folder: coding,
            isTemplate: true,
            variables: [
                PromptVariable(name: "role", defaultValue: "senior software architect", description: "Who the assistant should act as"),
                PromptVariable(name: "project_type", description: "What you are building, e.g. “menu bar utility”"),
                PromptVariable(name: "technology", defaultValue: "Swift and SwiftUI", description: "Languages and frameworks"),
            ]
        )

        createPrompt(
            title: "Summarize Clipboard",
            content: """
            Summarize the following text in {{count}} concise bullet points. Lead with the single most important takeaway.

            {{clipboard}}
            """,
            summary: "Uses the built-in {{clipboard}} variable — copy text, then use this prompt.",
            tags: ["summary", "reading"],
            folder: research,
            isFavorite: true,
            variables: [PromptVariable(name: "count", defaultValue: "5", description: "Number of bullet points")]
        )

        createPrompt(
            title: "Thorough Code Review",
            content: """
            Review the following {{language}} code as a meticulous senior engineer. Look for:
            - Bugs and edge cases
            - Performance problems
            - Readability and naming
            - Security concerns

            For each issue, quote the relevant line, explain the problem, and suggest a fix.

            ```{{language}}
            {{code}}
            ```
            """,
            summary: "Structured review covering bugs, performance, readability, and security.",
            tags: ["review", "quality"],
            folder: review,
            isFavorite: true,
            variables: [
                PromptVariable(name: "language", defaultValue: "Swift"),
                PromptVariable(name: "code", description: "Paste the code to review"),
            ]
        )

        createPrompt(
            title: "Conventional Commit Message",
            content: """
            Write a Conventional Commits message for the changes below. Use an imperative subject line under 72 characters, then a short body explaining what changed and why.

            {{diff}}
            """,
            summary: "Turns a diff into a well-formed commit message.",
            tags: ["git"],
            folder: coding,
            variables: [PromptVariable(name: "diff", description: "Output of git diff")]
        )

        createPrompt(
            title: "Improve My Writing",
            content: """
            Rewrite the text below to be clearer and more concise while keeping my voice. Tone: {{tone}}.
            Return the rewritten text first, then a short list of the most important changes you made.

            {{text}}
            """,
            summary: "Edit for clarity and concision without losing your voice.",
            tags: ["editing"],
            folder: writing,
            isFavorite: true,
            variables: [
                PromptVariable(name: "tone", defaultValue: "friendly and professional", isRequired: false),
                PromptVariable(name: "text", description: "The text to improve"),
            ]
        )

        createPrompt(
            title: "Meeting Notes → Action Items",
            content: """
            Turn these meeting notes into:
            1. A three-sentence summary
            2. Decisions that were made
            3. Action items as a table with owner, task, and due date

            Notes from {{date}}:
            {{notes}}
            """,
            summary: "Extracts decisions and owners from raw notes.",
            tags: ["meetings", "summary"],
            folder: writing,
            variables: [PromptVariable(name: "notes", description: "Paste your raw notes")]
        )

        createPrompt(
            title: "Explain Like I’m New to It",
            content: """
            Explain {{topic}} to someone who is smart but new to the field. Use a concrete analogy, define any jargon, and finish with three questions I can use to check my understanding.
            """,
            summary: "Plain-language explanations with an analogy and self-check questions.",
            tags: ["learning"],
            folder: research,
            variables: [PromptVariable(name: "topic", description: "The concept to explain")]
        )

        createPrompt(
            title: "Socratic Tutor",
            content: """
            Act as a Socratic tutor. Don’t give me answers directly — guide me with one question at a time, wait for my reply, and adjust based on what I say. If I’m stuck twice in a row, give a small hint.
            """,
            summary: "Learn by being asked the right questions.",
            tags: ["learning"],
            folder: research
        )

        createPrompt(
            title: "Product Launch Email",
            content: """
            Write a launch email for {{product}} aimed at {{audience}}. Keep it under 200 words, lead with the benefit, include one concrete example, and end with a single clear call to action: {{cta}}.
            """,
            summary: "Short, benefit-led announcement email.",
            tags: ["marketing", "email"],
            isTemplate: true,
            variables: [
                PromptVariable(name: "product", description: "Product or feature name"),
                PromptVariable(name: "audience", defaultValue: "existing customers"),
                PromptVariable(name: "cta", defaultValue: "Try it today", isRequired: false),
            ]
        )
    }
}
