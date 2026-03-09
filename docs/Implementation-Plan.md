# Backtick Implementation Plan

## Current State

- Product identity is `Backtick`.
- Current repo name, app target, and core module remain `PromptCue` / `PromptCueCore` for now.
- Planning decisions should be judged against Backtick as an AI coding scratchpad / thought staging tool, not a note app.
- Core interaction model:
  - Capture = frictionless dump
  - Stack = execution queue
  - AI compression happens in Stack

- Architecture direction is fixed: `native macOS utility app`, not `App Extension`.
- UI stack is fixed: `SwiftUI + AppKit hybrid`.
- The workspace already contains an early native scaffold:
  - `project.yml`
  - `PromptCue/App/*`
  - `PromptCue/Domain/*`
  - `PromptCue/Services/*`
  - `Sources/PromptCueCore/*`
- The app target is now wired to `PromptCueCore` for shared pure logic.
- Current overall status: `Phase 0 complete`, `Phase 1 in progress`, `Phase 2 and Phase 3 started`.
- A quality audit has now been completed and a remediation lane is active in `docs/Quality-Remediation-Plan.md`.
- A current-main-aligned design-system boundary proposal now exists in `docs/Design-System-Architecture-Proposal.md`.
- A design-system execution document now exists in `docs/Design-System-Execution-Plan.md`.
- A bounded capture/stack design-polish plan now exists in `docs/Design-Polish-Execution-Plan.md`.
- `Phase DS1`, `Phase DS2`, and `Phase DS3` are now implemented in the design-system strategy branch, and `Phase DS4` has started where reuse is already proven.

## Phase Summary

| Phase | Goal | Status | Notes |
| --- | --- | --- | --- |
| Phase 0 | Research and lock technical direction | Completed | Native macOS direction decided |
| Phase 1 | Foundation and shared contracts | In progress | Early scaffold exists, shared contracts need tightening |
| Phase 2 | Core capture flow | In progress | Services, panels, and capture UI skeleton are implemented |
| Phase 3 | Stack and export UX | In progress | Card stack and copy interactions are implemented, smoke testing pending |
| Phase 4 | Platform and operations hardening | In progress | Settings and screenshot folder access are now implemented |
| Phase 5 | Polish, validation, and release prep | Pending | Final integration phase |
| Phase R | Audit remediation and quality closure | In progress | Resolves MVP gaps, privacy model drift, and design-system drift |
| Phase DS1 | Design-system boundary freeze | Completed in strategy branch | Ownership boundaries are now explicit in docs and code comments |
| Phase DS2 | Runtime/value ownership split | Completed in strategy branch | Grouped contracts now back runtime callers; `AppUIConstants` is only a compatibility facade |
| Phase DS3 | Pattern recipe centralization | Completed in strategy branch | Capture shell chrome, stack card chrome, copied-stack recipe, and stack backdrop recipe now live in owner files |
| Phase DS4 | Reusable surface rationalization | In progress in strategy branch | Shared notification-card chrome and top-edge highlight helpers are now extracted where reuse is proven; broader reusable-surface cleanup is still pending |
| Phase DP | Capture and stack design polish | In progress | `DP0` review lock is complete; `DP1` capture elevation and `DP2` stack brightness are now in implementation with review still pending |

## Current Hot Slice

The immediate implementation slice is:

- `Phase R6: stack sync and light-mode readability`
- `Phase R7: capture input system hardening`
- queued next: `Phase R8: AI Export Tail / Prompt Suffix`
- queued after that: `Phase R9: stack card overflow and hover expansion`
- in parallel planning/visual lane: `Phase DP0 -> DP4` from `docs/Design-Polish-Execution-Plan.md`

This slice exists because the app currently has a user-visible mismatch between:

- a successful capture submission
- the stack panel's first rendered state
- the visibility of new cards in light mode

That means current work is prioritized in this order:

1. lock capture submission immediately when `Enter` is pressed so hotkeys cannot outrun the save path
2. keep `AppModel` as the source of truth for stack presentation during normal interaction
3. rework light-mode stack veil and card separation
4. rebuild the capture input around an AppKit-owned sizing model
5. add `AI Export Tail / Prompt Suffix` as an export-time-only setting and formatter slice
6. then return to grouped export validation and broader release verification

All work in this slice should preserve the product model:

- Capture stays optimized for fast dumping of raw thoughts
- Stack owns ordering, grouping, export, and AI-facing compression
- proposals that turn Capture into a note surface should be rejected

Progress on this slice:

