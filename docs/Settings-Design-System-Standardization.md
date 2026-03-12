# Backtick Settings Design System Standardization

## Purpose

This document defines how Backtick should build and maintain its macOS Settings UI without repeated screenshot-matching churn.

The goal is not to hand-tune every Settings page until it "looks Apple enough". The goal is to:

1. adopt native macOS settings structure
2. standardize a small Settings-specific token and component layer
3. stop page-local styling from drifting over time
4. make future Settings work compositional instead of bespoke

This is written against current `main` and the current local toolchain:

- `Xcode 16.2`
- `macOS SDK 15.2`

## Executive Conclusion

Yes, spending time on this will fix the current churn problem, but only if Backtick stops treating Settings as a screenshot-matching exercise.

The current failure mode is structural:

- shared design tokens are product-oriented, not Settings-oriented
- Settings styles are recreated privately inside one view file
- Connectors built a second mini design system inside the page
- page layout is mostly hand-built instead of thin wrappers over native macOS settings patterns

If Backtick creates a dedicated Settings lane with:

- native shell primitives
- Settings-specific semantic tokens
- reusable Settings row/group/sidebar components
- a small verification playbook

then future Settings work should stop devolving into repeated spacing, weight, divider, and icon debates.

If Backtick keeps styling each page directly inside `PromptCueSettingsView.swift`, the churn will continue.

## Compactness Standard

Backtick Settings should bias toward compact density by default.

That means:

- smaller shell before smaller text
- narrower content measure before arbitrary horizontal stretching
- one section description above a group instead of helper text repeated below rows
- one compact row grammar for short controls
- full-width blocks only for long editors, previews, or richer setup states

Compactness should be controlled through Settings tokens and shared primitives, not one-off local padding changes.

## Official Apple Direction

Apple's current public guidance points in one direction consistently:

- use platform-native navigation, windows, controls, and iconography
- use Apple design resources as reference material, not as a mandate to hardcode screenshot colors
- let system materials and semantic colors do most of the work
- use SF Symbols and standard control grammars instead of bespoke chrome

Relevant official sources:

- Apple Human Interface Guidelines: macOS overview
  - <https://developer.apple.com/design/human-interface-guidelines/designing-for-macos>
- Apple Human Interface Guidelines: SF Symbols
  - <https://developer.apple.com/design/human-interface-guidelines/sf-symbols>
- Apple Design Resources
  - <https://developer.apple.com/design/resources/>
- SwiftUI `NavigationSplitView`
  - <https://developer.apple.com/documentation/swiftui/navigationsplitview>
- SwiftUI `Form`
  - <https://developer.apple.com/documentation/swiftui/form>
- SwiftUI `LabeledContent`
  - <https://developer.apple.com/documentation/swiftui/labeledcontent>
- Technote TN3154: Adopting SwiftUI navigation split view
  - <https://developer.apple.com/documentation/technotes/tn3154-adopting-swiftui-navigation-split-view>
- AppKit window customization
  - <https://developer.apple.com/documentation/appkit/customizing-window-styles-and-state-restoration-behaviors-in-macos>
- Latest Apple direction for Liquid Glass
  - <https://developer.apple.com/documentation/technologyoverviews/liquid-glass>
  - <https://developer.apple.com/videos/play/wwdc2026/278/>
  - <https://developer.apple.com/videos/play/wwdc2026/317/>

Backtick-specific visual reference analysis:

- [macOS-Settings-Reference-Analysis.md](/Users/ilwonyoon/Documents/PromptCue/docs/macOS-Settings-Reference-Analysis.md)

### Important tooling note

Latest Apple documentation now describes Liquid Glass APIs and behaviors in the newest platform generation.

Backtick cannot treat those as current implementation requirements yet because the local toolchain in this repo is still:

- `Xcode 16.2`
- `macOS SDK 15.2`

That means the correct implementation strategy today is:

- use native AppKit and SwiftUI shells, controls, and semantic colors
- avoid fake Liquid Glass cloning from screenshots
- revisit native glass APIs only after the project upgrades to the newer SDK that actually exposes them

## Current Root Problem

The Settings UI is drifting because it has no authoritative Settings-specific system.

### Evidence in current code

1. Shared tokens are generic, not Settings-specific.

- `PromptCue/UI/DesignSystem/PrimitiveTokens.swift`
- `PromptCue/UI/DesignSystem/SemanticTokens.swift`

