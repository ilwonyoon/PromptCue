# Backtick Public Launch Hardening Plan

## Purpose

This document turns the current public-launch hardening review into the execution lane for macOS public launch readiness.

The goal is not broad cleanup. The goal is to close the concrete blockers that still keep Backtick from being a stable, low-surprise direct-download launch:

- no deterministic signed + notarized direct-download release lane
- bundled helper packaging that works for development but is not yet release-grade
- screenshot/privacy behavior that still exceeds the documented approved-folder contract in residual paths
- hidden cross-app inspection that can trigger surprise TCC prompts
- unnecessary idle wake-ups in a background utility app
- path/bookmark contracts that are not strong enough for Mac App Store compatibility later

This lane is constrained by one rule:

- preserve the current approved functionality and UI/UX wherever possible

If a fix would change behavior, it must either:

1. keep the visible UX unchanged while reducing hidden risk, or
2. become an explicit product decision outside the default v1 path.

## Authority And Roll-Up

This document is authoritative for `Phase H`.

It inherits:

- product contract from `docs/Execution-PRD.md`
- release/distribution baseline from `docs/Engineering-Preflight.md`
- phase roll-up and queue positioning from `docs/Implementation-Plan.md`
- top-level status roll-up from `docs/Master-Board.md`

Repo terminology for the active pre-release signed local lane is now:

- `DevSigned`

Historical `Beta` wording in older docs is superseded by `DevSigned` for current planning and configuration work.

## Current Lane Status

| Phase | Status | Notes |
| --- | --- | --- |
| `H0` | In progress | contract lock is active in docs; architecture policy for the shipped helper is the last material open decision |
| `H1` | Ready after `H0` | master-owned release/config/artifact work can begin in parallel now |
| `H2` | Planned | runtime merge waits for `H0` and the current `safe-main` slice to stay green |
| `H3` | Planned | startup and idle-lifecycle work follows the `H2` screenshot contract and `H5` sync gating contract |
| `H4` | Planned | this is containment of already-landed non-goal automation code, not expansion of a v1 feature |
| `H5` | Planned | this is containment of already-landed non-goal sync capability surface, not expansion of v1 scope |
| `H6` | Planned | final launch gate after `H1-H5` land |

## Execution Position Relative To Current Main Slice

This lane does not replace the current `safe-main` stabilization slice. It overlays it.

- `H0` and master-owned `H1` may proceed now in parallel with `safe-main`, `R7`, `R8`, `R9`, and `DP1/DP2` because they are docs/config/release-lane work.
- Runtime behavior changes from `H2-H5` should not merge ahead of the current `safe-main` gate unless the master agent carves out a narrow hard-blocker patch.
- `H6` only runs after the release lane and runtime containment slices have landed.

## Review Baseline

The current review found these primary public-launch gaps:

1. the project has no deterministic signed + notarized direct-download lane
2. the bundled `BacktickMCP` helper is present for runtime use, but is not yet a release-grade artifact with a frozen architecture/signing/notarization contract
3. screenshot auto-attach still has residual fallback behavior outside the approved-folder contract, especially temp-container scanning and raw stored-path recovery
4. suggested-target behavior starts too early and inspects other apps using Apple Events and subprocess enrichment paths
5. clipboard image detection still polls continuously at app idle
6. arbitrary `screenshotPath` values can still enter storage through multiple ingress paths and later be read back by UI/export/sync surfaces
7. stale bookmark recovery and live folder rebinding are weaker than they should be
8. CloudKit/push capability is broader than the runtime product default

## Hardening Principles

- Preserve Backtick's product model:
  - Capture = frictionless dump
  - Stack = execution queue
  - AI compression happens in Stack
- Prefer no-regret hardening before any behavior change.
- Do not add UI chrome, helper text, or settings noise unless a permission or risk boundary truly requires it.
- Hidden background work must earn its keep:
  - no always-on polling unless the user-facing value is strong and measured
  - no startup observers that exceed the current feature contract
- Release-sensitive configuration stays master-owned:
  - signing
  - entitlements
  - helper packaging
  - notarization
  - direct-distribution artifacts
