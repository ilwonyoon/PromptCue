# MCP Polish Plan

## Purpose

Lock the next MCP and Memory polish direction for Backtick so the product language, save behavior, and durable document model stop drifting apart.

This plan exists because the current Warm Memory lane exposed three problems at once:

- terminology drift between product/UI/docs/MCP/internal concepts
- automatic save behavior that is too eager and too opaque
- saved content that often keeps the wrong level of detail or the wrong document shape

The goal of this slice is not to add more MCP surface area first. The goal is to make the existing Memory lane understandable, predictable, and reviewable.

## Draft Direction

### Product Vocabulary

Backtick should use one consistent product vocabulary:

- `Prompt`
- `Memory`

Meaning:

- `Prompt` = the short-lived active working surface for prompt staging and immediate next actions
- `Memory` = the durable reviewed surface for longer-lived project context

Backtick remains the product name. `Prompt` and `Memory` are the two user-facing surfaces.

### Deprecated Vocabulary

These terms should be treated as deprecated for product-facing language:

- `Stack`
- `Hot`
- `Warm`

They may exist temporarily in old docs or code, but they should stop being the source vocabulary for new product, MCP, and UX decisions.

### Internal Vocabulary Rule

The target is one shared vocabulary across product, docs, MCP, and internal architecture:

- prefer `Prompt`
- prefer `Memory`

Do not keep separate conceptual languages for users and for internal planning if they describe the same product surface. That split creates avoidable confusion.

Implementation detail:

- code symbol migration may still land in slices
- but the intended vocabulary should be singular from this point on

## Information Architecture

### Prompt

`Prompt` is the active, short-lived surface.

It covers:

- quick capture
- prompt staging
- short-lived execution context
- immediate export/copy/send behavior

`Capture` becomes an interaction or entry behavior inside the Prompt lane, not a separate top-level mental model.

### Memory

`Memory` is the durable, reviewed, project-context surface.

It covers:

- saved decisions
- plans
- background context
- reviewed discussion summaries

The Memory viewer should feel topic-first, not schema-first.

## Topic And Type Model

### User-Visible Rule

Users should primarily see:

- project
- topic
- document content

Users should not need to think in `discussion / decision / plan / reference` during normal browsing.

### Internal Rule

`documentType` remains an internal storage and behavior contract.

Its job is to help:

- save/review behavior
- update rules
- retrieval behavior
- proposal quality

It is not the primary user-facing navigation model.

### Topic Rule

`topic` is the subject of the document, not the shape of the document.

Good topics:

- `tax-2025`
- `launch-pricing`
- `memory-save-flow`
- `company-research-pipeline`

Bad topics:

- `decision`
- `reference`
- `warm-memory`
- other internal taxonomy or implementation jargon

### Topic Generation Rule

Do not over-constrain topic creation with a rigid fixed taxonomy.

The model should be allowed to propose topics from the actual conversation context, with these guardrails:

- reuse an existing topic if it is clearly the same subject
- prefer narrower subject names over broad buckets
- avoid internal jargon
- avoid near-duplicates

## Save Behavior

### Default Save Flow

The default Memory save flow is:

- `proposal`
- `review`
- `confirm`
- `write`

This applies even when the user says "save this."

The point is not to block saving. The point is to let the user confirm:

- what is being saved
- under which topic
- whether it is a new document or an update
- whether the preview is clean enough to keep

### Why Direct Save Is Not The Default

Long discussions are hard to classify correctly after the fact.

Failure modes already seen:

- the wrong topic gets chosen
- internal jargon leaks into topics
- `documentType` is technically valid but user-expectation-invalid
- one document mixes decisions, plans, exploration, and implementation noise
- the saved result becomes a polished report instead of useful future context

### Long-Thread Rule

Do not directly auto-split a long mixed thread into multiple final Memory docs by default.

If the boundaries are unclear:

- first propose what should be saved
- if needed, fall back to one reviewed Memory summary
- only extract multiple shaped documents after review

## Proactive Behavior

Backtick should proactively notice when a save might help.

Examples:

- a meaningful decision was reached
- a plan was settled
- a long discussion is wrapping up
- a repeated explanation is likely to be needed again

The desired behavior is:

- ask first
- do not save silently

Preferred wording:

- `이 내용을 Backtick Memory에 저장할까요?`
- `이 결정 백틱 메모리에 남겨둘까요?`

Do not say only:

- `메모리에 저장할까요?`

