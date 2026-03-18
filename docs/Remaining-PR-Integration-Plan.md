# Backtick Remaining PR Integration Plan

## Purpose

This document is the execution plan for the remaining open PRs and dormant branches after the public-launch hardening train landed on `main`.

The goal is not to mechanically merge every stale branch.
The goal is to preserve the current `main` UX/UI baseline and selectively integrate only the behavior that still fits the current Backtick product direction.

## Ground Rules

- Use current `main` UX/UI as the visual and interaction baseline.
- Treat launch-prep cleanup as structure-only work unless a product decision explicitly says otherwise.
- Prefer fresh ports or small rebases over merging stale branches wholesale.
- Treat `AppModel.swift`, `AppCoordinator.swift`, `CardStackView.swift`, and `PromptCue.xcodeproj/project.pbxproj` as high-conflict integration surfaces.
- Do not reintroduce `ExecutionMap*`, `WorkItem*`, or board-window behavior unless product direction changes first.
- Keep GitHub merges on `main` and do conflict handling plus verification from a clean integration or verification worktree.
- Use `Create a merge commit` when a PR is actually merged.
- If capture panel behavior, stack behavior, recent screenshot slot/TTL, suggested-target chooser, or live Settings UX changes unexpectedly, stop and split the slice again.

## Current Status

- [x] Merged PRs are already closed automatically on GitHub. No manual close action was required.
- [x] `#41` merged to `main` with merge commit `985661d0be14828e5288cf20c1a2c6c5f9ff498a`.
- [x] Targeted screenshot/capture verification was run for `#41` before merge.
- [x] Replacement PR `#42` landed the current-main port of the aligned `#38` Stack-first MCP slice.
- [x] Replacement PR `#43` landed the current-main port of the aligned `#27` `Copy Raw` stack action.
- [x] Replacement PR `#45` landed the current-main port of the aligned `#28` stack edit flow.
- [x] Replacement PR `#46` landed the first behavior-preserving salvage slice from `architecture-cleanup`.
- [x] Replacement PR `#47` landed the second behavior-preserving salvage slice from `architecture-cleanup` with merge commit `5ed4bb7c5658115372de38ebaad4abb72c100cef`.
- [x] Replacement PR `#48` landed the third behavior-preserving salvage slice from `architecture-cleanup` with merge commit `ada40b787dee1fe81e055cb811ad3656f6ecbb39`.
- [x] Draft PR `#44` was closed and converted to a source-only branch after `#46` and `#47` landed as current-main replacement slices.
- [x] Stale PRs `#20` and `#21` were closed because their board and WorkItem directions no longer match current Backtick scope.
- [x] Stale PRs `#27` and `#28` were closed as superseded after their replacement merges landed.
- [x] Remaining open PRs were triaged; future architecture cleanup work will continue as fresh replacement PRs.
- [x] Dormant worktrees and obsolete branches were archived after the keep/port/close decision, excluding the explicitly retained source and verification surfaces.

## 2026-03-18 Stale Branch Follow-up

These branches were reviewed again after the MCP connector stabilization train landed on `main`.

### Fresh Port Required

- `origin/claude/add-expiration-timer-BCl2Q`
  - do not merge as-is
  - the branch is stale against current `main` and reintroduces unrelated old code
  - preserve only the timer-dot behavior as a fresh current-`main` port
  - verification target:
    - under one hour remaining, show rounded-up minute text next to the existing TTL dot
    - preserve pinned-card behavior and copied-card behavior
    - keep the timer accessible instead of hidden from accessibility

### Doc-Only Sync Required

- `origin/claude/expand-mcp-platforms-cSW7o`
  - do not merge as-is
  - the branch contains stale runtime and settings code relative to current `main`
  - preserve only branch-unique documentation that still adds value
  - current keep candidate:
    - `docs/Mem0-Takeaways-for-Backtick.md`
  - explicitly avoid reviving stale runtime directions from that branch

### Do Not Delete Yet

- local branch `feat/working-with-apps`
  - remote branch is already gone, but the local branch still contains unique unmerged commits
  - also attached to another worktree
  - keep it intact until the surviving behavior is either ported or explicitly abandoned

## Open PR Triage

### Merge Now

- [x] `#41` `fix/screenshot-expiration-suspend`
  - reason: low-risk fix on top of current `main`
  - UX/UI impact: none beyond preventing screenshot preview expiry during capture

- [x] `#46` `port/pr44-appmodel-split`
  - reason: first current-`main` salvage slice from `architecture-cleanup`
  - scope:
    - move suggested-target chooser state and lifecycle logic out of `AppModel.swift`
    - preserve current Capture, Stack, and Settings UX/UI exactly
  - rule:
    - merged to `main` with a merge commit

- [x] `#47` `port/pr44-capture-session-split`
  - reason: second current-`main` salvage slice from `architecture-cleanup`
  - scope:
    - move capture-session and edit-session flow out of `AppModel.swift`
    - preserve copied-card edit behavior, screenshot seeding, and capture submit handoff exactly
  - rule:
    - merged to `main` with a merge commit

- [x] `#48` `port/pr44-screenshot-split`
  - reason: third current-`main` salvage slice from `architecture-cleanup`
  - scope:
    - move screenshot-state helpers out of `AppModel.swift`
    - preserve current screenshot slot, placeholder, draft override, and suspend-expiration behavior exactly
  - rule:
    - merged to `main` with a merge commit

### Port Selectively

- [x] `#38` was ported selectively and landed through replacement PR `#42`
- [x] `#27` was ported selectively and landed through replacement PR `#43`
- [x] `#28` was split-ported selectively and landed through replacement PR `#45`

### Close Or Defer

