# MCP Platform Expansion & Information Temperature Architecture

Research doc — 2026-03-15

## Part 1: MCP Platform Expansion

### Current State

BacktickMCP is a **stdio-only** JSON-RPC 2.0 server bundled into the app at `Contents/Helpers/BacktickMCP`. It exposes 8 tools (list/get/create/update/delete/mark_executed/classify/group notes) and 4 prompt templates.

**Supported clients today:**

| Client | Transport | Status |
|--------|-----------|--------|
| Claude Code (CLI) | stdio | Supported |
| Codex (OpenAI CLI) | stdio | Supported |

### Target Platforms

| Platform | Transport Required | Feasibility |
|----------|-------------------|-------------|
| **Claude Desktop (Mac)** | stdio | Trivial — same transport, just needs `claude_desktop_config.json` registration |
| **Claude Web / Mobile** | Remote MCP (HTTP/SSE) | Requires new transport layer + auth |
| **ChatGPT Desktop** | N/A | OpenAI does not support MCP client natively (as of 2026-03) |
| **ChatGPT Web** | N/A | No MCP support |
| **ChatGPT via Codex CLI** | stdio | Already works |

### Expansion Plan

#### Phase 1: Claude Desktop (Low effort)

Claude Desktop reads `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "backtick": {
      "command": "/Applications/Backtick.app/Contents/Helpers/BacktickMCP",
      "args": []
    }
  }
}
```

**Work needed:**
- Add Claude Desktop detection in `MCPConnectorInspector` (check for `~/Library/Application Support/Claude/` directory)
- Generate config snippet for `claude_desktop_config.json`
- Add one-click setup button in Settings > MCP Connector
- Validate that the bundled helper path is stable across app updates

#### Phase 2: Remote MCP (HTTP Transport) for Claude Web/Mobile

Claude Pro/Max/Team/Enterprise users can connect to remote MCP servers via HTTP+SSE or Streamable HTTP.

**Architecture decision: Local server + tunnel vs. Cloud deployment**

Recommended: **Dual transport mode** on the local server.

```
BacktickMCP --transport stdio          # existing (Claude Code, Codex, Claude Desktop)
BacktickMCP --transport http --port 8321  # new (Claude Web via tunnel)
```

**Work needed:**
1. Add lightweight HTTP server to BacktickMCP (Swift NIO or built-in `HTTPServer`)
2. Implement MCP SSE endpoint (`/sse` for connection, `/message` for requests)
3. Add authentication (API key or token-based)
4. Document tunnel setup (Cloudflare Tunnel / ngrok)
5. Settings UI: "Enable Remote Access" toggle with generated auth token

**Considerations:**
- Mac must be running for remote access to work
- Security: auth token + localhost binding + optional tunnel
- SQLite concurrent access: current GRDB setup supports WAL mode for multi-reader

#### Phase 3: ChatGPT Integration (Alternative path)

Since ChatGPT doesn't support MCP natively:

**Option A: GPT Actions (Custom GPT)**
- Expose a REST API from BacktickMCP HTTP mode
- Register as a Custom GPT Action with OpenAPI spec
- Requires tunnel for external access

**Option B: Wait for OpenAI MCP support**
- OpenAI has shown interest in MCP compatibility
- Codex CLI already supports MCP

**Recommendation:** Phase 2's HTTP transport naturally enables Option A. Build HTTP first, then add OpenAPI spec generation as a follow-up.

---

## Part 2: Information Temperature Architecture

### Problem

Backtick is optimized for **Hot** information (today's tasks, 8h TTL). But AI workflows produce information at three temperature levels that all need a home:

| Temperature | Lifespan | Examples | Current Support |
|-------------|----------|----------|----------------|
| **Hot** | Hours | "Fix this API", "Run these tests" | Stack (exists) |
| **Warm** | Days–Weeks | Refactoring plan from Claude conversation, sprint notes | None |
| **Cold** | Permanent | Architecture docs, recurring prompts, reference material | None |

### Decision: Integrated in Backtick

All three tiers live in Backtick, accessible through the same MCP server.

### Proposed Data Model Changes

#### CaptureCard gets a `tier` field:

```swift
public enum CardTier: String, Codable, Sendable {
    case hot    // default, current behavior
    case warm   // days-to-weeks, manual expiry
    case cold   // permanent, reference
}
```

**Database migration:**
```sql
ALTER TABLE cards ADD COLUMN tier TEXT NOT NULL DEFAULT 'hot';
```

**TTL behavior by tier:**

| Tier | TTL | Auto-expire | Sorting |
|------|-----|-------------|---------|
| Hot | 8h (configurable) | Yes (if enabled) | By sortOrder/created |
| Warm | None (manual archive/delete) | No | By last modified |
| Cold | Never | No | By title/category |

#### MCP Tool Changes

**`create_note` gains a `tier` parameter:**
```json
{
  "name": "create_note",
  "inputSchema": {
    "properties": {
      "text": { "type": "string" },
      "tier": { "type": "string", "enum": ["hot", "warm", "cold"], "default": "hot" },
      "tags": { "type": "array" }
    }
  }
}
```

**New tool: `promote_note`**
Move a note between tiers (e.g., hot → warm when a conversation summary is worth keeping longer).

**`list_notes` gains `tier` filter:**
```json
{ "scope": "active", "tier": "warm" }
```

### UX Integration

The Stack panel currently has two sections: Active / Copied.

**Proposed navigation:**

```
Stack (default view — Hot tier)
├── Active
└── Copied

Library (new view — Warm + Cold)
├── Warm: Recent documents (collapsible by week)
└── Cold: Pinned references (collapsible by tag/category)
```

**Key UX principles:**
1. Stack remains "오늘 할 것" — zero friction, no change
2. Library is a second panel/tab, not clutter in Stack
3. AI auto-saves to warm/cold via MCP `create_note` with `tier` param
4. Promote button: Hot → Warm (or drag)
5. Cold items can be "pulled" into Hot as copies when needed

### MCP-Driven AI Workflow

```
Claude/ChatGPT conversation
    │
    ├── AI calls create_note(tier: "hot", text: "Run migration script")
    │   └── Appears in Stack immediately
    │
    ├── AI calls create_note(tier: "warm", text: "<conversation summary>", tags: ["#refactor", "#auth"])
    │   └── Appears in Library > Warm
    │
    └── AI calls create_note(tier: "cold", text: "<architecture decision record>", tags: ["#adr"])
        └── Appears in Library > Cold (permanent)
```

### Information Flow Between Tiers

```
Hot ──promote──→ Warm ──promote──→ Cold
 ↑                                  │
 └────── pull (creates copy) ───────┘
```

- **Promote**: Move up in permanence (removes TTL)
- **Pull**: Copy cold reference into hot for today's use
- **Demote**: Not needed — hot items naturally expire

---

## Implementation Priority

| # | Task | Effort | Dependencies |
|---|------|--------|-------------|
| 1 | Claude Desktop stdio registration in Settings | Small | None |
| 2 | `CardTier` model + migration | Small | None |
| 3 | MCP tools: `tier` param on create/list, `promote_note` | Medium | #2 |
| 4 | Library panel UI (Warm + Cold sections) | Medium | #2 |
| 5 | HTTP transport for BacktickMCP | Large | None |
| 6 | Auth + tunnel documentation | Medium | #5 |
| 7 | OpenAPI spec for ChatGPT Actions | Medium | #5 |

Tasks 1-4 can ship together as a first release. Task 5-7 is a separate track.
