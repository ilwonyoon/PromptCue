# macOS Settings Reference Analysis

## Purpose

This document classifies the provided macOS System Settings screenshots and extracts the structural foundations Backtick should standardize before further Settings UI work.

The goal is not screenshot matching. The goal is to identify:

- recurring page archetypes
- layout and spacing rules
- typography and alignment roles
- component patterns that repeat across pages
- the minimum foundation layer Backtick should copy

## Reference Set

Screenshots analyzed in-thread:

1. Wi-Fi
2. Bluetooth
3. Accessibility
4. VoiceOver
5. Hover Text
6. Appearance
7. Apple Intelligence & Siri
8. Control Center
9. Desktop & Dock
10. Spotlight
11. Notifications
12. Sound
13. Focus
14. Communication Limits
15. Lock Screen
16. Touch ID & Password
17. Wallet & Apple Pay

## Archetype Clusters

### A. Intro Card + Sectioned Detail Page

Screenshots:

- `1` Wi-Fi
- `2` Bluetooth
- `7` Apple Intelligence & Siri
- `16` Touch ID & Password
- `17` Wallet & Apple Pay

Pattern:

- page title in the toolbar/content header zone
- prominent top intro card with icon, title, short description, and sometimes a trailing toggle or action
- one or more grouped sections below
- often mixes status rows, pickers, toggles, or action rows

Backtick use:

- best fit for `Connectors`
- useful only when the page needs a short explanation before the detailed controls

### B. Intro Card + Category Index Page

Screenshots:

- `3` Accessibility

Pattern:

- intro card at top
- repeated grouped lists of destination rows below
- each row navigates deeper instead of directly editing state
- section headers such as `Vision`, `Hearing`

Backtick use:

- useful if Settings ever gains category hubs or deeper subpages
- not needed for the current 4-tab scope

### C. Simple Leaf Settings Page

Screenshots:

- `4` VoiceOver
- `5` Hover Text
- `13` Focus
- `14` Communication Limits

Pattern:

- compact page title
- either no intro card or one small top card
- small number of grouped blocks
- mostly toggles, radios, or action buttons
- sparse and vertically compact

Backtick use:

- good fit for `Capture`
- useful for smaller slices of `General`

### D. Dense Mixed-Control Form Page

Screenshots:

- `6` Appearance
- `9` Desktop & Dock
- `12` Sound
- `15` Lock Screen

Pattern:

- several grouped cards
- many row types in one page: segmented controls, sliders, pickers, toggles, radio rows
- strong emphasis on alignment and right-side accessory rails
- little decorative framing beyond grouped cards

Backtick use:

- best fit for `General`
- also the right baseline for `Stack`, with a long-form block exception

### E. List-Heavy Configuration Catalog

Screenshots:

- `8` Control Center
- `10` Spotlight
- `11` Notifications

Pattern:

- long grouped lists
- repeated row grammar
- trailing popups, toggles, checkboxes, chevrons, or info buttons
- sometimes includes a short intro card, but the page is dominated by repeated list rows

Backtick use:

- healthy/error connector states should lean toward this pattern
- best model for any repeated settings inventory

### F. Device/Item List Detail Page

Screenshots:

- `1` Wi-Fi
- `2` Bluetooth

Pattern:

- top intro/status card
- multiple grouped lists of discovered or known items
- repeated rows with identity, state, and accessory actions
- the list is the primary content, not the intro card

Backtick use:

- useful sub-pattern for `Connectors`
- especially useful once connected clients show tools, errors, or re-verify actions

## Shell Rules

### Window Shell

Observed pattern:

- dark mode shell is split into a left sidebar and right content pane
- sidebar and content pane are full-height and meet at a single vertical divider
- titlebar content blends into the same shell instead of creating a third visual band
- content is not centered on a huge canvas; it lives in a constrained reading column

Implication for Backtick:

- treat Settings as a true `2-column shell`, not `titlebar + sidebar + content`
- the left and right panes must fill the full window height
- avoid a large floating content area with arbitrary outer margins

### Content Measure

Observed pattern:

- even on wide windows, groups do not stretch to absurd widths
- most pages keep the main content on a readable vertical rail
- the left edge of page title, section headers, cards, and groups is shared

Implication for Backtick:

- set a stable content max width instead of letting settings rows drift across the whole panel
- align title, section headers, hero cards, and grouped rows on one leading rail

## Sidebar Rules

### Composition

Observed pattern:

