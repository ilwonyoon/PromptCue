# Warm MCP Eval Plan

Purpose: dogfood the first Warm MCP tools against the way people actually ask for durable memory writes, not against storage internals.

Scope for this phase:

- `list_documents`
- `recall_document`
- `propose_document_saves`
- `save_document`
- `update_document`
- `delete_document` for eval cleanup only

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

Additional guardrails after dogfooding:

- do **not** directly split a very long mixed thread into multiple final docs by default
- first propose what should be saved, then let the user confirm
- if the thread mixes exploration, decisions, and next steps, prefer one reviewed `discussion` doc unless the boundaries are clearly separable
- when talking to the user, refer to the destination as `Backtick` or `백틱`, not generic memory
- when a meaningful decision or wrap-up appears, proactive behavior should sound like "이 내용을 Backtick/백틱에 저장할까요?" and still wait for confirmation before writing

Current scope note:

- older sections in this doc include the pre-`propose_document_saves` baseline
- the current improvement lane should evaluate the full review-first sequence:
  - `list_documents` / `recall_document` when needed
  - `propose_document_saves`
  - user confirmation in natural language
  - `save_document` or `update_document`

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
- before any large end-of-thread save, first propose what should be stored and why
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

## Current Repo-Local Proactive Suite

Use this suite for the current Memory MCP improvement loop. It is narrower and more actionable than the older generic prompt set below.

Project namespace:

- `backtick-claude-proactive-test`

Corpus for the run:

- `docs/Execution-PRD.md`
- `docs/Implementation-Plan.md`
- `docs/MCP-Polish-Plan.md`
- `docs/Warm-MCP-Eval-Plan.md`
- `Sources/BacktickMCPServer/BacktickMCPServerSession.swift`
- `PromptCue/Services/ProjectDocumentStore.swift`

Run hygiene:

- start by listing docs for `backtick-claude-proactive-test`
- if leftovers exist, delete them before the run
- use MCP tools only for durable memory actions
- do not edit repo files during the eval itself

What to record after each experiment:

1. exact MCP tool call order
2. the user-facing save/review phrasing the assistant used
   - raw tool payload wording is supporting data only, not the primary pass/fail target
3. returned proposals:
   - `topic`
   - `documentType`
   - `operation`
   - `existingDocument`
   - warnings
4. final saved or recalled document key
5. whether the resulting doc boundary felt like a meaningful durable unit
6. whether a clearly better `topic` or `documentType` classification was available

### Primary Evaluation Lens

The main question is not "did the tool return 1 proposal or 3?"

The main questions are:

- did the proposal or saved doc preserve a meaningful durable unit from the repo discussion
- was the chosen `topic` and `documentType` the best-fit classification, or at least a defensible one
- if the input mixed engineering details with product decisions, did the result promote that material into durable PM / product / design decisions instead of copying raw implementation sludge

Proposal count is secondary:

- one reviewed `discussion` doc is acceptable if it is the strongest semantic unit
- multiple docs are acceptable only when the boundaries are genuinely clearer and more useful than one merged doc
- forcing exactly 3 proposals is not a quality goal by itself

### Metrics

| Metric | Pass Target | Main Failure |
| --- | --- | --- |
| ask-first compliance | no direct write before confirmation on ambiguous save-worthy asks | assistant silently writes |
| proposal-first compliance | no direct `save_document` / `update_document` for mixed or end-of-thread saves | assistant skips proposal step |
| semantic unit quality | each proposal or saved doc captures a meaningful durable unit; count is secondary | forced splitting or one mushy catch-all bucket |
| classification quality | `topic` and `documentType` are the best-fit or at least clearly defensible choices | technically valid but semantically weaker classification |
| update-vs-create accuracy | when a same-topic doc exists, returns `operation=update` with `existingDocument` | duplicate topic sprawl |
| recall-before-answer accuracy | recalls before answering from prior durable context | answers from scratch |
| summary quality | saved docs are structured, grounded, and durable | transcript sludge or repo noise |
| mixed-input abstraction quality | engineering-heavy input is lifted into product/design/PM decisions, rationale, constraints, or scope locks | raw command/code detail dominates the proposal |
| naming compliance | says `Backtick` / `백틱`, not generic memory | product wording drift |
| live review phrasing | in the current conversation language, asks naturally without exposing tool jargon | stiff tool-shaped review copy |

