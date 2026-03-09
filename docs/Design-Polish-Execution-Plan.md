# Backtick Design Polish Execution Plan

## Purpose

This document defines the next bounded UI-polish lane for Backtick.

The goal is not generic cleanup.
The goal is to finish the visual layer that sits on top of the now-stable design-system structure.

This plan exists because UI polish is high-risk when it is driven by ad hoc tweaks.
Backtick now has enough structure to enforce ownership, but the remaining work still needs explicit review checkpoints so the app does not drift away from:

1. native macOS feel
2. Backtick-specific identity
3. token-driven implementation
4. reusable components where reuse is real

## Scope

This plan covers only:

- capture shell elevation and surface polish
- stack card brightness and surface polish
- light/dark semantic token expansion for those surfaces
- review gates for visual work

This plan does not cover:

- capture runtime sizing behavior
- stack behavior / interaction changes
- long-card overflow behavior
- settings rework
- generic component-library expansion

## Current Diagnosis

### 1. Capture Shell Does Not Separate Enough From The Workspace

Symptoms:

- the capture surface shadow is too weak
- the shell can read like a tinted slab rather than a floating input layer
- light and dark mode do not feel equally intentional

Current owners:

- runtime capture shell:
  - [CapturePanelRuntimeViewController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift)
- SwiftUI capture shell recipe:
  - [SearchFieldSurface.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/SearchFieldSurface.swift)
  - [CaptureShellChromeRecipe.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/CaptureShellChromeRecipe.swift)
- shared shadow composition:
  - [PromptCueShadowModifiers.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/PromptCueShadowModifiers.swift)
- shared semantic roles:
  - [SemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/SemanticTokens.swift)

Root cause:

- the shipping capture shell is still styled in the AppKit runtime path, while the SwiftUI shell recipe also exists as a pattern layer
- capture shell recipe and capture shadow recipe are structurally separated, but the semantic roles for shell fill, highlight, border, and shadow are still too coarse for final tuning
- current shadow composition favors safety over clear elevation
- until the live runtime shell styling is extracted into an owner recipe, capture polish must be treated as a master-owned slice

### 2. Stack Cards Read Too Dim Or Too Flat

Symptoms:

- cards need to be brighter without turning into white sheets
- stack card separation from the backdrop is still too dependent on ad hoc tuning
- hover/focus states recover readability, but idle cards can still feel muted too early

Current owners:

- [StackNotificationCardSurface.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackNotificationCardSurface.swift)
- [StackNotificationCardChromeRecipe.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackNotificationCardChromeRecipe.swift)
- [CopiedStackRecipe.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/CopiedStackRecipe.swift)
- [SemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/SemanticTokens.swift)

Root cause:

- current notification-card semantic roles are intentionally conservative and stable, but still not split finely enough for final brightness/contrast tuning
- stack-card fill, backdrop, hover, and copied-stack depth do not yet have a dedicated final polish lane

### 3. Theme Awareness Is Structurally Present But Not Yet Fine-Grained

Symptoms:

- light mode and dark mode still require hand-tuned visual interpretation
- capture shell and stack card surfaces do not yet expose all the semantic knobs needed for final mode-specific polish

Current owners:

- [SemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/SemanticTokens.swift)
- [PrimitiveTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/PrimitiveTokens.swift)

Root cause:

- current token system is good enough for structure and regression prevention
- current token system is not yet fine-grained enough for final visual polish across both appearance modes

## Guardrails

### Guardrail 1: Runtime Ownership Is Out Of Scope

Do not use this polish lane to reopen runtime behavior or AppKit sizing.

These remain runtime-owned:

- [CaptureEditorRuntimeHostView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CaptureEditorRuntimeHostView.swift)
- [CapturePanelRuntimeViewController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift)
- [VisualEffectBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/VisualEffectBackdrop.swift)
- [AppUIConstants.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/App/AppUIConstants.swift)

Important nuance:

- the live capture shell styling currently still lives in the runtime host
- therefore `capture shell visual extraction` is allowed in this lane, but `capture sizing and editor behavior` are not

### Guardrail 2: Pattern Surfaces Stay Specialized

Do not collapse capture shell, stack backdrop, and stack notification cards into a generic shared card abstraction.

These remain pattern-owned:

- [SearchFieldSurface.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/SearchFieldSurface.swift)
- [StackNotificationCardSurface.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackNotificationCardSurface.swift)
- [StackPanelBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackPanelBackdrop.swift)

### Guardrail 3: No Inline Drift

This lane may not introduce:

- local `Color(nsColor: ...)` in feature views
- local one-off shadow values in feature views
- local one-off spacing or radius values in feature views

If a value changes twice, it must be owned either by:

- a semantic token, or
- a pattern recipe file

### Guardrail 4: Visual Review Is Mandatory

No polish slice is complete without explicit review artifacts for both:

- light mode
- dark mode

## Review Packet Requirements

Each design-polish slice must produce:

1. before/after screenshots for light mode
2. before/after screenshots for dark mode
3. one short note explaining what changed visually
4. one short note explaining what layer owned the change:
   - semantic token
   - pattern recipe
   - reusable surface