- App Store later compatibility should improve as a side effect of the direct-distribution lane, not require a future rewrite.
- PRD non-goals stay non-goals:
  - `Automatic terminal targeting` is not promoted by this lane
  - `Cloud sync` is not expanded by this lane
  - if those code paths remain in repo, this lane only contains and quiets them for default launch behavior

## Non-Regression Boundary

This lane should not regress these visible behaviors without an explicit decision:

- `Cmd + \`` still opens Capture immediately
- `Cmd + 2` still opens Stack immediately
- Capture remains low-chrome and raw
- Stack remains dense and keyboard-friendly
- approved current capture and stack visuals remain the baseline
- screenshot attach still works for the approved user-selected folder flow
- MCP read/write/execute behavior remains unchanged unless the write contract must tighten attachment ownership

## Change Classes

### Class A: No-Regret Hardening

These changes should not materially change the visible product behavior:

- add a deterministic direct-download release lane and artifact validation
- split direct and App Store entitlement/config lanes
- make `BacktickMCP` a release-grade packaged helper
- fix stale bookmark refresh behavior
- add live folder rebinding when the approved screenshot folder changes
- remove duplicate entitlement sources of truth
- remove warning noise and brittle build-graph configuration
- gate push registration and CloudKit startup behavior to actual sync enablement

### Class B: Behavior-Sensitive But UX-Preservable

These changes reduce hidden risk and battery cost, but they change internal behavior:

- restrict screenshot discovery to the explicit approved-folder contract
- ban temp-container screenshot scanning in the default product path
- stop continuous clipboard image polling outside the narrow session where it matters
- stop eager cross-app suggested-target inspection at app launch
- defer or scope startup maintenance so the utility app stays quiet at idle

These should be designed so that:

- the visible UI stays the same
- the user does not need more chrome
- only the hidden background behavior becomes stricter

### Class C: Explicit Product Decision Required

These should not land silently:

- keeping `TemporaryItems` / `NSIRD_screencaptureui` scanning in the default path
- keeping Apple Events or subprocess-based repo inference enabled on normal launch
- promoting non-goal sync or non-goal suggested-target behavior into v1 feature scope
- introducing a new permission prompt or new Settings surface by default

## Parallel Execution Model

This lane uses master-managed multi-track execution, but only after `H0` contract lock.

### Branch And Worktree Pattern

- integration lane:
  - current integration worktree remains the master-owned merge lane
- track worktrees:
  - `../PromptCue-services-security`
  - `../PromptCue-core-perf`
  - `../PromptCue-ui-battery`

Rules:

- workers do not merge directly into integration
- release/config/docs land only through the master-owned integration lane
- if a runtime track needs `AppModel` or app-entrypoint wiring, the master agent opens and closes that edit window explicitly

### Master-Owned Files

- `docs/Public-Launch-Hardening-Plan.md`
- `docs/Implementation-Plan.md`
- `docs/Master-Board.md`
- `docs/Engineering-Preflight.md`
- `project.yml`
- `Config/**`
- `PromptCue/PromptCue.entitlements`
- release scripts under `scripts/**`
- `PromptCue/App/AppCoordinator.swift`
- `PromptCue/App/AppDelegate.swift`
- `PromptCue/App/PromptCueApp.swift`
- shared-contract changes in `Sources/PromptCueCore/**`

### Track Ownership After Contract Lock

`services-security`

- screenshot access contract
- bookmark recovery and live rebinding
- attachment ingress rules across local capture, MCP, sync, migration, and note update
- attachment read-side policy for render/export/re-sync
- suggested-target privacy boundary
- CloudKit/push runtime gating

Primary files:

- `PromptCue/Services/ScreenshotDirectoryResolver.swift`
- `PromptCue/Services/RecentScreenshotDirectoryObserver.swift`
- `PromptCue/Services/RecentScreenshotLocator.swift`
- `PromptCue/Services/StackWriteService.swift`
- `Sources/BacktickMCPServer/**`
- `PromptCue/UI/Settings/ScreenshotSettingsModel.swift`

`core-perf`

- clipboard polling lifecycle
- recent screenshot coordinator lifecycle
- startup maintenance deferral
- observer/timer wake-up containment

Primary files:

- `PromptCue/Services/RecentClipboardImageMonitor.swift`
- `PromptCue/Services/RecentScreenshotCoordinator.swift`
- lifecycle helpers moved into `Sources/PromptCueCore/**` if they can be made pure

`ui-battery`

- minimal disclosure UI only if a security decision truly requires it
- runtime smoke verification focused on idle behavior, launch prompts, and interaction cost

Primary files:

- `PromptCue/UI/**` only when required by a master-approved privacy decision

### Track Gates

| Track | Required Verification | Review Focus |
| --- | --- | --- |
| `services-security` | `swift test`; `xcodegen generate`; `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build` when app surfaces move | permission boundaries, attachment ownership, TCC risk, regression of approved screenshot flow |
| `core-perf` | `swift test`; `xcodegen generate`; Debug app build when app surfaces move; idle-wake smoke before merge | timer/observer removal, startup quietness, capture-open and stack-open responsiveness |
| `ui-battery` | Debug app build when UI changes land; targeted runtime smoke | avoid new chrome, keep disclosure terse, verify no launch-time permission surprises |
| Master integration | all relevant track gates plus Release/DevSigned/artifact inspection checks from `H6` | merge sequencing, release safety, cross-track regressions |

## Phase H0: Contract Lock And Baseline Freeze

### Goal

Freeze the public-launch boundary before implementation starts.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Freeze `Class A` scope | Master | None | No | no-regret hardening scope is explicit and mergeable without UX debate | Completed |
| Freeze `Class B` scope | Master | None | No | behavior-sensitive work cannot expand silently | Completed |
| Freeze phase positioning relative to the current `safe-main` slice | Master | None | No | `H0/H1` are allowed now; `H2-H5` merge rules are explicit | Completed |
| Freeze repo nomenclature so `DevSigned` replaces historical `Beta` wording | Master | None | Yes | active docs and config planning use one term | Completed |
| Freeze the direct-download release contract and artifact set | Master | Review baseline | No | exact command chain and outputs are named in this document | Completed |
| Freeze the default-off privacy stance for non-goal suggested-target behavior | Master | Review baseline | No | normal launch uses no Apple Events or subprocess enrichment | Completed |
| Freeze the local-only default stance for non-goal sync behavior | Master | Review baseline | No | normal launch performs no CloudKit/push work | Completed |
| Decide whether shipped v1 artifacts are universal or Apple Silicon-only | Master | None | No | helper architecture policy is fixed before `H1` closes | Open |
| Record current verification and artifact inspection baseline | Master | None | Yes | before/after comparison remains possible | Completed |
| Choose the automated coverage path for lifecycle/privacy policy code | Master | Review baseline | Yes | `H6` knows whether to add an app-target test target or move more pure logic into `PromptCueCore` | Planned |

### Locked H0 Decisions

- `DevSigned` is the canonical near-production signed local lane in this repo.
- `H0` and master-owned `H1` may progress now in parallel with the current `safe-main` queue.
- `H2-H5` runtime behavior changes do not merge ahead of the current `safe-main` gate unless the master agent explicitly cuts a narrow blocker patch.
- suggested-target automation is not a v1 feature; the default launch path must not trigger Apple Events or subprocess-based enrichment
- Cloud sync is not a v1 feature; the default launch path must stay local-only and quiet

### Exit Criteria

- release lane expectations are explicit
- privacy boundary is explicit
- worktree ownership and merge rules are explicit
- no worker needs to guess whether a behavior change is allowed

## Phase H1: Release Lane And Artifact Hardening

### Goal

Make the direct-download lane deterministic and release-capable without changing user-visible behavior.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Add explicit config split for `Debug`, `DevSigned`, `Release`, and `AppStore` | Master | `H0` | No | direct and MAS-later lanes are separated in project config | Planned |
| Move entitlement definitions to one source of truth and split direct/App Store entitlement files | Master | config split | No | direct and MAS lanes no longer share one implicit entitlement shape | Planned |
| Add release settings for hardened runtime, signing identity, and lane selection | Master | config split | No | Release stops behaving like an unsigned local build | Planned |
| Replace ad hoc helper bundling with a deterministic release-grade helper build/sign/package path | Master | helper architecture decision | No | helper architecture and signing are inspectable and reproducible | Planned |
| Add in-repo archive/sign/notarize/staple/package validation | Master | above | Yes | repo can produce or validate a public-launch artifact deterministically | In progress |
| Expand CI or release automation to validate the Release lane | Master | above | Yes | release failures stop being discovered manually at the end | In progress |
| Add Release artifact recording for version/build/git SHA/checksum/notarization log | Master | above | Yes | every ship candidate has a reproducible release record | In progress |