- `Phase R7A` contract lock is implemented through `CaptureEditorMetrics`
- initial draft presentation now precomputes editor metrics before the panel is shown
- reserved-width remeasurement is in place at the scroll threshold
- automated capture QA now runs through `scripts/qa_capture_input.sh` and has produced screenshot + metrics artifacts
- current diagnosis confirms the next R7 step must move height ownership back into the AppKit editor host; further padding-only tweaks are not sufficient
- `Phase R7B` is now the active implementation lane: replace the live SwiftUI capture composition with an AppKit-owned host and keep geometry out of `AppModel`

## Active Remediation Lane

The current highest-priority work is tracked in:

- `docs/Quality-Remediation-Plan.md`
- `docs/Design-System-Architecture-Proposal.md` for design-system ownership boundaries
- `docs/Design-System-Execution-Plan.md` for phased design-system execution

That remediation lane is now authoritative for:

- multi-card selection and grouped export closure
- screenshot attachment ownership and cleanup
- explicit screenshot folder access and bookmark persistence
- clipboard reliability for image + text export
- `AI Export Tail / Prompt Suffix` settings, export-only append behavior, and test coverage
- design-system reconciliation and reuse cleanup
- app-level verification expansion

Design-system rule for all future polish work:

- generic tokenization must not collapse runtime-owned AppKit behavior or Backtick-specific pattern surfaces
- visual polish must follow the review gates in `docs/Design-Polish-Execution-Plan.md`, not ad hoc local tuning
- `Phase DP0` is now complete in docs; the first code slice should be `DP1` capture elevation with master-owned token changes

## Queued Next Slice

The next planned remediation slice after `Phase R7` is:

- `Phase R8: AI Export Tail / Prompt Suffix`

This slice exists to add a user-controlled export suffix without polluting stored cue content or capture UI.

Backtick rule for this slice:

- the suffix is export-time compression/output polish
- it must not turn Capture into a templated note surface

Planned scope:

1. add Settings controls for:
   - enable/disable toggle
   - multiline suffix text
2. append the suffix only at export time
3. keep stored cards unchanged in persistence and stack rendering
4. add formatter and app-level regression coverage before UI polish

Planned integration order:

1. freeze the export-tail contract and settings storage shape
2. update export formatter / clipboard composition path
3. wire Settings UI and state
4. add regression tests for enabled, disabled, empty, and multiline behavior

After `Phase R8`, the next planned slice is:

- `Phase R9: stack card overflow and hover expansion`

This slice exists because very long cue content currently turns Stack into a layout outlier instead of a stable execution queue.

Backtick rule for this slice:

- Stack should reveal that a card is long without letting one card dominate the queue by default
- expansion should feel temporary and lightweight, not like opening a document

Planned scope:

1. define one default max resting card height for active and copied-stack cards
   - initial target: text-only cards expose roughly `3-4` lines at rest
2. define one overflow affordance that communicates remaining hidden text
3. add hover or focus expansion that reveals more text without destabilizing surrounding layout
   - initial target: reveal roughly `6-8` lines before any deeper interaction
4. keep copied-stack collapsed summaries visually stable even when the first card is very long
5. add QA fixtures for short, medium, very long, and screenshot-plus-text cards

Planned integration order:

1. freeze card overflow metrics and interaction rules
2. update active stack cards
3. update collapsed copied-stack summaries
4. add automated visual/behavior verification for long-card fixtures

## Phase 0: Research And Decisions

### Goal

Confirm the right product shape, operating constraints, and implementation stack.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Confirm app form factor: utility app vs App Extension | Architecture lead | None | No | Decision captured in PRD and plan | Completed |
| Confirm UI shell: SwiftUI + AppKit hybrid | Architecture lead | None | No | Core windowing choice locked | Completed |
| Confirm distribution strategy: Gumroad-backed direct download first, MAS later optional | Product + platform lead | None | Yes | Distribution path documented with sandbox implications | Completed |
| Capture Alfred/Raycast interaction patterns to copy or avoid | UX lead | None | Yes | UX principles list approved | Completed |
| Identify key platform risks: hotkeys, panels, screenshot access, login item | Platform lead | None | Yes | Risk register created | Completed |

### Exit Criteria

- Product shape is stable enough to avoid rework.
- Native macOS stack is accepted as the long-term baseline.
- Constraints around screenshot permissions and distribution are documented.

## Phase 1: Foundation And Shared Contracts

### Goal

