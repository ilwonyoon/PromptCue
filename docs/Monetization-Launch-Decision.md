# Backtick Monetization Launch Decision

## Purpose

This document freezes the v1 launch strategy for pricing, beta, trial, storefront, and licensing.

The goal is not perfect monetization design. The goal is to choose a launchable, low-friction model that:

- lets users try Backtick before paying
- fits a solo developer support burden
- protects local capture reliability
- discourages casual reinstall abuse without turning v1 into DRM work

This document is the planning authority for monetization and licensing until implementation starts.

It inherits product constraints from:

- `docs/Execution-PRD.md`
- `docs/Engineering-Preflight.md`
- `docs/Master-Board.md`

## Product Constraint

Backtick is a native macOS utility app for AI-assisted coding loops.

That means the monetization model must not break the core promise:

- Capture must stay frictionless.
- Stack must stay available for review and export.
- Offline usage must remain reliable.
- License checks must not sit on the hot path for opening Capture or Stack.

## Launch Goal

Ship a direct-download paid product that feels fair:

- users can fully evaluate the product before paying
- price is low enough for impulse purchase
- support and billing operations stay realistic for one person
- the app does not hold user data hostage when access changes

## Option Summary

### 1. Beta And Trial

Options considered:

- one public beta period only
- one commercial trial only
- separate public beta and commercial trial

Recommendation:

- separate them

Reason:

- public beta is for bug discovery and launch feedback
- commercial trial is for post-launch conversion
- keeping them separate avoids turning beta into an indefinitely free product path

Locked v1 decision:

- public beta uses a calendar-expiring build
- recommended beta window: `14 days`
- commercial trial uses an in-app per-user timer
- commercial trial length: `14 days`

### 2. Storefront

Options considered:

- Gumroad
- Lemon Squeezy

Recommendation:

- Lemon Squeezy

Reason:

- lower current fee structure for direct sales
- better fit for software license-key issuance and activation flows
- simpler path for one-time purchase licensing than building custom billing

Locked v1 decision:

- direct-download storefront: `Lemon Squeezy`
- v1 compatibility baseline: `Apple Silicon only`
- Mac App Store remains a later compatibility lane, not the first ship target

### 3. Business Model

Options considered:

- freemium
- subscription
- full-feature trial followed by one-time purchase

Recommendation:

- full-feature trial followed by one-time purchase

Reason:

- freemium creates awkward product boundaries for a utility whose value is the whole capture/export loop
- subscription is harder to justify for a bounded local utility and adds churn/support overhead
- one-time purchase fits indie macOS utility expectations better

Locked v1 decision:

- `14-day full trial -> one-time purchase`

### 4. Pricing

Options considered:

- permanent low price such as `9.99`
- regular price `19.99`
- launch-only founding price followed by a higher regular price

Recommendation:

- use a real launch-only founding price, not a permanent fake discount

Reason:

- `9.99` is strong for launch conversion
- a permanent strike-through discount devalues the product and reads as false urgency
- a real launch window creates urgency without anchoring the product forever as a bargain-bin tool

Locked v1 decision:

- launch founding price: `9.99 USD`
- regular price after launch window: `19.99 USD`
- launch price must be framed as `Founding price` or `Launch price`
- do not run an always-on fake sale
- recommended launch price window: `7 days`

### 5. Activation Limit

Options considered:

- one device
- two devices
- unlimited devices

Recommendation:

- two devices

Reason:

- one device is too punitive for desktop + laptop users
- unlimited devices weakens the point of license gating for a paid indie utility
- two devices is a practical middle ground with low support cost

Locked v1 decision:

- activation limit: `2 Macs per license`

### 6. Expiry And Anti-Abuse

Options considered:

- hard lock after trial expiry
- read-only after expiry
- unrestricted local access with nagging only

Recommendation:

- allow read/export/license-management access after expiry, but block new capture/save

Reason:

- users should not lose access to their own captured data
- fully unrestricted expired use weakens conversion too much
- blocking all local access would create resentment and support burden

Locked v1 decision:

- after trial expiry:
  - existing cards remain visible
  - export remains available
  - license entry and activation remain available
  - new capture and new saves are blocked

Anti-abuse recommendation:

- v1 uses local `Keychain` state for trial and activation persistence
- trial stores:
  - `trial_started_at`
  - `last_seen_at`
- activated purchase stores:
  - license key metadata
  - activation instance identifier
- network failure must not block existing local notes or normal paid usage
- if significant abuse appears later, add a server-backed trial ledger in a follow-up slice

## Rejected v1 Paths

### Freemium

Rejected because:

- it complicates the product surface too early
- the free/pro boundary would likely cut through core capture or export behavior
- it adds ongoing packaging, messaging, and support overhead

### Subscription

Rejected because:

- Backtick is a bounded local utility, not a cloud-heavy service
- subscription resistance is likely higher than for one-time purchase
- it creates avoidable billing overhead for an initial solo launch

### Permanent Strike-Through Pricing

Rejected because:

- it is effectively the same as setting the lower price permanently
- it weakens long-term product positioning
- it creates trust and compliance risk if the higher price is not genuinely used

### Heavy Hardware-Bound DRM

Rejected because:

- it adds complexity before product-market validation
- it risks false positives during normal reinstalls or machine changes
- it conflicts with the product goal of low-friction local utility behavior

## Recommended User Journey

### Public Beta

- user downloads a public beta build
- build is fully usable
- build expires after the fixed beta window
- beta build messaging points users to the upcoming paid launch

### Paid Launch

- user downloads the app
- app starts a `14-day` full trial on first launch
- app shows remaining trial days in a minimal, non-blocking way
- user purchases through Lemon Squeezy if they want to continue
- user enters a license key
- app activates that key for up to `2 Macs`

### After Trial Expiry

- user can still open the app
- user can still review and export existing cards
- user can still activate a license
- user cannot create or save new cards until licensed

## Implementation Guardrails

The eventual implementation must preserve these rules:

1. no network call on the Capture open path
2. no network call on the Stack open path
3. no forced sign-in requirement inside the app
4. no data hostage behavior after expiry
5. no blocking paid-user lockout because a license revalidation request fails
6. no aggressive DRM that increases false failures more than it reduces abuse

## Execution Posture

This is a planning document, not an implementation branch.

Recommended next sequence:

1. lock this strategy in docs
2. implement a small `trial + licensing foundation` slice
3. add minimal purchase, activation, and expiry UI
4. validate the post-expiry local-access behavior before broad launch

Worktree guidance:

- no extra worktree is needed for this policy-lock step
- a separate implementation branch is enough when coding starts

## Locked v1 Recommendation

Ship Backtick as:

- `14-day` public beta build
- direct-download app sold through `Lemon Squeezy`
- `Apple Silicon only` for v1
- `14-day` full in-app trial after launch
- one-time purchase
- `9.99 USD` founding launch price for `7 days`
- `19.99 USD` regular price after the launch window
- `2-device` activation limit
- post-expiry access of `read/export/manage-license only`
- Keychain-backed trial and activation persistence in v1

This is the recommended launch default because it is the best balance of:

- low friction
- fair try-before-buy access
- manageable solo-developer operations
- enough enforcement to support a paid product
