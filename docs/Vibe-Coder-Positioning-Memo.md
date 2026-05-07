# Backtick Vibe-Coder Positioning Memo

## Purpose

This memo sharpens how Backtick should be described in external writing, especially when the surrounding discourse is about LLM memory, agent memory, or LLM knowledge bases.

The goal is not to force Backtick into a generic "AI memory" bucket. The goal is to explain the product in a way that matches the actual app structure and the real user tradeoff.

Backtick is best understood as a three-layer memory system for vibe coders:

1. `Capture`
2. `Stack / MCP`
3. `Memory / MCP`

This is a better framing than "notes app", "PKM app", or "knowledge base" without qualification.

## Product Shape

Backtick handles three distinct jobs:

### 1. Capture

Capture exists so the user does not lose thoughts while working with AI.

This layer is for:

- bugs noticed mid-flow
- prompt fragments
- follow-ups
- checks to run
- decisions that are not yet ready to become durable memory

The job is not organization. The job is loss prevention.

### 2. Stack / MCP

Stack is the execution layer.

This layer takes captured notes and makes them available to AI workflows again through MCP. It is not just a passive inbox. It is the short-lived working set that lets an AI tool pick up what matters now and continue the job.

The job is not archival memory. The job is workflow continuity.

### 3. Memory / MCP

Memory is the durable reviewed layer.

This is where project context, decisions, plans, constraints, and reviewed summaries become persistent across AI clients and across sessions.

The important product rule is:

- not everything should become memory
- durable memory should be reviewed
- AI can propose the save, but the user approves what becomes durable context

The job is not "save everything." The job is to preserve the right context.

## Primary User

The clearest target is the vibe coder or AI-native builder:

- builds products with ChatGPT, Claude, Claude Code, Codex, and similar tools
- context-switches across tools and topics constantly
- loses important thoughts between agent conversations
- needs continuity across AI clients, not just inside one platform
- often cares more about preserving decisions than building a giant archive

This user is different from a researcher or knowledge worker whose main problem is curating a very large and ever-growing corpus.

## Backtick Versus LLM Knowledge Bases

Backtick should not be positioned as "a better LLM knowledge base."

That claim is too broad and usually wrong.

A better framing is:

- LLM knowledge base systems are optimized for `coverage`
- Backtick is optimized for `precision`

LLM knowledge base systems tend to win when the user wants:

- broad accumulation
- ongoing ingest from many sources
- increasingly rich cross-references
- a large evolving corpus
- synthesis over a wide body of material

Backtick tends to win when the user wants:

- fast capture of volatile context
- continuity across multiple AI tools
- a selective memory of what actually matters
- reviewed durable context instead of silent extraction
- a clean project decision tree instead of a sprawling wiki

This is not a winner-take-all comparison.

These products are often solving adjacent problems.

## The Critical Tradeoff

The real tradeoff is not "automatic memory bad, human review good."

The real tradeoff is:

- `automatic memory` gives more coverage
- `approval-based memory` gives more precision

Backtick should explicitly embrace that tradeoff.

### Where approval-based memory is stronger

Approval-based memory is stronger when:

- the conversation is noisy
- the user works across several AI tools
- many observations are temporary but a few are durable
- the user wants a selective decision tree
- memory pollution is more dangerous than memory omission

This is often true for vibe coding and solo product building.

In these workflows, not all context deserves permanence. A lot of it is transient implementation chatter, half-formed ideas, or dead-end exploration. If all of that is promoted automatically, the memory layer becomes polluted and harder to trust.

### Where approval-based memory is weaker

Approval-based memory is weaker when:

- the user wants to ingest a huge amount of material continuously
- completeness matters more than selectivity
- the user is building a research wiki or long-horizon content base
- the value comes from retaining almost everything and connecting it later

In those cases, approval is real friction. It reduces throughput and may prevent the corpus from becoming richly populated enough to be useful.

This should be stated plainly. Backtick is not the ideal shape for every memory problem.

## The Key Strategic Claim

Backtick is not making the bet that users need infinite AI memory.

Backtick is making the bet that vibe coders need:

- a way to not lose thoughts
- a way to route those thoughts back into agent workflows
- a way to preserve only the context that should survive

That is a narrower claim than "universal memory for all AI use."

It is also a more defensible claim.

## Messaging Guardrails

When describing Backtick publicly, prefer these ideas:

- three-layer memory system
- for vibe coders
- capture -> workflow -> durable memory
- cross-client continuity
- reviewed project memory
- selective memory
- approval-based promotion
- protect against memory pollution
- preserve decisions, not everything

Avoid these ideas unless heavily qualified:

- universal knowledge base
- second brain for everything
- store all your context automatically
- replacement for research wiki tools
- better than every PKB or LLM wiki

## Recommended Positioning Language

### Core sentence

Backtick is a three-layer memory system for vibe coders: capture thoughts before they disappear, route them back into AI workflows, and promote only the context worth keeping into durable shared memory.

### Short version

Backtick is approval-based project memory for people who build with AI.

### Contrast sentence

If you want an ever-growing LLM knowledge base, there are better shapes for that. If you want a selective decision tree that survives across agent conversations, Backtick is a stronger fit.

### Tradeoff sentence

Automatic memory optimizes for coverage. Backtick optimizes for precision.

### Sharp version

The problem for vibe coders is not lack of memory. It is memory pollution, context loss, and broken continuity across AI tools.

## LinkedIn Post Angle

A strong external post should do three things:

1. name the user clearly: vibe coders / AI-native builders
2. explain the three layers clearly: capture, workflow, memory
3. state the tradeoff honestly: selective approved memory is not for every use case

The strongest version is not:

- "Backtick beats LLM knowledge bases"

The strongest version is:

- "Backtick is built for a different memory problem"

That problem is not infinite archival knowledge.

That problem is preserving the right decisions in the middle of messy, multi-agent, multi-tool work.
