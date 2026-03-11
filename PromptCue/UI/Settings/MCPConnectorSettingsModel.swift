import AppKit
import Foundation

enum MCPConnectorClient: String, CaseIterable, Identifiable {
    case claudeCode
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    var documentationURL: URL {
        switch self {
        case .claudeCode:
            return URL(string: "https://docs.anthropic.com/en/docs/claude-code/mcp")!
        case .codex:
            return URL(string: "https://platform.openai.com/docs/codex/cli#model-context-protocol-mcp")!
        }
    }

    var executableName: String {
        switch self {
        case .claudeCode:
            return "claude"
        case .codex:
            return "codex"
        }
    }

    var homeConfigRelativePath: String {
        switch self {
        case .claudeCode:
            return ".claude.json"
        case .codex:
            return ".codex/config.toml"
        }
    }

    var projectConfigRelativePath: String {
        switch self {
        case .claudeCode:
            return ".mcp.json"
        case .codex:
            return ".codex/config.toml"
        }
    }
}

enum MCPConnectorConfigPresence: Equatable {
    case configured
    case presentWithoutBacktick
    case missing

    var title: String {
        switch self {
        case .configured:
            return "Configured"
        case .presentWithoutBacktick:
            return "Present, Backtick missing"
        case .missing:
            return "Not found"
        }
    }
}

struct MCPConnectorConfigLocationStatus: Equatable {
    let path: String
    let presence: MCPConnectorConfigPresence
}

struct MCPServerLaunchSpec: Equatable {
    let command: String
    let arguments: [String]

    var commandLine: String {
        ([command] + arguments).map(shellEscaped).joined(separator: " ")
    }

