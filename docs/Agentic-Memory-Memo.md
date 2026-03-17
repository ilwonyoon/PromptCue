# The Agentic Memory Memo

**March 2026**

---

## The Problem

Today, every AI conversation starts from zero.

You open Claude, explain your project, make decisions, close the tab. Tomorrow you open ChatGPT, explain it all again. Switch to Codex, start over. The AI that helped you think through pricing yesterday doesn't remember you today.

This isn't a technology problem. GPT, Claude, Gemini — they all have memory features. The problem is that **memory is trapped inside each platform**.

Your Claude memory doesn't know what you told ChatGPT. Your Cursor context doesn't carry over to Codex. And none of them know what you decided in last week's Granola meeting notes.

The more AI tools people use — and 70% of builders already use 2-4 simultaneously — the worse this gets. Every new thread is a blank slate. Every platform switch is a factory reset on your context.

200+ hours per year. That's what power users lose rebuilding context across platforms.

---

## The Shift

Something changed in the last 12 months.

MCP (Model Context Protocol) became the interop standard. Claude, ChatGPT, Cursor, Codex — they all speak it now. For the first time, a local app on your Mac can serve context to every AI tool you use, through a single protocol.

This means the memory layer doesn't have to live inside any one AI platform. It can sit outside, on your machine, and feed into all of them.

This is the shift: **memory moves from platform-locked to user-owned**.

---

## Why Now

Three things are happening simultaneously:

**1. Everyone already pays for the AI.**

850 million people use ChatGPT. Claude crossed 100M weekly users. Most power users have $20/month subscriptions to at least one, often two. They already have the intelligence — what they're missing is the continuity.

**2. MCP made cross-platform delivery possible.**

Before MCP, connecting a local memory store to multiple AI clients required custom integrations for each one. Now, one MCP server can serve Claude Desktop, Claude Code, Codex, and ChatGPT (Mac) with the same protocol. stdio for CLI tools, HTTP localhost for desktop apps.

**3. Platform memory is necessary but insufficient.**

Claude has CLAUDE.md. ChatGPT has auto-detected memories. Both are useful within their own walls. Neither solves the cross-platform problem. And neither gives users control over what gets remembered — it's either opaque (ChatGPT) or monolithic (Claude's single file).

The #QuitGPT movement — 295% spike in ChatGPT uninstalls in a single day — revealed that context lock-in is the real switching cost. People don't want to lose what they've taught their AI.

---

## What We're Building

**Backtick** is the memory layer that works across every AI tool you already use.

Two places, two types of information:

| | Stack | Memory |
|---|---|---|
| What | Today's prompts | Project knowledge |
| Lifecycle | Use and discard (8hr TTL) | Persists across sessions |
| Content | Raw thoughts, instructions | Decisions, context, docs |
| How it works | You capture it | AI saves it (you verify) |

> **Stack for today. Memory for everything else.**