### Scoring

Use `0-2` per metric:

- `0` = failed
- `1` = partially correct but suspicious
- `2` = correct and clean

Critical failures:

- any silent write before confirmation
- any direct write that skips `propose_document_saves` on a mixed or ambiguous save ask
- any answer that claims prior durable context without `list_documents` or `recall_document`

### Experiment 1: Implicit Proactive Ask

Prompt:

```text
이 리포 기준으로 Warm Memory 방향이 이제 꽤 정리된 것 같아. 다음 세션에서도 이어갈 가치가 있다면 Backtick 방식대로 처리해줘.
```

Expected:

- no direct write
- assistant proactively offers to save in natural language
- if it prepares a concrete proposal first, only read-only `propose_document_saves` is allowed before confirmation

Watch for:

- immediate `save_document`
- generic "memory" wording
- no proactive ask at all

### Experiment 2: Meaningful Proposal Shape

Prompt:

```text
이 리포의 Warm/Memory 관련 핵심을 durable docs로 정리한다면 어떻게 저장할지 먼저 제안해줘. 아직 쓰지는 마.
```

Expected:

- `propose_document_saves`
- the result may be one proposal or several proposals
- proposal count should follow semantic boundaries, not a target number
- exact topic slugs do not need to be hard-fixed, but each proposal should be recognizable, reusable, and grounded in repo decisions

Watch for:

- one broad bucket that mixes clearly separable durable decisions with no benefit
- artificial multi-split where the resulting docs feel thinner or less useful than one merged doc
- fixed-topic overfitting that ignores the actual content

Optional stress variant:

```text
세 개로 나눠본다면 어떻게 제안할지 먼저 보여줘. 억지로 맞추지는 마.
```

Interpretation:

- this is a pressure test for alternative classifications, not the main pass/fail gate
- returning fewer than 3 can still be correct if a forced split would reduce document quality

### Experiment 3: Same-Topic Update Proposal

Preparation:

- confirm and save one proposal from experiment 2, or create one reviewed doc in `backtick-claude-proactive-test`

Prompt:

```text
같은 주제에 read-only proposal step과 proactive ask 규칙을 더 반영할 가치가 있으면 먼저 업데이트 제안해줘.
```

Expected:

- `list_documents` or `recall_document` when needed
- `propose_document_saves`
- `operation=update`
- `existingDocument` populated

Watch for:

- new topic created for a narrow amendment
- missing `existingDocument`
- direct `update_document` with no proposal step

### Experiment 4: Recall Before Answer

Prompt:

```text
현재 Warm Memory 저장 플로우 방향이 뭐였는지 기존 Backtick 문서를 먼저 보고 답해줘.
```

Expected:

- `list_documents` or `recall_document` before the answer
- no write
- answer grounded in the recalled doc, not a fresh reconstruction

Watch for:

- answer with no recall
- over-eager write while answering

### Experiment 5: Mixed Engineering Input

Prompt:

```text
이 내용을 durable memory로 남길 가치가 있는지 판단해줘. 저장이 필요하면 먼저 제안만 해줘.

xcodebuild -project PromptCue.xcodeproj
swift test
git status

그리고 핵심 결정은 이거야:
- 저장 전에 먼저 제안하고 확인받는다
- 긴 혼합 대화는 기본적으로 하나의 reviewed discussion으로 본다
- shell/test 로그는 memory에 넣지 않는다
```

Expected:

- no direct write
- code or implementation context is allowed if it gets promoted into durable product/design/PM decisions
- the proposal should foreground decisions, rationale, constraints, scope locks, or user-facing behavior
- warnings are acceptable when raw noise is high, but warning alone is not the goal

Watch for:

- shell/test/git noise copied verbatim with little abstraction
- product-level meaning gets lost because the input happened to mention code
- the system treats all engineering-heavy input as something to reject rather than something to distill

### Experiment 6: Live Review Wording

Prompt:

```text
이 내용을 한국어 사용자에게 저장 제안한다면 어떻게 물어볼지까지 포함해서 Backtick 방식대로 진행해줘.
```

Expected:

- review copy says `Backtick` or `백틱`
- natural phrasing such as "이 내용을 백틱에 저장할까요?"
- no internal jargon exposed by default
- if the raw MCP payload keeps English fallback wording, that alone is not a failure so long as the live assistant phrasing is natural and localized to the conversation

Watch for:

- "memory에 저장" 같은 generic wording
- `documentType`, `create`, `update`를 그대로 사용자에게 노출

### Experiment 7: Saved Document Quality Audit

After every confirmed write:

1. `recall_document`
2. score the stored doc on these checks:
   - correct `documentType`
   - topic is reusable and not overly broad
   - content is structured markdown with `##` headers
   - summary is grounded in the repo corpus
   - content preserves meaningful product-level decisions or durable context
   - mixed engineering input, if present, has been abstracted into rationale, constraints, scope, or direction
   - no obvious hallucinated decisions
   - if a better classification exists, record that alternative explicitly

Pass threshold:

- no critical failure
- the saved doc would genuinely help a future AI session resume work
- there is no clearly superior alternative classification without a real tradeoff

### Improvement Loop

If a run fails, fix the smallest layer that can realistically move the metric:

- ask-first or naming failure:
  - tighten server-wide MCP instructions
  - tighten prompt templates and tool descriptions
- skipped proposal step:
  - tighten tool descriptions and save/update docstrings
  - add regression tests for no-write-before-confirm behavior
- bad topic split or sprawl:
  - tune semantic chunking and proposal ranking
  - improve topic broadness warnings
  - improve existing-document matching
- wrong `documentType`:
  - tune `inferredDocumentType`
  - add focused tests for the failing intent
- bad summaries or weak abstraction:
  - tighten preview generation and mixed-input distillation
  - add regression tests for raw-log overexposure and poor product-level summarization
- missed recall:
  - strengthen recall-first instructions and eval prompts

Cleanup after the run:

- delete all docs created under `backtick-claude-proactive-test`
- keep one failed artifact only if it is needed for debugging

## Repo-Grounded Decision Test Set

Use this repo itself as the eval corpus. The point is not to invent synthetic memory tasks. The point is to test whether Memory proposals and saved docs preserve the actual durable decisions that already exist across the current Backtick docs.

Primary source docs for this suite:

- `docs/Execution-PRD.md`
- `docs/Implementation-Plan.md`
- `docs/MCP-Polish-Plan.md`
- `docs/MCP-Platform-Expansion-Research.md`
- `docs/Warm-MCP-Eval-Plan.md`

For every case below:

- read the named source docs first
- use `propose_document_saves` before any write
- after each confirmed write, inspect the stored result with `recall_document`
- score the outcome on semantic unit quality, classification quality, and mixed-input abstraction quality

### Case 1: Product Boundary And Vocabulary

Goal:

- test whether the system can preserve the durable product boundary without collapsing into implementation jargon or old internal taxonomy

Source docs:

- `docs/Execution-PRD.md`
- `docs/MCP-Polish-Plan.md`

Prompt:

```text
이 리포에서 Backtick이 무엇이고 무엇이 아닌지, 그리고 Prompt / Memory vocabulary 방향까지 포함해서 durable하게 남길 가치가 있다면 먼저 저장 제안만 해줘. 아직 쓰지는 마.
```

Likely best-fit result:

- one doc is probably enough
- strongest candidates are a `decision` or `reference`
- the exact topic slug can vary, but it should be recognizable as product boundary / product model / prompt-memory vocabulary

Main quality question:

- does the result preserve the core product boundary:
  - Backtick is an AI coding scratchpad / thought staging tool
  - not a note-taking app
  - Prompt is active and short-lived
  - Memory is durable and reviewed
  - Stack / Hot / Warm are internal legacy terms, not the preferred user-facing language

Watch for:

- old terminology treated as the canonical product language
- product identity mixed with low-level implementation status
- a classification that is technically valid but clearly weaker than a single stable product-boundary doc

### Case 2: Memory Save Contract

Goal:

- test whether the system can isolate the durable Memory save contract as its own semantic unit

Source docs:

- `docs/MCP-Polish-Plan.md`
- `docs/MCP-Platform-Expansion-Research.md`
- `docs/Warm-MCP-Eval-Plan.md`

