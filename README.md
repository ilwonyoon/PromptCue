<h1 align="center">Backtick</h1>
<p align="center">A macOS scratchpad for developers who think faster than their AI can code</p>

<p align="center">
  <a href="https://github.com/ilwonyoon/Backtick/releases/latest/download/Backtick.dmg">
    <img src="./docs/assets/download_for_mac_lg.png" alt="Download Backtick for macOS" width="200" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0+-555?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Free_during_beta-555" alt="Free during beta" />
  <a href="https://github.com/ilwonyoon/Backtick/releases/latest"><img src="https://img.shields.io/github/v/release/ilwonyoon/Backtick?label=latest" alt="Latest release" /></a>
</p>

<p align="center">
  <img src="./docs/assets/hero.png" alt="Backtick screenshot" width="900" />
</p>

---

Your AI is building. Your brain won't stop. **Now both can keep going.**

Backtick is a native macOS menu-bar utility for capturing thoughts while AI agents work. Capture what you notice now, stage it for action, then let it disappear.

> *The bottleneck isn't speed — it's that your thoughts have `nowhere to go`.*

## Features

<table>
<tr>
<td width="40%" valign="middle">
<h3>Capture</h3>
<code>Cmd + `</code> — type — enter. Done.<br><br>
A thought hits while your AI is mid-task. Two seconds later, it's captured. You never left.
</td>
<td width="60%">
<img src="./docs/assets/capture.gif" alt="Capture demo" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Stack</h3>
Three thoughts. One prompt.<br><br>
Select. Combine. Send. Your AI gets everything it needs to get it right the first time.
</td>
<td width="60%">
<img src="./docs/assets/stack.png" alt="Stack demo" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>MCP</h3>
Your AI reads your stack.<br><br>
Connect Backtick to Claude Code or Codex — your AI reads your notes, checks your repo, and recommends what to work on next.
</td>
<td width="60%">
<img src="./docs/assets/mcp.png" alt="MCP integration" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Memory</h3>
Long conversations become project knowledge.<br><br>
Backtick distills hours-long AI discussions into reviewed project documents with topic classification — not raw transcripts.
</td>
<td width="60%">
<img src="./docs/assets/memory.png" alt="Memory" width="100%" />
</td>
</tr>
</table>

- **Ephemeral by design** — Capture now. Act today. Forget tomorrow. Old notes auto-expire so the stack stays focused.
- **Native macOS** — Built with Swift and AppKit. Menu-bar utility, floating panels, global hotkeys. Not Electron.
- **MCP-connected** — Works with Claude Desktop, Claude Code, and Codex out of the box. Experimental ChatGPT support.
- **Screenshot attach** — Auto-detects recent screenshots from your approved folder. One less context switch.
- **Clipboard-first export** — Select cards, combine, copy. Paste into your next prompt.
- **iCloud sync** — Sync cards across Macs. Screenshots stay local.

## Install

### DMG (recommended)

<a href="https://github.com/ilwonyoon/Backtick/releases/latest/download/Backtick.dmg">
  <img src="./docs/assets/download_for_mac_lg.png" alt="Download Backtick for macOS" width="200" />
</a>

Download, open the DMG, drag to Applications. Requires macOS 14.0+.

### Build from source

```bash
# Prerequisites: Xcode 16+, XcodeGen
xcodegen generate
xcodebuild -project PromptCue.xcodeproj -scheme PromptCue -configuration Debug build
```

## MCP Setup

Backtick exposes your stack to AI clients via [Model Context Protocol](https://modelcontextprotocol.io/).

### Claude Code

```bash
claude mcp add backtick -- \
  "/Applications/Backtick.app/Contents/Helpers/BacktickMCP"
```

### Codex

Add to `~/.codex/config.json`:

```json
{
  "mcpServers": {
    "backtick": {
      "command": "/Applications/Backtick.app/Contents/Helpers/BacktickMCP"
    }
  }
}
```

Open Backtick Settings > Connectors to verify the connection.

## How it works

```
  Cmd+`          Cmd+2          Copy / MCP
    |              |              |
 Capture  --->   Stack   --->  Export
 (dump)        (review)       (action)
    |                            |
    '--- auto-expire after 8h --'
```

1. **Capture** — Global hotkey opens a floating panel. Type your thought. Press Enter. Gone.
2. **Stack** — Review your captures. Select what matters. Combine into one clipboard payload.
3. **Export** — Paste into your AI prompt, or let Claude Code / Codex read your stack directly via MCP.

## License

[MIT](LICENSE)

## Links

<a href="https://github.com/ilwonyoon/Backtick"><img src="https://img.shields.io/badge/GitHub-555?logo=github" alt="GitHub" /></a>