### Configuration Matrix

`DevSigned` is the current repo replacement for earlier `Beta` wording.

| Config | Purpose | Signing | Hardened Runtime | Entitlements Lane | Capability Default | Allowed Use |
| --- | --- | --- | --- | --- | --- | --- |
| `Debug` | fast local development | optional / `CODE_SIGNING_ALLOWED=NO` acceptable | off | direct-debug baseline only | local-only default, no ship expectations | local runs, CI smoke, test builds |
| `DevSigned` | stable signed local run for TCC and near-production smoke | local development identity | off unless a specific smoke requires parity | direct lane only | local-only default, no ship candidate status | manual QA, TCC smoke, helper/runtime smoke |
| `Release` | direct-download ship candidate | `Developer ID Application` | on | direct lane only | local-only default unless a later explicit product decision changes it | archive, notarize, staple, DMG/package, Gumroad candidate |
| `AppStore` | MAS-later compatibility lane | MAS signing identity | MAS governed | sandboxed App Store lane | stricter default-off capability surface | build compatibility checks only until MAS work opens |

Rules:

- `Release` is the only lane allowed to produce a public-launch artifact.
- `DevSigned` exists to make local TCC behavior stable; it is not a ship candidate.
- `AppStore` must be modeled in config even if it is not actively shipped yet.

### Canonical Entitlements And Release Credentials

`H1` must freeze these rules:

- one entitlements source of truth per lane
- no inline entitlement duplication in `project.yml`
- direct lane and App Store lane point at different entitlement files
- release scripts fail fast if required credentials are missing

Canonical credential inputs to freeze in scripts:

- Developer ID identity name
- Apple Team ID
- notarytool profile name

Ownership:

- release credential owner is the master/release lead role, not a worker track
- missing or rotated credentials are upload-blocking and must fail before archive packaging continues

### Direct vs App Store Delta Table

| Area | Direct Lane | App Store Later Lane | Constraint On Shared Code Now |
| --- | --- | --- | --- |
| signing | `Developer ID Application` + notarization | MAS signing | shared code may not assume one signing lane |
| sandbox | off by default | on | file access must stay bookmark-friendly now |
| screenshot access | approved folder + bookmark + managed import | same contract, sandbox-enforced | no hidden file scanning assumptions |
| bundled `BacktickMCP` helper | allowed if signed/notarized and deterministic | assume unavailable until MAS-safe policy is proven | app must not require helper presence at launch |
| updater path | manual DMG now, `Sparkle` later if adopted | App Store update path only | app runtime may not assume updater framework |
| CloudKit/push | default-off local-only launch | default-off unless future review approves | runtime must gate capability startup |
| suggested-target automation | default-off in v1 launch path | assume unavailable | runtime must not require Apple Events or subprocess enrichment |
| launch at login | allowed later if direct lane signs the helper path correctly | only if MAS-compliant path is verified | launch-at-login remains outside this lane unless it becomes a blocker |

### Direct-Download Release Contract

This contract should be implemented exactly, with script names and env/profile names frozen by `H1`.

Current master-owned script entrypoint:

- `scripts/archive_signed_release.sh`

| Step | Command Shape / Action | Required Output | Blocking |
| --- | --- | --- | --- |
| 1 | `xcodegen generate` | deterministic project file generation | Yes |
| 2 | `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Release -archivePath build/Release/PromptCue.xcarchive archive` | signed archive candidate | Yes |
| 3 | export/copy the app artifact from the archive into a deterministic release folder | `build/Release/Backtick.app` or equivalent frozen path | Yes |
| 4 | sign and verify all nested content, including `BacktickMCP`, before final artifact validation | helper + app signatures are valid | Yes |
| 5 | `xcrun notarytool submit ... --wait` | notarization success + archived log/output | Yes |
| 6 | `xcrun stapler staple <AppPath>` and `xcrun stapler validate <AppPath>` | stapled app | Yes |
| 7 | create branded DMG in a deterministic filename | `Backtick-<version>-<build>.dmg` | Yes |
| 8 | compute checksum and record version/build/git SHA/notarization reference | release record artifact | Yes |
| 9 | Gatekeeper and quarantine smoke on the final app/DMG | install/open path behaves correctly | Yes |
| 10 | only tagged or explicitly approved release automation may produce ship candidates | unambiguous release provenance | Yes |

