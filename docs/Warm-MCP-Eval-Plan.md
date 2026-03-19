# Warm MCP Eval Plan

Purpose: dogfood the first Warm MCP tools against the way people actually ask for durable memory writes, not against storage internals.

Scope for this phase:

- `list_documents`
- `recall_document`
- `save_document`
- `update_document`

The goal is **not** "did a tool run?" The goal is:

- did the model choose the right `documentType`
- did it prefer `list` / `recall` before write
- did it update the right existing doc instead of creating topic sprawl
- did it save structured markdown rather than transcript sludge

## Recommended First Pass

Run the first Warm MCP dogfood pass across both `ChatGPT` and `Claude`, not in a single client only.

Why:

- the product promise is cross-client durable context
- a save in one client should be reusable from another client without re-explaining
- the riskiest failures are topic sprawl, wrong `documentType`, and skipped recall before answer

Recommended order:

1. `ChatGPT`: save a `reference` doc
2. `Claude`: recall that `reference` before answering
3. `ChatGPT`: save an architecture `reference`
4. `Claude`: update that architecture `reference`
5. `ChatGPT`: save a `plan`
6. `Claude`: save or update a `decision`
7. `ChatGPT`: recall that `decision` before answering

This first pass is intentionally manual. Do **not** add a special eval runner yet. The current gap is model behavior, not transport or storage correctness.

## Core Tool Guardrails

These rules belong in the shared Warm MCP tool behavior regardless of client:

- save durable context, decisions, plans, constraints, and structured summaries
- do **not** save coding-session logs
- do **not** save file-by-file change logs
- do **not** save shell transcripts or test-command transcripts
- do **not** save git-like execution history
- use `update_document` for narrow durable changes instead of rewriting an entire doc

The point of Warm Memory is to help a future AI session resume project context, not to duplicate `git log`, terminal history, or a coding activity feed.

## Claude Code Handoff

If the fastest next step is a repo-local eval in `Claude Code`, use this repo itself as the source corpus instead of inventing a blank project.

Why:

- the repo already contains realistic product, planning, and MCP context
- Claude Code can read the local docs directly
- this isolates Warm tool behavior from transport noise

Use a separate eval project namespace so results do not pollute future real Warm docs:

- recommended project: `Backtick-eval-claude`

Use these repo docs as the primary source corpus:

- `docs/Execution-PRD.md`
- `docs/Implementation-Plan.md`
- `docs/MCP-Platform-Expansion-Research.md`
- `docs/Warm-MCP-Eval-Plan.md`

When the eval needs the latest implemented Warm behavior, also inspect the current code:

- `Sources/BacktickMCPServer/BacktickMCPServerSession.swift`
- `PromptCue/Services/ProjectDocumentStore.swift`

If roadmap docs and current code disagree, prefer the current Warm tool surface and validation logic over older planning language.

Claude Code should evaluate behavior against these rules:

- use MCP Warm tools, not local file writes, for durable memory actions
- prefer `list_documents` when topic or doc fit is ambiguous
- prefer `recall_document` before answering or before amending an existing durable doc
- prefer `update_document` over `save_document` for narrow deltas
- do not save coding-session logs, file-by-file change logs, shell transcripts, test-command transcripts, or git-like execution history
- keep topics tight and reusable
- after each write or recall step, report which MCP tools were called and which `(project, topic, documentType)` was used

### Claude Code Copy-Paste Prompt

```text
You are evaluating Backtick Warm Memory behavior inside the PromptCue repo.

Context:
- Use the local repo docs as source material:
  - docs/Execution-PRD.md
  - docs/Implementation-Plan.md
  - docs/MCP-Platform-Expansion-Research.md
  - docs/Warm-MCP-Eval-Plan.md
- Also inspect the current Warm implementation in:
  - Sources/BacktickMCPServer/BacktickMCPServerSession.swift
  - PromptCue/Services/ProjectDocumentStore.swift
- If planning docs and current code disagree, prefer the current Warm tool surface and validation logic.
- Do not create or modify repo files for the evaluation itself.
- Use Backtick MCP Warm tools for durable memory actions.
- Use the project name Backtick-eval-claude for every durable document created in this eval.

Behavior rules:
- Prefer list_documents when topic or documentType fit is ambiguous.
- Prefer recall_document before answering and before updating an existing durable doc.
- Prefer update_document over save_document for narrow amendments.
- Do not save coding-session logs, file-by-file change logs, shell transcripts, test-command transcripts, or git-like execution history.
- Keep topic reuse tight. Do not create near-duplicate topics unless clearly necessary.
- After each evaluation step, explicitly report:
  1. which MCP tool calls you made
  2. which (project, topic, documentType) you used
  3. whether the result looked correct or suspicious

Run this sequence:

1. Read the repo docs above and save a short durable project brief for Backtick-eval-claude.
   - Expected shape: topic=brief, documentType=reference

2. Save a durable architecture summary for Backtick-eval-claude focused on Stack, MCP, and Warm Memory.
   - Expected shape: topic=architecture, documentType=reference

3. Save only the latest durable Warm Memory decisions for Backtick-eval-claude.
   - Expected shape: topic=warm-memory, documentType=decision

4. Update the Warm Memory decision document with the newer decision that phase 1 stays limited to storage plus `list_documents`, `recall_document`, `save_document`, and `update_document`, and that coding-session logs do not belong in Warm docs.
   - Prefer updating the existing decision doc rather than creating a new one.

5. Recall the current Warm Memory decision document and summarize the current direction.
   - Do not save anything in this step.

At the end, give a short evaluation:
- whether documentType choice was correct
- whether topic reuse was clean
- whether any step created avoidable sprawl
- whether any write should have been an update instead
```

