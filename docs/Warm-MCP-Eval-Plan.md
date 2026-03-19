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