Required screens:

- empty capture shell
- active capture shell with one line of text
- stack with mixed active cards
- stack with copied collapsed state
- stack hover state on one card

## Ownership Model

### Master-Owned

- [SemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/SemanticTokens.swift)
- [PrimitiveTokens.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/PrimitiveTokens.swift)
- [PromptCueShadowModifiers.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/DesignSystem/PromptCueShadowModifiers.swift)
- [CapturePanelRuntimeViewController.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift) while live shell styling is still local to the runtime host
- this document
- planning and board docs

Reason:

- these files affect multiple surfaces and can create cross-pattern regressions

### Track A: Capture Polish

Owned files:

- [SearchFieldSurface.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/SearchFieldSurface.swift)
- [CaptureShellChromeRecipe.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/CaptureShellChromeRecipe.swift)

Goal:

- make capture read as a clearly elevated, native, quiet input shell

Restriction:

- Track A may not change runtime sizing, input metrics, or panel geometry
- if live capture shell extraction from the runtime host is required, master lands that contract first

### Track B: Stack Surface Polish

Owned files:

- [StackNotificationCardSurface.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackNotificationCardSurface.swift)
- [StackNotificationCardChromeRecipe.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackNotificationCardChromeRecipe.swift)
- [CopiedStackRecipe.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/CopiedStackRecipe.swift)
- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Views/CardStackView.swift)

Goal:

- brighten and clarify cards without flattening Backtick into a generic note list

### Track C: Backdrop Polish

Owned files:

- [StackPanelBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackPanelBackdrop.swift)
- [StackPanelBackdropRecipe.swift](/Users/ilwonyoon/Documents/PromptCue/PromptCue/UI/Components/StackPanelBackdropRecipe.swift)

Goal:

- keep backdrop atmospheric and unobtrusive while protecting card readability

## Phases

### Phase DP0: Review Lock

Goal:

- freeze polish targets and review gates before visual work starts

Tasks:

1. record diagnosis in docs
2. define ownership boundaries
3. define required screenshot review packet
4. define out-of-scope areas

Exit criteria:

- no polish work starts from ad hoc local preference only

### Phase DP1: Capture Elevation Pass

Goal:

- strengthen capture-shell elevation and shell readability

Tasks:

1. extract live capture shell appearance values from the runtime host into an explicit owner recipe if needed
2. tune capture shell fill and sheen recipe
3. tune capture border/highlight recipe
4. increase shadow clarity without making the shell loud
5. verify capture remains native in both appearance modes

Exit criteria:

- capture shell is clearly separated from the workspace
- light and dark mode both feel intentional
- live runtime shell and pattern recipe no longer drift apart

Current status:

- in progress
- semantic shadow roles and runtime shell fill/border roles are now being moved into shared owners
- final review packet still pending

### Phase DP2: Stack Card Brightness Pass

Goal:

- brighten stack cards and improve scanability

Tasks:

1. lift notification-card fill one controlled step
2. retune hover and selected emphasis so they still read above the brighter base
3. keep copied stack plates quieter than the front card
4. preserve icon/readability hierarchy

Exit criteria:

- active cards are easier to scan in both modes
- copied states still read as secondary depth

Current status:

- in progress
- stack-card brightness and copied-stack quieting are now being tuned through stack-owned recipe files
- final review packet still pending

### Phase DP3: Theme Token Split

Goal:

- expose the semantic roles needed for final mode-specific polish

Tasks:

1. split semantic roles for:
   - capture shell fill
   - capture shell border
   - capture shell highlight
   - capture shell shadow
   - stack card fill
   - stack card hover
   - stack card border
   - copied stack plate tones
2. keep primitive tokens stable unless a true scale issue is found
3. keep runtime-owned values out of token migration

Exit criteria:

- light and dark polish no longer depend on local view math

### Phase DP4: Backdrop And Review Pass

Goal:

- tune backdrop/card relationship and lock the final visual result through review

Tasks:

1. tune backdrop density only after card brightness is stable
2. confirm backdrop does not become the subject
3. produce final review packet for light/dark
4. reject any slice that fixes one mode by breaking the other

Exit criteria:

- backdrop supports readability without feeling like a panel slab
- review packet is complete and approved

## Validation Gates

### Gate A: Build Gate

- `python3 scripts/validate_ui_tokens.py --all`
- `swift test`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

### Gate B: Visual Regression Gate

Required per slice:

- before/after screenshots in light and dark mode
- no capture runtime sizing regressions
- no stack interaction regressions
- no backdrop/card recoupling

### Gate C: Review Gate

Required before moving to the next phase:

- review packet shared
- changed layer explicitly identified
- master sign-off that the slice did not drift out of scope

## Immediate Next Step

The next step is:

1. complete `Phase DP0`
2. open `Track A` and `Track B` in parallel
3. keep token changes master-owned
4. defer backdrop fine-tuning until after capture and card surfaces stabilize

That sequence keeps the visual work reviewable and stops the app from drifting through uncontrolled polish.