That wording collides with built-in model memory.

## Saved Content Quality

### Save This

Save durable project context such as:

- key decisions and why they were made
- active plans and next-step structure
- durable constraints
- project-specific background that future sessions will need
- reviewed summaries of explored options

### Do Not Save This

Do not save:

- coding-session logs
- file-by-file change logs
- shell transcripts
- test-command transcripts
- git-like execution history
- noisy implementation detail that changes day to day
- raw conversation transcripts
- taxonomy or jargon that only makes sense to the implementation

### Quality Standard

A good Memory document should help a future AI session resume work quickly.

It should not read like:

- a manual
- a changelog
- a terminal transcript
- a polished consulting report

It should read like:

- reviewed project context
- clear decisions
- active direction
- useful durable state

## MCP Contract Implications

The next MCP contract should reflect the review-first model.

### Keep

- `list_documents`
- `recall_document`
- `save_document`
- `update_document`

### Add

- `propose_document_saves`

`propose_document_saves` should be read-only and should return:

- proposed topic
- internal `documentType`
- create vs update recommendation
- why this is worth saving
- preview text
- warnings if the content is noisy or overmixed

### `propose_document_saves` Request Shape

The first implementation should stay minimal and explicit.

Proposed input:

```json
{
  "project": "backtick",
  "content": "Short reviewed summary of what the user may want to keep.",
  "userIntent": "latest_decisions",
  "preferredTopic": null,
  "maxProposals": 3
}
```

Rules:

- `project` is required
- `content` is required
- `userIntent` is optional but encouraged
- `preferredTopic` is optional
- `maxProposals` defaults to `3`

Why `content` exists:

- MCP tools do not directly receive the whole chat transcript
- the model must pass a concise candidate summary instead of forcing the server to classify an implicit conversation it cannot see
- the supplied content should be shorter and cleaner than a raw transcript

Recommended `userIntent` values:

- `general`
- `latest_decisions`
- `project_brief`
- `architecture_summary`
- `discussion_recap`
- `implementation_plan`
- `prd`

This is a hint, not a hard taxonomy.

### `propose_document_saves` Response Shape

The tool should return a small list of candidate proposals plus review warnings.

Proposed output:

```json
{
  "project": "backtick",
  "count": 1,
  "warnings": [],
  "proposals": [
    {
      "proposalID": "uuid",
      "topic": "memory-save-flow",
      "documentType": "decision",
      "confidence": "high",
      "operation": "create",
      "rationale": "The discussion reached a settled save-flow decision.",
      "preview": "## Save Flow Decision\\n\\n...",
      "existingDocument": null,
      "warnings": [],
      "review": {
        "displayTopic": "memory save flow",
        "summary": "This looks worth keeping in Backtick as memory save flow.",
        "confirmPrompt": "Save this to Backtick?",
        "hideInternalFieldsByDefault": true
      },
      "recommendation": {
        "kind": "create",
        "tool": "save_document",
        "needsRecall": false
      }
    }
  ],
  "globalWarnings": [],
  "recommendedNextStep": "confirm_one_proposal"
}
```

Field meanings:

- `project` = project namespace proposals were generated against
- `count` = number of returned proposals
- `proposalID` = ephemeral identifier for the review step
- `topic` = subject name the user will mostly recognize
- `documentType` = internal storage shape
- `confidence` = low, medium, or high confidence in the proposal fit
- `operation` = `create` or `update`
- `rationale` = one short explanation of why this candidate exists
- `preview` = reviewed markdown preview, not transcript text
- `existingDocument` = optional current doc summary if the best action is update
- `warnings` = proposal-local quality issues
- `review` = chat-first review copy the assistant can use without exposing tool jargon
- `globalWarnings` = discussion-level issues that affect all proposals
- `recommendation` = how the next write step should proceed if the user confirms

Recommended warning values:

- `mixed_content`
- `too_much_technical_noise`
- `topic_too_broad`
- `topic_may_duplicate_existing_doc`
- `classification_uncertain`
- `preview_needs_trimming`

Recommended `existingDocument` shape:

```json
{
  "project": "backtick",
  "topic": "memory-save-flow",
  "documentType": "decision",
  "updatedAt": "2026-03-19T22:59:38Z"
}
```

Recommended `recommendation` shape:

```json
{
  "kind": "update",
  "tool": "update_document",
  "needsRecall": true
}
```

Recommended `review` shape:

```json
{
  "displayTopic": "memory save flow",
  "summary": "This looks worth keeping in Backtick as memory save flow.",
  "confirmPrompt": "Save this to Backtick?",
  "hideInternalFieldsByDefault": true
}
```

The safest fit is to keep the existing MCP outer envelope unchanged and only add this proposal payload as the tool result body, following the same `content -> text -> JSON` pattern the current server already uses for tool results.

### Review Outcome Shape

The user review step should reduce to one of a small set of outcomes:

- `confirm`
- `confirm_with_topic_edit`
- `confirm_with_preview_edit`
- `skip`
- `ask_for_new_proposal`

The important point is that write tools do not run until one of the confirm states happens.

### Behavior Rules

- recall before answer when durable context likely matters
- ask before write when a save is useful
- never silently auto-save
- use `update_document` for narrow changes
- treat topic as the main subject bucket, not internal schema

## UI Implications

### Memory Viewer

The Memory viewer should stay topic-first.

Primary visible structure:

- project
- topic list
- document body

`documentType` may still exist for filtering, badges, or diagnostics, but it should not dominate the IA.

### Save Review UI

The next minimum UI need is a save review step, not a fully automatic summarizer.

The user should be able to see:

- what Backtick plans to save
- where it plans to save it
- whether it is a new doc or an update
- whether technical noise should be removed first

### Minimum UX: Chat Review First

The first save-review UX should be chat-mediated, not app-modal.

Reason:

- Backtick already reaches multiple AI clients
- the assistant can ask and receive confirmation in the current thread
- a native macOS confirmation sheet would not help ChatGPT web or Claude iPhone

Desired flow:

1. a meaningful decision or wrap-up appears
2. the model calls `propose_document_saves`
3. the model shows 1 to 3 reviewed proposals in chat
4. the user confirms, edits, or skips
5. only then does the model call `save_document` or `update_document`

The default chat presentation should include:

- topic
- operation
- one-line rationale
- short preview
- any warning badge in plain language

### Native Backtick Review Surface

Backtick app UI should support this later, but it is not required for the first usable slice.

The first native integration point should be lightweight:

- a temporary save-review card or sheet
- opened from Memory, not from Prompt
- focused on confirm/edit/skip, not long-form editing first

Suggested fields:

- project
- topic
- preview
- create vs update label
- warning summary

Suggested actions:

- `Save`
- `Edit Topic`
- `Trim Preview`
- `Skip`

### Existing UI Reuse Direction

Current insertion point is likely the Memory lane, not the Prompt lane.

Why:

- Memory already owns durable docs
- [MemoryViewerView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerView.swift) already has project/topic/detail structure
- [MemoryViewerModel.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerModel.swift) already owns refresh, selection, copy, and edit/save of current docs

That suggests the first native UX should be:

- proposal list adjacent to document browsing
- or a lightweight review state inside the Memory viewer

not:

- a brand new panel
- a Prompt-side blocking modal

### Prompt And Tooling Companion

This tool should be paired with prompt/workflow guidance, not only a raw tool description.

Companion prompt/workflow candidates:

- `save_latest_decisions`
- `save_project_brief`
- `save_architecture_summary`
- `save_as_prd`

Those should remain optional UX sugar on top of the core tool contract, not replacements for it.

## Migration Work

### Vocabulary Migration

Planned migration target:

- user-facing `Stack` -> `Prompt`
- old internal `Hot/Warm` references -> `Prompt/Memory`

This should be treated as one naming direction even if implementation lands in slices.

### Existing Memory Cleanup

Existing saved docs and examples that use broad or internal-jargon topics should be corrected over time.

Examples to avoid going forward:

- `warm-memory`
- type-like topics
- architecture-bucket topics that are really several separate subjects

## Next Slices

1. lock `Prompt / Memory` terminology in docs and MCP copy
2. add `propose_document_saves` with the request/response shape above
3. add proposal/review/confirm behavior to MCP instructions and prompts
4. ship chat-level review UX before native review UI
5. add a lightweight native save-review surface inside Memory
6. add lint rules that flag noisy or overmixed save proposals
7. clean up existing example docs and eval fixtures to use better topic naming

## Success Criteria

This polish slice is successful when:

- Backtick consistently speaks in `Prompt / Memory`
- users are not asked to understand internal document types
- save behavior is proposal-first instead of silent or direct
- topics feel like real subjects, not internal categories
- saved docs stop accumulating technical/session noise
- future AI sessions can resume work from Memory without reading a transcript