    private func shellEscaped(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || value.contains("\"") else {
            return value
        }

        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

struct MCPConnectorClientStatus: Equatable {
    let client: MCPConnectorClient
    let cliPath: String?
    let projectConfig: MCPConnectorConfigLocationStatus?
    let homeConfig: MCPConnectorConfigLocationStatus
    let addCommand: String?
    let configSnippet: String?

    var configurationSummary: String {
        let configuredScopes = [
            projectConfig?.presence == .configured ? "Project" : nil,
            homeConfig.presence == .configured ? "Home" : nil,
        ].compactMap { $0 }

        if !configuredScopes.isEmpty {
            return configuredScopes.joined(separator: " + ")
        }

        if projectConfig?.presence == .presentWithoutBacktick || homeConfig.presence == .presentWithoutBacktick {
            return "Config file present, Backtick missing"
        }

        return "Not configured"
    }

    var cliStatusText: String {
        cliPath ?? "Not detected"
    }
}

struct MCPConnectorInspection: Equatable {
    let repositoryRootPath: String?
    let launchSpec: MCPServerLaunchSpec?
    let clients: [MCPConnectorClientStatus]

    func status(for client: MCPConnectorClient) -> MCPConnectorClientStatus {
        clients.first(where: { $0.client == client })!
    }
}

struct MCPConnectorInspector {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectoryURL: URL
    private let repositoryRootURL: URL?

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        repositoryRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectoryURL = homeDirectoryURL
        self.repositoryRootURL = repositoryRootURL ?? Self.detectRepositoryRoot(fileManager: fileManager)
    }

    func inspect() -> MCPConnectorInspection {
        let launchSpec = launchSpecification()

        return MCPConnectorInspection(
            repositoryRootPath: repositoryRootURL?.path,
            launchSpec: launchSpec,
            clients: MCPConnectorClient.allCases.map { client in
                clientStatus(for: client, launchSpec: launchSpec)
            }
        )
    }

    static func detectRepositoryRoot(
        fileManager: FileManager = .default,
        sourceFilePath: String = #filePath
    ) -> URL? {
        var candidateURL = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()

        while candidateURL.path != "/" {
            let packageURL = candidateURL.appendingPathComponent("Package.swift")
            let projectURL = candidateURL.appendingPathComponent("PromptCue.xcodeproj", isDirectory: true)
            if fileManager.fileExists(atPath: packageURL.path),
               fileManager.fileExists(atPath: projectURL.path) {
                return candidateURL.standardizedFileURL
            }

            candidateURL.deleteLastPathComponent()
        }

        return nil
    }

    private func launchSpecification() -> MCPServerLaunchSpec? {
        guard let repositoryRootURL else {
            return nil
        }

        let candidateExecutableURLs = [
            repositoryRootURL.appendingPathComponent(".build/debug/BacktickMCP"),
            repositoryRootURL.appendingPathComponent(".build/arm64-apple-macosx/debug/BacktickMCP"),
            repositoryRootURL.appendingPathComponent(".build/x86_64-apple-macosx/debug/BacktickMCP"),
        ]

        if let executableURL = candidateExecutableURLs.first(where: isExecutableFile) {
            return MCPServerLaunchSpec(
                command: executableURL.path,
                arguments: []
            )
        }

        return MCPServerLaunchSpec(
            command: "/usr/bin/env",
            arguments: [
                "swift",
                "run",
                "--package-path",
                repositoryRootURL.path,
                "BacktickMCP",
            ]
        )
    }

    private func clientStatus(
        for client: MCPConnectorClient,
        launchSpec: MCPServerLaunchSpec?
    ) -> MCPConnectorClientStatus {
        let projectConfigURL = repositoryRootURL?.appendingPathComponent(client.projectConfigRelativePath)
        let homeConfigURL = homeDirectoryURL.appendingPathComponent(client.homeConfigRelativePath)

        return MCPConnectorClientStatus(
            client: client,
            cliPath: locateExecutable(named: client.executableName),
            projectConfig: projectConfigURL.map { configStatus(for: client, url: $0) },
            homeConfig: configStatus(for: client, url: homeConfigURL),
            addCommand: launchSpec.map { addCommand(for: client, launchSpec: $0) },
            configSnippet: launchSpec.map { configSnippet(for: client, launchSpec: $0) }
        )
    }

    private func configStatus(
        for client: MCPConnectorClient,
        url: URL
    ) -> MCPConnectorConfigLocationStatus {
        let presence: MCPConnectorConfigPresence
        if !fileManager.fileExists(atPath: url.path) {
            presence = .missing
        } else if hasBacktickConfiguration(for: client, url: url) {
            presence = .configured
        } else {
            presence = .presentWithoutBacktick
        }

        return MCPConnectorConfigLocationStatus(
            path: url.path,
            presence: presence
        )
    }

    private func hasBacktickConfiguration(
        for client: MCPConnectorClient,
        url: URL
    ) -> Bool {
        switch client {
        case .claudeCode:
            return hasBacktickConfigurationInClaudeJSON(url: url)
        case .codex:
            return hasBacktickConfigurationInCodexTOML(url: url)
        }
    }

    private func hasBacktickConfigurationInClaudeJSON(url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }

        return containsBacktickServerDefinition(in: json)
    }

    private func containsBacktickServerDefinition(in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            if let servers = dictionary["mcpServers"] as? [String: Any],
               containsMatchingBacktickServer(in: servers) {
                return true
            }

            for nestedValue in dictionary.values {
                if containsBacktickServerDefinition(in: nestedValue) {
                    return true
                }
            }
        }

        if let array = value as? [Any] {
            return array.contains(where: containsBacktickServerDefinition(in:))
        }

