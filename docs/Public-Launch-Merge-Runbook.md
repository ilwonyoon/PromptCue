# Backtick Public Launch Merge Runbook

## Purpose

This document is the operator runbook and execution record for the public-launch hardening train that landed on `main`.

`docs/Public-Launch-Hardening-Plan.md` remains the phase authority.
This file records the approved merge order, verification surface, stop conditions, and the actual post-merge repair steps that were required to get the lane green.

## Safety Decision

- GitHub merge target remains `main`.
- Active merge operations, conflict checks, and verification should run from a dedicated integration worktree, not from the checked-out local `main`.
- Clean verification surface for this train:
  - branch: `audit/public-launch-verify-main`
  - worktree: `/Users/ilwonyoon/Documents/PromptCue-public-launch-verify`
- Do not reuse ahead-of-main experiment worktrees as the verification surface for merged `main`.
- Every PR in this train must use `Create a merge commit`.
- Stop the train on any failed verification gate. Do not merge the next PR until the current merged state is green again.

## Why Local `main` Is The Wrong Execution Surface

- `#35`, `#36`, `#27`, and `#28` all touch `PromptCue/App/AppModel.swift`.
- `#33`, `#36`, `#27`, and `#28` all touch `PromptCue.xcodeproj/project.pbxproj`.
- `#37` adds the final `H6` verification runner, which expects a clean worktree by default.
- Local `main` should stay a recovery point and comparison baseline while the hardening train is in flight.
- ahead-of-main integration branches are useful for experiments, but they are the wrong baseline for post-merge regression gates.

Safe operating model:

1. Merge into GitHub `main` in the approved order.
2. Fast-forward the integration worktree to the new `origin/main`.
3. Run the required gate for that step.
4. Only then rebase or retarget the next PR.

## Setup

- [x] Fetch latest remote state.
- [x] Confirm `origin/main` is the intended landing target.
- [x] Create and confirm a clean verification worktree at `/Users/ilwonyoon/Documents/PromptCue-public-launch-verify`.
- [x] Confirm the merge method is `Create a merge commit`.
- [x] Confirm `#27` and `#28` stay out of this train until `#37` is complete.

Suggested commands:

```bash
git fetch origin --prune
git -C /Users/ilwonyoon/Documents/PromptCue-public-launch-verify status --short
git -C /Users/ilwonyoon/Documents/PromptCue-public-launch-verify fetch origin --prune
git -C /Users/ilwonyoon/Documents/PromptCue-public-launch-verify merge --ff-only origin/main
```

If a fresh integration worktree is needed:

```bash
git fetch origin --prune
git worktree add ../PromptCue-public-launch-verify -b audit/public-launch-verify-main origin/main
```

## Merge Train

### Step 1: `#33` Public launch baseline

- [x] Merge `#33` into `main` with `Create a merge commit`.
- [x] Fast-forward the integration worktree to the merged `origin/main`.
- [x] Run `scripts/verify_main_merge_safety.sh --profile safe-main --skip-perf`.
- [x] Record any fallout in release configs, entitlement wiring, or screenshot contract tests before touching `#34`.

Current note after `#33`:

- no blocking fallout
- repeated package exclude warnings for missing `.claude` in the clean verification worktree are non-blocking and pre-existing

### Step 2: `#34` Public launch privacy

- [x] Change `#34` base from `pr/public-launch-01-baseline` to `main`.
- [x] Rebase or update the branch onto the merged `main`.
- [x] Exit draft.
- [x] Merge `#34` into `main` with `Create a merge commit`.
- [x] Fast-forward the integration worktree to the merged `origin/main`.
- [x] Run `scripts/verify_main_merge_safety.sh --profile safe-main --skip-perf`.

### Step 3: `#35` Public launch battery

- [x] Change `#35` base from `pr/public-launch-02-privacy` to `main`.
- [x] Rebase or update the branch onto the merged `main`.
- [x] Exit draft.
- [x] Merge `#35` into `main` with `Create a merge commit`.
- [x] Fast-forward the integration worktree to the merged `origin/main`.
- [x] Run `scripts/verify_main_merge_safety.sh --profile safe-main --skip-perf`.
- [x] Confirm the merged state still opens Capture and Stack without startup-only service regressions.

Current note after `#35`:

- `safe-main` stayed green after the merge
- no startup-only capture or stack regression was observed in the merged state

### Step 4: `#36` Public launch cloud sync

- [x] Change `#36` base from `pr/public-launch-03-battery` to `main`.
- [x] Rebase or update the branch onto the merged `main`.
- [x] Exit draft.
- [x] Merge `#36` into `main` with `Create a merge commit`.
- [x] Fast-forward the integration worktree to the merged `origin/main`.
- [x] Run `scripts/verify_main_merge_safety.sh --profile safe-main --skip-perf`.
- [x] Run targeted cloud-sync lifecycle coverage:

```bash
xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO test \
  -only-testing:PromptCueTests/AppDelegateCloudSyncTests \
  -only-testing:PromptCueTests/AppModelCloudSyncLifecycleTests \
  -only-testing:PromptCueTests/CloudSyncSettingsTests
```

Current note after `#36`:

- the merged state exposed a cloud-sync lifecycle regression in the test-host startup path
- hotfix `#39` repaired `AppDelegate` / `AppModel` cloud-sync startup behavior and added focused regression coverage
- targeted cloud-sync lifecycle tests passed after `#39`

### Step 5: `#37` Public launch H6

- [x] Change `#37` base from `pr/public-launch-04-cloud-sync` to `main`.
- [x] Rebase or update the branch onto the merged `main`.
- [x] Exit draft.
- [x] Merge `#37` into `main` with `Create a merge commit`.
- [x] Fast-forward the integration worktree to the merged `origin/main`.
- [x] Run `scripts/verify_main_merge_safety.sh --profile safe-main`.
- [x] Run `scripts/run_h6_verification.sh`.
- [x] Record whether the signed release lane completed or was blocked by missing local credentials.

Current note after `#37`:

- the first `H6` run exposed an archive/package-cache collision caused by repo-local `build` outputs being picked up as SwiftPM target resources
- hotfix `#40` moved archive `DerivedData` and `SourcePackages` into temp directories outside the repo while keeping final artifacts under the requested output root
- `scripts/run_h6_verification.sh` passed after `#40`
- signed release lane result: `blocked-by-local-credentials`

## Completion Summary

- [x] `#33` merged to `main` with merge commit `b3782787f286eae8997568d4a043eae4d1964b2f`
- [x] `#34` merged to `main` with merge commit `bea3c338bfff8fca982912a186749bbe7da463e9`
- [x] `#35` merged to `main` with merge commit `6e59e7fd0a8dbc5d805b8d0160aab063e52b51d4`
- [x] `#36` merged to `main` with merge commit `a8b0cf98fdb129ca7a365e3a1cf86301d2e6a8e4`
- [x] `#37` merged to `main` with merge commit `941c8bb88de170dc56e18c822a586785d962710d`
- [x] post-merge cloud-sync repair `#39` merged to `main` with merge commit `330b07c3b9e21bae2d8d01dcf95827d3fe1acdfd`
- [x] post-merge H6 archive repair `#40` merged to `main` with merge commit `61730176f572aca43ab4d754aa36f439247d739a`
- [x] `scripts/verify_main_merge_safety.sh --profile safe-main` passed on the final merged state
- [x] `scripts/run_h6_verification.sh` passed on the final merged state
- [x] signed archive/notary lane remains gated by local credentials rather than product regressions

## Deferred Until After `#37`

These PRs stay out of the train until the `#33 -> #37` lane is fully green:

- [ ] Rebase `#27` on top of post-`#37` `main`.
- [ ] Rebase `#28` after the `#27` decision is finalized.
- [ ] Re-review `AppModel.swift` and `project.pbxproj` conflict surfaces before reopening the follow-up merge lane.

## Stop Conditions

Pause the train immediately if any of these occur:

- `scripts/verify_main_merge_safety.sh` fails after a merge
- `scripts/run_h6_verification.sh` fails for a reason other than missing local signing/notary credentials
- a PR rebase introduces `AppModel.swift` or `project.pbxproj` conflicts that are not obviously mechanical
- a merged state changes capture/stack behavior beyond the approved current baseline

If the train stops:

1. Keep `main` as the source of truth for the last merged PR.
2. Repair and verify in the integration worktree.
3. Resume only after the repaired state is green.
