# Stack Image Hover Restore Log (2026-03-13)

## Scope

- Task: verify intermittent image-card hover regression and confirm runtime stability before marking final checkpoint.
- Branch: `fix/stack-rail-controls`
- Latest code commit on branch at time of log: `060e5b7 - Stabilize stack card hover tracking for image cards`

## Root-cause findings

1. App is a menu-bar/utility style app (`LSUIElement=1`) and does not present a normal Dock app window by default.
   - If it appears “not opened,” this can be expected unless stack/capture is explicitly opened on launch.
   - Startup flags exist to force open behavior:
     - `PROMPTCUE_OPEN_STACK_ON_START`
     - `PROMPTCUE_OPEN_CAPTURE_ON_START`
     - `PROMPTCUE_OPEN_SETTINGS_ON_START`

2. Hover path is implemented with an NSView tracking area overlay in `CaptureCardView`.
   - Existing implementation logs are controlled by `PROMPTCUE_TRACE_STACK_CARD_HOVER=1` and persist to `/tmp/promptcue-hover.log`.
   - Tracking area is reinstalled from `updateTrackingAreas` / window lifecycle and synchronized with current cursor location after reinstall.

3. Remaining risk category when reproducing: build/runtime verification environment can differ between
   - launching from CLI without explicit stack-open flag, and
   - GUI-triggered stack launch in normal usage.
   - This previously looked like “nothing changed” when the panel was never visible due launch mode assumptions.

## Validation performed

1. Clean build:
   - `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`
   - Result: `** BUILD SUCCEEDED **`

2. Runtime launch test:
   - Executable path:
     - `/Users/ilwonyoon/Library/Developer/Xcode/DerivedData/PromptCue-emqyliogertgiifmocscbebowzee/Build/Products/Debug/Prompt Cue.app`
   - Launch command used:
     - `PROMPTCUE_TRACE_STACK_CARD_HOVER=1 PROMPTCUE_OPEN_STACK_ON_START=1 "…/Prompt Cue.app/Contents/MacOS/Prompt Cue"`
   - Result: process starts, stable PID, no startup crash in app log.

3. Trace checks:
   - `PROMPTCUE_HOVER_TRACKER_EVENT state=window_missing_card_area_released` during lifecycle events is expected during startup/rebind.
   - IMK startup lines appear normally.
   - No immediate crash/stall evidence observed while app is running.

## Practical guidance

- For future hover regression checks:
  - start with:
    - `rm -f /tmp/promptcue-hover.log`
    - launch with both `PROMPTCUE_OPEN_STACK_ON_START=1` and `PROMPTCUE_TRACE_STACK_CARD_HOVER=1`
  - move mouse in stack and inspect `/tmp/promptcue-hover.log` for `PROMPTCUE_CARD_HOVER_*` entries.
- If “still not visible” is reported again, first verify panel launch mode before editing hover logic.

## Residual risk

- No further hover code changes were applied in this checkpoint beyond existing stabilization commit.
- User-visible hover behavior should still be re-verified on-device after each major panel/rendering refactor because image-card row rebuilds can reintroduce intermittent timing effects.