Create the stable technical foundation that other tracks can build on without file conflicts.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Normalize project structure around `project.yml` and app target layout | Foundation lead | Phase 0 | No | Buildable app project structure is agreed | In progress |
| Freeze shared contracts: card model, draft model, panel constants, service protocols | Foundation lead | Phase 0 | No | Shared types stop changing daily | In progress |
| Add `GRDB` and define SQLite-backed storage for cards and attachments | Data lead | Shared contracts | Yes | Persistence interface is stable and migration-ready | In progress |
| Define screenshot source abstraction and permission model | Platform lead | Shared contracts | Yes | Folder selection and watcher rules are agreed | In progress |
| Define global shortcut abstraction and action routing | Platform lead | Shared contracts | Yes | Capture and stack actions are centrally routed | Pending |
| Add baseline test targets and verification commands | Foundation lead | Project structure | Yes | Unit test target exists and runs | Completed |

### Parallel Tracks

- Track A: Contracts and domain models
- Track B: Platform services contracts
- Track C: Test harness and build validation

### Exit Criteria

- App compiles with placeholder implementations.
- Shared types and ownership boundaries are frozen.
- Worker tracks can proceed without touching the same files.

## Phase 2: Core Capture Flow

### Goal

Ship the fastest path from hotkey to saved card.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Implement global shortcut registration for quick capture and stack toggle | Platform lead | Phase 1 contracts | Yes | Hotkeys fire reliably from any app | In progress |
| Implement capture panel controller and panel positioning | Windowing lead | Phase 1 contracts | Yes | Panel opens in the intended edge position and accepts focus | In progress |
| Implement capture composer UI with `Enter` submit and `Esc` cancel | UI lead | Capture panel controller | Yes | User can dump a thought in under 2 seconds | In progress |
| Implement card persistence with TTL cleanup | Data lead | Storage abstraction | Yes | Cards survive relaunch and expired cards are removed | In progress |
| Implement screenshot lookup/attachment for recent screenshots | Platform lead | Screenshot abstraction | Yes | Recent screenshot attaches automatically when eligible | In progress |
| Wire model actions: create card, clear draft, reset screenshot state | App state lead | Persistence and screenshot support | No | Capture flow is end-to-end functional | In progress |

### Parallel Tracks

- Track A: Hotkeys + panel shell
- Track B: Persistence + TTL + screenshot attachment
- Track C: Capture UI and view model binding

### Exit Criteria

- The configured capture shortcut opens the capture panel. The default is `Cmd + \``.
- Typing and pressing `Enter` creates a card.
- Screenshot auto-attach works for the agreed MVP rule.
- State persists locally across app restarts.

## Phase 3: Stack And Export UX

### Goal

Make stored thoughts easy to review, compress, and export from the execution queue without slowing the workflow.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Implement right-side stack panel window behavior | Windowing lead | Phase 2 panel shell | Yes | Stack panel opens/closes cleanly and preserves size/placement rules | In progress |
| Implement newest-first card stack UI | UI lead | Phase 2 persistence | Yes | Cards render in correct order with timestamps | In progress |
| Implement screenshot thumbnail rendering | UI lead | Phase 2 screenshot attachment | Yes | Attached screenshots render safely and do not block the UI | In progress |
| Implement single-card click-to-copy behavior | UX lead | Card stack UI | Yes | Clicking a card copies its payload immediately | In progress |
| Implement multi-select and grouped clipboard export | UX lead | Card stack UI | Yes | Multiple selected cards copy in display order | In progress |
| Implement delete/expiry refresh behavior in the stack | App state lead | Persistence | Yes | Stack reflects deletions and TTL cleanup without stale state | In progress |

Backtick judgment rule for this phase:

- Stack can add grouping, selection, and AI compression affordances
- Capture should not accumulate note-taking features that belong in Stack

### Parallel Tracks

- Track A: Window behavior
- Track B: Card list UI and image rendering
- Track C: Clipboard/export interactions

### Exit Criteria

- The configured stack shortcut opens the review/export surface. The default is `Cmd + 2`.
- Single-card copy works.
- Multi-card selection and export works.
- The stack remains visually stable under frequent updates.

## Phase 4: Platform And Operations Hardening

### Goal

