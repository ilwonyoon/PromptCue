import Foundation

struct MCPPromptTemplate: Equatable, Sendable {
    let name: String
    let description: String
    let arguments: [MCPPromptArgument]
    let bodyTemplate: String
}

struct MCPPromptArgument: Equatable, Sendable {
    let name: String
    let description: String
    let required: Bool
}

enum MCPPromptCatalog {
    static let all: [MCPPromptTemplate] = [triage, diagnose, execute]

    static func template(named name: String) -> MCPPromptTemplate? {
        all.first { $0.name == name }
    }

    private static let sharedArguments: [MCPPromptArgument] = [
        MCPPromptArgument(
            name: "noteText",
            description: "The raw note text (or merged group text) to process.",
            required: true
        ),
        MCPPromptArgument(
            name: "repositoryName",
            description: "Repository name for context.",
            required: false
        ),
        MCPPromptArgument(
            name: "branch",
            description: "Branch name for context.",
            required: false
        ),
    ]

    static let triage = MCPPromptTemplate(
        name: "triage",
        description: "Classify and group Stack notes for review before execution.",
        arguments: sharedArguments,
        bodyTemplate: """
        You are an engineering triage assistant.

        ## Notes

        {noteText}

        ## Context
        Repository: {repositoryName}
        Branch: {branch}

        ## Instructions

        1. Group related notes that should be addressed together.
           - Same intent but different modules = separate groups.
           - User should understand the group just from the title.
        2. For each group: title, intent tag (diagnose/execute/investigate), difficulty (easy/medium/hard).
        3. If a note is ambiguous or exploratory, tag it as investigate — do not promote to execute.
        4. Suggest processing order: easy first, respect dependencies.

        Return JSON: { groups: [{ title, intent, difficulty, noteIDs, rationale }] }
        """
    )

    static let diagnose = MCPPromptTemplate(
        name: "diagnose",
        description: "Perform root cause analysis on grouped notes without executing fixes.",
        arguments: sharedArguments,
        bodyTemplate: """
        You are a senior debugger performing root cause analysis.

        ## Problem Description

        {noteText}

        ## Context
        Repository: {repositoryName}
        Branch: {branch}

        ## Goal
        Identify the root cause. Do NOT execute fixes.

        ## Constraints
        - Hypotheses ranked by likelihood
        - Each hypothesis: verification method (log, test, repro steps)
        - Distinguish symptoms from causes
        """
    )

    static let execute = MCPPromptTemplate(
        name: "execute",
        description: "Implement changes described in grouped notes step by step.",
        arguments: sharedArguments,
        bodyTemplate: """
        You are an implementer working in an existing codebase.

        ## Task

        {noteText}

        ## Context
        Repository: {repositoryName}
        Branch: {branch}

        ## Goal
        Implement the changes step by step.

        ## Constraints
        - Follow existing code patterns
        - Minimal, focused changes
        - Verify each step compiles
        - Do not refactor unrelated code
        """
    )
}
