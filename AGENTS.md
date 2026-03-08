# Prompt Cue Agent Guide

## Purpose

This repository defaults to fast, high-quality execution with explicit coordination. Use agents to improve speed, quality, or conflict isolation. Do not use agents by default when a task is small, tightly coupled, or faster to complete directly.

## Product Context

- Product: `Prompt Cue`
- Shape: native macOS utility app
- App stack: `SwiftUI + AppKit hybrid`
- Distribution baseline: Gumroad-backed direct download first
- Compatibility lane: Mac App Store later
- Core shared logic: `PromptCueCore`

Source-of-truth docs:

- `docs/Execution-PRD.md`
- `docs/Implementation-Plan.md`
- `docs/Master-Board.md`
- `docs/Engineering-Preflight.md`

## Execution Default

Preferred default for broad or decomposable work:

- one master agent coordinates
- worker agents own disjoint files or tracks
- master reviews and integrates sequentially

Single-agent is preferred when:

- the task is one file or one tightly coupled change
- the task is mostly analysis or quick cleanup
- parallel work would create merge risk or overhead

Use multi-agent only when it improves one or more of:

- delivery speed
- review quality
- conflict isolation
- verification coverage

## Planning Rules

Before editing:

- identify the smallest useful outcome
- check source-of-truth docs first
- define ownership boundaries if more than one agent will edit
- freeze shared contracts before parallel implementation

If the task is substantial, keep a short live plan with:

- current step
- blocked dependencies
- next verification command

## File Ownership Guidance

Master-owned by default:

- app entrypoints
- dependency wiring
- release-sensitive config
- shared contract changes
- integration docs

Typical split:

- `Sources/PromptCueCore/**`
  - pure logic, formatting, domain rules, testable models
- `PromptCue/Services/**`
  - macOS integrations, persistence, hotkeys, screenshot access
- `PromptCue/UI/**`
  - views, panels, interaction behavior
- `docs/**`
  - product, planning, release, and process docs

Do not let two agents edit the same file unless the master explicitly opens that edit window.

## PromptCueCore Rule

Prefer `PromptCueCore` for:

- domain models
- TTL logic
- formatting rules
- pure transformation logic
- code that should be covered by `swift test`

Prefer app target code for:

- `AppKit`
- `SwiftUI`
- `NSPasteboard`
- panel controllers
- filesystem access
- security-scoped bookmarks
- launch-at-login

If logic starts in the app and is pure, move it into `PromptCueCore` early so tests cover real code instead of duplicated code.

## Verification Expectations

Minimum verification for relevant changes:

- `swift test`
- `xcodegen generate`

Add app-target verification when touching buildable app surfaces:

- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

If you do not run a relevant verification step, say so explicitly and explain why.

## Release-Sensitive Areas

Treat these as high-risk and review carefully:

- signing and bundle identifiers
- entitlements and sandbox behavior
- screenshot folder access
- security-scoped bookmarks
- launch-at-login
- notarization
- DMG packaging
- Gumroad release artifacts
- App Store compatibility

Changes in these areas should usually stay master-owned or be reviewed by the master before integration.

## Context Discipline

- Keep context small
- Read only the files needed for the current step
- Prefer updating existing docs over creating overlapping docs
- Avoid speculative refactors during feature work
- Do not fan out agents unless contracts and ownership are clear

## UI Restraint Rule

- Preserve Prompt Cue's minimal, less invasive, Spotlight-first, and quiet ambient behavior.
- Do not add verbose UI chrome, helper copy, subtitles, status rows, or redundant cues unless they resolve a real ambiguity, permission block, error, or destructive consequence.
- Apply a subtraction test to capture UI changes: if the panel still works after removing a new element, keep it out.

## Output Standard

When finishing a task, report:

- what changed
- what was verified
- remaining risks or gaps

For multi-agent work, the master should also report:

- which tracks ran in parallel
- merge order
- any deferred conflicts or follow-up cleanup
