# Backtick Performance Remediation Plan

## Purpose

This document defines the current performance remediation lane for Backtick.

The goal is not generic optimization. The goal is to remove the concrete latency and frame-drop regressions that now break the product contract:

- Capture must open immediately
- Capture must submit immediately
- Stack must stay scannable under long-card load
- common state changes must not invalidate unrelated UI

Identity note:

- user-facing product identity is `Backtick`
- current repo/app target/core module names remain `PromptCue` / `PromptCueCore`
- Capture stays a frictionless dump surface
- Stack stays an execution queue

## Current Baseline

The current codebase shows four primary performance regressions:

1. `Stack` long-card overflow measurement now performs synchronous text measurement during view rendering.
2. card mutations still trigger whole-array resort, full-table persistence rewrite, and whole-stack republish on the main actor.
3. `Capture` panel open still performs screenshot discovery and cache work before the panel is shown.
4. recent sync and startup maintenance work amplify main-thread pressure and make existing rerenders more expensive.

Recent-change read:

- the strongest current `Stack` regression is in the active overflow worktree changes
- the strongest current shared-state regression correlates with the iCloud sync slice from `2026-03-09`
- the strongest recent `Capture` visual cost increase correlates with the `2026-03-09` shadow follow-up

## Performance Principles

- fix hot-path invalidation before visual compositor tuning
- move file I/O and database writes off the main actor first
- prefer cached measurement over repeated view-time measurement
- keep `Capture` and `Stack` state fan-out separate where possible
- preserve Backtick's product model:
  - Capture = frictionless dump
  - Stack = execution queue

## Quantitative Verification Standard

Every performance slice must ship with a reproducible before/after measurement.

- define one primary metric per slice before editing code
- record both `baseline` and `after` with the same fixture, machine state, and command
- capture the exact benchmark or test command in the slice notes so the run can be repeated later
- if an intermediate attempt improves the metric but still leaves the hot path too expensive, record it and mark it as `rejected`, not `done`
- keep one regression guardrail alongside the performance win:
  - correctness tests still pass
  - UI behavior does not change unless the slice explicitly intends it
  - build/test verification remains green for touched surfaces
- prefer numbers that map to the product contract:
  - `hotkey -> focused editor`
  - `Enter -> panel close`
  - `Cmd + 2 -> first frame`
  - `n` repeated long-card measurements

Minimum evidence per slice:

| Evidence | Requirement |
| --- | --- |
| Primary metric | one elapsed-time number or ratio that reflects the hotspot being fixed |
| Command | exact command used to gather the number |
| Fixture | short description of text/card/screenshot load used for the run |
| Attempt log | any intermediate attempt that was measured and rejected before the final fix |
| Guardrail | tests/build commands that prove behavior still holds |
| Result note | short interpretation of whether the slice materially improved the targeted path |

Acceptance rule:

- a slice is only `accepted` when the final measured result is small enough for the targeted user path, not merely better than baseline
- if a measured improvement still leaves a visible hot path cost, the slice remains open and the rejected attempt stays in the ledger

## Execution Order

1. `Phase P0`: instrumentation baseline
2. `Phase P1`: stack overflow and rerender containment
3. `Phase P2`: incremental persistence and state publication
4. `Phase P3`: capture-open path decoupling
5. `Phase P4`: sync/startup throttling and batching
6. `Phase P5`: compositor cleanup and regression verification

## Phase P0: Instrumentation Baseline

### Goal

Measure the real hot paths before broad tuning changes hide the regressions.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Add signposts around capture open, screenshot discovery, capture submit, stack copy/delete, and stack overflow measurement | Master | None | No | hot paths have elapsed timings in Instruments |
| Define fixture scenarios for short, medium, and very long cards | Master | None | Yes | stack traces are comparable across runs |
| Record baseline timings for `hotkey -> editor focused`, `Enter -> panel close`, and `Cmd + 2 -> first frame` | Master | instrumentation | No | future slices have before/after comparisons |

