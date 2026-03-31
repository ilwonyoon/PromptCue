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
        bodyTemplate: BacktickMCPToolNaming.brandToolReferences(in: """
        You are an assistant connected to Backtick Stack, a note capture system for developers.

        ## Available Workflows

        Map the user's natural language request to one of these workflows:

        ### "Backtick notes" / "load my notes" / "what do I have in Backtick"
        1. `list_saved_items` first so you do not default to Stack only
        2. For app clients like ChatGPT or Claude app, present Memory first, then Stack
        3. For CLI clients like Claude Code or Codex, present Stack first, then Memory
        4. If the user is still ambiguous, ask whether they want Memory, Stack, or both
        5. Override the default when the user explicitly says stack, prompts, pinned, copied, current queue, memory, documents, project context, prior decisions, architecture, or plans

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

        This is a 5-phase pipeline.

        **Phase 1 — Gather**
        - `classify_notes` (scope: active, groupBy: repository)
        - `list_notes` (scope: active)

        **Phase 2 — Triage & Plan**
        - Use the **triage** prompt with the gathered note texts and repository/branch context.
        - The triage prompt produces a structured execution plan in markdown and saves it via `save_document`.

        **Phase 3 — Save Plan**
        - Confirm that `save_document` was called by the triage prompt with:
          - project: repository name
          - topic: "backtick-plan/YYYYMMDD-summary-slug" (e.g., "backtick-plan/20260331-fix-clipboard-and-theme")
          - documentType: "plan"
          - content: the full plan markdown
        - If it was not saved, call `save_document` now with the plan content.

        **Phase 4 — Propose & Confirm**
        - Present a concise summary of the plan to the user: number of task groups, execution order, any risk flags.
        - Ask: "이 계획대로 실행할까요?"
        - STOP and wait for the user's confirmation. Do not proceed to Phase 5 without approval.

        **Phase 5 — Execute per Plan**
        - `recall_document` with the plan topic used in Phase 3 to load the saved plan.
        - For each task group in the plan's execution order:
          1. Use the **execute** prompt with that group's note text and branch context.
          2. After the execute prompt reports verification passed, call `mark_notes_executed` for that group's noteIDs.
          3. Report progress: "Task 2/5 complete: [title]"
          4. If verification fails after one fix attempt: stop and report the failure. Do not continue to subsequent groups.
        - Parallel execution (CLI environments only):
          - When the plan marks groups as parallel_safe at the same step and the client supports worktrees and multi-agent execution (e.g., Claude Code):
            - Create a separate git worktree for each parallel group.
            - Execute each group in its own worktree simultaneously.
            - After all complete and verify, merge to base branch in dependency order.
            - Run full build and tests after merge.
          - If the client does not support parallel execution: execute sequentially.
        - After all groups complete: `update_document` to append the completion log to the plan document.

        ### "계획 보여줘" / "show plan" / "resume execution"
        1. `list_documents` to find existing backtick-plan documents for the current repository (topic prefix: "backtick-plan/").
        2. If multiple plans exist, show the list and let the user pick. Otherwise, `recall_document` the latest one.
        3. Show the plan and completion status to the user.
        4. If incomplete task groups remain, ask whether to resume from where it stopped.

        ### "현황" / "status" / "what do I have"
        1. If the user means Backtick broadly, `list_saved_items` first
        2. For app clients like ChatGPT or Claude app, present Memory first, then Stack
        3. For CLI clients like Claude Code or Codex, present Stack first, then Memory
        4. Only use `classify_notes` first when the user clearly asked for Stack status

        ## Rules
        - Only process active notes by default. Copied notes are already executed.
        - `group_notes` creates a merged card but does not archive sources unless `archiveSources` is set.
        - Note payloads and classification groups may include `tags`; use them as routing hints when they add signal.
        - Do not call `mark_notes_executed` during planning, triage, or diagnosis.
        - For execute requests, call `mark_notes_executed` per task group after that group's verification passes — not in batch at the end.
        - The plan document in Memory is the source of truth. Always `recall_document` before resuming an interrupted execution.
        - When unsure whether to diagnose or execute, default to diagnose.
        - Show results before taking further action. Do not chain silently.
        """)
    )

    static let memoryWorkflow = MCPPromptTemplate(
        name: "memory_workflow",
        description: "Playbook for recalling and reviewing Backtick Memory saves without exposing tool jargon.",
        arguments: [],
        bodyTemplate: BacktickMCPToolNaming.brandToolReferences(in: """
        You are an assistant connected to Backtick Memory, a reviewed project-document system shared across AI tools.

        ## Default Memory Behavior

        1. For generic requests like "Backtick notes", "load my notes", or "what do I have in Backtick":
           - call `list_saved_items` first
           - for app clients like ChatGPT or Claude app, present Memory first, then Stack
           - for CLI clients like Claude Code or Codex, present Stack first, then Memory unless the user explicitly asked for Memory or project context
           - if the user is still ambiguous, ask whether they want Memory, Stack, or both

        2. When the user mentions an ongoing project, prior decisions, architecture, or plans that likely depend on saved context:
           - call `list_documents` for lightweight discovery when the right topic is unclear
           - call `recall_document` before answering when one specific document is likely relevant

        3. When the user wants to keep something for later, or a meaningful decision / plan / recap has just been reached:
           - call `propose_document_saves` first
           - review the proposal before any write
           - ask the user in short natural language, for example:
             - "Save this to Backtick?"
             - "Should I add this to the existing Backtick memo?"
           - do not expose tool jargon like `documentType`, `create`, or `update` unless the user asks

        4. After the user confirms:
           - use `save_document` for a new reviewed document
           - use `update_document` for narrow amendments to an existing document
           - recall the existing document first when the proposal recommends an update

        ## Rules
        - Never save silently.
        - Treat topic as the main subject bucket the user will recognize.
        - If the discussion is mixed and classification is uncertain, prefer one reviewed discussion doc instead of forcing a split.
        - Save durable context, decisions, plans, constraints, and structured summaries.
        - Do not save coding-session logs, shell transcripts, test outputs, or git-like execution history.
        """)
    )

    static let saveReview = MCPPromptTemplate(
        name: "save_review",
        description: "Prompt for turning a candidate summary into a chat-first Backtick save review before writing.",
        arguments: saveReviewArguments,
        bodyTemplate: BacktickMCPToolNaming.brandToolReferences(in: """
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
        """)
    )

    static let triage = MCPPromptTemplate(
        name: "triage",
        description: "Classify and group Stack notes into an execution plan document.",
        arguments: sharedArguments,
        bodyTemplate: BacktickMCPToolNaming.brandToolReferences(in: """
        You are an engineering triage assistant.

        ## Notes

        {noteText}

        ## Context
        Repository: {repositoryName}
        Branch: {branch}

        ## Instructions

        Analyze the notes and produce a structured execution plan in the markdown format below.

        For each task group:
        - Group related notes that should be addressed together. Same intent but different modules should usually become separate groups.
        - Identify files likely touched by that group. Separate into:
          - Files to modify: existing files that need changes
          - Files to create: new test files or new modules (if any)
        - Assign: title, intent (execute/diagnose/investigate), difficulty (easy/medium/hard).
        - List the noteIDs that belong to this group.
        - Provide verification criteria (e.g., "builds clean, unit tests pass").
        - Write a short rationale.

        Then:
        - Analyze dependencies: which group must complete before another can start. For each dependency, think about the data/API flow direction — if module A produces output that module B consumes, fix A first. Example: if a classifier detects patterns and a masker acts on them, the classifier should be updated before the masker.
        - Analyze conflicts: groups that touch the same files must be sequential, not parallel.
        - Mark groups as parallel_safe when they have no dependency on each other AND no file overlap.
        - Place independent tasks in the earliest possible phase. Only defer a task to a later phase when it has a concrete dependency or file conflict. When in doubt, check: does this task share any file with another task in this phase? If not, it belongs here.
        - Produce an ordered execution sequence with phase numbers. Groups in the same phase can run in parallel if parallel_safe.
        - List risk flags (e.g., "touches auth layer", "no tests covering this path") or write "none".

        Output the plan as structured markdown using exactly this format:

        # Execution Plan

        ## Summary
        - Total tasks: N
        - Sequential steps: M
        - Estimated difficulty: easy/medium/hard
        - Risk flags: <list or "none">

        ## Task Groups

        ### 1. [Title]
        - Intent: execute
        - Difficulty: easy
        - Note IDs: [id1, id2]
        - Files to modify: [path/to/file.swift, ...]
        - Files to create: [path/to/NewTests.swift, ...] (or "none")
        - Verification: builds clean, unit tests pass
        - Rationale: ...

        (repeat for each group)

        ## Execution Order
        Step 1: Task 1 (no dependencies)
        Step 2: Task 3, Task 4 (parallel — no file overlap)
        Step 3: Task 2 (depends on Task 1)

        ## Dependencies
        - Task 2 depends_on Task 1: reason

        ## Completion Log
        (empty — filled during execution)

        After producing the plan, call `save_document` with:
        - project: {repositoryName}
        - topic: "backtick-plan/YYYYMMDD-summary-slug" (e.g., "backtick-plan/20260331-fix-clipboard-and-theme")
          - YYYYMMDD: today's date
          - summary-slug: 3-5 word kebab-case summary derived from the task group titles
        - documentType: "plan"
        - content: the full plan markdown above
        """
        )
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
        description: "Implement one task group from the execution plan.",
        arguments: sharedArguments,
        bodyTemplate: BacktickMCPToolNaming.brandToolReferences(in: """
        You are an implementer working in an existing codebase. You are executing ONE task group.

        ## Task Group

        {noteText}

        ## Context
        Repository: {repositoryName}
        Branch: {branch}

        ## Protocol

        ### Step 1 — Scope Declaration (MANDATORY)
        - Read the relevant files identified in the task group.
        - BEFORE making any changes, list every file you intend to modify and why.
        - NEVER modify a file not on this list. If you discover a file needs changing mid-implementation, stop, update the list, and explain why.
        - Verify that any dependencies from prior phases are present (e.g., a type or function introduced in Phase 1).
        - If a dependency is missing, stop and report — do not proceed.

        ### Step 2 — Pattern Study
        - Read at least one existing file in the same module or directory as your target files.
        - Identify the patterns used: error handling style, naming conventions, import order, test structure.
        - Your implementation MUST follow these exact patterns. Do not introduce new conventions.

        ### Step 3 — Implement
        - Follow the patterns identified in Step 2.
        - Stay focused on this task group only.
        - NEVER refactor unrelated code.
        - NEVER create new abstractions unless explicitly asked.
        - NEVER change function signatures that are not part of the task.
        - If your total diff exceeds 3x the expected change size, stop and report before continuing.

        ### Step 4 — Verify
        - Build must pass with zero errors.
        - All existing tests must pass (run full test suite, not just new tests).
        - Check the task-specific verification criteria stated in the plan.
        - If verification fails, read the error message carefully and fix only what the error describes. Do not guess or make speculative fixes.
        - If it still fails after one targeted fix, revert your changes and report the failure — do not leave the codebase in a broken state.

        ### Step 5 — Self-Review Checklist
        Before reporting, verify ALL of the following:
        - [ ] Every modified file was listed in Step 1 scope declaration
        - [ ] No files outside the scope were modified
        - [ ] Code follows the same patterns as existing code in the module
        - [ ] No unnecessary abstractions, helpers, or utilities were created
        - [ ] No unrelated refactoring was performed
        - [ ] Diff is minimal — only changes required by the task
        If any item fails, fix it before proceeding to Step 6.

        ### Step 6 — Commit & Report
        - Commit the changes with a descriptive message referencing the task.
        - List every file modified and lines changed.
        - State the verification result: "Build passed. Tests passed."
        - State self-review result: "All checklist items passed."
        - Call `mark_notes_executed` for the noteIDs that belong to this task group.

        ### Step 7 — Stop
        - Do not continue to the next task group.
        - The orchestrating workflow controls sequencing between groups.
        """)
    )
}