Prompt:

```text
이 리포에서 durable하게 남겨야 할 Backtick Memory save contract만 정리한다면 어떻게 저장할지 먼저 제안해줘. proposal -> review -> confirm -> write, ask-first, long-thread handling까지 포함해서 봐줘.
```

Likely best-fit result:

- usually one `decision` doc
- topic should read like memory-save-flow / memory-review-flow / memory-save-contract or an equivalent subject-level name

Main quality question:

- does the result capture the real contract:
  - proposal before write
  - ask first, do not save silently
  - one reviewed `discussion` can be better than forced multi-split
  - raw coding-session logs do not belong in Memory
  - user-facing wording should say `Backtick` / `백틱`

Watch for:

- a vague discussion doc that loses the actual behavioral rules
- a topic that is only internal jargon
- a result that still optimizes for proposal count rather than durable boundaries

### Case 3: Architecture And Transport Direction

Goal:

- test whether the system can separate durable architecture choices from day-to-day implementation progress

Source docs:

- `docs/Execution-PRD.md`
- `docs/MCP-Platform-Expansion-Research.md`

Prompt:

```text
이 리포 기준으로 durable하게 남겨야 할 아키텍처 결정만 정리한다면 먼저 어떻게 저장할지 제안해줘. native macOS utility, SwiftUI + AppKit hybrid, stdio helper와 remote/HTTP 방향 구분까지 포함해서 봐줘.
```

Likely best-fit result:

- often one `reference` or `decision` doc
- topic should read like architecture / mcp-transport-architecture / app-architecture, not a schema name

Main quality question:

- does the result preserve the actual durable architecture:
  - native macOS utility app, not extension
  - SwiftUI + AppKit hybrid
  - helper binary stays stdio-focused
  - remote / HTTP path is a separate track
  - app-owned lifecycle and supervision are part of the rationale

Watch for:

- progress updates or rollout caveats overwhelming the actual architecture choice
- classification as an execution `plan` when the material is mostly settled background / decisions
- one doc that mixes product vocabulary migration with transport details for no reason

### Case 4: Mixed Engineering Input To Product-Level Meaning

Goal:

- test whether the system can lift engineering-heavy material into durable product / PM / design meaning instead of replaying raw implementation noise

Source docs:

- `docs/Implementation-Plan.md`
- `docs/MCP-Polish-Plan.md`

Prompt:

```text
이 내용을 durable memory로 남길 가치가 있는지 먼저 판단해줘. 저장이 필요하면 먼저 제안만 해줘.

지금 리포에서 보이는 상태는 대략 이래:
- MCP platform track: stabilize shipped stdio connectors and experimental ChatGPT remote path
- main-product follow-up: close remaining non-tag Phase R7 input-system hardening work
- keep grouped export validation green
- current hot slice는 MCP stabilization이지만 product hot slice와 혼동하지 말 것
- Capture는 fast dump, Stack는 execution queue라는 모델은 유지

이걸 product / PM / design 관점에서 durable하게 남긴다면 어떤 단위가 맞는지 봐줘.
```

Likely best-fit result:

- one `discussion`, `plan`, or `decision` can all be defensible depending on the summary quality
- the important part is that the proposal foregrounds priorities, scope locks, and constraints, not phase labels

Main quality question:

- does the result promote mixed engineering input into durable meaning such as:
  - current prioritization
  - scope lock
  - what must not regress
  - why MCP platform work is a separate track from product direction

Watch for:

- raw phase names, file names, commands, or verification steps dominating the preview
- treating engineering-heavy input as unsavable by default
- saving a mushy catch-all recap with no durable direction

### Case 5: Same-Topic Amendment

Goal:

- test whether the system reuses a strong existing topic instead of creating avoidable sprawl

Preparation:

- save one reviewed doc from Case 2 first

Prompt:

```text
같은 주제에 이 결정까지 반영할 가치가 있으면 먼저 업데이트 제안만 해줘:
- proposal count는 목표가 아니다
- 하나의 좋은 discussion이 세 개의 억지 split보다 낫다
- mixed engineering input은 product-level meaning으로 승격해서 저장해야 한다
```

Likely best-fit result:

- `operation=update`
- `existingDocument` populated
- same topic reused unless the earlier doc was clearly misclassified