- search field at top
- account/family block below search
- dense navigation list below

Backtick does not need search or account chrome immediately, but the actual navigation row language is still important.

### Row Behavior

Observed pattern:

- selection is a compact blue pill with white label and white icon glyph
- unselected rows sit directly on the background, not inside separate cards
- icon tile is small and consistent across all rows
- label is medium weight, not bold
- text and icon are tightly spaced

Approximate reconstruction:

- row height: `30-32pt`
- icon tile: `22-24pt`
- icon/text gap: `4-8pt`
- row gap: `4-6pt`, with slightly larger breaks between special blocks
- corner radius: `8-10pt`

Implication for Backtick:

- keep the selection pill tight and optically dense
- use one sidebar row primitive across all tabs
- do not overpad or use oversized icon tiles
- keep label weight at `medium`, not bold

## Content Rules

### Typography Roles

Approximate roles reconstructed from the screenshots:

- page title: `20-22pt semibold`
- hero card title: `13pt semibold`
- section title: `13pt semibold`
- row title: `13pt regular/medium`
- row secondary/help: `11-12pt regular`
- sidebar label: `13pt medium`
- badge text: `9-10pt bold`

Confidence:

- high for role hierarchy
- medium for exact point sizes

### Grouped Cards

Observed pattern:

- groups are rounded containers with internal row dividers
- rows touch edge-to-edge inside a group
- dividers appear only between sibling rows, never as arbitrary floating lines
- radius is restrained, not pill-like

Approximate reconstruction:

- group radius: `10-12pt`
- row horizontal inset: `12-14pt`
- compact row height: `40-44pt`
- row height with secondary text: `48-56pt`

Implication for Backtick:

- grouped cards should be the default container grammar
- parent group owns the dividers
- rows should not invent their own separator logic

### Alignment

Observed pattern:

- one left rail for page title, section titles, cards, and row content
- one right rail for toggles, popups, chevrons, info buttons, and status controls
- primary and secondary text in rows share the same left alignment
- Apple avoids giant fixed label columns on modern settings pages

Implication for Backtick:

- stop using very wide form label columns
- right-side controls should line up across a group
- rows should adapt to content rather than forcing huge dead space between label and value

## Repeating Component Patterns

### Hero / Intro Card

Seen in:

- `1`, `2`, `3`, `4`, `7`, `10`, `11`, `16`, `17`

Behavior:

- icon at leading edge
- title and short description next to it
- sometimes a trailing toggle or action
- establishes what the page or feature is before detailed settings begin

Backtick use:

- appropriate for `Connectors`
- maybe useful for `Capture` only when it resolves a real permission or status ambiguity
- not necessary for every tab

### Compact Control Row

Seen in:

- `5`, `6`, `9`, `12`, `15`

Behavior:

- left-aligned title
- sometimes one-line secondary text below it
- trailing toggle, picker, segmented control, or chevron
- strong vertical rhythm and tight width discipline

Backtick use:

- default row grammar for `General`, `Capture`, and parts of `Stack`

### Repeated Item List Row

Seen in:

- `1`, `2`, `8`, `10`, `11`

Behavior:

- repeated item rows with consistent accessory placement
- row is identity + state + trailing actions
- list itself carries most of the page density

Backtick use:

- `Connectors` healthy/error rows should follow this more than a custom card workflow layout

### Long-Form Block

Seen indirectly in:

- `12`, `15`, and dense pages where sliders or larger controls require more height

Behavior:

- still contained by the same grouped-card grammar
- but not forced into the exact same height as small settings rows

Backtick use:

- `Stack` editor and preview need this
- they should be full-width blocks, not squeezed into a standard labeled row

## What Apple Repeats Consistently

1. Tight sidebar density.
2. Constrained content measure.
3. Small semibold section headers outside groups.
4. Rounded grouped cards with dividers.
5. One left alignment rail.
6. One right alignment rail.
7. Sparse helper text.
8. Short vertical gaps between title, section header, and card.
9. Compact control rows unless the content genuinely needs extra height.
10. Long-form or media-like content handled as a distinct block, not as a malformed settings row.

## What Apple Avoids

1. Huge floating footers under cards.
2. Oversized titles and section gaps.
3. Very wide label columns that create dead space.
4. Random local spacing changes between pages.
5. Mixing long editors into standard form rows.
6. Repeating the same explanation in section header, row, and footer.
7. Letting accessory controls float without a shared trailing rail.

## Foundation Extraction

These are reconstruction targets, not Apple-official tokens.

