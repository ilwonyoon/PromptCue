# Backtick Launch Readiness Blocker Report

## Scope

This report summarizes the current pre-DMG launch-risk review on `main`.

It follows the review buckets and execution model from
`docs/Launch-Readiness-Review-Plan.md`.

## Baseline

- current unsigned `H6` validation is green
- full app test suite is green on current `main`
- signed release lane is still blocked by missing local release credentials, not
  by a known archive/build failure

Reference:

- `/tmp/promptcue-h6-verification-20260321/h6-summary.txt`

## Blocking Findings

### 1. DMG ship artifact is not the artifact the release lane notarizes

The signed release script notarizes the submission ZIP, staples the exported
app, and validates the app, but then creates the final DMG after notarization
without submitting or assessing that DMG artifact itself.

Evidence:

- [archive_signed_release.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/archive_signed_release.sh#L424)
- [archive_signed_release.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/archive_signed_release.sh#L432)
- [archive_signed_release.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/archive_signed_release.sh#L445)

Why it matters:

- the Gumroad ship artifact for the DMG lane is the DMG
- the current script proves notarization for the app bundle, not for the final
  DMG container that users will download

## Closed In This Pass

### 1. Screenshot auto-detect now respects the approved-folder privacy contract

Runtime screenshot file detection now tracks only the bookmark-backed folder the
user approved in Backtick. The resolved macOS screenshot directory remains a
settings suggestion only. Clipboard screenshots keep their dedicated fast path.

Evidence:

- [RecentScreenshotCoordinator.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentScreenshotCoordinator.swift#L43)
- [RecentScreenshotLocator.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentScreenshotLocator.swift#L62)
- [RecentScreenshotLocator.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentScreenshotLocator.swift#L153)
- [RecentScreenshotDirectoryObserver.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentScreenshotDirectoryObserver.swift#L32)
- [RecentScreenshotDirectoryObserver.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentScreenshotDirectoryObserver.swift#L65)
- [ScreenshotDirectoryResolver.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/ScreenshotDirectoryResolver.swift#L155)
- [ScreenshotDirectoryObserverTests.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCueTests/ScreenshotDirectoryObserverTests.swift#L89)

Outcome:

- runtime file access no longer silently follows Desktop, Downloads, or
  `TemporaryItems`
- screenshot file attach remains explicit and user-approved
- clipboard screenshot speed-sensitive behavior stays unchanged

### 2. Stack card rendering no longer reads arbitrary existing local screenshot files

Stack rendering now requires managed attachment access for screenshot previews,
and capture edit seeding only reuses managed attachments that already live in
Backtick's attachment store.

Evidence:

- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CaptureCardView.swift#L152)
- [LocalImageThumbnail.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/LocalImageThumbnail.swift#L6)
- [AppModel+CaptureSession.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel+CaptureSession.swift#L40)
- [AttachmentStore.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/AttachmentStore.swift#L127)
- [AppModelEditingTests.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCueTests/AppModelEditingTests.swift#L190)
- [LocalImageThumbnailTests.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCueTests/LocalImageThumbnailTests.swift#L1)

Outcome:

- tampered or legacy external screenshot paths no longer render directly in the
  Stack
- external files must be imported into managed storage before card preview
  rendering uses them

### 3. Experimental remote `apiKey` mode now fails closed when the key is absent

The HTTP helper now rejects requests when `apiKey` auth is selected without a
non-empty key, instead of treating missing configuration as allow-all.

Evidence:

- [BacktickMCPHTTPServer.swift](/Users/ilwonyoon/Documents/PromptCue/Sources/BacktickMCPServer/BacktickMCPHTTPServer.swift#L445)
- [BacktickMCPServerTests.swift](/Users/ilwonyoon/Documents/PromptCue/Tests/BacktickMCPServerTests/BacktickMCPServerTests.swift#L1638)

Outcome:

- misconfigured remote helper launch no longer exposes an unauthenticated MCP
  surface

### 4. Memory markdown rendering no longer reparses identical documents on every recomposition

Parsed markdown sections now use deterministic IDs and an in-process parse cache
for repeated bodies.

Evidence:

- [MemoryViewerView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerView.swift#L669)
- [MemoryViewerView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Memory/MemoryViewerView.swift#L728)
- [ParsedMemoryMarkdownTests.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCueTests/ParsedMemoryMarkdownTests.swift#L32)

Outcome:

- repeated render passes reuse parsed structure for unchanged memory content
- section identity is stable across recomposition

## Remaining Mitigate Before Ship

### 1. Capture-session screenshot detection still uses timer polling and submit-path waits

Clipboard polling and screenshot settle polling are scoped to capture sessions,
not whole-app idle, but they still add repeated wakeups and a submit-time wait
loop. This pass intentionally did not rewrite that timing model in order to
avoid another screenshot-speed regression during launch hardening.

Evidence:

- [RecentClipboardImageMonitor.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentClipboardImageMonitor.swift#L54)
- [RecentClipboardImageMonitor.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentClipboardImageMonitor.swift#L228)
- [RecentScreenshotCoordinator.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentScreenshotCoordinator.swift#L113)
- [RecentScreenshotCoordinator.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentScreenshotCoordinator.swift#L169)
- [RecentScreenshotCoordinator.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/Services/RecentScreenshotCoordinator.swift#L595)
- [AppModel+CaptureSession.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppModel+CaptureSession.swift#L97)
- [AppTiming.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppTiming.swift#L5)

Impact:

- not an idle background blocker, but still a meaningful responsiveness and
  wakeup tradeoff in a core flow
- follow-up should be benchmark-driven and explicitly approved before changing
  screenshot responsiveness characteristics

## Defer After Launch

### 1. Release metadata is not fully self-contained for support triage

The metadata writer drops malformed JSON quietly and does not preserve enough
artifact-side evidence to answer every support question from the metadata file
alone.

Evidence:

- [write_release_metadata.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/write_release_metadata.sh#L205)
- [write_release_metadata.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/write_release_metadata.sh#L247)
- [write_release_metadata.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/write_release_metadata.sh#L252)

### 2. Stack-open perf trace fallback is not deterministic enough

The trace script can fall back to the latest app bundle by modification time
instead of a caller-specified app path.

Evidence:

- [record_stack_open_trace.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/record_stack_open_trace.sh#L32)
- [record_stack_open_trace.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/record_stack_open_trace.sh#L61)
- [record_stack_open_trace.sh](/Users/ilwonyoon/Documents/PromptCue/scripts/record_stack_open_trace.sh#L108)

## Remaining Release Dependencies

These are release-lane dependencies, not code blockers:

- `Developer ID Application` certificate installed on the release Mac
- `Config/Local.xcconfig` with:
  - `PROMPTCUE_RELEASE_SIGNING_SHA1` or `PROMPTCUE_RELEASE_SIGNING_IDENTITY`
  - `PROMPTCUE_RELEASE_TEAM_ID`
  - `PROMPTCUE_RELEASE_NOTARY_PROFILE`
- `notarytool` keychain profile present on the release Mac

## Current Recommendation

Do not cut the first signed DMG candidate yet.

The non-DMG launch findings closed in this pass are green under repo
verification. The remaining launch blocker is the DMG notarization lane:

1. DMG notarization gap