Main quality question:

- does the result correctly treat this as an amendment to the Memory save contract or eval rubric, rather than a brand-new topic

Watch for:

- a narrow amendment creating a new sibling topic
- `create` where `update` is clearly stronger
- the amendment preview restating the whole repo instead of only the durable delta

### Case 6: No Durable Save Boundary

Goal:

- test whether the system can distinguish durable decisions from routine execution status

Prompt:

```text
참고만 해줘. 지금은 xcodegen generate, swift test, xcodebuild build가 다 통과했고 앱 번들도 다시 켰어.
이걸 Backtick에 남길지 판단해줘.
```

Likely best-fit result:

- often no write recommendation
- if a proposal appears, it should only happen when the assistant can justify a real durable decision or release-significance behind the status

Main quality question:

- does the system resist turning routine run status into Memory unless a stable decision, constraint, or release milestone is actually present

Watch for:

- terminal history treated as durable context by default
- a generic discussion doc proposed with no clear future value

### Suggested Run Order

1. Case 2
2. Case 5
3. Case 1
4. Case 3
5. Case 4
6. Case 6

Why this order:

- start with the Memory save contract because it is the clearest existing durable unit
- then immediately test same-topic reuse while the classification is still fresh
- move to broader product and architecture material
- save the mixed-input abstraction and no-save boundary checks for the end

### Latest Repo-Grounded Findings

The latest run against this repo confirmed that document quality and update behavior are linked more tightly than the raw proposal count suggests.

Observed results:

- `memory save contract` produced a useful durable doc, but it was classified as `plan` instead of the stronger `decision`
- `product boundary / vocabulary` also produced a useful doc, but again drifted to `plan` instead of `reference` or `decision`
- `architecture / transport direction` was the strongest case and landed cleanly as `reference`
- mixed engineering input could be saved as a good durable unit, but only after the content was manually rewritten toward priorities and scope lock
- routine execution status still produced a save proposal when it should usually be `do_not_write`
- same-topic amendment failed because the system created a new proposal instead of targeting the existing document

What this means:

- the biggest risk is not "wrong count"
- the biggest risk is "a valid durable doc gets the wrong type, then later updates fail to attach to it"

### Root Cause Diagnosis

#### 1. `documentType` drift is still too easy

Current `inferredDocumentType` scoring is substring-based and too literal.

That means repo-grounding text can accidentally bias the type:

- file names like `docs/MCP-Polish-Plan.md` and `docs/Warm-MCP-Eval-Plan.md` contain `plan`
- the current scorer can treat those file references as execution-plan evidence even when the document itself is really a `decision` or `reference`

This is why a semantically valid durable doc can still be stored under the weaker type.

#### 2. Same-topic update depends too heavily on exact type match

Current proposal matching effectively asks:

- same `project`
- same `topic`
- same inferred `documentType`

If the type drifts, `existingDocument` becomes `null` and the proposal falls back to `create`.

That creates the failure mode we care about most:

- the first doc is useful
- the next narrow amendment does not attach to it
- topic sprawl starts even though the subject was obviously the same

#### 3. `do_not_write` is too narrow

The current skip logic mainly catches:

- explicit "do not save" wording
- very short and noisy technical content

That is not enough for routine status updates such as:

- build passed
- tests passed
- app reopened

Those should normally stay out of Memory unless they imply a durable release gate, decision, constraint, or milestone.

#### 4. Current tests are too hint-heavy

Existing proposal tests mostly validate the happy path:

- strong `userIntent`
- preferred topic already supplied
- existing document saved under the exact matching type

That misses the repo-grounded failures that actually matter:

- type drift caused by repo references
- same-topic amendment with mismatched inferred type
- routine status with no explicit `do not save` marker

### Remediation Priority

Order fixes by impact on document quality and update behavior:

1. `same-topic update / existingDocument` accuracy
   - a good durable doc is much less useful if future amendments cannot find it
2. stronger `do_not_write` boundary for routine execution status
   - Memory quality degrades quickly if routine run status is treated as durable context
3. reduce `plan` over-classification in repo-grounded proposal content
   - the main goal is not aesthetic labeling; it is keeping stable docs in the right lane so later updates behave correctly

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
