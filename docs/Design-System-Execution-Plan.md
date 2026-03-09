# Backtick Design System Execution Plan

## Purpose

This document turns the architecture proposal into an execution plan.

Reference:

- [Design-System-Architecture-Proposal.md](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/docs/Design-System-Architecture-Proposal.md)

This plan is intentionally conservative.

It assumes:

- current `main` is the source of truth
- runtime-critical behavior must not regress
- design-system work must not re-couple stack backdrop, stack cards, and capture runtime sizing

## Goals

The plan is successful if it improves all four of these without destabilizing current behavior:

1. macOS native look and feel
2. custom to Backtick
3. no uncontrolled hardcoding in app UI
4. reusable components where reuse is real

## Non-Goals

This plan does not aim to:

- genericize every component
- move all values into primitive tokens
- replace AppKit-owned runtime sizing with token-driven layout
- flatten Backtick-specific capture and stack patterns into a component library

## Guardrails

### Guardrail 1: Runtime Ownership Stays Explicit

These files are runtime contracts, not generic design-system primitives:

- [AppUIConstants.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/App/AppUIConstants.swift)
- [VisualEffectBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/VisualEffectBackdrop.swift)
- [CaptureEditorRuntimeHostView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Capture/CaptureEditorRuntimeHostView.swift)
- [CapturePanelRuntimeViewController.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift)

### Guardrail 2: Pattern Ownership Stays Explicit

These files are Backtick-specific patterns, not generic shared surfaces:

- [SearchFieldSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/SearchFieldSurface.swift)
- [StackNotificationCardSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackNotificationCardSurface.swift)
- [StackPanelBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackPanelBackdrop.swift)
- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Views/CaptureCardView.swift)
- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Views/CardStackView.swift)

### Guardrail 3: “No Hardcoding” Means “No Inline Drift”

Eliminate:

- repeated inline visual numbers in feature views
- repeated local opacity/shadow math across multiple files
- duplicated material recipes with no single owner

Allow temporarily:

- recipe-local values inside one owner file
- runtime constants inside runtime contract files

## Ownership Model

### Master-Owned

- [Design-System-Architecture-Proposal.md](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/docs/Design-System-Architecture-Proposal.md)
- [Design-System-Execution-Plan.md](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/docs/Design-System-Execution-Plan.md)
- [Implementation-Plan.md](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/docs/Implementation-Plan.md)
- [Master-Board.md](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/docs/Master-Board.md)
- [Quality-Remediation-Plan.md](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/docs/Quality-Remediation-Plan.md)

### Track A: Foundations And Semantics

- [PrimitiveTokens.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/DesignSystem/PrimitiveTokens.swift)
- [SemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/DesignSystem/SemanticTokens.swift)
- [PromptCueShadowModifiers.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/DesignSystem/PromptCueShadowModifiers.swift)

### Track B: Reusable Component Surfaces

- [GlassPanel.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/GlassPanel.swift)
- [CardSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/CardSurface.swift)
- [PromptCueChip.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/PromptCueChip.swift)
- [PanelHeader.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/PanelHeader.swift)

### Track C: Pattern Recipes

- [SearchFieldSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/SearchFieldSurface.swift)
- [StackNotificationCardSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackNotificationCardSurface.swift)
- [StackPanelBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackPanelBackdrop.swift)

### Track D: Audit And Preview

- [Design-System.md](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/docs/Design-System.md)
- [Design-System-Audit.md](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/docs/Design-System-Audit.md)
- [DesignSystemPreviewView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Preview/DesignSystemPreviewView.swift)
- [DesignSystemPreviewTokens.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/DesignSystem/DesignSystemPreviewTokens.swift)

## Execution Phases

### Phase DS1: Boundary Freeze

Goal:

- make the architecture enforceable before visual cleanup starts

Status:

- implemented on `feat/design-system-strategy-integration`
- boundary comments and ownership lanes now exist in code for capture runtime, stack backdrop, and stack notification surfaces

Tasks:

1. document the five-layer system as authoritative
2. mark runtime-owned and pattern-owned files explicitly in planning docs
3. define which files are not allowed to be flattened into generic abstractions
4. freeze the meaning of `no hardcoding` for this project