These files define global typography, spacing, surfaces, shadows, and capture/stack-oriented recipes. They do not define a Settings shell, sidebar, section, form row, or inline help model.

2. Settings created a second private token system inside the page.

- `PromptCue/UI/Settings/PromptCueSettingsView.swift`

This file currently hardcodes:

- sidebar row heights
- icon sizes
- row heights
- label fonts
- supporting fonts
- section radii
- settings background colors
- divider colors

3. Shell rules are split across multiple files.

- `PromptCue/App/PanelMetrics.swift`
- `PromptCue/UI/WindowControllers/SettingsWindowController.swift`
- `PromptCue/UI/Settings/PromptCueSettingsView.swift`

This means Settings has no single contract for:

- window geometry
- sidebar width
- titlebar behavior
- row density
- content inset

4. Connectors introduced a second layout grammar.

- general/capture/stack use one `settingsFormRow`-style layout
- connectors uses its own row/card/inline-panel/sheet structures

That split is the direct reason one page often looks coherent while the others look off.

5. Settings is borrowing product chrome it should not borrow.

The repository's own design-system proposal already states the correct rule:

> Settings should not reuse stack/capture chrome.

Source:

- `docs/Design-System-Architecture-Proposal.md`

This rule is right. The implementation is not enforcing it hard enough.

## Reference Analysis

Use this document together with the screenshot-derived archetype analysis:

- [macOS-Settings-Reference-Analysis.md](/Users/ilwonyoon/Documents/PromptCue/docs/macOS-Settings-Reference-Analysis.md)

That reference analysis is the source for:

- page archetype classification
- spacing and alignment heuristics
- foundation token targets
- the current Backtick gap against the macOS reference set

## What Backtick Should Standardize

Backtick should create a dedicated Settings design-system lane made of four layers.

### 1. Native platform primitives

These should come from AppKit/SwiftUI first, not from custom hex values:

- `NSColor.labelColor`
- `NSColor.secondaryLabelColor`
- `NSColor.tertiaryLabelColor`
- `NSColor.separatorColor`
- `NSColor.windowBackgroundColor`
- `NSColor.controlBackgroundColor`
- `NSColor.selectedContentBackgroundColor`
- system SF Pro fonts
- system controls:
  - `Toggle`
  - `Picker`
  - `TextField`
  - `Button`
  - `List`
  - `NavigationSplitView`
  - `Form`
  - `LabeledContent`

### 2. Settings-specific semantic tokens

Backtick should add a dedicated namespace, for example:

- `SettingsTokens`
- `SettingsSemanticTokens`

These should contain only values that stay stable across Settings pages.

Recommended ownership:

- geometry
  - sidebar width
  - page content inset
  - group radius
  - row min height
  - label column width
  - icon tile size
  - icon/text gap
- typography roles
  - page title
  - sidebar label
  - row label
  - helper/footer text
  - inline mono/code text
- settings semantic surfaces
  - sidebar background
  - content background
  - grouped surface fill
  - row separator
  - inline inset panel

These should not live as private computed properties inside `PromptCueSettingsView.swift`.

### 3. Settings components

Backtick should extract reusable Settings components outside the page file.

Minimum set:

- `SettingsWindowShell`
- `SettingsSidebar`
- `SettingsSidebarItem`
- `SettingsPage`
- `SettingsSection`
- `SettingsFormGroup`
- `SettingsRow`
- `SettingsTwoColumnGroupRow`
- `SettingsInlinePanel`
- `SettingsActionBar`
- `SettingsNotice`

Rules:

- each component should own one layout grammar only
- dividers should be parent-managed, not reimplemented by each page
- row labels and controls should align through one shared primitive
- if a grouped section uses a 2-column label/content layout, the label rail must be defined once per group and reused by every row and long-form block inside that group
- Connectors must compose the same primitives instead of inventing its own parallel row system

### 4. Page patterns

These are the patterns Backtick should allow in Settings:

1. Sidebar navigation
2. Page title
3. Section header + short footer
4. Grouped settings rows
5. Shared 2-column group rows for hybrid settings boxes
6. Inline inset panel for advanced/manual/config detail
7. Destructive or recovery notice only when needed

### Box Archetype Catalog

Backtick should only use these box archetypes in Settings:

- `Simple Trailing-Control Group`
  - label left, value/control right
  - no long-form content
- `Detail Group`
  - label left, detail value or short explanatory copy on the content rail
  - optional compact trailing action/status
- `Long-Form Exception Group`
  - one shared 2-column rail
  - one or more short rows plus editor/preview blocks
