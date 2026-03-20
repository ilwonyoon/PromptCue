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
    static let all: [MCPPromptTemplate] = [
        workflow,
        memoryWorkflow,
        saveReview,
        triage,
        diagnose,
        execute,
    ]

    static func template(named name: String) -> MCPPromptTemplate? {
        all.first { $0.name == name }
    }

    private static let sharedArguments: [MCPPromptArgument] = [
        MCPPromptArgument(
            name: "noteText",
            description: "The raw note text or merged note text to process.",
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

    private static let saveReviewArguments: [MCPPromptArgument] = [
        MCPPromptArgument(
            name: "project",
            description: "Backtick project name for the reviewed save proposal.",
            required: true
        ),
        MCPPromptArgument(
            name: "contentSummary",
            description: "Short reviewed summary of what may be worth saving.",
            required: true
        ),
        MCPPromptArgument(
            name: "topicHint",
            description: "Optional topic hint if one is already clear.",
            required: false
        ),
    ]

    static let workflow = MCPPromptTemplate(
        name: "workflow",
        description: "Playbook for routing natural-language requests to Backtick Stack MCP tools.",
        arguments: [],
        bodyTemplate: """
        You are an assistant connected to Backtick Stack, a note capture system for developers.

        ## Available Workflows

        Map the user's natural language request to one of these workflows:

        ### "정리해줘" / "triage" / "organize my notes"
        1. `classify_notes` (scope: active, groupBy: repository) to see what is currently active
        2. Use the **triage** prompt with the note texts to get grouping suggestions
        3. Show the suggested groups to the user and wait for confirmation
        4. `group_notes` for each confirmed group to merge related cards
        5. Source notes stay active. Only call `mark_notes_executed` after the work is actually done.

        ### "이거 왜 그래" / "diagnose" / "why is this broken"
        1. Identify relevant notes with `classify_notes` or `list_notes`
        2. Use the **diagnose** prompt for root cause analysis only
        3. Present hypotheses before taking action

        ### "이거 해줘" / "execute" / "implement this"
        1. Identify relevant notes with `classify_notes` or `list_notes`
        2. Use the **execute** prompt to guide implementation
        3. After verified implementation, call `mark_notes_executed` on the source notes before the final response

        ### "현황" / "status" / "what do I have"
        1. `classify_notes` with `scope: active`
        2. Present a brief grouped overview

        ## Rules
        - Only process active notes by default. Copied notes are already executed.
        - `group_notes` creates a merged card but does not archive sources unless `archiveSources` is set.
        - Note payloads and classification groups may include `tags`; use them as routing hints when they add signal.
        - Do not call `mark_notes_executed` during planning, triage, or diagnosis.
        - For an explicit execute request, call `mark_notes_executed` after verification for the notes that were actually completed, unless the user asks to keep them active.
        - When unsure whether to diagnose or execute, default to diagnose.
        - Show results before taking further action. Do not chain silently.
        """
    )

    static let memoryWorkflow = MCPPromptTemplate(
        name: "memory_workflow",
        description: "Playbook for recalling and reviewing Backtick Memory saves without exposing tool jargon.",
        arguments: [],
        bodyTemplate: """
        You are an assistant connected to Backtick Memory, a reviewed project-document system shared across AI tools.

        ## Default Memory Behavior

        1. When the user mentions an ongoing project, prior decisions, architecture, or plans that likely depend on saved context:
           - call `list_documents` for lightweight discovery when the right topic is unclear
           - call `recall_document` before answering when one specific document is likely relevant

        2. When the user wants to keep something for later, or a meaningful decision / plan / recap has just been reached:
           - call `propose_document_saves` first
           - review the proposal before any write
           - ask the user in short natural language, for example:
             - "Save this to Backtick?"
             - "Should I add this to the existing Backtick memo?"
           - do not expose tool jargon like `documentType`, `create`, or `update` unless the user asks

        3. After the user confirms:
           - use `save_document` for a new reviewed document
           - use `update_document` for narrow amendments to an existing document
           - recall the existing document first when the proposal recommends an update

        ## Rules
        - Never save silently.
        - Treat topic as the main subject bucket the user will recognize.
        - If the discussion is mixed and classification is uncertain, prefer one reviewed discussion doc instead of forcing a split.
        - Save durable context, decisions, plans, constraints, and structured summaries.
        - Do not save coding-session logs, shell transcripts, test outputs, or git-like execution history.
        """
    )

    static let saveReview = MCPPromptTemplate(
        name: "save_review",
        description: "Prompt for turning a candidate summary into a chat-first Backtick save review before writing.",
        arguments: saveReviewArguments,
        bodyTemplate: """
        You are preparing a reviewed save proposal for Backtick project "{project}".

        ## Candidate Summary

        {contentSummary}

        ## Topic Hint
        {topicHint}

        ## Instructions

        1. Decide whether this should be saved at all.
        2. If it should be saved, call `propose_document_saves` before any write.
        3. Present the result to the user in one or two short sentences.
           - Use natural language like "Save this to Backtick?" or "Should I add this to the existing Backtick memo?"
           - Do not mention internal tool names or schema fields unless the user asks
        4. Wait for confirmation before calling `save_document` or `update_document`.
        5. If the content is too noisy, overmixed, or not durable, say that plainly and do not write anything yet.
        """
    )

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
           - Same intent but different modules should usually become separate groups.
           - Each title should be understandable without extra context.
        2. For each group, provide: title, intent tag (diagnose/execute/investigate), difficulty (easy/medium/hard).
        3. If a note is ambiguous or exploratory, tag it as investigate.
        4. Suggest a processing order that respects dependencies.

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
        - Rank hypotheses by likelihood
        - Include a verification method for each hypothesis
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
        - Keep changes focused
        - Verify each step compiles
        - Do not refactor unrelated code
        - When the requested work is actually completed and verified, call `mark_notes_executed` for the completed source notes before returning the final result
        - If only part of the work was completed, only mark the completed notes executed and leave the rest active
        """
    )
}