### Layout Foundation

- sidebar width: `220-240pt`
- sidebar row height: `30-32pt`
- sidebar icon tile: `22-24pt`
- sidebar icon gap: `4-8pt`
- content inset X: `24-28pt`
- content inset top: `18-24pt`
- content readable measure: `500-560pt`
- section gap: `20-28pt`
- section title to group gap: `8-10pt`
- group radius: `10-12pt`
- row min height: `40-44pt`
- row inset X: `12-14pt`
- row inset Y: `10-12pt`
- trailing rail inset: `12-14pt`

### Typography Foundation

- page title: `20-22pt semibold`
- section title: `13pt semibold`
- row title: `13pt regular/medium`
- row body: `12-13pt regular`
- row secondary: `11-12pt regular`
- sidebar label: `13pt medium`
- badge text: `9-10pt bold`

### Alignment Foundation

- one shared leading rail for title, section header, card, and row content
- one shared trailing rail for control placement
- no giant fixed label column on modern settings pages
- secondary text aligns to the same left edge as the row title
- accessory icons and buttons pack tightly on the trailing edge instead of spreading out

## Current Backtick Gap

Current Backtick settings tokens and components still diverge from the reference in a few high-impact areas.

### Token gaps

| Area | Current | Reference target | Main issue |
| --- | --- | --- | --- |
| `settingsPanelWidth` | `840` | `780-820` | Still a bit wide for a 4-tab app with simpler content |
| `settingsSidebarWidth` | `220` | `220-240` | In range |
| `contentMaxWidth` | `560` | `500-560` | In range, but only works if rows stop using giant label columns |
| `labelColumnWidth` | `168` | `none` or much smaller | Apple avoids a large fixed label rail on modern pages |
| `sidebarIconSize` | `22` | `22-24` | In range |
| `sidebarIconTextSpacing` | `4` | `4-8` | In range |
| `formRowMinHeight` | `40` | `40-44` | In range |
| `groupCornerRadius` | `10` | `10-12` | In range |

### Structural gaps

1. `General`, `Capture`, `Stack`, and `Connectors` still do not fully share one page grammar.
2. `Connectors` remains the most custom page.
3. The remaining fixed label-column behavior still creates more dead space than the reference.
4. Some pages still treat section copy and helper copy as layout filler instead of explicit section metadata.

## Backtick Mapping

### General

Best archetype:

- `D. Dense Mixed-Control Form Page`

Should copy:

- compact grouped rows
- tighter title-to-section rhythm
- no floating footer copy

### Capture

Best archetype:

- `C. Simple Leaf Settings Page`
- with occasional `D` row grammar

Should copy:

- one small set of grouped rows
- status or config rows with short helper text

### Stack

Best archetype:

- `D. Dense Mixed-Control Form Page`
- plus a custom `long-form block` exception

Should copy:

- grouped rows for retention and behavior
- full-width editor and preview blocks below, not squeezed into standard rows

### Connectors

Best archetype:

- hybrid of `A. Intro Card + Sectioned Detail Page` and `E/F. Repeated Item List`

Should copy:

- top summary only when needed
- repeated connector rows with strong trailing CTA or status
- grouped settings language, not a separate workflow-card visual system

## Foundation Elements Backtick Should Extract

### Layout tokens

- sidebar width
- sidebar row height
- sidebar row gap
- sidebar icon tile size
- sidebar icon/text gap
- content top inset
- content horizontal inset
- content max width
- section-to-section gap
- section-title-to-group gap
- row min height
- group radius
- group inner insets
- trailing rail inset

### Typography tokens

- page title
- section title
- row title
- row secondary
- sidebar label
- badge text

### Component patterns

- settings shell
- sidebar row
- intro card
- settings section header
- grouped settings card
- compact settings row
- repeated list row
- long-form block
- trailing action rail

## Highest-Value Conclusion

The screenshots do not show one generic `Settings page`. They show a small set of repeated archetypes.

Backtick should stop tuning each tab separately and instead decide:

- which archetype each tab belongs to
- which row grammar that archetype allows
- which exceptions are valid

If Backtick standardizes those foundations first, spacing and polish become much easier. If it keeps styling each tab page-by-page, the churn will continue.

## Dry-Run Simulation

This section answers a practical question:

Can Backtick validate the plan before fully rebuilding the Settings UI?

Yes.

The correct method is a rule-based dry run:

1. fix the archetype for each Backtick tab
2. compare current tokens against the extracted Apple reference ranges
3. compare each shared component against the structural rules
4. reject changes early when they violate the archetype contract

This is not a screenshot diff. It is a design-system simulation.

### Foundation Fit Matrix

| Foundation rule | Apple reference | Current Backtick | Status | Why |
| --- | --- | --- | --- | --- |
| `pageTitle` | `20-22pt semibold` | `15pt semibold` | `Mismatch` | title hierarchy is still too weak |
| `sidebarWidth` | `220-240` | `220` | `Match` | within reference range |
| `sidebarIconTile` | `22-24` | `22` | `Match` | within reference range |
| `sidebarIconTextSpacing` | `4-8` | `4` | `Close` | acceptable, but at the tight edge |
| `contentMaxWidth` | `500-560` | `560` | `Close` | okay only if row grammar gets tighter |
| `contentTopInset` | `18-24` | `16` | `Mismatch` | top rhythm is still too compressed |
| `sectionGap` | `20-28` | `16` | `Mismatch` | sections stack too tightly |
| `groupCornerRadius` | `10-12` | `10` | `Match` | within reference range |
| `rowMinHeight` | `40-44` | `40` | `Match` | within reference range |
| `rowInsetX` | `12-14` | `8` | `Mismatch` | grouped cards are too tight internally |
| `labelColumnBehavior` | natural row flow | fixed `168` column | `Mismatch` | Apple avoids a wide, dead label rail |
| `trailingRail` | single right rail | mixed by page | `Close` | simple pages are okay, richer pages drift |

### Structural Rule Check

| Rule | Status | Notes |
| --- | --- | --- |
| one left alignment rail | `Close` | much better than before, but title rhythm still needs work |
| one trailing rail for controls | `Close` | decent on `General`, weaker on `Connectors` |
| grouped cards with internal dividers | `Match` | the shared group surface is correct |
| section description above group, not below | `Close` | improved, but some helper copy still behaves like layout filler |
| long-form content separated from ordinary rows | `Close` | `Stack` is improved; `Connectors` still mixes grammars |
| one archetype per page | `Mismatch` | `Connectors` still breaks the shared pattern most often |

### Tab Fit Simulation

#### General

Target archetype:

- `Dense Mixed-Control Form`

Current fit:

- `Close`

What already fits:

- grouped rows
- compact control density
- overall page type is correct

What still breaks:

- title hierarchy is too weak
- label column is wider than Apple would use
- top and section spacing are too compressed

Estimated fit:

- `70 / 100`

#### Capture

Target archetype:

- `Simple Leaf Settings`

Current fit:

- `Close`

What already fits:

- small number of groups
- simple content model
- limited number of controls

What still breaks:

- inherited fixed label-column grammar
- action row still feels more custom than Apple leaf pages

Estimated fit:

- `72 / 100`

#### Stack

Target archetype:

- `Dense Mixed-Control Form`
- plus a `Long-Form Exception`

Current fit:

- `Close`

What already fits:

- editor and preview are no longer jammed into normal rows
- retention is separated from long-form content

What still breaks:

- long-form blocks are still more custom than Apple exception blocks
- section rhythm is tighter than the screenshots
- label rail is still wider than the Apple references suggest

Estimated fit:

- `62 / 100`

#### Connectors

Target archetype:

- `Intro Card + Sectioned Detail`
- plus a `Repeated Item List`

Current fit:

- `Mismatch`

What already fits:

- action-first thinking is much better than before
- grouped surfaces are helping

What still breaks:

- there is no true intro-card primitive yet
- row, inline panel, setup flow, and status patterns still feel like a local mini system
- command/config blocks are still only partially aligned to Apple detail-page grammar

Estimated fit:

- `48 / 100`

### What This Simulation Says

The current direction is not wrong. It is incomplete.

The dry run says the next implementation pass should do these in order:

1. raise the page-title hierarchy
2. remove the wide fixed label-column row layout
3. move top and section spacing back into Apple range
4. increase grouped-row horizontal inset to Apple range
5. give `Connectors` a dedicated `Hero Detail` primitive instead of forcing it into ordinary preference grammar

### Pre-Implementation Verification Checklist

Before accepting future Settings changes, Backtick should reject any design that fails one of these:

- page title is smaller than Apple detail pages
- section descriptions float below cards
- label column creates large dead space
- long-form editor is placed inside a normal settings row
- grouped rows do not share one trailing control rail
- `Connectors` does not declare its archetype first
