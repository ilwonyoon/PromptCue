# macOS Structural Audit — Resolution Summary

Generated: 2026-03-09

## PR Tracker

| PR | Branch | Items | Status |
|----|--------|-------|--------|
| #1 | `worktree-fix-structural-audit` | C-4, C-5, C-6 | Open |
| #2 | `fix/h1-timer-race-guard` | H-1 | Open |
| #3 | `fix/h5-accessibility` | H-5 | Open |
| #4 | `fix/m1-shadow-tokens` | M-1 | Open |
| #5 | `fix/m6-l1-l3-misc-cleanup` | M-6, L-1, L-3 | Open |
| #6 | `fix/l2-l4-type-safety-concurrency` | L-4 | Open |
| #7 | `fix/l5-codec-roundtrip-test` | L-5 | Open |
| #8 | `fix/m4-window-screen-change` | M-4 | Open |
| #9 | `fix/m5-constrain-frame-docs` | M-5 | Open |
| #10 | `fix/m2-m3-view-cleanup` | M-2, M-3 | Open |

## Item Resolution Status

### Critical (resolved prior to audit PRs)
| ID | Description | Status |
|----|-------------|--------|
| C-1 | GRDB transaction atomicity | Resolved (prior work) |
| C-2 | Combine subscription lifecycle | Resolved (prior work) |
| C-3 | Timer invalidation race | Resolved (prior work) |
| C-4 | NSEvent monitor deinit leak | **PR #1** |
| C-5 | CapturePanelRuntimeVC deinit cleanup | **PR #1** |
| C-6 | Strong panel capture in animation block | **PR #1** |

### High
| ID | Description | Status |
|----|-------------|--------|
| H-1 | Timer callback race after stop | **PR #2** |
| H-2 | Screenshot directory sandbox compliance | Resolved (prior work) |
| H-3 | Pasteboard change count tracking | Resolved (prior work) |
| H-4 | Image task cancellation | Resolved (prior work) |
| H-5 | VoiceOver accessibility labels | **PR #3** |

### Medium
| ID | Description | Status |
|----|-------------|--------|
| M-1 | Shadow modifier token alignment | **PR #4** |
| M-2 | SearchFieldSurface overlay complexity | **PR #10** |
| M-3 | CaptureCardView 21 color conditionals | **PR #10** |
| M-4 | windowDidChangeScreen handling | **PR #8** |
| M-5 | constrainFrameRect bypass documentation | **PR #9** |
| M-6 | Stale bookmark refresh | **PR #5** |
| M-7 | ScreenshotMonitor resource lifecycle | Resolved (prior work) |
| M-8 | Clipboard monitor edge cases | Resolved (prior work) |

### Low
| ID | Description | Status |
|----|-------------|--------|
| L-1 | StatusItem cleanup in stop() | **PR #5** |
| L-2 | NSEvent monitor type safety | Dropped (API returns `Any?`) |
| L-3 | UserDefaults key namespacing | **PR #5** |
| L-4 | DispatchQueue → Task.sleep migration | **PR #6** |
| L-5 | CaptureCard codec round-trip test | **PR #7** |
