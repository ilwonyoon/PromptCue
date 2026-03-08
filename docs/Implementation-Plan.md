# Prompt Cue Implementation Plan

## Current State

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

## Phase Summary

| Phase | Goal | Status | Notes |
| --- | --- | --- | --- |
| Phase 0 | Research and lock technical direction | Completed | Native macOS direction decided |
| Phase 1 | Foundation and shared contracts | In progress | Early scaffold exists, shared contracts need tightening |
| Phase 2 | Core capture flow | In progress | Services, panels, and capture UI skeleton are implemented |
| Phase 3 | Stack and export UX | In progress | Card stack and copy interactions are implemented, smoke testing pending |
| Phase 4 | Platform and operations hardening | Pending | Depends on working feature flows |
| Phase 5 | Polish, validation, and release prep | Pending | Final integration phase |

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
| Add `GRDB` and define SQLite-backed storage for cards and attachments | Data lead | Shared contracts | Yes | Persistence interface is stable and migration-ready | Pending |
| Define screenshot source abstraction and permission model | Platform lead | Shared contracts | Yes | Folder selection and watcher rules are agreed | Pending |
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
| Implement capture composer UI with `Enter` submit and `Esc` cancel | UI lead | Capture panel controller | Yes | User can create a note in under 2 seconds | In progress |
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

Make stored thoughts easy to review and export without slowing the workflow.

### Tasks

| Task | Suggested Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Implement right-side stack panel window behavior | Windowing lead | Phase 2 panel shell | Yes | Stack panel opens/closes cleanly and preserves size/placement rules | In progress |
| Implement newest-first card stack UI | UI lead | Phase 2 persistence | Yes | Cards render in correct order with timestamps | In progress |
| Implement screenshot thumbnail rendering | UI lead | Phase 2 screenshot attachment | Yes | Attached screenshots render safely and do not block the UI | In progress |
| Implement single-card click-to-copy behavior | UX lead | Card stack UI | Yes | Clicking a card copies its payload immediately | In progress |
| Implement multi-select and grouped clipboard export | UX lead | Card stack UI | Yes | Multiple selected cards copy in display order | In progress |
| Implement delete/expiry refresh behavior in the stack | App state lead | Persistence | Yes | Stack reflects deletions and TTL cleanup without stale state | In progress |

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
| Add settings surface for screenshot folder, TTL, and startup behavior | Product engineering lead | Working core flows | Yes | Sensitive behaviors are user-configurable | Pending |
| Implement security-scoped bookmark storage for screenshot folder | Platform lead | Settings surface | Yes | Folder access persists across launches | Pending |
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