## ChatGPT / Claude App Handoff

For `ChatGPT` web/macOS/iPhone and `Claude` desktop-style app evals, the expected durable outputs are usually more product- and planning-oriented than code-session-oriented.

Bias these clients toward:

- project briefs
- architecture summaries
- implementation briefs or PRD-shaped plans
- latest settled pricing, launch, or product decisions
- recap documents that preserve options and open questions

Still apply the same core guardrails:

- no coding-session logs
- no file-by-file change logs
- no shell or test-command transcripts
- no git-like execution history

Use app-style eval asks when you want to validate whether natural user language such as "turn this into a PRD" or "save the latest decisions" maps cleanly onto the Warm tools.

## Eval Rules

- Prefer realistic user asks over synthetic API-shaped requests.
- Evaluate on durable outcomes, not raw conversation replay.
- `PRD` is a `plan`-shaped output, not a new `documentType`.
- "Latest decisions" should usually update a `decision` doc, not create a new one.
- `list_documents` is the discovery step when topic or `documentType` is unclear.
- `recall_document` should happen proactively when prior durable context matters.
- `update_document` should win over `save_document` for narrow deltas.

## Core Intents

| Intent | Expected `documentType` | Expected tool flow | Main failure to watch |
|--------|--------------------------|--------------------|-----------------------|
| Turn this conversation into a PRD / implementation brief | `plan` | `list_documents` → `recall_document` if matching plan exists → `save_document` or `update_document` | Wrongly saved as `discussion`, or raw transcript dumped into content |
| Save only the latest decisions | `decision` | `list_documents` → `recall_document` → `update_document` | Creates a new doc instead of amending the current decision doc |
| Save a recap of what we explored | `discussion` | `list_documents` → `save_document` or `update_document` | Over-compressed into decision bullets with no rationale/open questions |
| Save a project brief / architecture summary / constraints | `reference` unless clearly execution-oriented | `list_documents` → `recall_document` if matching doc exists → `save_document` or `update_document` | Misclassified as `plan` when no execution framing exists |
| Answer using prior durable context first | existing type | `list_documents` or `recall_document` before answering | Skips recall and answers from scratch |

## Prompt Set

### 1. PRD Save

```text
Turn this conversation into a PRD for the Backtick onboarding flow and save it for later.
```

Expected:

- chooses `documentType=plan`
- uses an existing `onboarding`-like topic if one already exists
- saves structured markdown with `##` headers such as `## Goal`, `## User Flow`, `## Open Questions`

Watch for:

- `discussion` used instead of `plan`
- transcript-like content
- no recall/list before write when a matching doc already exists

### 2. Latest Decisions Only

```text
Document only the latest decisions we made about pricing and save them.
```

Expected:

- chooses `documentType=decision`
- prefers `update_document` if a `pricing` decision doc already exists
- writes only the new settled choices, not the full conversation recap

Watch for:

- rewriting the whole doc when only one section changed
- saving rationale/options as if this were a `discussion` recap

### 3. Project Brief

```text
Write a short project brief from what we just decided and keep it in memory.
```

Expected:

- usually `documentType=reference`
- may become `plan` only if the content is clearly execution-oriented
- concise but still structured markdown

Watch for:

- ambiguous `documentType`
- single-paragraph summary with no headings

### 4. Architecture Summary Update

```text
Update our architecture summary with what we just decided about remote MCP and OAuth recovery.
```

Expected:

- targets an existing `reference` or `discussion` doc for `architecture`
- uses `recall_document` first
- uses `update_document` on a single relevant section

Watch for:

- creating a duplicate architecture doc
- using `save_document` for a tiny amendment

### 5. Discussion Recap

```text
Save a recap of this conversation about branding options so we can pick it up later.
```

Expected:

- chooses `documentType=discussion`
- preserves alternatives, rationale, and open questions

Watch for:

- premature conversion into a `decision` doc
- dropping unresolved options

### 6. Recall Before Answering

