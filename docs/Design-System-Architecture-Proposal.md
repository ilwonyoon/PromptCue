# Backtick Design System Architecture Proposal

## Purpose

This proposal defines how Backtick's design system should evolve from the current implementation without regressing the app's runtime behavior.

The goal is not to genericize everything. The goal is to make the system:

1. native to macOS
2. specific to Backtick
3. hostile to uncontrolled hardcoding
4. reusable where reuse is real

This proposal is written against the current `main` architecture, not against an abstract greenfield system.

## Design Goals

Backtick should feel like:

- a native macOS utility
- a fast scratch surface for AI coding
- a staging layer between thoughts and execution

Backtick should not feel like:

- a note app
- a document editor
- a generic design-system demo
- a fully bespoke visual toy detached from macOS conventions

The app should preserve:

- macOS-native materials, typography, focus, and windowing
- Backtick-specific capture and stack patterns
- AppKit ownership where native behavior matters
- design-token discipline where values are stable and shared

## Current Structure

The current codebase already has a usable design-system foundation, but it is not one flat hierarchy. It is closer to five layers.

### 1. Foundations

Raw scales and primitives:

- [PrimitiveTokens.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/DesignSystem/PrimitiveTokens.swift)

This file currently holds:

- typography scale
- spacing scale
- radii
- component sizes
- shadow magnitudes
- motion constants

### 2. Semantic Roles

Meaningful visual roles:

- [SemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/DesignSystem/SemanticTokens.swift)

This file currently holds:

- fills
- borders
- text roles
- accent roles
- material choices
- shared shadow colors

### 3. Native Runtime Bridges

Bridges that adapt AppKit behavior into Backtick:

- [VisualEffectBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/VisualEffectBackdrop.swift)
- [CaptureEditorRuntimeHostView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Capture/CaptureEditorRuntimeHostView.swift)
- [CapturePanelRuntimeViewController.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift)
- [CueTextEditor.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/CueTextEditor.swift)

These are not pure design-system components. They are runtime infrastructure.

### 4. Reusable Surfaces And Controls

Reusable visual building blocks:

- [GlassPanel.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/GlassPanel.swift)
- [CardSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/CardSurface.swift)
- [PromptCueChip.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/PromptCueChip.swift)
- [PanelHeader.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/PanelHeader.swift)

### 5. Backtick-Specific Patterns

Product-specific surfaces that should stay specialized:

- [SearchFieldSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/SearchFieldSurface.swift)
- [StackNotificationCardSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackNotificationCardSurface.swift)
- [StackPanelBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackPanelBackdrop.swift)
- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Views/CaptureCardView.swift)
- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Views/CardStackView.swift)

These are not generic library parts. They encode product behavior and product taste.

## Root Diagnosis

The current design-system discussion gets unstable whenever one of these boundaries is crossed by accident.

### 1. Genericization is being attempted at the wrong layer

The design system is healthiest at the `primitive -> semantic -> reusable surface` layers.

The largest regressions have happened when we tried to flatten `runtime bridges` or `Backtick-specific patterns` into the same abstraction level.

Examples:

- stack backdrop changes accidentally changed card appearance
- capture input styling changes accidentally changed runtime geometry
- light/dark backdrop work accidentally redefined stack card chrome

### 2. `AppUIConstants` is a mixed contract layer, not a token file

- [AppUIConstants.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/App/AppUIConstants.swift)

This file mixes:

- stable visual geometry
- panel dimensions
- editor runtime thresholds
- timing constants
- screenshot-related timeouts

Treating all of it as “token debt” would be wrong. Some of it is live runtime behavior.

### 3. Not all hardcoded values are equally bad

There are three different categories:

1. `bad hardcoding`
   - inline values scattered in feature views
   - untracked opacity math duplicated across files
   - one-off corner radius and shadow values
2. `acceptable ownership-local values`
   - recipe values inside one dedicated surface component
   - values that only define one product-specific pattern
3. `runtime constants`
   - measurement thresholds
   - scroll indicator timing
   - panel flush timeouts

The current architecture needs to eliminate category 1 first.

### 4. The design system currently lacks a formal pattern layer

The current implementation has one in practice, but not in name.

That is why generic components and specialized Backtick patterns keep getting conflated.

## macOS Guidance That Matters Here

The most relevant Apple guidance is architectural more than visual.

From Apple's Mac app documentation and platform conventions:

- Cocoa apps should build on the standard conventions and infrastructure provided by AppKit rather than reimplementing core behavior. [Core App Design](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/CoreAppDesign/CoreAppDesign.html)
- Single-window utility-style apps are a preferred shape for streamlined Mac experiences when the app is not document-heavy. [Core App Design](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/CoreAppDesign/CoreAppDesign.html)
- Windows and views should let the system event, layout, and responder infrastructure do the primary work. [Core App Design](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/CoreAppDesign/CoreAppDesign.html)
- Preferences should stay simple and use the system preference model and defaults storage rather than inventing exotic settings infrastructure. [Preferences and Settings Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/Introduction/Introduction.html)
- Apple explicitly recommends data-driven designs instead of hard-coding app behavior throughout source. [Application Development Overview](https://developer.apple.com/library/archive/documentation/General/Conceptual/ApplicationDevelopmentOverview/DevelopYourApplication/DevelopYourApplication.html)

Practical implications for Backtick:

1. Use native materials through AppKit bridges instead of simulating blur in pure SwiftUI.
2. Let AppKit own the multiline text system and input behavior.
3. Keep utility-app surfaces quiet, compact, and standard in behavior even when visually customized.
4. Use system defaults/preferences patterns for user settings.
5. Prefer adapting system behaviors instead of overriding them everywhere.

## Proposed Architecture

Backtick should explicitly adopt a five-part design-system architecture.

### Layer A. Foundations

Purpose:

- raw scales only

Contains:

- spacing
- radii
- base typography sizes
- motion durations
- elevation magnitudes
- stable component dimensions

Lives in:

- [PrimitiveTokens.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/DesignSystem/PrimitiveTokens.swift)

Rules:

- no semantic meaning
- no product-specific names
- no runtime logic

### Layer B. Semantics

Purpose:

- map foundations to roles

Contains:

- text roles
- surface roles
- border roles
- material roles
- accent roles
- shared shadow color roles

Lives in:

- [SemanticTokens.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/DesignSystem/SemanticTokens.swift)

Rules:

- should explain meaning, not implementation
- should be theme-aware
- should be reused by both generic and product-specific surfaces

### Layer C. Runtime Contracts

Purpose:

- own native behavior that cannot safely be collapsed into static tokens

Contains:

- AppKit text system behavior
- NSVisualEffectView bridging
- panel geometry resolution
- live editor sizing ownership
- scroll-indicator runtime behavior

Lives in:

- [VisualEffectBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/VisualEffectBackdrop.swift)
- [CaptureEditorRuntimeHostView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Capture/CaptureEditorRuntimeHostView.swift)
- [CapturePanelRuntimeViewController.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift)
- [AppUIConstants.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/App/AppUIConstants.swift)

Rules:

- these files may own values that are not yet promotable to tokens
- no feature view should replicate their geometry logic
- values here should become structured contracts, not ad hoc literals

### Layer D. Reusable Components

Purpose:

- supply stable building blocks used across more than one feature

Contains:

- shells
- chips
- generic cards
- headers
- accessory controls

Lives in:

- [GlassPanel.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/GlassPanel.swift)
- [CardSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/CardSurface.swift)
- [PromptCueChip.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/PromptCueChip.swift)
- [PanelHeader.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/PanelHeader.swift)

Rules:

- only extract reuse that already exists
- do not force Backtick-specific patterns into generic surfaces

### Layer E. Backtick Patterns

Purpose:

- encode the product's distinct capture and stack feel

Contains:

- capture lane shell
- stack card shell
- stack atmospheric backdrop
- copied stack visualization
- settings pane layout pattern

Lives in:

- [SearchFieldSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/SearchFieldSurface.swift)
- [StackNotificationCardSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackNotificationCardSurface.swift)
- [StackPanelBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackPanelBackdrop.swift)
- [CaptureCardView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Views/CaptureCardView.swift)
- [CardStackView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Views/CardStackView.swift)
- [PromptCueSettingsView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Settings/PromptCueSettingsView.swift)

Rules:

- pattern code is allowed to be product-specific
- patterns may consume semantics plus local recipe contracts
- patterns should not own raw literals in feature views

## Responsibility Boundaries

These boundaries should be made explicit and preserved.

### Stack Background

Owner:

- [StackPanelBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackPanelBackdrop.swift)

Allowed to own:

- blur recipe
- gradient density
- edge fade behavior
- theme-aware atmosphere recipe

Must not own:

- stack card fill
- stack card text colors
- card spacing or copy action state

### Stack Card Surface

Owner:

- [StackNotificationCardSurface.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackNotificationCardSurface.swift)

Allowed to own:

- card-specific fill and chrome recipe
- top highlight
- hover emphasis behavior

Must not own:

- backdrop recipe
- copied-stack plate offsets
- stack section ordering logic

### Capture Runtime Geometry

Owner:

- [CaptureEditorRuntimeHostView.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Capture/CaptureEditorRuntimeHostView.swift)
- [CapturePanelRuntimeViewController.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Capture/CapturePanelRuntimeViewController.swift)

Allowed to own:

- measured content height
- visible editor height
- scroll state
- placeholder ownership
- panel preferred height

Must not be re-tokenized blindly:

- live editor thresholds
- submit-time sizing behavior
- internal scrolling contracts

### App-Level Constants

Owner:

- [AppUIConstants.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/App/AppUIConstants.swift)

Should be split over time into:

1. stable visual constants
2. runtime editor contracts
3. app timing constants

Until then, this file should be treated as a contract file, not a primitive-token file.

## What “No Hardcoding” Should Mean

For Backtick, `no hardcoding` should mean:

- no inline feature-view visual values
- no duplicated numeric styling logic across multiple files
- no hidden secondary token systems created by accident

It should not mean:

- every value must become a global primitive token immediately
- every product-specific recipe must be flattened into a generic component
- runtime geometry must be represented as purely visual tokens

Backtick should use three value lanes:

1. `Foundation tokens`
   - shared, stable, reusable
2. `Pattern recipe values`
   - product-specific but centralized in one owner file
3. `Runtime contracts`
   - live behavior values owned by AppKit/runtime adapters

That is the most realistic way to reduce hardcoding without reintroducing regressions.

## Proposed Improvements

### 1. Formalize the Pattern Layer

Add a documented category in the design system for:

- Backtick capture patterns
- Backtick stack patterns
- Backtick settings patterns

This solves the repeated mistake of forcing stack/capture surfaces into generic components.

### 2. Split `AppUIConstants`

Create three explicit groups over time:

- `PanelMetrics`
- `CaptureRuntimeMetrics`
- `AppTiming`

Not all of these belong in the design system proper.

### 3. Promote repeated visual recipe values into semantic variants, not global primitives

Examples:

- stack card hover chrome
- stack backdrop density variants
- capture shell top highlight recipe

These should become named recipe structs or semantic variants owned by their pattern files.

### 4. Keep AppKit-owned text sizing outside token migration work

The capture editor is a native text system problem, not just a styling problem.

The current AppKit-owned sizing path should be preserved and only cleaned up through runtime contracts, not through broad token migration.

### 5. Use NSVisualEffectView recipes as first-class backdrop contracts

Backdrop experimentation should happen through:

- `material`
- `blendingMode`
- `appearance`
- `density recipe`
- `mask recipe`

These should be centralized in [StackPanelBackdrop.swift](/Users/ilwonyoon/Documents/PromptCue-design-system-strategy/PromptCue/UI/Components/StackPanelBackdrop.swift), not scattered through feature views.

### 6. Reduce overlap between generic cards and stack cards

Short term:

- keep `CardSurface` and `StackNotificationCardSurface` separate

Medium term:

- extract shared `CardChromeRecipe` primitives used by both
- keep final application specialized per surface

### 7. Keep settings native, not system-themed through custom cards

Backtick settings should follow native macOS preference-pane conventions:

- sections
- labels aligned to controls
- short explanatory footers
- defaults-backed controls

Settings should not reuse stack/capture chrome.

## Phase Plan

### Phase DS1: Contract Freeze

Goal:

- document the five-layer architecture and ownership boundaries

Tasks:

- add this proposal
- mark `Pattern` and `Runtime` as explicit lanes in docs
- define the rule for what can and cannot migrate into tokens

### Phase DS2: Split Value Ownership

Goal:

- reduce accidental hardcoding without destabilizing runtime behavior

Tasks:

- split `AppUIConstants` into visual/runtime/timing groups
- move obvious stable visual values into tokens
- keep live editor geometry in runtime contracts

### Phase DS3: Pattern Recipe Cleanup

Goal:

- centralize product-specific visual recipes

Tasks:

- extract stack backdrop recipe contract
- extract stack notification card chrome recipe
- extract capture shell chrome recipe

### Phase DS4: Reusable Surface Rationalization

Goal:

- reduce duplication between generic surfaces without flattening patterns

Tasks:

- define shared card/shell/chip recipe helpers
- keep final surfaces specialized

### Phase DS5: Native macOS Alignment Pass

Goal:

- strengthen macOS-native feel without losing Backtick identity

Tasks:

- audit materials and vibrancy usage
- audit typography against SF/macOS usage
- audit settings and panel behaviors against utility-app expectations
- verify all changes against light and dark mode

## Immediate Recommendation

Do not implement the previous design-system improvement plan as a direct blueprint.

Instead:

1. adopt this architecture as the new boundary map
2. keep stack backdrop, stack cards, and capture runtime sizing as separate owners
3. treat `no hardcoding` as controlled ownership, not maximal abstraction
4. only genericize surfaces after their behavior is proven stable

## Success Criteria

This proposal is successful if:

1. stack background work no longer changes stack card appearance
2. capture styling work no longer destabilizes AppKit sizing behavior
3. feature views stop carrying inline visual literals
4. reusable components become easier to trust
5. Backtick feels more native to macOS without reading as a generic Apple clone