### Bundled Helper Contract

`BacktickMCP` must ship under a frozen release contract:

- helper canonical path:
  - `Prompt Cue.app/Contents/Helpers/BacktickMCP`
- helper architecture policy:
  - either universal, or explicitly Apple Silicon-only with that decision reflected in release metadata and download expectations
- helper build path:
  - deterministic release-owned build/package step, not an implicit dev-only fallback
- signing order:
  - build helper
  - sign helper
  - verify helper
  - sign/archive app
  - verify nested helper signature inside the final app
- shipped-build smoke:
  - run the bundled helper from a temp directory with no source checkout present
  - verify at minimum `initialize` and `tools/list`

### Exit Criteria

- `Release` no longer means "unsigned local build"
- helper packaging is deterministic and release-grade
- direct-distribution artifact validation exists in repo
- App Store later lane is modeled instead of implied

## Phase H2: Screenshot Permission And Attachment Contract Closure

### Goal

Bring screenshot behavior back inside the documented user-approved folder model while preserving the visible screenshot-attach experience for the approved flow.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Fix stale bookmark refresh so a successfully refreshed bookmark stays connected | `services-security` | `H0` | Yes | reconnect is only required when refresh actually fails | Planned |
| Add live bookmark-change rebinding for choose, reconnect, and clear-folder flows | `services-security` + Master wiring | `H0` | No | changing the folder immediately drops old scope, rebinds watchers, and clears stale pending session state | Planned |
| Remove `TemporaryItems` / `NSIRD_screencaptureui` watch, probe, and readable-scan behavior from the default path | `services-security` + Master wiring | `H0` | No | default screenshot attach stays inside the approved-folder contract | Planned |
| Define one attachment ingress matrix for local capture, MCP, CloudKit inbound, legacy migration, and note update | Master + `services-security` | `H0` | No | all screenshot-path ingress rules are explicit | Planned |
| Enforce write-side import or rejection rules for every attachment ingress path | `services-security` | ingress matrix | No | storage no longer accepts unsupported external paths | Planned |
| Enforce read-side rules so only managed attachments or explicitly imported approved-folder files are rendered, exported, or re-synced | `services-security` | ingress matrix | No | UI/export/sync no longer consume raw unsupported external paths | Planned |
| Verify reconnect, clear-folder, restart, and live-folder-switch behavior against the bookmark contract | `services-security` | above | Yes | screenshot settings recovery is stable and testable | Planned |

### Exit Criteria

- screenshot access is explicit
- no temp-container watch/probe/scan remains in the default product path
- arbitrary external screenshot paths stop flowing through storage and read-side surfaces
- bookmark recovery and live folder switching are reliable
- approved screenshot attach UX still works

## Phase H3: Idle Wake-Up And Startup Containment

### Goal

Reduce idle battery cost and background churn without changing visible UI/UX.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Freeze a master-owned deferred startup contract for production builds | Master | `H0` | No | no cleanup timer when TTL is off; no screenshot/target service starts until needed; no always-on startup work survives by accident | Planned |
| Stop continuous clipboard image polling outside the capture session or other proven-needed scope | `core-perf` + Master wiring | startup contract | No | idle app no longer wakes every 250 ms for pasteboard checks | Planned |
| Scope screenshot observers to the interaction window where screenshot attach matters | `core-perf` | `H2` | No | directory watchers are not always on at idle | Planned |
| Defer non-critical startup maintenance and avoid cleanup timers when TTL is off | `core-perf` + Master wiring | startup contract | No | startup work matches actual enabled features | Planned |
| Re-check capture-open and stack-open latency after lifecycle changes | `core-perf` | above | Yes | battery wins do not regress interaction speed | Planned |