Turn the working prototype into an operable macOS utility app.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Add launch-at-login support via `SMAppService` | Platform lead | Working app shell | Yes | Login item can be enabled and disabled reliably | Pending |
| Add settings surface for screenshot folder, TTL, and startup behavior | Product engineering lead | Working core flows | Yes | Sensitive behaviors are user-configurable | In progress |
| Implement security-scoped bookmark storage for screenshot folder | Platform lead | Settings surface | Yes | Folder access persists across launches | In progress |
| Add logging for hotkey, capture, storage, and watcher failures | Platform lead | Core services | Yes | Failure paths are observable | Pending |
| Decide update strategy and wire `Sparkle` if shipping direct | Release lead | Distribution decision | Yes | Auto-update path is documented or implemented | Pending |
| Add notarization/signing pipeline | Release lead | Build stability | Yes | Signed and notarized app can be shipped | Pending |
| Add DMG packaging pipeline for Gumroad releases | Release lead | Signed app build | Yes | Versioned DMG can be generated repeatably | Pending |
| Prepare Gumroad release assets and delivery checklist | Product + release lead | DMG pipeline | Yes | Store listing, version notes, and upload checklist exist | Pending |
| Define MAS compatibility lane and gap list | Platform + release lead | Working direct-distribution build | Yes | Sandbox blockers and entitlement differences are documented | Pending |

### Parallel Tracks

- Track A: Permissions and folder access
- Track B: Settings and startup behavior
- Track C: Release and update pipeline
- Track D: Commerce packaging and distribution ops

### Exit Criteria

- The app is operable on a clean machine.
- Folder access survives relaunch.
- Startup and update behavior are not manual hacks.
- Gumroad-ready DMG packaging is repeatable.
- App Store blockers are explicitly listed, not assumed away.

## Phase 5: Polish, Validation, And Release Prep

### Goal

Verify that the product feels like a native macOS utility, not just a working prototype.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Refine spacing, typography, animation, and focus behavior | UI lead | Phase 3 complete | Yes | UI feels intentional and lightweight | Pending |
| Add keyboard navigation and selection polish | UX lead | Phase 3 complete | Yes | Keyboard-first flow is smooth | Pending |
| Add automated tests for TTL, formatting, persistence, and watcher logic | Test lead | Core services complete | Yes | Critical logic is covered by unit tests | Pending |
| Add smoke test checklist for capture, recall, export, and restart | QA lead | Phases 2-4 complete | Yes | Repeatable manual validation exists | Pending |
| Run performance and memory checks for idle utility behavior | Platform lead | Stable build | Yes | Idle footprint is acceptable | Pending |
| Prepare release checklist and rollback plan | Release lead | Stable build | Yes | Release path is reversible | Pending |

### Parallel Tracks

- Track A: UI polish
- Track B: automated testing
- Track C: release validation

### Exit Criteria

- Core journeys pass on a clean machine.
- Idle behavior is lightweight.
- Release artifacts and rollback plan are documented.

## Suggested Ownership Map

- Master only:
  - App entrypoints
  - Dependency wiring
  - Shared contracts
  - Integration docs
- Track A:
  - Domain models
  - Persistence
  - TTL logic
- Track B:
  - Hotkeys
  - Panel/window controllers
  - Login item
- Track C:
  - SwiftUI views
  - Selection/copy UX
  - Visual polish
- Track D:
  - Release pipeline
  - Signing/notarization
  - Update path

## Multi-Agent Execution Rules

1. Freeze shared contracts before parallel code work starts.
2. Assign each track a file ownership boundary, not a vague feature label.
3. Do not allow workers to edit the same file unless master opens an explicit edit window.
4. Integrate in this order:
   1. shared contracts
   2. core services
   3. UI/interaction
   4. ops/release
5. Require each worker to submit:
   - what changed
   - what was verified
   - remaining risks
6. If a shared contract changes, pause dependent tracks and rebase work at the plan level before more edits land.

## Master Review Gates

### Track Gate

- Touched files stay inside ownership boundaries.
- The changed surface builds locally or has a concrete blocker documented.
- New behavior is covered by at least one verification step.
- The worker calls out behavioral risk and rollback approach.

### Integration Gate

- The app builds from the integration branch/workspace.
- Shared handoff points compile together.
- Core journeys work:
  - quick capture
  - stack open
  - single-card copy
  - multi-card copy
  - relaunch persistence
  - TTL cleanup

### Release Gate

- No unresolved TODOs on hotkey, persistence, or permission-critical paths.
- Signing and launch-at-login behavior are validated.
- Update path and rollback plan are documented.

## Locked Implementation Choices

- Primary storage: `SQLite + GRDB`
- Primary distribution: Gumroad-backed direct download first, signed and notarized
- App Store path: deferred until screenshot permission flow is proven
- UI shell: `SwiftUI + AppKit hybrid`

## Immediate Next Slice

1. Tighten shared contracts in `Sources/PromptCueCore/*` and app-facing aliases.
2. Add `GRDB` and land the first SQLite-backed persistence slice.
3. Lock file ownership for:
   - services
   - window controllers
   - SwiftUI views
4. Build Phase 2 and Phase 3 in parallel under master review.
