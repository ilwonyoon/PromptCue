# Backtick Launch Readiness Review Plan

## Purpose

This document defines the pre-DMG launch review lane.

The goal is not a broad cleanup pass. The goal is to review the current `main`
branch for issues that would make a direct-download Backtick release too risky
to ship, then close or consciously defer those findings before a notarized DMG
candidate is produced.

## Authority And Roll-Up

This document is a child plan under `Phase H` and `Phase 5`.

It inherits:

- product contract from `docs/Execution-PRD.md`
- release/distribution baseline from `docs/Engineering-Preflight.md`
- phase positioning from `docs/Implementation-Plan.md`
- public launch hardening scope from `docs/Public-Launch-Hardening-Plan.md`
- artifact and manual-ship checks from `docs/DMG-Launch-Checklist.md`
- top-level status roll-up from `docs/Master-Board.md`

If this document conflicts with the product contract or release baseline, the
upstream source-of-truth docs win.

## Review Goal

Before the first signed DMG ship candidate:

1. identify launch-blocking issues on current `main`
2. separate true blockers from acceptable launch-day risk
3. land no-regret fixes where needed
4. leave a short blocker report that can gate the final DMG decision

## Review Scope

This review is release-risk based.

### In Scope

- correctness and regression risk in the core user flow
  - Capture
  - Stack
  - MCP connector setup and runtime
  - screenshot ingest
  - local persistence and sync-default-off behavior
- crash and data-loss risk
- security and privacy boundaries
- performance and idle resource use
- release and distribution safety
  - signing
  - helper packaging
  - notarization lane
  - entitlements
  - first-launch behavior
- operability and supportability
  - diagnostics
  - error clarity
  - release records

### Out Of Scope

- speculative refactors
- design polish that does not affect launch safety
- feature expansion beyond the current approved product contract
- Mac App Store feature work beyond direct-download compatibility hygiene

## Review Buckets

Every finding should be classified into one of these buckets:

| Bucket | Meaning | Launch Effect |
| --- | --- | --- |
| `Blocking` | likely crash, data loss, broken core flow, broken release lane, or security/privacy failure | must be fixed or explicitly cut from launch scope |
| `Mitigate Before Ship` | serious but bounded risk with a clear mitigation | should be fixed or guarded before DMG handoff |
| `Defer` | real issue, but not a launch blocker | document and move post-launch |

## Execution Model

Run the review in three parallel tracks under master integration.

### Track A: Release And Security

Focus:

- signing and notarization lane
- helper packaging and helper launch contract
- entitlements and provisioning assumptions
- bookmark, file-access, and screenshot privacy boundaries
- MCP auth/token handling and remote surface safety

Primary files:

- `scripts/**`
- `Config/**`
- `PromptCue/PromptCue.entitlements`
- `Sources/BacktickMCPServer/**`
- release-sensitive app wiring under `PromptCue/App/**`

### Track B: Correctness And Stability

Focus:

- Capture and Stack regressions
- crash and data-loss paths
- DB and persistence behavior
- connector-state correctness
- screenshot attachment flow

Primary files:

- `Sources/PromptCueCore/**`
- `PromptCue/Services/**`
- `PromptCue/UI/Capture/**`
- `PromptCue/UI/Views/**`
- `PromptCue/UI/Settings/**`

### Track C: Performance And Operability

Focus:

- idle polling and wake-up cost
- panel open latency and rendering hot paths
- memory/markdown rendering cost
- logging, diagnostics, and supportability

Primary files:

- `PromptCue/Services/**`
- `PromptCue/UI/**`
- release metadata and validation scripts

## Baseline Evidence Before Review Closure

The launch review should keep these facts explicit:

- current unsigned `H6` validation is green on `main`
- the signed release lane is currently blocked by local credentials, not by a
  known product or packaging failure
- the review should not mutate `.omc/`, `build/`, or other local-only release
  artifacts outside an intentional release run

## Exit Criteria

The launch review is considered complete when:

1. all `Blocking` findings are fixed, scope-cut, or explicitly accepted by the
   release owner
2. `Mitigate Before Ship` findings are either fixed or have a concrete ship-day
   mitigation
3. current `main` has a short launch blocker report
4. the required verification passes for the landed fixes
5. the repo is ready to resume the signed DMG lane as soon as local credentials
   are available

## Required Verification

Minimum verification for findings that lead to code or config changes:

- `xcodegen generate`
- `swift test`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

When the release lane changes:

- `scripts/run_h6_verification.sh --require-signed` once local credentials exist
- `scripts/archive_signed_release.sh --package-format dmg --output-root build/signed-release`

## Output Format

The final launch review report should contain:

- `Blocking findings`
- `Mitigate before ship`
- `Deferred after launch`
- `Verification run`
- `Remaining release dependencies`

Keep the report short and release-oriented.
