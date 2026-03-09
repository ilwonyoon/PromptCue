# Prompt Cue Master Board

## Objective

Ship Prompt Cue as a native macOS utility app that gives AI-assisted developers a frictionless buffer for capture, recall, and clipboard export.

## Locked Decisions

- Platform shape: standard macOS utility app, not an App Extension
- App shell: `LSUIElement` background utility with status item and floating panels
- UI stack: SwiftUI for view composition, AppKit for windowing and system integration
- Distribution baseline: Gumroad-backed direct distribution first, Mac App Store compatibility deferred
- Screenshot strategy: user-selected screenshot folder with security-scoped bookmark support
- Persistence baseline: local-only storage with 8-hour TTL and automatic pruning
- Storage engine baseline: `SQLite + GRDB`

## Current Status

| Area | Status | Notes |
| --- | --- | --- |
| Execution PRD | Completed | Repo-backed and aligned to native macOS direction |
| Implementation plan | Completed | Phase/task breakdown landed in repo |
| Engineering preflight | Completed | Setup, distribution, Gumroad, DMG, and MAS considerations documented |
| Architecture decision | Locked | Native macOS utility app |
| Repo scaffold | In progress | App target, local package, CI, and XcodeGen wiring are in place |
| Core contracts | In progress | App target now depends on `PromptCueCore`; some app-only state contracts remain local |
| Hotkey integration | In progress | Carbon-backed registration is implemented; runtime smoke test still needed |
| Windowing | In progress | NSPanel controllers are implemented; runtime focus behavior still needs verification |
| Persistence | In progress | SQLite-backed `CardStore` is implemented via GRDB and attachment ownership is app-managed |
| Screenshot attachment | In progress | Recent screenshot detection now depends on an explicitly approved folder |
| Core UI | In progress | Capture and stack views now render real MVP UI |
| Quality audit | Completed | Findings captured and prioritized for remediation |
| Remediation lane | In progress | Contract lock and phased closure tracked in `docs/Quality-Remediation-Plan.md` |
| Settings surface | In progress | Shortcut recorders and screenshot folder controls are now implemented |
| Stack sync and light-mode readability | In progress | `Phase R6` now uses tracked capture submission plus a stronger light-mode veil; real-device QA is still the gate |
| Capture input system hardening | In progress | `Phase R7A` contract lock and QA harness are complete; `Phase R7B` now rewrites the live capture panel around an AppKit-owned sizing host |

## Current File Ownership

- Master only:
  - `/Users/ilwonyoon/Documents/PromptCue/docs/Master-Board.md`
  - `/Users/ilwonyoon/Documents/PromptCue/project.yml`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppCoordinator.swift`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppDelegate.swift`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/PromptCueApp.swift`
- Track A, product execution docs:
  - `/Users/ilwonyoon/Documents/PromptCue/docs/Execution-PRD.md`
  - `/Users/ilwonyoon/Documents/PromptCue/docs/Engineering-Preflight.md`
- Track B, delivery planning docs:
  - `/Users/ilwonyoon/Documents/PromptCue/docs/Implementation-Plan.md`
- Future implementation Track C, foundation and services:
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/Domain`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services`
  - `/Users/ilwonyoon/Documents/PromptCue/Sources/PromptCueCore`
- Future implementation Track D, windowing and shell:
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/WindowControllers`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel.swift`
- Future implementation Track E, views and interaction:
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views`
  - `/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Theme.swift`

## Integration Order

1. Contracts and persistence
2. Screenshot monitoring and clipboard formatting
3. Hotkeys and panel shell
4. Capture UI and stack UI
5. Launch-at-login, settings, and polish
6. DMG packaging, Gumroad release prep, and MAS compatibility review

## Remediation Merge Order

1. Phase R0 contract lock
2. Track A, data integrity and attachment ownership
3. Track C, screenshot access and settings
4. Track B, selection and clipboard export
5. Track D, design-system reconciliation
6. Full verification pass

## Track Gates

### Gate 1: Track Review

- Touched files stay within ownership
- Build passes for affected target
- Self-review includes behavior change, risk, and rollback note
- No unresolved stubs in claimed scope

### Gate 2: Integration Review

- Full app builds on macOS target
- Capture flow works with keyboard only
- Card stack opens and closes reliably
- Clipboard export works for single and multi-card selection
- TTL cleanup runs without data corruption

### Gate 3: Release Review

- Screenshot permission path is explicit and understandable
- Launch-at-login behavior is stable
- Window focus and hotkey behavior are verified across apps
- Failure states are surfaced without blocking capture flow

## Immediate Next Moves

1. QA `Phase R6` against real `capture -> Enter -> Cmd + 2` timing in light and dark mode
2. Tune any remaining light-mode veil or capture-surface shadow issues without reopening the sync path
3. Close the remaining `Phase R7` follow-up on IME-safe command routing and placeholder ownership
4. Keep deterministic capture QA and input metrics coverage green
5. Keep regression coverage for `submit -> immediate stack open` green
6. Resume grouped export validation against target paste destinations