        return false
    }

    private func containsMatchingBacktickServer(in servers: [String: Any]) -> Bool {
        for (name, definition) in servers {
            if name.lowercased() == "backtick" {
                return true
            }

            if let dictionary = definition as? [String: Any] {
                if let command = dictionary["command"] as? String,
                   command.contains("BacktickMCP") {
                    return true
                }

                if let arguments = dictionary["args"] as? [String],
                   arguments.contains(where: { $0.contains("BacktickMCP") || $0.contains("PromptCue") }) {
                    return true
                }
            }
        }

        return false
    }

    private func hasBacktickConfigurationInCodexTOML(url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url) else {
            return false
        }

        return contents.contains("[mcp_servers.backtick]")
            || contents.contains("[mcp_servers.\"backtick\"]")
            || contents.contains("BacktickMCP")
    }

    private func locateExecutable(named executableName: String) -> String? {
        let pathSegments = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidateDirectories = Array(
            Set(
                pathSegments + [
                    "/opt/homebrew/bin",
                    "/usr/local/bin",
                    "/usr/bin",
                    homeDirectoryURL.appendingPathComponent(".local/bin").path,
                ]
            )
        )

        for directoryPath in candidateDirectories {
            let filePath = URL(fileURLWithPath: directoryPath)
                .appendingPathComponent(executableName)
                .path
            if isExecutableFile(atPath: filePath) {
                return filePath
            }
        }

        return nil
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        isExecutableFile(atPath: url.path)
    }

    private func isExecutableFile(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path)
    }

    private func addCommand(
        for client: MCPConnectorClient,
        launchSpec: MCPServerLaunchSpec
    ) -> String {
        switch client {
        case .claudeCode:
            return "claude mcp add --transport stdio --scope project backtick -- \(launchSpec.commandLine)"
        case .codex:
            return "codex mcp add backtick -- \(launchSpec.commandLine)"
        }
    }

    private func configSnippet(
        for client: MCPConnectorClient,
        launchSpec: MCPServerLaunchSpec
    ) -> String {
        switch client {
        case .claudeCode:
            let object: [String: Any] = [
                "mcpServers": [
                    "backtick": [
                        "command": launchSpec.command,
                        "args": launchSpec.arguments,
                    ],
                ],
            ]
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            return String(data: data ?? Data(), encoding: .utf8) ?? "{}"

        case .codex:
            let arguments = launchSpec.arguments
                .map { argument in
                    "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
                }
                .joined(separator: ", ")

            return """
            [mcp_servers.backtick]
            command = "\(launchSpec.command.replacingOccurrences(of: "\"", with: "\\\""))"
            args = [\(arguments)]
            """
        }
    }
}

@MainActor
final class MCPConnectorSettingsModel: ObservableObject {
    @Published private(set) var inspection: MCPConnectorInspection

    private let inspector: MCPConnectorInspector
    private let workspace: NSWorkspace
    private let pasteboard: NSPasteboard

    init(
        inspector: MCPConnectorInspector = MCPConnectorInspector(),
        workspace: NSWorkspace = .shared,
        pasteboard: NSPasteboard = .general
    ) {
        self.inspector = inspector
        self.workspace = workspace
        self.pasteboard = pasteboard
        self.inspection = inspector.inspect()
    }

    var repositoryRootPath: String {
        inspection.repositoryRootPath ?? "Not detected"
    }

    var serverStatusTitle: String {
        inspection.launchSpec == nil ? "Unavailable" : "Ready"
    }

    var serverStatusDetail: String {
        if let launchSpec = inspection.launchSpec {
            return launchSpec.commandLine
        }

        return "Backtick MCP needs a detectable source checkout or bundled helper before connector setup can be generated."
    }

    var clients: [MCPConnectorClientStatus] {
        inspection.clients
    }

    func refresh() {
        inspection = inspector.inspect()
    }

    func copyServerCommand() {
        copy(inspection.launchSpec?.commandLine)
    }

    func copyAddCommand(for client: MCPConnectorClient) {
        copy(inspection.status(for: client).addCommand)
    }

    func copyConfigSnippet(for client: MCPConnectorClient) {
        copy(inspection.status(for: client).configSnippet)
    }

    func openDocumentation(for client: MCPConnectorClient) {
        workspace.open(client.documentationURL)
    }

    func revealProjectConfig(for client: MCPConnectorClient) {
        guard let projectConfig = inspection.status(for: client).projectConfig else {
            return
        }

        revealPath(projectConfig.path)
    }

    func revealHomeConfig(for client: MCPConnectorClient) {
        revealPath(inspection.status(for: client).homeConfig.path)
    }

    private func copy(_ value: String?) {
        guard let value, !value.isEmpty else {
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func revealPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let existingURL = fileManagerItemURL(for: url)
        workspace.activateFileViewerSelecting([existingURL])
    }

    private func fileManagerItemURL(for url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardizedURL.path) {
            return standardizedURL
        }

        return standardizedURL.deletingLastPathComponent()
    }
}