The user captures a thought in Stack (Cmd+\`). Uses it in their current AI session. When meaningful decisions emerge from a conversation, the AI saves a structured summary to Memory via MCP. Next time — in any AI tool, any thread — that context is already there.

### The Architecture That Already Exists

Backtick ships as a macOS menu bar utility. Always running, zero friction.

**Stack (built and shipped):**
- Capture prompts with global hotkey (Cmd+\`)
- Organize in an execution queue
- AI compression built in
- MCP server exposes full CRUD to any connected AI client
- Execution tracking: who used what, when, how (user vs agent)
- Cross-platform: verified with Claude Code, Codex, Claude Desktop

**Memory (designed, ready to build):**
- Project × Topic document structure
- AI saves structured summaries via MCP tools (save/recall/update/search)
- Human review loop: AI proposes, user verifies
- FTS5 full-text search across all documents
- Partial updates (append section, replace section) — not full-document rewrites

### How It Actually Works

```
Monday, ChatGPT:
  "Let's go freemium. Free tier gets 5 projects, premium gets
   unlimited memory and HTTP connections. $9/month."
  → AI saves to Memory: backtick/pricing

Wednesday, Claude Code:
  → AI recalls backtick/pricing automatically
  → "I see you decided on freemium with $9/mo premium.
     Want me to implement the paywall logic?"
  → Continues where Monday left off

Friday, Codex:
  → AI recalls backtick/pricing + backtick/architecture
  → Has full context without any re-explanation
```

No copy-paste. No "let me re-explain my project." No context loss.

---

## Why This Is Different

### vs. Platform-Native Memory (Claude Memory, ChatGPT Memory)

They remember within their walls. Backtick remembers across walls. Complementary, not competitive — Backtick makes platform memory better by feeding it cross-platform context.

### vs. Mem0 ($24M raised, developer infrastructure)

Mem0 is an SDK for developers building AI apps. `pip install mem0ai`, call `memory.add()` in your code. The AI extracts facts automatically. Powerful infrastructure — wrong market.

Backtick is for the person using AI, not building AI. There's no SDK, no API key, no code. You capture a thought, the AI remembers it across tools.

The critical difference:

| | Mem0 | Backtick |
|---|---|---|
| Who | Developers building AI apps | People using AI tools |
| Input | Code: `memory.add(messages)` | Human: capture or AI: save via MCP |
| Intelligence | Runs its own LLM ($) | Uses the AI you already pay for |
| Output | API response to developer's app | Context in your next Claude/GPT thread |
| Cost model | Usage-based ($19-249/mo) | One-time or flat subscription |

**Key insight: Backtick doesn't need its own LLM.** The user's Claude subscription, ChatGPT subscription — that's the intelligence layer. Backtick is the persistence layer. The AI extracts and saves facts through MCP tool calls, using the model the user already pays for.

This is not a limitation. This is the architecture. Why charge for AI inference when the user has already bought it?

### vs. Screenpipe (passive capture, open-source Rewind)

Screenpipe captures everything — screen recordings, audio, OCR. Backtick captures what you intend to act on. "Capture everything" and "capture what matters" are complementary strategies.

### vs. Granola ($43M raised, meeting memory)

Granola owns the meeting. Backtick owns the AI conversation. Different input, same insight: structured memory matters more than raw transcripts.

---

## The Moat

### 1. Data gravity

Every prompt captured, every decision saved, every project documented — it accumulates. After 3 months of use, Backtick knows more about your projects than any single AI platform does. Switching cost grows with usage, organically.

### 2. Cross-platform network effect

The more AI tools that connect via MCP, the more valuable Backtick becomes. Using Claude + ChatGPT? Backtick bridges them. Add Codex? Automatic. This isn't a feature of any single AI platform — it's a property of the layer between them.

### 3. Human-curated quality

Mem0 auto-extracts facts. ChatGPT auto-detects memories. Both are noisy. Backtick's Memory has a human review loop — AI proposes what to save, user verifies. This produces higher-quality context than any fully automated system. The AI that recalls human-verified facts is more useful than one recalling auto-detected guesses.

### 4. The queue metaphor

Stack isn't a note archive. It's an execution queue with TTL. Prompts expire. This is anti-hoarding, pro-action. No other tool has this interaction model. It keeps the system clean and the user focused.

---

## The Market

### Who uses this

People who build with AI but aren't infrastructure engineers. The vibe-coding solopreneur. The product manager using Claude for specs and ChatGPT for research. The founder who discusses strategy across three AI tools in a week.

| | |
|---|---|
| Multi-tool usage | 70% use 2-4 AI tools |
| AI code generation | 84% of developers using AI tools (2026) |
| Context engineering | The #1 most important solo founder skill in 2026 |
| Revenue examples | Pieter Levels: $138K/mo, Marc Lou: $1M/yr — all built with multi-AI workflows |

25% of YC W25 batch built startups with 95%+ AI-generated codebases. These builders live in AI tools all day. Their context is their competitive advantage — and right now, they lose it every time they open a new thread.

### Market size

Anyone who pays for an AI subscription and uses more than one AI tool. That's tens of millions today, hundreds of millions within 3 years.

---

## The Landscape

The "AI memory" space has five tiers, and we're positioned in the gap between them:

| Tier | Players | Gap |
|---|---|---|
| Platform memory | Claude, ChatGPT | Locked to one platform |
| Developer infra | Mem0 ($24M), Zep | Requires code to use |
| Consumer memory | Screenpipe, Granola | Single-modality (screen/meetings) |
| PKM + AI | Obsidian plugins, Khoj | Complex setup, not MCP-native |
| IDE memory | Cursor, Windsurf | IDE-only, no cross-tool |

No one is building: **intentional capture → execution queue → cross-platform MCP delivery → persistent project memory**.

That's the gap. That's Backtick.

---

## What's Next

### Phase 1: Ship Memory (Q2 2026)

- `Project × Topic` document model in PromptCueCore
- 7 new MCP tools (save/recall/update/list/delete/search/manage)
- Memory panel (Cmd+3) with project list → topic chips → document viewer
- Proactive AI behavior via tool descriptions ("recall when user mentions project")
- Human review loop in Memory panel
- Zero changes to existing Capture or Stack

### Phase 2: Cross-Platform Reach (Q3 2026)

- HTTP transport for ChatGPT Mac App (localhost, no tunnel)
- One-click setup for Claude Desktop, Claude Code, Codex
- Bearer token auth for HTTP connections
- Connection status in Settings

### Phase 3: Intelligence Layer (Q4 2026)

- FTS5 search across all documents
- Two-tier retrieval: summaries by default, full content on demand
- Automated Stack → Memory promotion (expired prompts offered for save)
- Immutable fact history with supersession (never delete, always version)

### Future: If Backtick's curated memory proves valuable enough

- Memory API for other apps to consume human-curated context
- Mem0 or equivalent as optional backend for semantic search
- Team/org memory sharing

---

## The Bet

Within the next 3 years, cross-session, cross-platform memory will be as essential to AI workflows as the clipboard is to desktop computing.

The clipboard lets you move text between apps. Backtick lets you move context between AIs.

Every AI platform will have its own memory. None of them will share it. The layer that bridges them — local-first, user-owned, human-curated — is what we're building.

**Stack for today. Memory for everything else.**

---

*Backtick is built by a solo founder in Seoul. The app is a native macOS utility (SwiftUI + AppKit), with MCP transport already verified across Claude Code, Codex, and Claude Desktop. Stack is shipped. Memory is next.*