### Exit Criteria

- no obvious idle polling remains for clipboard/screenshot flows
- startup is quieter and feature-scoped
- capture and stack still feel immediate

## Phase H4: Suggested Target Privacy Boundary

### Goal

Contain or remove already-landed non-goal automation behavior so normal launch stays prompt-free and privacy-safe.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Freeze the safe default suggested-target data shape for v1 | Master | `H0` | No | normal launch may not depend on Apple Events, subprocess repo inference, or hidden privileged enrichment | Completed |
| Move suggested-target discovery off unconditional app startup | `services-security` + Master wiring | `H0` | No | normal launch no longer starts privileged target inspection paths | Planned |
| Split safe signal from privileged enrichment and define explicit policy for `CGWindowListCopyWindowInfo`, Apple Events, and subprocess-based repo inference | Master + `services-security` | `H0` | No | each signal source has an explicit allowed/default-off policy | Planned |
| Remove or default-off Apple Events and subprocess-based enrichment for v1 | `services-security` | privacy policy | No | no surprise cross-app automation occurs in the default launch path | Planned |
| Keep UI minimal if any disclosure or future opt-in remains necessary | `ui-battery` | privacy policy | Yes | any new UI stays terse and action-first | Planned |
| Verify "no prompt on normal launch" and, if any opt-in survives later, "prompt only after explicit user action" | Master + `ui-battery` | above | Yes | privacy behavior is intentionally testable | Planned |

### Exit Criteria

- Backtick no longer surprises the user with hidden automation behavior on normal launch
- any remaining non-goal suggested-target behavior is explicitly default-off and reviewable

## Phase H5: Cloud Sync Capability Tightening

### Goal

Contain already-landed non-goal sync capability surface so the default local-only launch stays quiet.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Freeze the v1 sync stance as containment-only, not feature expansion | Master | `H0` | No | docs treat sync as default-off/local-only in this lane | Completed |
| Gate remote-notification registration to actual sync enablement | Master + `services-security` | `H1` | No | default launch does not register for remote notifications | Planned |
| Gate CloudKit engine construction and startup to actual sync enablement | `services-security` + Master wiring | `H1` | No | default launch performs no CloudKit work | Planned |
| Verify sync enabled/disabled transitions still work if the existing setting remains reachable | `services-security` | above | Yes | contained opt-in path remains functional or is explicitly deferred | Planned |
| Document direct-lane versus App Store lane capability expectations | Master | `H1` | Yes | capability decisions are explicit in docs and config | Planned |

### Exit Criteria

- default local-only launch is quiet
- sync code does not widen the public-launch surface by accident
- capability surface is easier to reason about for release review

## Phase H6: Final Verification And Release Gate

### Goal

Prove that hardening landed without harming the approved product surface.

### Tasks

| Task | Owner | Dependency | Parallelizable | Exit Criteria | Status |
| --- | --- | --- | --- | --- | --- |
| Add automated coverage for lifecycle/privacy policy code by app-target tests or `PromptCueCore` extraction | Master | `H0` | No | reviewed risk areas are no longer covered only by manual smoke | Planned |
| Re-run package, app, and project generation verification | Master | `H1-H5` | No | automated baseline stays green | Planned |
| Run bundled helper smoke from a temp directory with no source checkout present | Master | `H1` | Yes | shipped helper behavior is independent of repo layout | Planned |
| Run the release artifact inspection checklist | Master | `H1` | Yes | signing/notarization/Gatekeeper failures are caught before upload | Planned |
| Run TCC smoke for normal launch, capture open, screenshot folder connect, and any surviving suggested-target path | Master + `ui-battery` | `H2-H4` | Yes | no surprise permission prompts remain in default flows | Planned |
| Run idle-energy and wake-up smoke on a signed local build | Master + `core-perf` | `H3` | Yes | idle utility behavior is acceptable for public launch | Planned |
| Record remaining launch risks, rollback plan, and deliberately deferred behavior-sensitive items | Master | all phases | No | launch decision is explicit rather than implicit | Planned |

### Exit Criteria

- public launch blocker list is closed or consciously deferred
- signed artifact behavior is understood
- visible capture/stack UX remains intact

