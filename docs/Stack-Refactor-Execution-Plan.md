# Stack Refactor Execution Plan

## Purpose

Backtick's current Stack surface now has three related pressures that should be handled as one coordinated refactor, not as isolated patches:

- visible stack jank during interaction
- long-card text clipping and overflow instability
- pending Stack UX changes for the header rail, filtering, TTL signaling, and stage-based launch language

This document defines the umbrella execution plan for that work.

It intentionally treats the Stack work as a bounded subsystem refactor:

- keep current product model
- preserve current copy-on-click and commit-on-close semantics
- improve render stability, performance, and language together
- avoid reopening unrelated capture, selector, or cloud-sync work

## Why This Is Bigger Than One UI Pass

The current Stack issues are structurally connected.

### 1. Performance

Current stack rendering still does non-trivial work during view evaluation:

- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CardStackView.swift) partitions active and copied cards in `body`
- the same file rebuilds or lazily mutates `classificationCache`
- each row checks staged membership with `stagedCopiedCardIDs.contains(card.id)`
- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CaptureCardView.swift) still resolves display configuration and overflow metrics during render
- [StackCardOverflowPolicy.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackCardOverflowPolicy.swift) is cached now, but still measures synchronously on cache misses

The product symptom is not only panel-open latency. It is also interaction heaviness once the stack is already visible.

### 2. Text Clipping And Overflow

The current long-card path is functionally better than before, but the text layout path is still fragile.

Likely root cause:

- [StackCardOverflowPolicy.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackCardOverflowPolicy.swift) measures text height with an AppKit `NSAttributedString` path
- [InteractiveDetectedTextView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/InteractiveDetectedTextView.swift) renders with SwiftUI `Text`, `AttributedString`, `lineSpacing`, `fixedSize`, and optional stronger tag ranges
- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CaptureCardView.swift) then pins a height and clips the view

That means measurement and rendering do not fully share one source of truth.

The product symptom is:

- bottom clipping
- cut descenders or final line bottoms
- fragile behavior when long text, highlighted tags, and overflow affordances coexist

### 3. Header / Filter / TTL / Logo UX

The existing Stack header is still conditional:

- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CardStackView.swift) only shows the header when staged count is non-zero

That creates layout jump and prevents Stack from owning a stable queue summary.

At the same time, launch language and TTL signaling are now product-level concerns:

- header should use `On Stage / Offstage`
- immediate action feedback should remain `Copied`
- ephemerality should become visible on cards
- Stack needs `All / On Stage / Offstage` filtering
- the Backtick mark should behave correctly in both app-theme and macOS-theme contexts

These UX changes are easier and safer after the rendering and overflow surface is stabilized.

## Locked Product Rules

Do not change these while doing the stack refactor:

- Capture remains a frictionless dump surface
- Stack remains an execution queue
- clicking a card stages grouped copy
- clicking again unstages it
- clipboard payload updates immediately while Stack stays open
- copied ordering commits on stack close

Do not redesign in this slice:

- AI grouping
- capture selector
- capture panel keyboard ownership
- cloud-sync policy
- MCP copied-state semantics

## Terminology

Keep internal/storage/MCP terms:

- `active`
- `staged`
- `copied`

Use launch-facing Stack language:

- `On Stage`
- `Offstage`

Keep immediate action feedback:

- `1 Copied`
- `2 Copied`

Rationale:

- `On Stage / Offstage` matches Backtick's thought-staging product metaphor
- `Copied` remains accurate for the immediate clipboard action
- no storage migration is required

## Existing Child Plan

The UI-specific slice for the new header rail already exists in:

- [Stack-Header-Rail-Plan.md](/Users/ilwonyoon/Documents/PromptCue/docs/Stack-Header-Rail-Plan.md)

That document now acts as the Stack UX child plan under this broader refactor plan.

## Refactor Strategy

Do not try to land everything in one branch.

Use this order:

1. render/performance foundation
2. text-layout and overflow repair
3. header rail, filter, TTL ring, and logo rules
4. final integration and smoke QA

Reason:

- the UX slice should not ship on top of an unstable render path
- text clipping is easier to verify before the header rail adds new moving pieces
- the rail/filter work should consume a stable stack view model rather than invent one mid-flight

## Phase Breakdown

### Phase SR0: Baseline Lock And Instrumentation Refresh

Goal:

- restate stack-open and in-stack interaction baselines before new edits begin

Tasks:

- rerun `scripts/record_stack_open_trace.sh --app <Prompt Cue.app>`
- record current stack interaction jank points with:
  - short stack fixture
  - long-text fixture
  - mixed active/copied fixture
- define one visible regression metric for:
  - `Cmd + 2 -> first frame`
  - card click response while stack is open
  - long-card render/expand path

Exit criteria:

- one before-state packet exists for the stack refactor branch

### Phase SR1: Stack Render Containment

Goal:

- make stack rendering cheaper without changing user-visible behavior

Tasks:

- move active/copied partitioning out of ad hoc `body` logic and into a dedicated stack presentation layer
- stop per-row staged membership checks from using repeated linear searches
- move classification resolution behind a stable memoized view-model instead of lazy mutation during render
- narrow re-render surfaces so one card change does not fan out across the whole visible stack unnecessarily