Exit criteria:

- future PRs can be reviewed against explicit boundaries
- token cleanup work has a clear “no-go” list

### Phase DS2: Value Ownership Split

Goal:

- separate stable design values from runtime behavior values

Status:

- implemented on `feat/design-system-strategy-integration`
- `PanelMetrics`, `CaptureRuntimeMetrics`, and `AppTiming` now exist
- `AppUIConstants` is reduced to a transitional compatibility facade, and runtime callers now use grouped contracts directly

Tasks:

1. split `AppUIConstants` conceptually into:
   - panel metrics
   - capture runtime metrics
   - app timing
2. move only stable shared visual values into design-system lanes
3. keep runtime/editor timing values outside primitive-token migration

Exit criteria:

- fewer mixed-responsibility constants
- no visual cleanup PR needs to edit runtime timing by accident

### Phase DS3: Pattern Recipe Centralization

Goal:

- move repeated Backtick-specific visual math into explicit owner files

Status:

- implemented on `feat/design-system-strategy-integration`
- capture shell chrome, stack notification card chrome, copied-stack recipe extraction, and stack backdrop recipe extraction now live in owner files

Tasks:

1. centralize capture shell chrome recipe
2. centralize stack card chrome recipe
3. centralize stack backdrop blur/density recipe
4. remove duplicated local opacity and border math from feature views

Exit criteria:

- one pattern = one owner file
- feature views compose patterns instead of restyling them locally

### Phase DS4: Reusable Surface Rationalization

Goal:

- reduce duplication among truly shared surfaces

Status:

- started on `feat/design-system-strategy-integration`
- shared notification-card chrome and top-edge highlight helpers now exist where reuse is already real

Tasks:

1. identify shared card/shell/chip recipe helpers
2. extract only what is already reused
3. leave final application specialized per pattern

Exit criteria:

- reuse increases
- Backtick capture/stack identity does not collapse into generic cards

### Phase DS5: Native macOS Alignment Pass

Goal:

- improve macOS fidelity after boundaries are stable

Reference:

- [Design-Polish-Execution-Plan.md](/Users/ilwonyoon/Documents/PromptCue/docs/Design-Polish-Execution-Plan.md)

Tasks:

1. audit materials and blur recipes against actual macOS utility behavior
2. audit typography and control density against system expectations
3. audit settings layout against native preference-pane conventions
4. verify appearance in both light and dark mode
5. complete the bounded capture/stack polish slices defined in the design-polish execution plan

Exit criteria:

- Backtick reads more native
- custom identity remains intact

## Validation Gates

### Gate A: Architecture Gate

Required before code cleanup starts:

- proposal and execution plan accepted
- boundary map linked from planning docs

### Gate B: No-Regression Gate

Required for each phase:

- no capture sizing regressions
- no stack backdrop/card cross-regressions
- no settings regression into non-native layout

### Gate C: Hardcoding Gate

Required for each merged slice:

- no new inline one-off visual values in feature views
- no duplicated recipe math introduced across files

### Gate D: Native-Feel Gate

Required before any design-system work is considered done:

- light mode and dark mode both feel intentional
- blur/material usage feels macOS-native
- Backtick still reads as a quiet AI scratchpad, not an Apple clone

## Current Progress Summary

- `DS1`: complete
- `DS2`: complete
- `DS3`: complete
- `DS4`: started
- `DS5`: active via `Phase DP0` planning and review-lock work

What is already true in code:

- runtime contracts are split from shared visual foundations
- `AppUIConstants` is now a transitional facade instead of the primary value owner
- capture shell chrome, stack notification chrome, copied-stack recipe, and stack backdrop defaults now live in owner files
- a shared top-edge highlight helper and shared notification-card chrome helper are now reused where duplication was already real

## Immediate Next Step

The next step is not a large refactor.

It is:

1. expand `Phase DS4` only where reuse is already proven
2. enter `Phase DS5` through the bounded capture/stack polish plan
3. keep feature-specific surfaces specialized while removing only genuinely duplicated shared chrome
4. split value ownership without touching runtime-critical behavior

That gives future design-system cleanup a safe foundation.