- `Workflow / Status Group`
  - richer state summary, CTA, and inline repair/setup content
  - currently the right target for `Connectors`

### Alignment Contract

Every grouped Settings box must follow these rules:

1. one left rail for labels
2. one content rail for values or long-form content
3. one right rail for trailing controls or accessories
4. one divider owner per group

If a grouped section uses 2 columns, that rail is defined once per group and reused by every row and long-form block inside it.

These are the patterns Backtick should avoid:

- stack-style cards
- capture-style glass surfaces
- decorative background gradients
- repeated helper copy
- page-local divider math
- page-local type scales
- screenshot-matched hardcoded colors as primary implementation tokens

## Recommended Baseline Tokens

These values are the right starting point for Backtick's Settings lane.

They come from a mix of:

- native AppKit defaults measured locally on the current toolchain
- Apple reference materials
- already-proven current layout choices in the repo

### Typography

Use these as Settings roles:

- page title: `15pt semibold`
- sidebar label: `13pt medium`
- settings row label: `13pt medium`
- supporting/helper/footer text: `11pt regular`
- supporting emphasis: `11pt semibold`
- code/config text: `11pt monospaced`

Why:

- local AppKit defaults on this machine show:
  - `NSFont.systemFontSize = 13`
  - `NSFont.smallSystemFontSize = 11`
- these align with Apple's current Settings and form density better than the product-wide `15/13/11` scale being applied ad hoc

### Spacing and geometry

Recommended Settings defaults:

- sidebar width: `240`
- content outer inset: `20`
- sidebar tile size: `24`
- sidebar icon/text gap: `4`
- sidebar item spacing: `8`
- grouped surface radius: `12`
- inline field radius: `10`
- form row min height: `44`
- label column width: `180...190`
- section gap: `20`

These should be centralized and never page-owned.

### Colors

Implementation rule:

- prefer system semantic colors first
- use hardcoded snapshot values only as visual audit references, not as primary tokens

Recommended implementation palette:

- primary text: `NSColor.labelColor`
- secondary text: `NSColor.secondaryLabelColor`
- tertiary text: `NSColor.tertiaryLabelColor`
- row separator: `NSColor.separatorColor`
- selection: `NSColor.selectedContentBackgroundColor`
- field/group surfaces: derive from `windowBackgroundColor`, `controlBackgroundColor`, and very low-alpha overlays

Observed local semantic values on `macOS 15.2`:

Light:

- `labelColor`: `rgba(0, 0, 0, 0.847)`
- `secondaryLabelColor`: `rgba(0, 0, 0, 0.498)`
- `tertiaryLabelColor`: `rgba(0, 0, 0, 0.259)`
- `separatorColor`: `rgba(0, 0, 0, 0.098)`
- `selectedContentBackgroundColor`: `rgba(0, 100, 225, 1.0)`

Dark:

- `labelColor`: `rgba(255, 255, 255, 0.847)`
- `secondaryLabelColor`: `rgba(255, 255, 255, 0.549)`
- `tertiaryLabelColor`: `rgba(255, 255, 255, 0.247)`
- `separatorColor`: `rgba(255, 255, 255, 0.098)`
- `selectedContentBackgroundColor`: `rgba(0, 89, 209, 1.0)`

### Icons

Sidebar icon rules:

- use SF Symbols, not product logos
- icon tile size: `24`
- keep one symbol weight per lane
- keep one corner radius per tile
- do not mix filled brand badges with system sidebar items

Connectors client logos are allowed in content rows because they represent external tools, not Settings navigation.

## Latest Apple Direction vs. Current Local Reality

Backtick should separate these two questions:

1. What is the latest Apple design direction?
2. What can this repo implement correctly today?

### Latest Apple direction

Apple is moving more UI chrome toward Liquid Glass and automatic material adaptation in the latest generation.

That matters strategically because it reinforces the same architectural conclusion:

- use standard containers and controls
- do not hardcode the shell visually
- let the system own more of the polish

### Current local reality

This repo is not on the newest SDK yet.

Therefore:

- do not fake Liquid Glass by cloning screenshots
- do not freeze Apple screenshot hex values into product tokens
- do not build a custom glass recipe just for Settings

Instead:

- keep the Settings shell native and restrained now
- upgrade to newer APIs later in one bounded pass

## Implementation Standard for Backtick

Backtick should adopt these rules immediately.

### Rule 1: Settings gets its own semantic lane

Create:

- `PromptCue/UI/Settings/SettingsTokens.swift`
- `PromptCue/UI/Settings/SettingsSemanticTokens.swift`
- `PromptCue/UI/Settings/Components/**`

Do not continue adding settings colors and sizes as private properties inside `PromptCueSettingsView.swift`.

### Rule 2: Settings must be composed from shared Settings primitives

Every page should be built only from:

- `SettingsPage`
- `SettingsSection`
- `SettingsFormGroup`
- `SettingsRow`
- `SettingsInlinePanel`

No page should introduce its own row/divider/card grammar.

### Rule 3: Connectors must stop being a mini design system

Connectors can have richer states, but they still need to use the same shell and row primitives.

Allowed customizations:

- client logo in content row
- connection status dot
- inline setup panel
- error notice

Not allowed:

- custom card family unrelated to other settings pages
- separate divider logic
- separate typography scale
- separate modal shell recipe

### Rule 4: Settings pages should prefer native control composition

Preferred structure:

- `NavigationSplitView` or equivalent split-shell contract
- sidebar list
- grouped content built from `Form` and `LabeledContent`-like row behavior
- native `Toggle`, `Picker`, `Button`, `TextField`, `ScrollView`

The more layout math Backtick writes by hand, the more drift it invites.

### Rule 5: Apple references are audit material, not implementation tokens

Use Apple screenshots, Figma kits, and design resources for:

- proportions
- icon grammar
- hierarchy
- control density
- sidebar/content relationship

Do not use them to justify:

- freezing OS screenshot hex values as canonical product colors
- cloning exact shadow recipes
- recreating whole shells manually when native controls already exist

## What To Change In The Current Codebase

### Current problems to remove

- private Settings token layer in `PromptCueSettingsView.swift`
- duplicated inset panel patterns
- duplicated group/card patterns
- page-specific divider math
- shell geometry split across too many files
- connectors-specific modal and row grammar

### Minimum extraction plan

1. Add `SettingsTokens.swift`
2. Add `SettingsSemanticTokens.swift`
3. Extract:
   - `SettingsSidebarItem`
   - `SettingsSection`
   - `SettingsFormGroup`
   - `SettingsRow`
   - `SettingsInlinePanel`
4. Refactor `General`, `Capture`, `Stack`, and `Connectors` onto those primitives
5. Delete the page-local styling branches that become dead after extraction

## Verification Playbook

To stop future churn, Backtick should verify Settings changes in a fixed order.

### 1. Structural review

Before polishing:

- is this page built from shared Settings primitives only?
- did it introduce a new private color/spacing/font rule?
- did it reuse stack/capture chrome?

If yes, stop and extract first.

### 2. Visual review

Review against Apple references for:

- sidebar density
- icon slot consistency
- title and helper hierarchy
- divider placement
- row alignment
- control sizing

### 3. Theme review

Check both light and dark mode for:

- text contrast
- separator visibility
- inline panel contrast
- selection color behavior

### 4. Runtime review

For UI changes that touch the app:

- `xcodegen generate`
- `swift test`
- `xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug CODE_SIGNING_ALLOWED=NO build`

## Recommended Near-Term Roadmap

### Phase S1: Freeze Settings tokens and components

Outcome:

- one Settings token file
- one Settings semantic file
- one Settings components folder

### Phase S2: Migrate all four current tabs

Outcome:

- `General`, `Capture`, `Stack`, and `Connectors` all share one layout grammar

### Phase S3: Add preview and review tooling

Outcome:

- side-by-side previews for:
  - light/dark
  - long/short helper text
  - empty/error/connected connector states

### Phase S4: Revisit latest Apple glass APIs after toolchain upgrade

Only after the repo upgrades to the newer SDK:

- reassess whether the settings shell should adopt native glass APIs
- remove temporary fallback recipes only if the new APIs improve the result

## Bottom Line

The issue is not that Backtick lacks enough screenshots.

The issue is that Backtick has no authoritative Settings system, so every Settings pass re-litigates:

- fonts
- spacing
- divider behavior
- sidebar density
- icon treatment
- inline panel styling

This is fixable.

It becomes fixable when Backtick decides that:

- Apple references are audit material
- native platform controls are the implementation baseline
- Settings gets its own semantic/token/component lane
- page-local styling is no longer allowed

If Backtick follows that rule, future Settings work should become routine.

If Backtick keeps editing `PromptCueSettingsView.swift` as a one-file custom design canvas, the churn will continue no matter how many Apple references are collected.