Expected touched areas:

- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CardStackView.swift)
- new stack presentation helper files
- possibly `PromptCueCore` if pure formatting or partition helpers are extracted

Exit criteria:

- stack render path is structurally cheaper before any UX redesign lands

### Phase SR2: Text Layout And Overflow Repair

Goal:

- eliminate stack-card text bottom clipping and make overflow measurement/rendering use one coherent contract

Tasks:

- define one authoritative stack text layout path
- stop mixing an AppKit measurement model with a diverging SwiftUI render model without an explicit reconciliation layer
- validate long text, highlighted tags, single-line link/path cards, and copied-stack summaries against the same metrics contract
- preserve the approved overflow affordance and copied-summary stability

Expected touched areas:

- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CaptureCardView.swift)
- [InteractiveDetectedTextView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/InteractiveDetectedTextView.swift)
- [StackCardOverflowPolicy.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackCardOverflowPolicy.swift)
- [ContentDisplayFormatter.swift](/Users/ilwonyoon/Documents/PromptCue/Sources/PromptCueCore/ContentDisplayFormatter.swift)
- overflow and rendering tests

Exit criteria:

- no visible bottom clipping in long-card fixtures
- overflow behavior remains stable for active and copied surfaces

### Phase SR3: Header Rail, Filter, TTL Ring, And Logo

Goal:

- land the new stack header rail on top of the stabilized render path

Tasks:

- replace the conditional staged header with a persistent rail
- use `N on stage · N offstage` summary language
- show `N Copied` as right-side transient action feedback
- add `All / On Stage / Offstage` filtering
- add active-card TTL rings
- lock stack-header logo to app appearance and keep status-item logo tied to macOS appearance

Expected touched areas:

- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CardStackView.swift)
- new stack header/filter components
- [AppCoordinator.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppCoordinator.swift) only if status-item appearance needs a small supporting guardrail
- `PromptCueCore` only for pure TTL math or label formatting helpers

Exit criteria:

- no header jump
- terminology and filter behavior match launch intent
- TTL ring is present, quiet, and cheap

### Phase SR4: Integration QA

Goal:

- verify the combined stack refactor as one user-facing system

Required QA:

- panel opens in the current acceptable band
- card click feels immediate with the stack already open
- long text does not crop at the bottom
- copied summary remains visually stable
- filter modes behave correctly
- `On Stage / Offstage` language feels coherent
- TTL ring only appears where intended
- stack header logo follows app theme
- status-item icon follows macOS theme

## File Ownership And Parallelization

This work is large enough to justify a dedicated integration branch and worktrees.

Recommended structure:

- Integration branch:
  - `feat/stack-refactor-integration`
- Track branch A:
  - `feat/stack-refactor-foundation`
- Track branch B:
  - `feat/stack-refactor-overflow`
- Track branch C:
  - `feat/stack-refactor-rail`

Recommended worktrees:

- `../PromptCue-stack-refactor-integration`
- `../PromptCue-stack-foundation`
- `../PromptCue-stack-overflow`
- `../PromptCue-stack-rail`

### Ownership Map

Master-only:

- shared plan docs
- final terminology lock
- final merge sequencing
- any `AppCoordinator` edits
- final integration and verification

Track A, foundation/performance:

- stack presentation partitioning
- classification caching and view-model boundaries
- narrow state/publication changes needed only for stack rendering

Track B, text/overflow:

- `CaptureCardView.swift`
- `InteractiveDetectedTextView.swift`
- `StackCardOverflowPolicy.swift`
- overflow tests and fixtures

Track C, rail/filter/TTL:

- `CardStackView.swift`
- new stack header/filter components
- TTL ring presentation
- header-logo presentation

Conflict rule:

- `CardStackView.swift` is Track C owned once SR3 starts
- if Track A needs a temporary edit window there, it must land before Track C begins

## Verification Gates

Minimum for every implementation slice:

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Required stack-specific verification:

- `scripts/record_stack_open_trace.sh --app <Prompt Cue.app>`
- targeted stack tests:
  - [StackMultiCopyTests.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCueTests/StackMultiCopyTests.swift)
  - [StackCardOverflowPolicyTests.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCueTests/StackCardOverflowPolicyTests.swift)
- new tests for:
  - stack presentation partitioning
  - filter state
  - TTL progress math
  - clipped-text regression fixtures

## Recommended Merge Sequence

1. docs and contract lock
2. SR1 foundation/performance
3. SR2 text/overflow repair
4. SR3 header/filter/TTL/logo
5. SR4 final integration QA

Do not merge SR3 before SR2 unless the clipping issue is explicitly deferred.

## Abort Conditions

Stop and split the work again if any of these happen:

- stack refactor requires changing capture panel ownership
- cloud-sync or MCP semantics get pulled into the same branch
- copied-state storage rename becomes necessary
- selector or screenshot behavior regresses and becomes part of the same edit surface

If one of those appears, the stack refactor has become too broad and needs to be re-cut.
