# Competitive Landscape & Future Backlogs

> Last updated: 2026-03-15
> Status: Living document — research synthesis + actionable backlog extraction

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [The Felix / OpenClaw Case Study](#2-the-felix--openclaw-case-study)
3. [AI Memory & Context Competitors](#3-ai-memory--context-competitors)
4. [Vibe-Coding Solopreneur Ecosystem](#4-vibe-coding-solopreneur-ecosystem)
5. [Backtick Positioning Analysis](#5-backtick-positioning-analysis)
6. [Backlog: What to Apply](#6-backlog-what-to-apply)
7. [Anti-Backlog: What NOT to Apply](#7-anti-backlog-what-not-to-apply)
8. [Open Questions](#8-open-questions)
9. [Sources](#9-sources)

---

## 1. Executive Summary

Backtick sits at the intersection of three converging trends: (1) AI memory/context is becoming a platform feature, (2) vibe-coding solopreneurs desperately need cross-session continuity, and (3) MCP is becoming the interop standard. The competitive window is narrow — platforms are adding native memory, but none solve **cross-platform context portability** well.

### Key Findings

- **200+ hours/year** lost by power users rebuilding context when switching AI platforms
- **70% of developers** use 2-4 AI tools simultaneously — context fragmentation is universal
- **Felix/OpenClaw** proves that 3-layer memory (knowledge graph + daily notes + tacit knowledge) works, but requires enormous setup effort
- **Mem0** is the developer infrastructure leader ($24M Series A, 41K GitHub stars) but is not a consumer product
- **Rewind AI is dead** (Meta acqui-hire Dec 2025) — the local-first personal memory space has a vacuum
- **Granola** ($43M raised) proves meeting-centric memory is a viable wedge at $14/mo
- **Screenpipe** (16K GitHub stars) inherited Rewind's user base with open-source, local-first approach
- **Claude Memory** went free in March 2026, using transparent CLAUDE.md files — validating Backtick's file-based approach
- **ChatGPT Memory** has the largest deployment but is opaque and unreliable for exact recall
- The **#QuitGPT movement** drove 295% increase in ChatGPT uninstalls — context lock-in is the trigger

---

## 2. The Felix / OpenClaw Case Study

### Why This Matters for Backtick

Nat Eliason's Felix is the most publicly documented "AI second brain" implementation. It validates our warm memory thesis while revealing exactly where the pain points are.

### Architecture Summary

Felix runs on a Mac Mini (~$550/month operational cost) using Claude + Codex in a two-layer architecture: Felix (Claude/Opus) plans and delegates, Codex implements. Revenue: ~$195K in 3-4 weeks.

**3-Layer Memory System:**

| Layer | What | Storage | Update Cadence |
|-------|------|---------|---------------|
| Knowledge Graph | PARA-structured atomic facts with metadata (category, status, supersededBy, relatedEntities, lastAccessed) | `~/life/` folder, Markdown | Nightly consolidation from daily notes |
| Daily Notes | Chronological session logs | `memory/YYYY-MM-DD.md` | Continuous during conversations |
| Tacit Knowledge | User model — communication style, hard rules, lessons learned | Single file | Slow, pattern-detected updates |

**Search: QMD** (by Tobi Lutke) — local CLI combining BM25 + vector search + LLM re-ranking over SQLite. Keeps context windows lean by loading only relevant snippets.

**Key Design Decisions:**
- Facts are never deleted — old facts get `supersededBy` pointers (immutable history)
- Summary files serve most queries; full fact store only loaded on demand (two-tier retrieval)
- Nightly self-improvement cron job: Felix reviews all conversations, identifies one improvement, builds new skills/automation
- Redundant cron jobs (backup at 2:30 AM checks if primary ran) — reliability is hard
- Sub-agents (Iris for support, Remy for sales) with escalation to Felix, then to Nat

### Lessons Learned (Nat's Own Reflections)

1. **"Memory is the single biggest unlock"** — set it up before anything else
2. **Onboarding is the hardest part** — a fresh agent is "a teenager entering the workforce"; Felix's advantage is months of accumulated knowledge
3. **Client deployments revealed real limits** — building web apps is easy for agents; handling nuanced customer emails is "exceptionally difficult"
4. **Context synthesis is the hardest AI task** — not retrieval, but *making sense* of retrieved context
5. **Resist doing the work yourself** — "If I were working 100 hours a week on Felix, that would be a failure"
6. **Give agents their own accounts** — blast radius containment

### OpenClaw Framework Status

- 315K+ GitHub stars, MIT license, Node.js/TypeScript
- 20+ messaging channels (WhatsApp, Telegram, Slack, Discord, iMessage, etc.)
- Skills system: markdown-based, composable, community marketplace (ClawHub)
- **Critical security issues**: CVE-2026-25253 (one-click RCE), 512 vulnerabilities found in audit, 42K exposed instances, ClawHub supply chain attacks (824+ malicious skills)
- Peter Steinberger (creator) joined OpenAI Feb 2026; project transitioned to independent foundation

### Backtick Relevance Assessment

| Felix Pattern | Apply to Backtick? | Reasoning |
|--------------|-------------------|-----------|
| 3-layer memory hierarchy | **YES — core architecture** | Validates our Hot/Warm/Cold model. Knowledge graph + daily notes + user model maps directly to Stack + Warm Memory + user preferences |
| PARA-based organization | **MAYBE — simplified** | Full PARA is overkill for capture-first UX. But project × topic structure is validated |
| Immutable facts with supersededBy | **YES — for Warm Memory** | Never delete, always supersede. Enables time-travel and avoids data loss |
| Two-tier retrieval (summary first, details on demand) | **YES** | Critical for keeping MCP tool responses lean |
| QMD-style hybrid search | **LATER** | BM25 + vector + LLM re-ranking is ideal but complex. Start with simpler search, upgrade later |
| Nightly consolidation | **YES — automated** | Hot → Warm promotion should be automatic, not manual |
| Redundant cron jobs | **NO** | Over-engineering for our use case. macOS scheduling is reliable enough |
| Sub-agent delegation | **NO** | Not our problem space. Backtick is a memory tool, not an agent framework |
| Skills marketplace | **NO** | Premature. Also, ClawHub's security disasters are a cautionary tale |

---

## 3. AI Memory & Context Competitors

### Tier 1: Platform-Native Memory (Biggest Threat)

#### Claude Memory (Anthropic)
- **Status**: Active, free for all users (March 2026)
- **Approach**: File-based (CLAUDE.md), transparent, user-editable
- **Strengths**: Honest architecture, growing fast, conversation import from ChatGPT
- **Weaknesses**: Monolithic file → "fading memory" as it grows; no semantic search over memories; no graph; no cross-app context
- **Threat to Backtick**: Medium. Validates file-based memory but doesn't solve cross-platform or structured organization. Backtick's MCP server can *enhance* Claude Memory rather than compete with it

#### ChatGPT Memory (OpenAI)
- **Status**: Active, largest deployment
- **Approach**: Auto-detected facts + full chat history reference (April 2025)
- **Strengths**: Massive user base, zero-friction ("just use it")
- **Weaknesses**: Opaque (can't see internal representation), unreliable for exact recall, stale memories persist, no cross-app context
- **Threat to Backtick**: Low-medium. Different philosophy entirely. Users who want control and transparency will still need Backtick

#### Apple Intelligence
- **Status**: Behind schedule. Writing Tools shipped; personal Siri context delayed to spring/summer 2026
- **Approach**: On-device, privacy-first, cross-app (promised)
- **Strengths**: Massive distribution, privacy advantage
- **Weaknesses**: Persistently delayed. No third-party API for personal context. Not competitive with dedicated tools today
- **Threat to Backtick**: Low (near-term), potentially high (if Siri personal context actually ships and is good). Monitor closely

### Tier 2: Developer Infrastructure (Different Market)

#### Mem0
- **Status**: Active, $24M Series A. 41K GitHub stars, 186M API calls/quarter
- **Pricing**: Free → $19/mo → $249/mo (graph memory) → Enterprise
- **Approach**: Extraction + update pipeline, hybrid vector/graph/KV stores, 22+ vector backends
- **Differentiator**: Graph memory (Mem0-g) for complex reasoning
- **Target**: AI product builders, not end users
- **Threat to Backtick**: None directly. Potential partner — Backtick could use Mem0 as backend infrastructure

#### Zep
- **Status**: Active, competing with Mem0
- **Approach**: Graphiti temporal knowledge graph — tracks how relationships evolve over time
- **Differentiator**: Sub-100ms retrieval, temporal reasoning
- **Threat to Backtick**: None directly. Same as Mem0 — potential infrastructure

#### LangMem (LangChain)
- **Status**: Active, free/open-source. Requires LangGraph
- **Weaknesses**: LangGraph lock-in, terrible latency (p50: 18s, p95: 60s)
- **Threat to Backtick**: None

### Tier 3: Consumer Memory Products (Direct Competition)

#### Screenpipe (Open-Source Rewind Successor)
- **Status**: Active, 16K GitHub stars, 80+ contributors
- **Pricing**: $400 lifetime license
- **Approach**: Continuous screen + audio capture, local-first, MCP server for Claude/Cursor
- **Differentiator**: Open-source Rewind. OS accessibility tree for structured text extraction
- **Threat to Backtick**: Low. Different input modality (passive capture vs. intentional capture). Complementary — Screenpipe captures everything, Backtick captures what you *intend* to act on

#### Granola
- **Status**: Active, $43M raised at $250M valuation
- **Pricing**: Free (25 meetings) → $14/mo Pro
- **Approach**: Meeting-centric. Local audio capture (no bot), human notes + AI enhancement, "Ask Granola" cross-meeting search, lightweight CRM
- **Differentiator**: No meeting bot, hybrid human+AI notes, MCP integration (Feb 2026)
- **Threat to Backtick**: Low. Meeting-only focus. But the "Recipes" concept (templated AI prompts applied as lenses over captured content) is worth studying

#### Pluro
- **Status**: Active, early-stage
- **Approach**: Cross-platform memory sync (ChatGPT + Claude + Gemini unified timeline)
- **Differentiator**: Zero-knowledge encryption, consumer-facing
- **Threat to Backtick**: Medium. Solves the same "I told ChatGPT but now I'm in Claude" problem. But no structured organization or execution queue. Backtick's Stack model is deeper

#### Rewind AI / Limitless
- **Status**: DEAD. Meta acqui-hired Dec 2025. App shut down Dec 19, 2025
- **Lesson**: Local-first personal AI memory had real PMF. The pivot to cloud + hardware pendant killed it. Screenpipe inherited the user base

### Tier 4: PKM + AI (Adjacent)

#### Obsidian + AI Plugins
- **Smart Connections**: Suite of 3 plugins (discovery, RAG chat, context management). Moved to freemium — community pushback
- **Copilot for Obsidian**: Vault QA using your own API key. Growing as free alternative
- **Khoj AI**: YC-backed, open-source, self-hostable. Multi-platform (Browser, Obsidian, Emacs, WhatsApp). Automations feature for scheduled tasks
- **Key Insight**: PKM community solves AI memory bottom-up (own data, choose provider, compose plugins). Opposite of top-down (ChatGPT/Claude native memory). Tradeoff: setup complexity vs. control

#### Mem 2.0
- **Status**: Complete rebuild Oct 2025. AI-native note-taking with offline support, voice capture, agentic AI layer
- **Threat to Backtick**: Low-medium. Different interaction model (notes vs. capture queue)

#### AFFiNE
- **Status**: Active, open-source, local-first. "Notion + Obsidian + AI" without complexity
- **Threat to Backtick**: Low. Workspace tool, not capture/execution tool

### Tier 5: Coding IDE Memory (Relevant for Target Users)

#### Cursor
- **Approach**: Layered — rules files (.cursor/rules/*.mdc), Notepads, Generate Memories, community "Memory Bank" pattern, MCP-based external memory
- **Key Insight**: The community Memory Bank pattern (structured markdown files read at session start) emerged organically. Not built-in but widely adopted. This validates Backtick's approach
- **Threat to Backtick**: None. Backtick's MCP server *feeds into* Cursor. Complementary

#### Windsurf
- **Approach**: Built-in Memories feature + Cascade Flows (graph-based reasoning)
- **Key Insight**: Stronger built-in memory than Cursor, but no equivalent of .cursorrules for team sharing
- **Threat to Backtick**: None. Same complementary relationship

---

## 4. Vibe-Coding Solopreneur Ecosystem

### The Target User Profile

| Metric | Data |
|--------|------|
| Multi-tool usage | 70% use 2-4 AI tools simultaneously |
| Context loss cost | 200+ hours/year rebuilding context across platforms |
| AI code generation | 84% of developers using AI tools (2026). Gartner: 60% of new code AI-generated by 2026 |
| Revenue examples | Pieter Levels: $138K/mo, Marc Lou: $1M/yr, Danny Postma: $100K+/mo |

### Notable Solopreneurs & Their Workflows

**Pieter Levels (@levelsio)**
- $138K/month across portfolio. Built Fly.Pieter.com (3D flight sim) with Cursor + ThreeJS + Grok 3 + Claude → 89K players in 10 days, $50K+/mo
- Organized 2025 Vibe Coding Game Jam (1,170 submissions)
- Philosophy: ship before ready, master one stack deeply

**Marc Lou**
- $1,032,000 in 2025. ShipFa.st ($25K/mo) + portfolio
- "AI makes everything easier: it writes my code, improves my broken English, and brainstorms video ideas"
- Strategy: tools for indie hackers, ship fast, build in public

**Danny Postma**
- $100K+/month across ~20 projects. HeadshotPro ($300K/mo, 40K+ users)
- SEO-first discovery → rapid iteration → AI-native products

**Nat Eliason**
- Started vibe coding Jan 2024 with Cursor; "less than 20% of the code himself"
- Built Covici (book writing tool) entirely through AI coding
- Current stack: GPT Codex CLI, Conductor, Claude Code
- Created "Build Your Own Apps with AI" course

**25% of YC Winter 2025 batch** built startups with 95%+ AI-generated codebases.

### Pain Points (Ranked by Severity)

1. **Cross-session memory** (#1 most discussed frustration)
   - "Each session is a blank slate. The decisions, the dead ends — evaporates"
   - One developer reported **losing 4 hours of work** when architectural reasoning evaporated
   - Two sub-problems: intra-session compaction (losing detail in long sessions) + cross-session amnesia

2. **Cross-tool context portability**
   - No automatic sync between platforms. Switching = "starting from zero"
   - #QuitGPT movement: context lock-in is the primary blocker to switching
   - 295% increase in ChatGPT uninstalls in a single day

3. **Prompt reuse and organization**
   - No standard tooling for maintaining prompt libraries across AI tools
   - Prompts are "assets" but have no portable format

4. **Context window degradation**
   - Quality drops sharply past ~60% capacity
   - "Pushing a thread to 90% capacity causes sharp decline in reasoning and increases hallucinations"

5. **The "strategic layer" gap**
   - "Vibe coding makes you faster. It doesn't make you smarter about what to build"
   - AI makes building faster but doesn't help decide *what* to build

### The Current Stack (What They Use Together)

| Category | Tools |
|----------|-------|
| AI Coding | Claude Code (46% "most loved"), Cursor (42% indie hackers), Codex, Copilot, Bolt/Lovable/v0 |
| PKM | Obsidian (privacy-conscious), Notion (collaboration), hybrid workflows bridged via Zapier |
| Memory | CLAUDE.md/MEMORY.md (manual), MCP servers, "document & clear" pattern, /compact commands |
| Bridging | MCP (emerging standard), manual markdown handoffs |

### Emerging Patterns

**Becoming standard:**
- Multi-tool workflows (2-4 tools)
- CLAUDE.md / rules files as project context
- MCP as interop layer
- "Context engineering" as the most important solo founder skill in 2026

**Still painful:**
- Cross-session memory (no mainstream solution)
- Cross-tool context portability
- Prompt reuse and organization ← **Backtick's core value prop**
- Context window degradation

---

## 5. Backtick Positioning Analysis

### Where Backtick Fits

```
                    Passive Capture ──────────── Intentional Capture
                         │                              │
                    Screenpipe                      ★ Backtick ★
                    Rewind (dead)                    Granola (meetings)
                         │                              │
                    Everything ───────────────── Structured/Actionable
                         │                              │
           Platform Memory ──────────────── Cross-Platform Memory
           (Claude, ChatGPT)                    Pluro, AI Context Flow
                                                ★ Backtick (via MCP) ★
```

### Backtick's Unique Position

No one else is building: **intentional capture → structured execution queue → cross-platform MCP delivery**

- **Capture**: Frictionless dump (not passive recording, not meeting transcription)
- **Stack**: Execution queue with AI compression (not a note archive, not a knowledge graph)
- **MCP**: Deliver structured context to any AI tool (Claude, Cursor, ChatGPT, Codex)

### Competitive Moats

1. **Interaction model**: Capture (dump) → Stack (execute) → Archive. No one else has this queue metaphor
2. **macOS-native**: Menu bar utility with global hotkeys. Faster than opening any app
3. **MCP-first delivery**: Context goes *to* the AI tools, not stored separately
4. **TTL-based lifecycle**: Cards expire (8hr default). This is anti-hoarding, pro-action — opposite of every PKM tool

---

## 6. Backlog: What to Apply

### P0 — Core Differentiators (Ship First)

#### 6.1 Cross-Platform MCP Delivery
**Source**: Vibe-coder pain point #2, Pluro's existence, 70% multi-tool usage
**What**: Backtick's MCP server should work with Claude Desktop, Cursor, ChatGPT (when MCP support lands), Codex
**Why**: This is the #1 reason someone would use Backtick over platform-native memory. "Capture once, use everywhere"
**Priority**: Already in progress (BacktickMCP exists). Ensure it works seamlessly with top 3 clients

#### 6.2 Prompt/Context Reuse
**Source**: Vibe-coder pain point #3, no existing solution
**What**: Saved prompts, templates, snippets that persist beyond TTL. Reusable across sessions and tools
**Why**: "No standard tooling for maintaining prompt libraries across AI tools" — this is an open gap
**Priority**: Natural extension of Stack. Pinned cards or a separate "Templates" concept

#### 6.3 Session Handoff Support
**Source**: Vibe-coder pain point #1 (cross-session amnesia), Felix's daily notes pattern
**What**: Quick-capture of "session summary" that becomes available in next AI session via MCP
**Why**: "Each session is a blank slate" is the #1 frustration. Backtick can be the bridge
**Priority**: High. Simple to implement — a card type or tag that MCP tools prioritize in context delivery

### P1 — Validated Patterns (Build Next)

#### 6.4 Automated Hot → Warm Promotion
**Source**: Felix's nightly consolidation, Claude's CLAUDE.md approach
**What**: Cards in Stack that aren't acted on within TTL get offered for promotion to Warm Memory (project × topic structure) instead of just expiring
**Why**: Felix proves the daily-notes → knowledge-graph promotion pattern works. Automated > manual
**Priority**: After Warm Memory architecture is defined

#### 6.5 Two-Tier Retrieval for MCP
**Source**: Felix's "summary first, details on demand" pattern
**What**: MCP tool responses return summaries by default, with a follow-up tool to get full detail
**Why**: Keeps AI context windows lean. Felix's "most of the time, the summary is enough" is validated
**Priority**: MCP server enhancement. Critical for scaling beyond small card counts

#### 6.6 Immutable Facts with Supersession
**Source**: Felix's knowledge graph design
**What**: Warm Memory entries are never deleted — updated entries create new versions with `supersededBy` pointers
**Why**: Enables time-travel ("what did I know about this project last month?"), prevents accidental data loss
**Priority**: Design into Warm Memory data model from day one

#### 6.7 Granola-Style "Recipes" / Lenses
**Source**: Granola's Recipes feature
**What**: User-defined AI prompt templates applied as a "lens" over captured content (e.g., "extract action items", "summarize as PRD", "convert to user story")
**Why**: Transforms raw capture into structured, actionable output. Fits Stack's compression philosophy
**Priority**: After core capture/stack flow is solid

### P2 — Future Exploration

#### 6.8 Local Hybrid Search
**Source**: Felix's QMD (BM25 + vector + LLM re-ranking)
**What**: As Warm Memory grows, add local semantic search beyond SQLite FTS
**Why**: FTS alone won't scale to hundreds of project documents
**When**: When Warm Memory has enough content to justify complexity

#### 6.9 Meeting Context Integration
**Source**: Granola's success, but inverse approach
**What**: Not building meeting transcription (Granola does this). Instead, accept meeting summaries *from* Granola via MCP or paste, and route them into Stack
**Why**: Meetings generate action items. Those belong in an execution queue, not a transcript archive
**When**: After MCP ecosystem matures

#### 6.10 Screenpipe Integration
**Source**: Screenpipe's MCP server, complementary capture model
**What**: Accept context from Screenpipe (what you were looking at when you captured something) as metadata enrichment
**Why**: Passive context enriches intentional capture without changing Backtick's interaction model
**When**: If users request it

---

## 7. Anti-Backlog: What NOT to Apply

### 7.1 Do NOT Build an Agent Framework
**Source**: Felix/OpenClaw
**Why**: OpenClaw has 315K GitHub stars and massive security problems. Agent frameworks are a different product category entirely. Backtick is a **memory and capture tool**, not an agent runtime. The sub-agent delegation pattern, skills marketplace, and autonomous execution are all out of scope.

### 7.2 Do NOT Build Passive Screen/Audio Capture
**Source**: Rewind (dead), Screenpipe
**Why**: Rewind died. Screenpipe exists and is open-source. Privacy implications are enormous. Backtick's value is *intentional* capture — the user decides what matters. "If a capture UI element can be removed and capture still works, remove it" — this philosophy is incompatible with always-on recording.

### 7.3 Do NOT Build a Full Knowledge Graph
**Source**: Mem0-g, Zep Graphiti, Felix's PARA system
**Why**: Graph memory is powerful but complex (Mem0 charges $249/mo for it). A full knowledge graph with entity extraction, relation generation, and conflict detection is infrastructure-level work. If we need it later, use Mem0 or Zep as infrastructure rather than building our own.

### 7.4 Do NOT Build Cross-Platform Chat Sync
**Source**: Pluro
**Why**: Syncing full conversation histories across ChatGPT/Claude/Gemini is a massive technical challenge with rapidly moving API targets. Pluro is trying this and it's early/unproven. Backtick's approach is better: capture the *important bits* intentionally and deliver them via MCP. Don't try to vacuum up entire chat histories.

### 7.5 Do NOT Add Crypto/Token Mechanics
**Source**: Felix's $FELIX token
**Why**: Obviously. The token speculation around Felix is a distraction from the actual product value. Nat himself distances from it.

### 7.6 Do NOT Build a Community Marketplace (Yet)
**Source**: OpenClaw's ClawHub disasters (824+ malicious skills)
**Why**: Supply chain security is extremely hard. A skills/templates marketplace sounds appealing but the security surface area is enormous. If we ever do this, it needs serious vetting infrastructure.

### 7.7 Do NOT Compete with Platform-Native Memory
**Source**: Claude Memory, ChatGPT Memory
**Why**: Both are free and built-in. Backtick should **complement** them, not replace them. Backtick feeds context *into* these platforms via MCP. The positioning is "Backtick makes Claude Memory / ChatGPT Memory better" not "use Backtick instead of Claude Memory."

### 7.8 Do NOT Over-Invest in Onboarding Automation
**Source**: Felix's "fresh agent is a teenager" problem
**Why**: Felix's cold-start problem is real for agents. Backtick doesn't have this problem because we're capture-first — the user populates context naturally through use. Don't build elaborate onboarding flows; let the tool fill up organically.

---

## 8. Open Questions

1. **Warm Memory data model**: Project × topic structure is validated by Felix's PARA. But how simplified should it be? Full PARA (Projects/Areas/Resources/Archives) or just Project × Topic?

2. **MCP tool design for Warm Memory**: Felix's two-tier retrieval (summary → detail) is the right pattern. How do we expose this? `list_notes` returns summaries, `get_note` returns full content? Or a single `search` tool with depth parameter?

3. **Promotion UX**: When a Stack card's TTL expires, how do we prompt for Warm Memory promotion? Silent auto-promotion? Notification? Batch review?

4. **Granola-style Recipes**: Should these be a first-class feature or just prompt templates users can save as cards? The simpler version (saved prompt cards with a "apply to selection" action) might be enough.

5. **Competitive timing**: Claude Memory went free in March 2026 and added ChatGPT import. MCP adoption is accelerating. The window for "cross-platform context" as a differentiator is open now but may narrow. How fast do we need to ship MCP multi-client support?

6. **Screenpipe/Granola integrations**: Do we proactively build these, or wait for user demand? The MCP standard means they might "just work" if both sides implement MCP.

---

## 9. Sources

### Felix / OpenClaw
- [Bankless Podcast: Building a Million Dollar Zero Human Company](https://www.bankless.com/podcast/building-a-million-dollar-zero-human-company-with-openclaw-nat-eliason)
- [Peter Yang / CreatorEconomy.so: Full Tutorial](https://creatoreconomy.so/p/use-openclaw-to-build-a-business-that-runs-itself-nat-eliason)
- [Every.to: OpenClaw Setting Up Your First Personal AI Agent](https://every.to/source-code/openclaw-setting-up-your-first-personal-ai-agent)
- [Nat Eliason X: Inside Felix](https://x.com/nateliason/status/2024953009524932705)
- [Nat Eliason X: Agentic PKM with PARA and QMD](https://x.com/nateliason/status/2017636775347331276)
- [Nat Eliason X: Sentry → Codex pipeline](https://x.com/nateliason/status/2017270908986016044)
- [Sentry-to-PR Gist](https://gist.github.com/Nateliason/5d63ac0ae0539ada7a73292ceae2f938)
- [Felix Craft product site](https://felixcraft.ai/)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [Nat Eliason: Past and Future of Vibe Coding](https://blog.nateliason.com/p/the-past-and-future-of-vibe-coding)
- [Nat Eliason: Best Vibe Coding Tools Oct 2025](https://blog.buildyourownapps.com/p/the-best-vibe-coding-tools-as-of)
- [The Register: OpenClaw security issues](https://www.theregister.com/2026/02/02/openclaw_security_issues/)
- [Microsoft Security Blog: Running OpenClaw Safely](https://www.microsoft.com/en-us/security/blog/2026/02/19/running-openclaw-safely-identity-isolation-runtime-risk/)

### AI Memory Competitors
- [Mem0 Homepage](https://mem0.ai/) | [GitHub](https://github.com/mem0ai/mem0) | [Research Paper](https://arxiv.org/abs/2504.19413)
- [TechCrunch: Mem0 raises $24M](https://techcrunch.com/2025/10/28/mem0-raises-24m-from-yc-peak-xv-and-basis-set-to-build-the-memory-layer-for-ai-apps/)
- [Pluro Cloud](https://www.pluro.cloud/)
- [TechCrunch: Meta acquires Limitless](https://techcrunch.com/2025/12/05/meta-acquires-ai-device-startup-limitless/)
- [Granola Homepage](https://www.granola.ai/) | [TechCrunch: Granola debuts](https://techcrunch.com/2024/05/22/granola-debuts-an-ai-notepad-for-meetings/)
- [Screenpipe Homepage](https://screenpi.pe) | [GitHub](https://github.com/mediar-ai/screenpipe)
- [Zep vs Mem0 Comparison](https://dev.to/anajuliabit/mem0-vs-zep-vs-langmem-vs-memoclaw-ai-agent-memory-comparison-2026-1l1k)
- [Claude Memory API Docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)
- [OpenAI Memory FAQ](https://help.openai.com/en/articles/8590148-memory-faq)
- [Khoj AI](https://khoj.dev/) | [GitHub](https://github.com/khoj-ai/khoj)
- [Smart Connections](https://smartconnections.app/)
- [Cursor Rules Docs](https://cursor.com/docs/context/rules)
- [Medium: Top 10 AI Memory Products 2026](https://medium.com/@bumurzaqov2/top-10-ai-memory-products-2026-09d7900b5ab1)
- [Plurality Network: Best AI Memory Extensions 2026](https://plurality.network/blogs/best-universal-ai-memory-extensions-2026/)

### Vibe-Coding Solopreneurs
- [FastSaaS: Pieter Levels Success Story](https://www.fast-saas.com/blog/pieter-levels-success-story/)
- [Marc Lou: $1,032,000 in 2025](https://newsletter.marclou.com/p/i-made-1-032-000-in-2025)
- [SupaBird: Danny Postma Profile](https://supabird.io/articles/danny-postma-how-a-solo-hacker-built-an-ai-empire-from-bali)
- [NxCode: One-Person Unicorn Guide 2026](https://www.nxcode.io/resources/news/one-person-unicorn-context-engineering-solo-founder-guide-2026)
- [DEV: Claude Code Memory Fix](https://dev.to/gonewx/i-tried-3-different-ways-to-fix-claude-codes-memory-problem-heres-what-actually-worked-30fk)
- [TechCrunch: Users ditching ChatGPT for Claude](https://techcrunch.com/2026/03/02/users-are-ditching-chatgpt-for-claude-heres-how-to-make-the-switch/)
- [AI Fire: Mastering Context Windows](https://www.aifire.co/p/mastering-ai-context-windows-memory-hacks-for-2026)
- [FlowHunt: Context Engineering Guide](https://www.flowhunt.io/blog/context-engineering/)
- [HN: Is long term AI memory a real problem?](https://news.ycombinator.com/item?id=45937180)
- [HN: Hive Memory](https://news.ycombinator.com/item?id=47207442)
- [Pragmatic Engineer: AI Tooling 2026](https://newsletter.pragmaticengineer.com/p/ai-tooling-2026)
- [Anthropic: Effective Context Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Theanna: What Shipping Product Looks Like](https://theanna.io/building-theanna/vibe-coding-what-actually-shipping-product-looks-like)
- [Snyk: Highs and Lows of Vibe Coding](https://snyk.io/articles/the-highs-and-lows-of-vibe-coding/)