```text
Before answering, load the current Backtick pricing decisions and use them in your response.
```

Expected:

- recalls a `decision` doc before answering
- does not save anything unless asked

Watch for:

- answering without recall
- over-eager write

### 7. Existing Topic Fit

```text
Save this as durable context for our website work, but fit it into an existing topic if one already exists.
```

Expected:

- runs `list_documents`
- reuses existing `website` topic if present
- only creates a new topic if clearly distinct

Watch for:

- topic explosion from near-duplicate topics

### 8. Narrow Section Change

```text
Only update the open questions section of our launch plan with the two unresolved items from this chat.
```

Expected:

- `documentType=plan`
- `recall_document` first
- `update_document(action=replace_section)` or `append` depending on section state

Watch for:

- whole-doc rewrite
- wrong section targeting

### 9. No Durable Save

```text
Summarize what we just discussed for this answer, but do not save anything yet.
```

Expected:

- no `save_document`
- no `update_document`

Watch for:

- over-eager save

## First Manual Run Order

Use the same project name throughout, for example `Backtick`.

### A. ChatGPT saves a project brief

```text
Write a short project brief from what we just decided about Backtick and keep it in memory.
```

Expected:

- chooses `documentType=reference`
- saves structured markdown with `##` headings
- fits into an existing `brief` or equivalent topic if one already exists

### B. Claude recalls before answering

```text
Before answering, load the current Backtick project brief and use it in your response.
```

Expected:

- recalls before answering
- does not save anything

### C. ChatGPT saves an architecture summary

```text
Save an architecture summary for the Backtick MCP stack so future sessions can reuse it.
```

Expected:

- chooses `documentType=reference`
- saves durable background, not an execution plan

### D. Claude updates that architecture summary

```text
Update our architecture summary with what we just decided about remote MCP and OAuth recovery.
```

Expected:

- recalls first
- uses a narrow update instead of rewriting the whole doc

### E. ChatGPT saves a PRD

```text
Turn this conversation into a PRD for the Backtick onboarding flow and save it for later.
```

Expected:

- chooses `documentType=plan`
- writes a `plan`-shaped doc with sections like `## Goal`, `## User Flow`, `## Open Questions`

### F. Claude saves only latest pricing decisions

```text
Document only the latest decisions we made about pricing and save them.
```

Expected:

- chooses `documentType=decision`
- updates an existing pricing decision doc if present
- stores settled choices only

### G. ChatGPT recalls pricing decisions before answering

```text
Before answering, load the current Backtick pricing decisions and use them in your response.
```

Expected:

- recalls the existing `decision` doc before answering
- does not save anything

## Pass Criteria

- correct `documentType` chosen for the user ask
- existing topic/doc reused when appropriate
- markdown is structured and durable
- no raw transcript dumps
- no save when the user only asked for recall or answer-time context
- no unnecessary whole-doc rewrite for section-level deltas

## Failure Patterns To Track

- `plan` vs `reference` confusion
- `discussion` vs `decision` confusion
- skipping `list_documents` when topic fit is ambiguous
- skipping `recall_document` before write
- creating duplicate topics
- over-eager save on read-only asks
- transcript-shaped content instead of reviewed markdown

## Recorded Results

### Single-Client Baselines

- `Claude Code` single-client eval passed on `Backtick-eval-claude`
  - stored `brief/reference`, `architecture/reference`, and `warm-memory/decision`
  - reused the same `warm-memory` topic for update
  - chose `update_document` instead of `save_document` for a narrow amendment
- `Codex` single-client eval passed on `Backtick-eval-codex`
  - tool/storage contract verified directly in the local CLI lane
  - stored the same three durable docs with one superseded `warm-memory/decision` version after update

Observed difference:

- Claude produced richer decision content but could drift stale when it relied too heavily on planning docs
- Codex produced fresher brief/reference content when it was grounded in the current tool surface and implementation

This is why shared eval prompts should inspect current code as well as planning docs when the latest implemented Warm behavior matters.

### Shared Cross-Client Handoff

Shared eval project: `Backtick-eval-shared`

Verified sequence:

1. `Claude` saved `brief/reference`
2. `Codex` recalled that same `brief/reference` and updated only `## Current Status`
3. `Codex` saved `warm-memory/decision`
4. `Claude` recalled that same `warm-memory/decision` and appended `## Phase 1 Scope Lock`

What passed:

- cross-client recall worked
- cross-client update worked
- existing `(project, topic, documentType)` docs were reused instead of creating new topics
- supersession worked for both `brief/reference` and `warm-memory/decision`
- `update_document` was used for narrow amendments instead of whole-doc rewrites

Current shared baseline is sufficient to move past single-client validation and into broader cross-client dogfood.

Optional follow-up:

- add one more shared `architecture/reference` handoff if we want extra confidence on reference-doc updates, but this is no longer the critical path