### Exit Criteria

- Instruments runs can attribute time to the main performance hotspots.
- The team can compare future slices against one baseline.

## Phase P1: Stack Overflow And Rerender Containment

### Goal

Remove the biggest current `Stack` regression without reopening interaction behavior.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| Cache stack overflow metrics by text + width | Master | None | No | long-card measurement no longer reruns on every body evaluation |
| Stop recomputing overflow metrics multiple times inside one card render | Master | above | No | one card render uses one resolved metrics value |
| Stop repeated active/copied filtering inside one stack render | Master | None | Yes | body evaluation partitions cards once |
| Add focused tests for overflow metrics stability | Master | above | Yes | metric behavior stays correct while caching lands |

### Exit Criteria

- Hover, selection, and expand no longer trigger repeated full-card text measurement work.
- Stack body evaluation is materially cheaper for long-card fixtures.

## Phase P2: Incremental Persistence And State Publication

### Goal

Remove full-table rewrites and whole-stack invalidation from steady-state user actions.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| move `CardStore` write paths off the main actor | Master | None | No | DB I/O no longer blocks UI directly |
| replace `save([all cards])` on create/copy/delete with targeted `upsert` / `delete` / batch upsert | Master | storage refactor | No | single-card actions do not rewrite the whole table |
| reduce `AppModel.cards` whole-array replacement for single-item mutations | Master | storage refactor | No | stack invalidation is narrower |
| split stack-facing observable state from capture-only state | Master | state refactor | No | capture typing does not republish the whole stack |

### Exit Criteria

- capture submit, copy, and delete are no longer O(n) table rewrites.
- stack refresh cost scales with changed cards, not total cards.

## Phase P3: Capture-Open Path Decoupling

### Goal

Make the capture panel appear immediately even when screenshot discovery is expensive.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| show the capture panel before screenshot refresh work starts | Master | None | No | hotkey open is no longer blocked on directory scans |
| move screenshot discovery and clipboard-image caching off-main | Master | open-path split | No | open latency is not dominated by file/clipboard work |
| memoize preview image decode by cache URL or session ID | Master | screenshot async work | Yes | repeated preview presentation does not re-decode large images |
| reduce synchronous panel resize churn during multiline growth | Master | capture path cleanup | Yes | wrap growth stays smooth under typing and paste |

### Exit Criteria

- `hotkey -> focused editor` is fast even with large screenshot folders or clipboard images.

## Phase P4: Sync And Startup Throttling

### Goal

Stop sync and startup maintenance from compounding UI latency.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| batch copied-card sync instead of per-card push fan-out | Master | P2 | No | multi-card copy no longer causes one network task per card |
| apply remote sync changes incrementally instead of full save | Master | P2 | No | remote sync does not rewrite the whole store |
| defer migration, prune, and sync fetch from first interactive launch path | Master | None | Yes | first panel open is not competing with maintenance |

### Exit Criteria

- startup and sync do not materially delay first interaction.

## Phase P5: Compositor Cleanup And Final Verification

### Goal

Trim visual rendering cost after invalidation and I/O hotspots are controlled.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria |
| --- | --- | --- | --- | --- |
| simplify resting stack card chrome where the visual delta is negligible | Master | P1-P4 | Yes | card chrome no longer adds avoidable compositor cost |
| test a lighter stack backdrop variant against current default | Master | P1-P4 | Yes | backdrop cost is understood and intentional |
| run final Instruments passes for capture, stack, and sync scenarios | Master | P1-P4 | No | the remediation lane has measured wins |

### Exit Criteria

- Backtick feels fast in the real capture and stack flows, not only in isolated tests.

## Immediate Next Slice

The active slice is:

- none; `P1-P4`, the approved capture/stack visuals, the long-note overflow path, and the live `Cmd + 2 -> first frame` stack-open trace are active in the merge-safe landing candidate, and the performance remediation lane is complete for that scope. `P5` remains documented here as the quantified visual-retune experiment from the integration branch, but the merge-safe candidate does not ship the historical benchmark file itself.

Current status:

- `P1A-P1C` landed and is quantitatively verified.
- `P2` landed and is quantitatively verified.
- `P3A-P3B` landed and are quantitatively verified.
- `P3C-P3D` landed and are quantitatively verified.
- `P4A` landed and is quantitatively verified.
- `P4B` landed and is quantitatively verified.
- `P4C` landed and is quantitatively verified.
- `P4` is now fully accepted and quantitatively verified.
- `P5` landed and is quantitatively verified.
- the live stack-open trace harness has been captured against the real panel presentation path.
- the performance remediation lane is now complete.

Current verification target:

- `swift test`
- `xcodegen generate`
- if app surfaces are touched, `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Primary metric for the final accepted slice:

- stack visual render preparation cost under the current stack backdrop + card chrome, measured against the pre-remediation visual stack under a fixed fixture
- live `Cmd + 2 -> first frame` timing under the stack-open trace harness on a real app launch

Required benchmark capture for the final accepted slice:

- baseline: current stack-open and resting-scroll compositor cost under a fixed long-card fixture
- after: lighter backdrop/card-chrome variant under the same fixture
- fixture: fixed long-card stack, same panel size, same light/dark appearance, same interaction sequence
- command: store the exact benchmark or Instruments capture invocation alongside the recorded result
- live trace command: `scripts/record_stack_open_trace.sh --app <Prompt Cue.app>`

## Results Ledger

Use this section as a compact running log for landed or active slices.

| Slice | Attempt | Metric | Baseline | After | Command | Status | Note |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `P1A-P1C` | `A1` text-hash cache only | repeated long-card overflow measurement, 1440 iterations | `uncached = 459.83 ms` | `cached warm = 211.98 ms`, `2.17x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/StackCardOverflowPerformanceTests` | rejected | better than baseline, but warm-cache key generation still left the render hot path too expensive |
| `P1A-P1C` | `A2` id-keyed cache | repeated long-card overflow measurement, 2000 iterations | `uncached = 646.17 ms` | `cached warm = 1.54 ms`, `420.62x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/StackCardOverflowPerformanceTests` | accepted | warm-cache cost is now effectively negligible for the stack render path |
| `P2` | `A1` incremental delete | single-card delete persistence cost, 24 iterations, 600-card fixture | `replaceAll = 349.77 ms` | `incrementalDelete = 9.69 ms`, `36.08x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CardStorePerformanceTests` | accepted | single-card delete no longer rewrites the full table in the steady-state path |
| `P2` | `A2` incremental mutation | single-card mutation persistence cost, 24 iterations, 600-card fixture | `replaceAll = 344.78 ms` | `incrementalUpsert = 9.92 ms`, `34.74x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CardStorePerformanceTests` | accepted | steady-state edit/copy paths now use targeted writes instead of full-table replacement |
| `P3A-P3B` | `A1` async capture-session preparation | `prepareForCaptureSession()` return latency, 24 iterations, 25 ms slow-locator fixture | `slow locator baseline = 619.81 ms` | `prepare return = 0.50 ms`, `1247.15x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/RecentScreenshotCoordinatorPerformanceTests` | accepted | capture open no longer blocks on screenshot directory scan; panel show/focus can complete before scan results arrive |
| `P3C` | `A1` preview image decode memoization | repeated preview image load, 120 iterations, 2048x1536 PNG fixture | `direct decode = 12015.01 ms` | `warm cache = 2.36 ms`, `5089.59x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CapturePreviewImagePerformanceTests` | accepted | repeated preview presentation now reuses decoded images instead of reloading the same large screenshot payload |
| `P3D` | `A1` preferred-height callback guard | repeated preferred-height callback path, 2400 iterations, one growth event plus 2399 redundant heights | `unguarded = 14.11 ms` | `guarded = 0.26 ms`, `54.08x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CapturePanelResizePerformanceTests` | accepted | unchanged multiline measurements no longer fan out redundant panel-resize callbacks |
| `P3D` | `A2` same-frame panel resize guard | repeated panel frame apply, 2400 iterations, one target frame plus 2399 redundant frames | `unguarded = 14.73 ms` | `guarded = 0.40 ms`, `36.64x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CapturePanelResizePerformanceTests` | accepted | once multiline growth has already resized the panel, repeated same-frame updates are now skipped cheaply |
| `P4A` | `A1` copied-card sync batching | copied-card sync dispatch cost, 120 iterations, 120-card fixture | `per-card push = 3726.10 ms` | `batched push = 30.76 ms`, `121.15x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncPushPerformanceTests` | accepted | multi-card copy now pays one sync dispatch instead of one dispatch per copied card |
| `P4B` | `A1` indexed merge + lazy remote screenshot import | remote sync apply completion cost, 24 iterations, 600-card fixture with 400 upserts, 200 deletes | `legacy = 7141.17 ms` | `optimized = 3751.90 ms`, `1.90x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testRemoteApplyBenchmark` | rejected | merge/apply completion got cheaper, but the synchronous remote-apply entry path was still too expensive to leave on the interactive hot path |
| `P4B` | `A2` queued remote apply handoff | remote sync apply dispatch latency, 24 iterations, 600-card fixture with 400 upserts, 200 deletes | `synchronous = 3061.76 ms` | `queued = 0.92 ms`, `3336.44x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testRemoteApplyDispatchBenchmark` | accepted | remote sync apply is now handed off without blocking the interactive entry path; completion work still continues in the background |
| `P4B` | `A3` queued selective-import completion | queued remote sync apply completion cost, 24 iterations, 600-card fixture with 400 upserts, 200 deletes | `queued eager preprocess = 5614.42 ms` | `queued selective import = 3245.15 ms`, `1.73x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/CloudSyncApplyPerformanceTests/testQueuedRemoteApplyCompletionBenchmark` | accepted | background remote-apply completion now avoids eager asset import and reuses the indexed merge/apply path, so the queued path is materially cheaper end to end |
| `P4C` | `A1` deferred startup maintenance and initial sync fetch | `start()` return latency, 24 iterations, 600-card fixture with 80 ms prune stub | `synchronous startup = 2050.89 ms` | `deferred startup = 94.48 ms`, `21.71x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/AppStartupPerformanceTests` | accepted | first interactive launch no longer blocks on prune/migration maintenance or the initial cloud fetch setup path |
| `P5` | `A1` backdrop layer collapse + resting chrome gating | stack visual render preparation cost, 18 iterations, 28-card fixture across light and dark schemes | `legacy = 21893.06 ms` | `optimized = 4189.88 ms`, `5.23x speedup` | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -DPROMPTCUE_RUN_PERF_BENCHMARKS' test -only-testing:PromptCueTests/StackPanelVisualPerformanceTests/testStackVisualRenderBenchmark` | accepted | stack backdrop blur layering and resting-card elevation chrome no longer dominate fixed-fixture stack render preparation |
| `P5` | `A2` live stack-open trace harness | real `Cmd + 2 -> first frame` panel presentation timing, single live trace capture on the current Debug build | `n/a` | `109.50 ms` | `scripts/record_stack_open_trace.sh --app <Prompt Cue.app>` | accepted | the real stack-open path is now captured under `xctrace` with a saved `.trace`, so future windowing/compositor changes can be checked against a concrete first-frame number |

## Guardrails

- do not turn Capture into a richer editor in the name of performance work
- do not flatten runtime-owned AppKit capture behavior into generic SwiftUI-only abstractions
- do not accept design polish regressions just because a surface becomes cheaper to render