## Verification Standard

Minimum automated verification for this lane:

- `swift test`
- `xcodegen generate`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Required release-lane verification when `H1` lands:

- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Release CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration DevSigned build`
- `codesign -dvv <AppPath>`
- `codesign -d --entitlements - <AppPath>`
- `codesign --verify --deep --strict --verbose=4 <AppPath>`
- `spctl --assess --type execute --verbose=4 <AppPath>`
- `xcrun stapler validate <AppPath>`
- `file <HelperPath>`
- `lipo -info <HelperPath>`
- `shasum -a 256 <DMGPath>`

Required verification for policy-heavy runtime phases:

- automated coverage for:
  - stale bookmark refresh
  - live folder switch / folder clear
  - external `screenshotPath` rejection or import across MCP, CloudKit inbound, legacy migration, and note update
  - no launch-time suggested-target inspection in the default path
  - no idle clipboard polling or cleanup timer when the feature is inactive

Required manual verification:

- TCC reset smoke for screenshot folder connect and normal launch
- quarantine-first-launch smoke from the final DMG
- bundled helper smoke from a temp directory with no source checkout
- idle wake-up / Energy Log pass
- capture open / stack open responsiveness smoke

## Release Artifact Inspection Checklist

| Check | Method | Blocking |
| --- | --- | --- |
| app signature validity | `codesign --verify --deep --strict --verbose=4 <AppPath>` | Yes |
| helper signature validity | `codesign --verify --strict --verbose=4 <HelperPath>` | Yes |
| notarization success record | `xcrun notarytool submit ... --wait` log archived with release record | Yes |
| stapled artifact validity | `xcrun stapler validate <AppPath>` | Yes |
| Gatekeeper acceptance | `spctl --assess --type execute --verbose=4 <AppPath>` | Yes |
| helper architecture policy | `file <HelperPath>` and `lipo -info <HelperPath>` match the chosen v1 policy | Yes |
| bundled helper runtime smoke | run bundled `BacktickMCP` from a temp dir with no source checkout | Yes |
| DMG checksum and release record | `shasum -a 256 <DMGPath>` plus version/build/git SHA/notarization record | Yes |
| clean install / quarantine smoke | mount DMG, copy app, first launch from quarantined path | Yes |
| Gumroad listing assets and marketing copy | release operations checklist outside this lane | No |
| updater framework choice | deferred unless it becomes a direct-launch blocker | No |

## Explicitly Deferred From This Lane

These items stay out unless they become direct launch blockers:

- `Sparkle` or any in-app updater choice
- Gumroad marketing copy and storefront assets
- launch-at-login expansion beyond existing release-safety requirements
- new sync product work
- new suggested-target product work

## Recommended Track Open Order

1. `services-security`
   - closes the strongest public-launch blockers first
   - locks permission and attachment contracts before optimization work
2. `core-perf`
   - removes idle wake-ups and startup churn once security contracts are frozen
3. `ui-battery`
   - only opens when a behavior-sensitive change requires minimal disclosure or runtime smoke support

## Merge Order

1. `Phase H0` contract lock
2. `Phase H1` release lane and helper hardening
3. `Phase H2` screenshot permission and attachment contract closure
4. `Phase H4` suggested-target privacy boundary
5. `Phase H5` Cloud sync capability tightening
6. `Phase H3` idle wake-up and startup containment
7. `Phase H6` final verification gate

Why this order:

- release and permission contracts should be fixed before optimization work starts hiding risk
- privacy containment should land before energy work so startup quietness is not masking unsafe behavior
- battery work is safer once always-on observers and hidden capability surfaces are already constrained

## Launch Exit Bar

Backtick is ready to leave this lane only when:

- Release output is signable/notarizable by a deterministic repo-backed path
- helper packaging is architecture-correct for the chosen v1 distribution strategy
- screenshot behavior stays inside the explicit user-approved contract
- default launch no longer risks surprise Terminal/iTerm automation prompts
- default launch performs no accidental CloudKit/push work
- obvious idle polling and avoidable wake-ups are removed or tightly scoped
- current approved capture and stack UI/UX still hold
- rollback notes and any consciously deferred items are recorded
