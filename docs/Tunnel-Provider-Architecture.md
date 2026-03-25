# Tunnel Provider Architecture

Design for multi-provider tunnel support in Backtick's Remote MCP feature, replacing the ngrok-only implementation with a provider-agnostic system that supports Cloudflare Named Tunnels (owner) and ngrok/cloudflared Quick Tunnels (general users).

---

## Current State

### Settings Model (MCPConnectorSettingsModel.swift)

- `ExperimentalMCPHTTPSettings` holds: `isEnabled`, `port` (default 8321), `authMode`, `apiKey`, `publicBaseURL`
- Tunnel detection is ngrok-specific: `ExperimentalMCPHTTPNgrokTunnelDetector` polls `http://127.0.0.1:4040/api/tunnels`
- "Launch tunnel" action runs `pkill -f 'ngrok http'; sleep 1; ngrok http <port>` in Terminal
- "Install tunnel" action runs `brew install ngrok && ngrok http <port>`
- `experimentalRemoteTunnelDocumentationURL` hardcoded to `https://ngrok.com/download`
- Public base URL can be manually configured (overrides auto-detection) or auto-detected from ngrok API

### HTTP Server (BacktickMCPHTTPServer.swift)

- Listens on configurable port (default 8321) via NWListener
- Assigns `Mcp-Session-Id` header on every response after `initialize` (line 335: `sessionID = UUID()`)
- `unauthorizedResponse()` already includes `WWW-Authenticate: Bearer` header for both auth modes
- Response Content-Type for MCP POST responses is `application/json` (line 337 `jsonResponse`)
- CORS origin is derived from `publicBaseURL` when set

### Existing Cloudflare Infrastructure

- `cloudflared` installed at `/opt/homebrew/bin/cloudflared`
- Named tunnel `muninn` (ID `37ab5a6a-c63f-49dc-b318-869762866bf7`) already exists
- Credentials file at `~/.cloudflared/37ab5a6a-c63f-49dc-b318-869762866bf7.json`
- Config at `~/.cloudflared/config.yml` routes `muninn.ilwonyoon.com` to `localhost:8000`
- Previous launchd plist at `~/Library/LaunchAgents/disabled/com.cloudflare.muninn-tunnel.plist`
- Domain `ilwonyoon.com` is on Cloudflare (DNS managed)

---

## Part 1: Owner's Cloudflare Named Tunnel Setup

### Goal

Stable, permanent tunnel: `mcp.ilwonyoon.com` -> `localhost:8321`, running as a launchd service that survives reboots. No ngrok dependency.

### 1.1 Update Existing cloudflared Config

The existing `~/.cloudflared/config.yml` already defines the `muninn` tunnel. Add a second hostname entry for the MCP server:

```yaml
tunnel: 37ab5a6a-c63f-49dc-b318-869762866bf7
credentials-file: /Users/ilwonyoon/.cloudflared/37ab5a6a-c63f-49dc-b318-869762866bf7.json

ingress:
  - hostname: muninn.ilwonyoon.com
    service: http://localhost:8000
  - hostname: mcp.ilwonyoon.com
    service: http://localhost:8321
  - service: http_status:404
```

**Alternative (dedicated tunnel):** Create a separate tunnel for isolation. The shared-tunnel approach is simpler and recommended since both services share the same machine.

### 1.2 DNS Record

Add a CNAME record in Cloudflare DNS dashboard (or via CLI):

```bash
cloudflared tunnel route dns muninn mcp.ilwonyoon.com
```

This creates a CNAME: `mcp.ilwonyoon.com` -> `37ab5a6a-c63f-49dc-b318-869762866bf7.cfargotunnel.com`

Cloudflare handles TLS termination automatically. No certificate management needed.

### 1.3 launchd Service

Re-enable and update the existing plist. Save to `~/Library/LaunchAgents/com.cloudflare.muninn-tunnel.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cloudflare.muninn-tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/cloudflared</string>
        <string>tunnel</string>
        <string>run</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/ilwonyoon/.local/share/muninn/cloudflared.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/ilwonyoon/.local/share/muninn/cloudflared.log</string>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
```

Load commands:

```bash
# Move from disabled back to active
cp ~/Library/LaunchAgents/disabled/com.cloudflare.muninn-tunnel.plist \
   ~/Library/LaunchAgents/com.cloudflare.muninn-tunnel.plist

# Ensure log directory exists
mkdir -p ~/.local/share/muninn

# Load the service
launchctl load ~/Library/LaunchAgents/com.cloudflare.muninn-tunnel.plist

# Verify
launchctl list | grep muninn
curl -s https://mcp.ilwonyoon.com/health
```

### 1.4 Backtick Settings Configuration

In Backtick Settings > Remote MCP:
- Set **Public Base URL** to `https://mcp.ilwonyoon.com`
- Auth mode: OAuth (already configured) or API Key
- The tunnel detection polling becomes unnecessary since the URL is manually configured and stable

### 1.5 Verification Checklist

```bash
# 1. Tunnel is running
cloudflared tunnel info muninn

# 2. DNS resolves
dig mcp.ilwonyoon.com CNAME

# 3. Health endpoint reachable
curl -s https://mcp.ilwonyoon.com/health
# Expected: {"status":"ok"}

# 4. MCP endpoint reachable
curl -s https://mcp.ilwonyoon.com/mcp
# Expected: {"name":"backtick-stack-mcp","transport":"streamable-http-foundation","ready":true}

# 5. ChatGPT can connect
# Paste https://mcp.ilwonyoon.com/mcp as the MCP server URL in ChatGPT settings
```

---

## Part 2: Settings Architecture for Tunnel Provider Selection

### 2.1 New Tunnel Provider Enum

```swift
enum TunnelProvider: String, CaseIterable, Identifiable {
    case ngrok
    case cloudflare
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ngrok: return "ngrok"
        case .cloudflare: return "Cloudflare Tunnel"
        case .custom: return "Custom / Manual"
        }
    }

    var installURL: URL {
        switch self {
        case .ngrok: return URL(string: "https://ngrok.com/download")!
        case .cloudflare: return URL(string: "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/")!
        case .custom: return URL(string: "https://github.com/nicepkg/backtick")! // placeholder
        }
    }
}
```

### 2.2 Updated ExperimentalMCPHTTPSettings

```swift
struct ExperimentalMCPHTTPSettings: Equatable {
    static let defaultPort: UInt16 = 8321

    var isEnabled: Bool
    var port: UInt16
    var authMode: ExperimentalMCPHTTPAuthMode
    var apiKey: String
    var publicBaseURL: String
    var tunnelProvider: TunnelProvider  // NEW — default: .ngrok for backward compat
}
```

New UserDefaults key: `Backtick.ExperimentalMCPHTTP.TunnelProvider`

### 2.3 Tunnel Detector Protocol (Already Exists)

The existing `ExperimentalMCPHTTPTunnelDetecting` protocol is provider-agnostic:

```swift
protocol ExperimentalMCPHTTPTunnelDetecting {
    func detectedPublicBaseURL(for port: UInt16) async -> URL?
}
```

Add a Cloudflare implementation:

```swift
struct ExperimentalMCPHTTPCloudflareTunnelDetector: ExperimentalMCPHTTPTunnelDetecting {
    func detectedPublicBaseURL(for port: UInt16) async -> URL? {
        // cloudflared Quick Tunnel exposes a metrics endpoint at localhost:33843
        // For Named Tunnels, detection is unnecessary (URL is stable and configured)
        // For Quick Tunnels: parse cloudflared stdout for the trycloudflare.com URL
        // Return nil — Named Tunnel users configure the URL manually
        return nil
    }
}
```

### 2.4 Compound Tunnel Detector

Route detection to the correct provider:

```swift
struct ExperimentalMCPHTTPCompoundTunnelDetector: ExperimentalMCPHTTPTunnelDetecting {
    let provider: TunnelProvider
    private let ngrokDetector = ExperimentalMCPHTTPNgrokTunnelDetector()
    private let cloudflareDetector = ExperimentalMCPHTTPCloudflareTunnelDetector()

    func detectedPublicBaseURL(for port: UInt16) async -> URL? {
        switch provider {
        case .ngrok:
            return await ngrokDetector.detectedPublicBaseURL(for: port)
        case .cloudflare:
            return await cloudflareDetector.detectedPublicBaseURL(for: port)
        case .custom:
            return nil  // Manual URL entry only
        }
    }
}
```