- [x] `#21` `backtick-mcp-manual-grouping`
  - reason:
    - reintroduces `WorkItem*` and derived work-item creation, which conflicts with current Stack-first MCP direction
  - planned action:
    - closed instead of merged; any aligned behavior should return as a fresh current-main slice

- [x] `#20` `backtick-mcp-board`
  - reason:
    - reintroduces `ExecutionMap*` board/window behavior that is outside current product direction
  - planned action:
    - closed instead of merged; any aligned behavior should return as a narrow current-main slice

- [x] `#44` `architecture-cleanup`
  - reason:
    - the branch remains useful as a source of small structure-only ports, but the draft PR itself is too large and stale to merge safely
  - planned action:
    - closed instead of merged; future aligned cleanup returns through fresh replacement PRs on top of current `main`

## Dormant Branch And Worktree Triage

- branch-content triage result:
  - `feat/pr20-model-slice` and `feat/pr20-view-slice` only preserve `ExecutionMap*` surfaces that no longer match current Backtick scope
  - `audit/public-launch-core-perf`, `audit/public-launch-services-security`, and `audit/public-launch-ui-battery` contain no unique still-aligned behavior beyond landed `main`
  - `audit/public-launch-integration`, `merge/pr33`, `merge/pr33-clean`, `merge/pr36-clean`, `hotfix/public-launch-appdelegate-init`, and `hotfix/h6-build-exclude` are operational history only
  - `audit/public-launch-verify-main` should be kept only if a dedicated clean verification surface still adds operational value

## No-Regression Constraint

- launch-prep cleanup and refactor work must preserve the current live UX/UI
- do not merge or port any slice that changes visible capture, stack, settings, or screenshot-slot behavior unless that behavior change is explicitly intended and separately reviewed
- prefer structural replacement PRs on top of current `main` over rebasing stale large branches

### Keep As Source Only

- [x] `architecture-cleanup`
  - keep as a source branch for small refactor ports
  - do not merge wholesale
  - closed PR:
    - `#44` was closed after its safe pieces started landing through replacement PRs
  - landed replacement slice:
    - `#46` suggested-target chooser extraction from `AppModel.swift`
    - `#47` capture-session and edit-session extraction from `AppModel.swift`
    - `#48` screenshot-state extraction from `AppModel.swift`
  - safe salvage candidates:
    - further behavior-preserving `AppModel` decomposition after `#48`, one domain block at a time
    - cloud-sync split only if lifecycle gating remains unchanged
    - Settings shell and tab decomposition only if no concurrent Settings refactor is in flight
    - `ScreenshotScanResultHandler` only after screenshot parity gates are isolated
  - defer from the current branch as written:
    - provider extraction that introduces `TargetDetailResolver`, terminal session probing, or richer auto-resolution behavior
    - any screenshot-coordinator split that changes capture-mode expiration or live preview semantics
  - current assessment:
    - this is a large refactor stack, not a single safe merge
    - `#44` should be treated as multiple replacement PRs, not as one integration event
    - hard rule: preserve current capture, stack, and Settings UX/UI exactly; if a slice needs a user-visible behavior change, stop and split it out

### Archive After Review

- [x] `feat/pr20-model-slice`
- [x] `feat/pr20-view-slice`
- [x] `feat/pr21-integration`
- [x] `audit/public-launch-core-perf`
- [x] `audit/public-launch-services-security`
- [x] `audit/public-launch-ui-battery`
- [x] `audit/public-launch-integration`
- [x] `merge/pr33`
- [x] `merge/pr33-clean`
- [x] `merge/pr36-clean`
- [x] `hotfix/public-launch-appdelegate-init`
- [x] `hotfix/h6-build-exclude`

Archive rules:

- keep `audit/public-launch-verify-main` only if a dedicated clean verification surface is still useful
- keep product branches only when they contain unique, still-aligned behavior
- remove operational merge/hotfix branches after their changes are already on `main`

Triage notes:

- `feat/pr20-model-slice` and `feat/pr20-view-slice` only retain `ExecutionMap*` behavior that no longer matches current Backtick scope
- `audit/public-launch-core-perf`, `audit/public-launch-services-security`, and `audit/public-launch-ui-battery` have no unique commits beyond the landed `main` lineage
- `audit/public-launch-integration`, `merge/pr33`, `merge/pr33-clean`, `merge/pr36-clean`, `hotfix/public-launch-appdelegate-init`, and `hotfix/h6-build-exclude` are operational history only and can be archived after the branch cleanup pass
- `audit/public-launch-verify-main` is only worth keeping as an operational clean verification surface
- retained after cleanup:
  - `architecture-cleanup`
  - `audit/public-launch-verify-main`
  - `mcp-tool-update`
  - `backtick-mcp-bundled-helper`

## Recommended Integration Order

1. continue mining `architecture-cleanup` into small current-`main` replacement PRs only when each slice is behavior-preserving
2. archive obsolete dormant branches and worktrees

## Verification Gates

For each remaining integration slice:

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Add focused gates where relevant:

- `#46`: focused `AppModel*`, capture-session, screenshot, and cloud-sync regression tests before app-wide build
- later `#44` AppModel slices: focused `AppModel*`, capture-session, screenshot, and cloud-sync regression tests before app-wide build
- `#44` screenshot slice: recent screenshot coordinator tests, clipboard tests, and capture submit/manual smoke

## Stop Conditions

Stop and split the slice if any of these occur:

- the port changes current Capture or Stack interaction semantics beyond the approved baseline
- the slice requires reviving `ExecutionMap*`, `WorkItem*`, or board-window behavior
- the rebase conflict in `AppModel.swift` is not mechanical
- the port requires `project.pbxproj` churn that is unrelated to the feature behavior
