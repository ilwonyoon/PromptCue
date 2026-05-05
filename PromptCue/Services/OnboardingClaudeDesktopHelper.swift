import Foundation

@MainActor
struct OnboardingClaudeDesktopHelper {
    enum BackupError: Error {
        case notReadable
        case writeFailed(String)
    }

    static func configURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
            .appendingPathComponent("claude_desktop_config.json", isDirectory: false)
    }

    static func currentConfigJSON() -> String? {
        let url = configURL()
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func proposedConfigJSON(currentJSON: String?, backtickEntry: [String: Any]) -> String {
        var root: [String: Any] = [:]
        if let currentJSON,
           let data = currentJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        }

        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers["backtick"] = backtickEntry
        root["mcpServers"] = servers

        guard let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "(unable to serialize)"
        }

        return String(data: data, encoding: .utf8) ?? "(unable to serialize)"
    }

    @discardableResult
    static func writeBackup() throws -> URL? {
        let url = configURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let timestamp = ISO8601DateFormatter.backupFormatter.string(from: Date())
        let backupURL = url.deletingPathExtension()
            .appendingPathExtension("backup-\(timestamp).json")

        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }

        return backupURL
    }

    static func backtickEntryPreview(launchSpec: MCPServerLaunchSpec) -> [String: Any] {
        [
            "command": launchSpec.command,
            "args": launchSpec.arguments,
            "env": launchSpec.environment,
        ]
    }

    /// Build a single shell command that, when run in Terminal, will:
    ///   1. back up the current Claude Desktop config (if any)
    ///   2. add (or update) the `backtick` entry under `mcpServers`
    ///   3. print a one-line confirmation reminding the user to restart Claude
    ///
    /// Uses `python3` because it ships with macOS and gives us safe JSON
    /// merge semantics without depending on jq.
    static func makeTerminalInstallCommand(launchSpec: MCPServerLaunchSpec) -> String {
        let entry = backtickEntryPreview(launchSpec: launchSpec)
        let entryData = (try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])) ?? Data("{}".utf8)
        let entryJSON = String(data: entryData, encoding: .utf8) ?? "{}"
        let escapedEntry = shellSingleQuote(entryJSON)

        let configPath = configURL().path
        let escapedConfigPath = shellSingleQuote(configPath)

        let pythonScript = """
        import json, os, sys
        path = os.path.expanduser($CONFIG_PATH)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = {}
        if os.path.exists(path):
            try:
                with open(path) as f: data = json.load(f) or {}
            except Exception: data = {}
        data.setdefault('mcpServers', {})['backtick'] = json.loads($ENTRY_JSON)
        with open(path, 'w') as f:
            json.dump(data, f, indent=2, sort_keys=True)
        print('✓ Backtick added to Claude Desktop config.')
        print('  Quit Claude Desktop completely (⌘Q) and reopen to activate.')
        """

        let scriptWithSubs = pythonScript
            .replacingOccurrences(of: "$CONFIG_PATH", with: escapedConfigPath)
            .replacingOccurrences(of: "$ENTRY_JSON", with: escapedEntry)

        let backupSegment = "[ -f \(escapedConfigPath) ] && cp \(escapedConfigPath) \"\(configPath).backup-$(date +%Y%m%d-%H%M%S).json\" && echo \"  Backup written.\"; "
        let pythonInvocation = "python3 - <<'PY'\n\(scriptWithSubs)\nPY"

        return backupSegment + pythonInvocation
    }

    private static func shellSingleQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

private extension ISO8601DateFormatter {
    static let backupFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return formatter
    }()
}