### 2.5 Behavior Changes Per Provider

| Behavior | ngrok | cloudflare | custom |
|----------|-------|------------|--------|
| "Launch tunnel" button label | "Launch ngrok" | "Launch cloudflared" | Hidden |
| "Install tunnel" button label | "Install ngrok" | "Install cloudflared" | Hidden |
| Launch command | `ngrok http <port>` | `cloudflared tunnel --url http://localhost:<port>` | N/A |
| Install command | `brew install ngrok` | `brew install cloudflared` | N/A |
| Auto-detect URL | Yes (ngrok API at :4040) | No (manual for Named; parse stdout for Quick) | No |
| Documentation URL | ngrok.com/download | cloudflare tunnel docs | N/A |
| Public Base URL field | Optional (auto-detected) | Required (Named) or auto (Quick) | Required |
| Tunnel guidance text | "Install ngrok, run..." | "Run cloudflared tunnel..." | "Paste your tunnel URL" |

### 2.6 Action Handler Updates

```swift
func performExperimentalRemoteStatusAction(_ action: ExperimentalMCPHTTPStatusAction) {
    switch action {
    case .launchTunnel:
        switch experimentalRemoteSettings.tunnelProvider {
        case .ngrok:
            launchNgrokTunnel()
        case .cloudflare:
            launchCloudflareTunnel()
        case .custom:
            break  // No launch action for custom
        }
    case .installTunnel:
        switch experimentalRemoteSettings.tunnelProvider {
        case .ngrok:
            _ = terminalLauncher.launchInTerminal(
                command: "brew install ngrok && ngrok http \(experimentalRemoteSettings.port)"
            )
        case .cloudflare:
            _ = terminalLauncher.launchInTerminal(
                command: "brew install cloudflared && cloudflared tunnel --url http://localhost:\(experimentalRemoteSettings.port)"
            )
        case .custom:
            break
        }
    // ... rest unchanged
    }
}

private func launchCloudflareTunnel() {
    let port = experimentalRemoteSettings.port
    _ = terminalLauncher.launchInTerminal(
        command: "cloudflared tunnel --url http://localhost:\(port)"
    )
}
```

### 2.7 ExperimentalMCPHTTPStatusAction Updates

```swift
enum ExperimentalMCPHTTPStatusAction: Equatable {
    case launchTunnel
    case installTunnel
    case copyPublicMCPURL
    case resetLocalState
    case retry

    // Title becomes provider-aware via the settings model, not the enum itself.
    // The view layer reads the tunnelProvider to pick the right label.
}
```

The `title` computed property on `ExperimentalMCPHTTPStatusAction` currently hardcodes "Launch ngrok" / "Install ngrok". This should be moved to the view or the settings model should provide a `tunnelActionTitle(for:)` method:

```swift
func tunnelActionTitle(for action: ExperimentalMCPHTTPStatusAction) -> String {
    switch action {
    case .launchTunnel:
        switch experimentalRemoteSettings.tunnelProvider {
        case .ngrok: return "Launch ngrok"
        case .cloudflare: return "Launch cloudflared"
        case .custom: return "Launch Tunnel"
        }
    case .installTunnel:
        switch experimentalRemoteSettings.tunnelProvider {
        case .ngrok: return "Install ngrok"
        case .cloudflare: return "Install cloudflared"
        case .custom: return "Install Tunnel"
        }
    // ... rest unchanged
    }
}
```

### 2.8 MCPConnectorInspector Changes

Add `cloudflaredPath` alongside existing `ngrokPath`:

```swift
struct MCPConnectorInspection {
    let repositoryRootPath: String?
    let bundledHelperPath: String?
    let launchSpec: MCPServerLaunchSpec?
    let ngrokPath: String?
    let cloudflaredPath: String?  // NEW
    let clients: [MCPConnectorClientStatus]
}
```

In `inspect()`:

```swift
return MCPConnectorInspection(
    // ...existing fields...
    ngrokPath: locateExecutable(named: "ngrok"),
    cloudflaredPath: locateExecutable(named: "cloudflared"),
    // ...
)
```

The `experimentalRemoteRecommendedTunnelPath` property should then route based on provider:

```swift
var experimentalRemoteRecommendedTunnelPath: String? {
    switch experimentalRemoteSettings.tunnelProvider {
    case .ngrok: return inspection.ngrokPath
    case .cloudflare: return inspection.cloudflaredPath
    case .custom: return nil
    }
}
```

---

## Part 3: Stateless MCP Improvements

### 3.1 Session ID Assignment

**Current:** `BacktickMCPServerSession.initializeResult()` assigns `sessionID = UUID()` on every `initialize` call (line 335). The HTTP handler then echoes it in `Mcp-Session-Id` response headers.

**Issue:** For a stateless server (no SSE, no session resumption), assigning a session ID creates client expectations of statefulness. ChatGPT may try to maintain session affinity.

**Change:** Remove session ID assignment from `initializeResult()`:

```swift
// In BacktickMCPServerSession.initializeResult()
// DELETE: sessionID = UUID().uuidString.lowercased()
// The sessionID property remains for use by tool calls that pass sessionID as a parameter
// (e.g., markNotesExecuted, groupNotes), but those are domain-level session IDs,
// not MCP transport session IDs.
```

**Also remove from HTTP handler responses** (lines 311-312, 333-334):
- Remove `if let sessionID = await session.sessionID { ... Mcp-Session-Id ... }` blocks
- Remove `Mcp-Session-Id` from `Access-Control-Expose-Headers`

**Risk:** Low. The server is already stateless in practice (no SSE subscriptions, no session resumption). Removing the header makes the contract explicit.

**Note on domain-level sessionID:** The `sessionID` field on `BacktickMCPConnectionActivity` and tool parameters like `markNotesExecuted(sessionID:)` are unrelated to MCP transport sessions. Those are domain concepts (tracking which copy/execution session triggered an action) and remain unchanged.

### 3.2 WWW-Authenticate Header

**Current:** Already present. `unauthorizedResponse()` returns `WWW-Authenticate: Bearer` for API key mode and `WWW-Authenticate: Bearer resource_metadata="..."` for OAuth mode. No changes needed.

### 3.3 Response Content-Type

**Current:** MCP POST responses use `jsonResponse()` which sets `Content-Type: application/json`. This is correct for the Streamable HTTP transport (non-SSE responses).

**Verify:** The 202 Accepted response for notifications (line 314-319) returns no Content-Type since the body is empty. This is acceptable per HTTP semantics. No changes needed.

---

## Part 4: Implementation Phases

### Phase 1: Owner's Cloudflare Setup + Stateless MCP (Immediate)

**Scope:** Manual setup (scripts/commands) + small code changes. No UI changes.

| Task | Type | Files |
|------|------|-------|
| 1a. Update `~/.cloudflared/config.yml` to add `mcp.ilwonyoon.com` ingress | Manual | `~/.cloudflared/config.yml` |
| 1b. Add DNS CNAME via `cloudflared tunnel route dns` | Manual CLI | None |
| 1c. Move plist from disabled to active, load via launchctl | Manual CLI | `~/Library/LaunchAgents/` |
| 1d. Set Public Base URL to `https://mcp.ilwonyoon.com` in Backtick Settings | Manual UI | None |
| 1e. Remove `sessionID = UUID()` from `initializeResult()` | Code | `BacktickMCPServerSession.swift` |
| 1f. Remove `Mcp-Session-Id` header emission from HTTP handler | Code | `BacktickMCPHTTPServer.swift` |
| 1g. Remove `Mcp-Session-Id` from `Access-Control-Expose-Headers` | Code | `BacktickMCPHTTPServer.swift` |
| 1h. Verify end-to-end: health, MCP init, ChatGPT connection | Manual | None |

**Estimated effort:** 1-2 hours (mostly verification and DNS propagation).

**Commit strategy:**
- Commit 1: `fix: remove MCP transport session ID from stateless HTTP responses`
- Manual steps are not committed (infrastructure config).

### Phase 2: Settings UI for Tunnel Provider (Near-term)

**Scope:** Add `tunnelProvider` to settings, update action handlers, add Cloudflare tunnel detector.

| Task | Type | Files |
|------|------|-------|
| 2a. Add `TunnelProvider` enum | Code | New or in `MCPConnectorSettingsModel.swift` |
| 2b. Add `tunnelProvider` to `ExperimentalMCPHTTPSettings` | Code | `MCPConnectorSettingsModel.swift` |
| 2c. Add UserDefaults persistence for `tunnelProvider` | Code | `MCPConnectorSettingsModel.swift` |
| 2d. Add `cloudflaredPath` to `MCPConnectorInspection` | Code | `MCPConnectorSettingsModel.swift` |
| 2e. Create `ExperimentalMCPHTTPCloudflareTunnelDetector` | Code | `MCPConnectorSettingsModel.swift` |
| 2f. Create `ExperimentalMCPHTTPCompoundTunnelDetector` | Code | `MCPConnectorSettingsModel.swift` |
| 2g. Update `performExperimentalRemoteStatusAction` for provider routing | Code | `MCPConnectorSettingsModel.swift` |
| 2h. Update action titles to be provider-aware | Code | `MCPConnectorSettingsModel.swift` |
| 2i. Update recommended tunnel path/command/summary for provider | Code | `MCPConnectorSettingsModel.swift` |
| 2j. Add tunnel provider picker to Settings UI | Code | `PromptCueSettingsView.swift` |
| 2k. Update tests for new settings field | Code | Tests |

**Estimated effort:** 3-4 hours.

**Commit strategy:**
- Commit 1: `feat: add TunnelProvider enum and settings persistence`
- Commit 2: `feat: add Cloudflare tunnel detector and compound detector`
- Commit 3: `feat: update tunnel launch actions for provider selection`
- Commit 4: `feat: add tunnel provider picker to Settings UI`

### Phase 3: General User cloudflared Support (Future)

**Scope:** Polish cloudflared Quick Tunnel UX, auto-detection, documentation.

| Task | Type | Files |
|------|------|-------|
| 3a. Implement Quick Tunnel stdout parsing for auto URL detection | Code | `MCPConnectorSettingsModel.swift` |
| 3b. Add in-app guidance text for cloudflared Quick Tunnel setup | Code | Settings view |
| 3c. Handle Quick Tunnel URL rotation (trycloudflare.com URLs change) | Code | Tunnel detector |
| 3d. Add "Which tunnel should I use?" help section | Code | Settings view |
| 3e. Documentation for general users | Docs | `docs/Remote-MCP-Setup.md` |

**Estimated effort:** 4-6 hours.

**Note on Quick Tunnels:** `cloudflared tunnel --url http://localhost:8321` creates a temporary `*.trycloudflare.com` URL (similar to ngrok free tier). This URL changes on every restart. For general users, this is comparable to ngrok but without the SSE buffering issues.

---

## Migration Notes

### Backward Compatibility

- Default `tunnelProvider` is `.ngrok` -- existing users see no change
- The `publicBaseURL` field continues to work as before (manually entered URL overrides auto-detection)
- ngrok auto-detection remains the default behavior until the user switches providers

### Data Migration

No data migration needed. The new `tunnelProvider` UserDefaults key defaults to `.ngrok` when absent. All existing settings are preserved.

---

## Open Questions

1. **Shared vs dedicated tunnel for owner?** The design above reuses the existing `muninn` tunnel (shared with other services on the same machine). A dedicated tunnel provides isolation but adds management overhead. Recommendation: shared tunnel, since both services are on the same machine and the ingress rules provide clear routing.

2. **Quick Tunnel URL detection for cloudflared?** Unlike ngrok (which exposes a local API at :4040), cloudflared Quick Tunnels print the URL to stdout. Detection requires either parsing process output or querying the cloudflared metrics endpoint. This is Phase 3 work.

3. **Should the Settings UI show provider-specific instructions inline?** The current design shows "Install ngrok" / "Launch ngrok" buttons. With multiple providers, the guidance text should adapt. The `experimentalRemoteRecommendedTunnelSummary` computed property already provides this -- it just needs provider-aware variants.
