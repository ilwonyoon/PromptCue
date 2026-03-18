import AppKit
import Foundation

enum MCPConnectorClient: String, CaseIterable, Identifiable {
    case claudeDesktop
    case claudeCode
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeDesktop:
            return "Claude Desktop"
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    var documentationURL: URL {
        switch self {
        case .claudeDesktop:
            return URL(string: "https://modelcontextprotocol.io/quickstart/user")!
        case .claudeCode:
            return URL(string: "https://docs.anthropic.com/en/docs/claude-code/mcp")!
        case .codex:
            return URL(string: "https://platform.openai.com/docs/codex/cli#model-context-protocol-mcp")!
        }
    }

    /// Whether this client uses a CLI command (`claude mcp add`) vs direct config file writing.
    var usesDirectConfig: Bool {
        switch self {
        case .claudeDesktop:
            return true
        case .claudeCode, .codex:
            return false
        }
    }

    var supportsTerminalSetupAutomation: Bool {
        switch self {
        case .claudeDesktop:
            return false
        case .claudeCode, .codex:
            return true
        }
    }

    var executableName: String? {
        switch self {
        case .claudeDesktop:
            return nil
        case .claudeCode:
            return "claude"
        case .codex:
            return "codex"
        }
    }

    var homeConfigRelativePath: String {
        switch self {
        case .claudeDesktop:
            return "Library/Application Support/Claude/claude_desktop_config.json"
        case .claudeCode:
            return ".claude.json"
        case .codex:
            return ".codex/config.toml"
        }
    }

    var projectConfigRelativePath: String? {
        switch self {
        case .claudeDesktop:
            return nil
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
            return "Set up"
        case .presentWithoutBacktick:
            return "Other config found"
        case .missing:
            return "Not found"
        }
    }
}

enum MCPConnectorConfiguredScope: Equatable {
    case project
    case home
    case both

    var title: String {
        switch self {
        case .project:
            return "Project"
        case .home:
            return "Home"
        case .both:
            return "Project + Home"
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

    var cliStatusText: String {
        cliPath ?? "Not detected"
    }

    var hasConfiguredScope: Bool {
        configuredScope != nil
    }

    var configuredScope: MCPConnectorConfiguredScope? {
        switch (
            projectConfig?.presence == .configured,
            homeConfig.presence == .configured
        ) {
        case (true, true):
            return .both
        case (true, false):
            return .project
        case (false, true):
            return .home
        default:
            return nil
        }
    }

    var hasOtherConfigFiles: Bool {
        projectConfig?.presence == .presentWithoutBacktick || homeConfig.presence == .presentWithoutBacktick
    }

    var hasDetectedCLI: Bool {
        cliPath != nil
    }

    /// Whether this client is ready for setup. Direct-config clients (Claude Desktop)
    /// don't need a CLI; CLI-based clients (Claude Code, Codex) do.
    var isClientAvailable: Bool {
        client.usesDirectConfig || hasDetectedCLI
    }
}

struct MCPConnectorInspection: Equatable {
    let repositoryRootPath: String?
    let bundledHelperPath: String?
    let launchSpec: MCPServerLaunchSpec?
    let ngrokPath: String?
    let clients: [MCPConnectorClientStatus]

    func status(for client: MCPConnectorClient) -> MCPConnectorClientStatus {
        clients.first(where: { $0.client == client })!
    }
}

extension Notification.Name {
    static let experimentalMCPHTTPSettingsDidChange = Notification.Name(
        "MCPConnectorSettingsModel.experimentalMCPHTTPSettingsDidChange"
    )
    static let experimentalMCPHTTPRetryRequested = Notification.Name(
        "MCPConnectorSettingsModel.experimentalMCPHTTPRetryRequested"
    )
    static let experimentalMCPHTTPOAuthResetRequested = Notification.Name(
        "MCPConnectorSettingsModel.experimentalMCPHTTPOAuthResetRequested"
    )
}

enum ExperimentalMCPHTTPAuthMode: String, CaseIterable, Equatable {
    case apiKey
    case oauth

    var title: String {
        switch self {
        case .apiKey:
            return "Bearer Token"
        case .oauth:
            return "OAuth"
        }
    }
}

struct ExperimentalMCPHTTPSettings: Equatable {
    static let defaultPort: UInt16 = 8321

    var isEnabled: Bool
    var port: UInt16
    var authMode: ExperimentalMCPHTTPAuthMode
    var apiKey: String
    var publicBaseURL: String
}

enum ExperimentalMCPHTTPRuntimeState: Equatable {
    case stopped
    case starting
    case restarting
    case running
    case failed(String)

    var title: String {
        switch self {
        case .stopped:
            return "Off"
        case .starting:
            return "Starting"
        case .restarting:
            return "Restarting"
        case .running:
            return "Running"
        case .failed:
            return "Needs attention"
        }
    }

    var failureDetail: String? {
        guard case .failed(let detail) = self else {
            return nil
        }

        return detail
    }
}

enum ExperimentalMCPHTTPStatusTone: Equatable {
    case neutral
    case accent
    case success
    case warning
    case danger
}

enum ExperimentalMCPHTTPStatusAction: Equatable {
    case launchTunnel
    case installTunnel
    case copyPublicMCPURL
    case resetLocalState
    case retry

    var title: String {
        switch self {
        case .launchTunnel:
            return "Launch ngrok"
        case .installTunnel:
            return "Install ngrok"
        case .copyPublicMCPURL:
            return "Copy ChatGPT MCP URL"
        case .resetLocalState:
            return "Reset Local State"
        case .retry:
            return "Try Again"
        }
    }
}

struct ExperimentalMCPHTTPStatusPresentation: Equatable {
    let title: String
    let reason: String
    let tone: ExperimentalMCPHTTPStatusTone
    let action: ExperimentalMCPHTTPStatusAction?
}

enum ExperimentalMCPHTTPProbeIssue: Equatable {
    case localEndpointUnreachable
    case publicEndpointUnreachable
}

protocol ExperimentalMCPHTTPProbing {
    func probe(
        port: UInt16,
        authMode: ExperimentalMCPHTTPAuthMode,
        publicBaseURL: URL?
    ) async -> ExperimentalMCPHTTPProbeIssue?
}

protocol ExperimentalMCPHTTPTunnelDetecting {
    func detectedPublicBaseURL(for port: UInt16) async -> URL?
}

struct ExperimentalMCPHTTPURLProbe: ExperimentalMCPHTTPProbing {
    private let session: URLSession

    init(session: URLSession = ExperimentalMCPHTTPURLProbe.makeSession()) {
        self.session = session
    }

    func probe(
        port: UInt16,
        authMode: ExperimentalMCPHTTPAuthMode,
        publicBaseURL: URL?
    ) async -> ExperimentalMCPHTTPProbeIssue? {
        guard let localHealthURL = URL(string: "http://127.0.0.1:\(port)/health"),
              await isSuccessfulGET(localHealthURL) else {
            return .localEndpointUnreachable
        }

        guard let publicBaseURL else {
            return nil
        }

        let publicProbeURL: URL
        switch authMode {
        case .oauth:
            publicProbeURL = publicBaseURL.appending(path: ".well-known/oauth-protected-resource")
        case .apiKey:
            publicProbeURL = publicBaseURL.appending(path: "health")
        }

        guard await isSuccessfulGET(publicProbeURL) else {
            return .publicEndpointUnreachable
        }

        return nil
    }

    private func isSuccessfulGET(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        return URLSession(configuration: configuration)
    }
}

struct ExperimentalMCPHTTPNgrokTunnelDetector: ExperimentalMCPHTTPTunnelDetecting {
    private let session: URLSession

    init(session: URLSession = ExperimentalMCPHTTPNgrokTunnelDetector.makeSession()) {
        self.session = session
    }

    func detectedPublicBaseURL(for port: UInt16) async -> URL? {
        guard let apiURL = URL(string: "http://127.0.0.1:4040/api/tunnels") else {
            return nil
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tunnels = object["tunnels"] as? [[String: Any]] else {
                return nil
            }

            let expectedLocalTargets = [
                "http://localhost:\(port)",
                "http://127.0.0.1:\(port)",
                "localhost:\(port)",
                "127.0.0.1:\(port)"
            ]

            let matchingTunnel = tunnels.first { tunnel in
                guard let publicURL = tunnel["public_url"] as? String,
                      publicURL.lowercased().hasPrefix("https://") else {
                    return false
                }

                if let config = tunnel["config"] as? [String: Any],
                   let addr = config["addr"] as? String {
                    return expectedLocalTargets.contains { addr.contains($0) }
                }

                return false
            } ?? tunnels.first { tunnel in
                guard let publicURL = tunnel["public_url"] as? String,
                      publicURL.lowercased().hasPrefix("https://") else {
                    return false
                }

                return tunnels.count == 1
            }

            guard let publicURLString = matchingTunnel?["public_url"] as? String,
                  let url = URL(string: publicURLString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https",
                  url.host != nil else {
                return nil
            }

            return url
        } catch {
            return nil
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        return URLSession(configuration: configuration)
    }
}

private enum ExperimentalMCPHTTPRecoveryIssue: Equatable {
    case staleChatGPTGrant
}

enum MCPConnectorPrimaryAction: Equatable {
    case writeConfig
    case launchTerminalSetup
    case copyAddCommand
    case openDocumentation
    case runServerTest

    var title: String {
        switch self {
        case .writeConfig:
            return "Connect"
        case .launchTerminalSetup:
            return "Connect"
        case .copyAddCommand:
            return "Set Up"
        case .openDocumentation:
            return "Open Install Guide"
        case .runServerTest:
            return "Verify Setup"
        }
    }
}

enum MCPServerConnectionState: Equatable {
    case idle
    case running
    case passed(MCPServerConnectionReport)
    case failed(MCPServerConnectionFailure)

    var title: String {
        switch self {
        case .idle:
            return "Not run yet"
        case .running:
            return "Running…"
        case .passed:
            return "Connection test passed"
        case .failed:
            return "Connection test failed"
        }
    }

    var isRunning: Bool {
        if case .running = self {
            return true
        }

        return false
    }
}

struct MCPServerConnectionReport: Equatable {
    let protocolVersion: String
    let toolNames: [String]

    var detail: String {
        "Backtick MCP launched and answered initialize/tools/list for \(toolNames.count) tools."
    }
}

protocol MCPConnectorTerminalLaunching {
    func launchInTerminal(command: String) -> Bool
}

enum MCPServerConnectionFailure: Error, Equatable {
    case unavailable
    case launchFailed(String)
    case invalidResponse(String)
    case missingExpectedTools([String])

    var detail: String {
        switch self {
        case .unavailable:
            return "Backtick MCP launch command is unavailable. Build the helper or use a detected source checkout first."
        case .launchFailed(let message):
            return message
        case .invalidResponse(let message):
            return message
        case .missingExpectedTools(let toolNames):
            return "Backtick MCP launched, but these expected tools were missing: \(toolNames.joined(separator: ", "))"
        }
    }
}

protocol MCPServerConnectionTesting {
    func run(launchSpec: MCPServerLaunchSpec) async -> MCPServerConnectionState
}

struct MCPConnectorInspector {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectoryURL: URL
    private let applicationBundleURL: URL?
    private let repositoryRootURL: URL?

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationBundleURL: URL? = Bundle.main.bundleURL,
        repositoryRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectoryURL = homeDirectoryURL
        self.applicationBundleURL = applicationBundleURL
        self.repositoryRootURL = repositoryRootURL ?? Self.detectRepositoryRoot(fileManager: fileManager)
    }

    func inspect() -> MCPConnectorInspection {
        let bundledHelperURL = bundledHelperURL()
        let launchSpec = launchSpecification(bundledHelperURL: bundledHelperURL)

        return MCPConnectorInspection(
            repositoryRootPath: repositoryRootURL?.path,
            bundledHelperPath: bundledHelperURL?.path,
            launchSpec: launchSpec,
            ngrokPath: locateExecutable(named: "ngrok"),
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

    private func launchSpecification(bundledHelperURL: URL?) -> MCPServerLaunchSpec? {
        if let bundledHelperURL {
            return MCPServerLaunchSpec(
                command: bundledHelperURL.path,
                arguments: []
            )
        }

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

    private func bundledHelperURL() -> URL? {
        guard let applicationBundleURL else {
            return nil
        }

        let helperURL = applicationBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("BacktickMCP")

        if isExecutableFile(helperURL) {
            return helperURL.standardizedFileURL
        }

        return nil
    }

    private func clientStatus(
        for client: MCPConnectorClient,
        launchSpec: MCPServerLaunchSpec?
    ) -> MCPConnectorClientStatus {
        let projectConfigURL: URL?
        if let relativePath = client.projectConfigRelativePath {
            projectConfigURL = repositoryRootURL?.appendingPathComponent(relativePath)
        } else {
            projectConfigURL = nil
        }
        let homeConfigURL = homeDirectoryURL.appendingPathComponent(client.homeConfigRelativePath)
        let cliPath = client.executableName.flatMap { locateExecutable(named: $0) }

        return MCPConnectorClientStatus(
            client: client,
            cliPath: cliPath,
            projectConfig: projectConfigURL.map { configStatus(for: client, url: $0) },
            homeConfig: configStatus(for: client, url: homeConfigURL),
            addCommand: launchSpec.flatMap { addCommand(for: client, cliPath: cliPath, launchSpec: $0) },
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
        case .claudeDesktop, .claudeCode:
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
        cliPath: String?,
        launchSpec: MCPServerLaunchSpec
    ) -> String? {
        let cliCommand = MCPServerLaunchSpec(
            command: cliPath ?? (client.executableName ?? client.rawValue),
            arguments: ["mcp", "add"]
        ).commandLine

        switch client {
        case .claudeDesktop:
            return nil
        case .claudeCode:
            return "\(cliCommand) --transport stdio --scope user backtick -- \(launchSpec.commandLine)"
        case .codex:
            return "\(cliCommand) backtick -- \(launchSpec.commandLine)"
        }
    }

    private func configSnippet(
        for client: MCPConnectorClient,
        launchSpec: MCPServerLaunchSpec
    ) -> String {
        switch client {
        case .claudeDesktop, .claudeCode:
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
    private static let experimentalRemoteTunnelDocumentationURL = URL(string: "https://ngrok.com/download")!

    private enum ExperimentalRemoteDefaultsKey {
        static let isEnabled = "Backtick.ExperimentalMCPHTTP.Enabled"
        static let port = "Backtick.ExperimentalMCPHTTP.Port"
        static let authMode = "Backtick.ExperimentalMCPHTTP.AuthMode"
        static let apiKey = "Backtick.ExperimentalMCPHTTP.APIKey"
        static let publicBaseURL = "Backtick.ExperimentalMCPHTTP.PublicBaseURL"
    }

    @Published private(set) var inspection: MCPConnectorInspection
    @Published private(set) var connectionState: MCPServerConnectionState = .idle
    @Published private(set) var clientConnectionStates: [MCPConnectorClient: MCPServerConnectionState] = [:]
    @Published private(set) var experimentalRemoteSettings: ExperimentalMCPHTTPSettings
    @Published private(set) var experimentalRemoteRuntimeState: ExperimentalMCPHTTPRuntimeState = .stopped
    @Published var directConfigSuccessClient: MCPConnectorClient?
    private var experimentalRemoteRecoveryIssue: ExperimentalMCPHTTPRecoveryIssue?
    private var experimentalRemoteHasSeenRemoteSuccess = false

    private let inspector: MCPConnectorInspector
    private let connectionTester: MCPServerConnectionTesting
    private let terminalLauncher: MCPConnectorTerminalLaunching
    private let workspace: NSWorkspace
    private let pasteboard: NSPasteboard
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let experimentalRemoteProbe: ExperimentalMCPHTTPProbing
    private let experimentalRemoteTunnelDetector: ExperimentalMCPHTTPTunnelDetecting
    private let experimentalRemoteOAuthStateFileURL: URL?
    private let setupRefreshPollIntervalNanoseconds: UInt64
    private let setupRefreshMaxAttempts: Int
    private var connectionTask: Task<Void, Never>?
    private var connectionTaskClient: MCPConnectorClient?
    private var setupRefreshTask: Task<Void, Never>?
    private var experimentalRemoteProbeTask: Task<Void, Never>?
    private var experimentalRemoteTunnelDetectionTask: Task<Void, Never>?
    private var experimentalRemoteProbeIssue: ExperimentalMCPHTTPProbeIssue?
    private var experimentalRemoteDetectedPublicBaseURL: URL?

    init(
        inspector: MCPConnectorInspector = MCPConnectorInspector(),
        connectionTester: MCPServerConnectionTesting = MCPServerSelfTester(),
        terminalLauncher: MCPConnectorTerminalLaunching = MCPConnectorTerminalLauncher(),
        workspace: NSWorkspace = .shared,
        pasteboard: NSPasteboard = .general,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        experimentalRemoteProbe: ExperimentalMCPHTTPProbing = ExperimentalMCPHTTPURLProbe(),
        experimentalRemoteTunnelDetector: ExperimentalMCPHTTPTunnelDetecting = ExperimentalMCPHTTPNgrokTunnelDetector(),
        experimentalRemoteOAuthStateFileURL: URL? = nil,
        setupRefreshPollIntervalNanoseconds: UInt64 = 350_000_000,
        setupRefreshMaxAttempts: Int = 18
    ) {
        self.inspector = inspector
        self.connectionTester = connectionTester
        self.terminalLauncher = terminalLauncher
        self.workspace = workspace
        self.pasteboard = pasteboard
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        self.experimentalRemoteProbe = experimentalRemoteProbe
        self.experimentalRemoteTunnelDetector = experimentalRemoteTunnelDetector
        self.experimentalRemoteOAuthStateFileURL = experimentalRemoteOAuthStateFileURL
            ?? Self.defaultExperimentalRemoteOAuthStateFileURL(fileManager: fileManager)
        self.setupRefreshPollIntervalNanoseconds = setupRefreshPollIntervalNanoseconds
        self.setupRefreshMaxAttempts = setupRefreshMaxAttempts
        self.inspection = inspector.inspect()
        self.experimentalRemoteSettings = Self.loadExperimentalRemoteSettings(from: userDefaults)
        ensureExperimentalRemoteAPIKeyIfNeeded()
        refreshExperimentalRemoteTunnelDetection()
    }

    var repositoryRootPath: String {
        inspection.repositoryRootPath ?? "Not detected"
    }

    var isServerAvailable: Bool {
        inspection.launchSpec != nil
    }

    var serverSourcePath: String {
        inspection.bundledHelperPath ?? inspection.repositoryRootPath ?? "Not detected"
    }

    var serverSourceLabel: String {
        if inspection.bundledHelperPath != nil {
            return "Bundled helper"
        }

        if inspection.repositoryRootPath != nil {
            return "Repository"
        }

        return "Not detected"
    }

    var serverStatusTitle: String {
        inspection.launchSpec == nil ? "Needs build" : "Available"
    }

    var serverStatusDetail: String {
        if let launchSpec = inspection.launchSpec {
            return launchSpec.commandLine
        }

        return "Backtick MCP needs a detectable source checkout or bundled helper before connector setup can be generated."
    }

    var serverStatusFootnote: String {
        if let bundledHelperPath = inspection.bundledHelperPath {
            return "Backtick MCP is bundled inside this app build at \(bundledHelperPath)."
        }

        if let repositoryRootPath = inspection.repositoryRootPath {
            return "Backtick MCP is being launched from the current source checkout at \(repositoryRootPath)."
        }

        return "No bundled helper or source checkout was detected."
    }

    var clients: [MCPConnectorClientStatus] {
        inspection.clients
    }

    var serverSummary: String {
        if inspection.bundledHelperPath != nil {
            return "Backtick is already built into this app. Choose a client below to finish setup."
        }

        if inspection.repositoryRootPath != nil {
            return "Backtick can launch its MCP helper from this source checkout. Choose a client below to finish setup."
        }

        return "Backtick cannot generate setup commands until its MCP helper is available."
    }

    var serverVerificationTitle: String {
        switch connectionState {
        case .idle:
            return "Not tested"
        case .running:
            return "Testing"
        case .passed:
            return "Local server OK"
        case .failed:
            return "Test failed"
        }
    }

    var hasConfiguredClients: Bool {
        clients.contains(where: \.hasConfiguredScope)
    }

    var serverOverviewTitle: String {
        if !isServerAvailable {
            return "Fix Backtick first"
        }

        return "Start with a client below"
    }

    var serverOverviewDetail: String {
        if !isServerAvailable {
            return "Backtick itself is unavailable right now. Open the fix section below before trying any client."
        }

        if hasConfiguredClients {
            return "Backtick is ready in this build. Each client below will tell you whether to verify setup or fix a problem."
        }

        return "Backtick is ready in this build. Pick any client below and follow the next step shown there."
    }

    var serverTroubleshootingTitle: String {
        if !isServerAvailable {
            return "Fix This"
        }

        if case .failed = connectionState {
            return "Fix This"
        }

        return "Troubleshooting"
    }

    func refresh() {
        let updatedInspection = inspector.inspect()
        inspection = updatedInspection
        experimentalRemoteSettings = Self.loadExperimentalRemoteSettings(from: userDefaults)
        ensureExperimentalRemoteAPIKeyIfNeeded()
        refreshExperimentalRemoteTunnelDetection()
        let configuredClients = Set(
            updatedInspection.clients
                .filter(\.hasConfiguredScope)
                .map(\.client)
        )
        clientConnectionStates = clientConnectionStates.filter { configuredClients.contains($0.key) }
    }

    var experimentalRemoteLocalEndpoint: String {
        "http://127.0.0.1:\(experimentalRemoteSettings.port)/mcp"
    }

    var experimentalRemotePublicEndpoint: String? {
        experimentalRemotePublicBaseURL?.appending(path: "mcp").absoluteString
    }

    var experimentalRemoteConfiguredPublicBaseURL: URL? {
        let trimmedValue = experimentalRemoteSettings.publicBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              (url.path.isEmpty || url.path == "/"),
              url.host != nil else {
            return nil
        }

        return url
    }

    var experimentalRemotePublicBaseURL: URL? {
        experimentalRemoteConfiguredPublicBaseURL ?? experimentalRemoteDetectedPublicBaseURL
    }

    var experimentalRemoteRecommendedTunnelPath: String? {
        inspection.ngrokPath
    }

    var experimentalRemoteRecommendedTunnelCommand: String {
        MCPServerLaunchSpec(
            command: experimentalRemoteRecommendedTunnelPath ?? "ngrok",
            arguments: ["http", "\(experimentalRemoteSettings.port)"]
        ).commandLine
    }

    var experimentalRemoteRecommendedTunnelSummary: String {
        if let ngrokPath = experimentalRemoteRecommendedTunnelPath {
            return "Recommended for advanced users. ngrok is installed at \(ngrokPath). Run it against port \(experimentalRemoteSettings.port) to get a public HTTPS URL, then paste that base URL below."
        }

        return "Recommended for advanced users. Install ngrok, sign in, then run `ngrok http \(experimentalRemoteSettings.port)` to get a public HTTPS URL for this Mac."
    }

    var experimentalRemoteOAuthStateExists: Bool {
        guard let experimentalRemoteOAuthStateFileURL else {
            return false
        }

        return fileManager.fileExists(atPath: experimentalRemoteOAuthStateFileURL.path)
    }

    var experimentalRemoteIsConnected: Bool {
        experimentalRemoteRecoveryIssue == nil
            && experimentalRemoteHasSeenRemoteSuccess
            && experimentalRemoteRuntimeState == .running
    }

    var experimentalRemoteShouldShowInlinePublicBaseURL: Bool {
        guard experimentalRemoteSettings.isEnabled else {
            return false
        }

        if experimentalRemoteRecoveryIssue == .staleChatGPTGrant {
            return false
        }

        return experimentalRemotePublicBaseURL == nil
            || experimentalRemoteProbeIssue == .publicEndpointUnreachable
    }

    var experimentalRemoteShouldShowInlineChatGPTMCPURL: Bool {
        guard experimentalRemoteSettings.isEnabled,
              experimentalRemotePublicEndpoint != nil else {
            return false
        }

        return !experimentalRemoteIsConnected
    }

    var experimentalRemoteStatusPresentation: ExperimentalMCPHTTPStatusPresentation {
        if !experimentalRemoteSettings.isEnabled {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Off",
                reason: "Turn this on when you want Backtick to host a local MCP endpoint on this Mac.",
                tone: .neutral,
                action: nil
            )
        }

        if experimentalRemoteRecoveryIssue == .staleChatGPTGrant {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Reconnect needed",
                reason: "ChatGPT is still holding an older Backtick grant. Reset local state here, then recreate the Backtick app in ChatGPT.",
                tone: .warning,
                action: .resetLocalState
            )
        }

        if experimentalRemoteIsConnected {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Connected",
                reason: "ChatGPT has already reached this Backtick endpoint with your current app setup.",
                tone: .success,
                action: .copyPublicMCPURL
            )
        }

        switch experimentalRemoteRuntimeState {
        case .starting:
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Starting",
                reason: "Backtick is starting the local MCP endpoint now.",
                tone: .accent,
                action: nil
            )
        case .restarting:
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Restarting",
                reason: "Backtick is restarting the local MCP endpoint with your latest settings.",
                tone: .accent,
                action: nil
            )
        case .failed(let detail):
            return statusPresentationForRuntimeFailure(detail: detail)
        case .running, .stopped:
            break
        }

        if experimentalRemotePublicBaseURL == nil {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Public URL required",
                reason: "Start a public HTTPS tunnel, then paste its base URL below before you connect ChatGPT.",
                tone: .warning,
                action: experimentalRemoteRecommendedTunnelPath == nil ? .installTunnel : .launchTunnel
            )
        }

        if let experimentalRemoteProbeIssue,
           experimentalRemoteRuntimeState == .running {
            return statusPresentationForProbeIssue(experimentalRemoteProbeIssue)
        }

        return ExperimentalMCPHTTPStatusPresentation(
            title: "Ready to connect",
            reason: runningStatusReason,
            tone: experimentalRemoteRuntimeState == .running ? .success : .accent,
            action: .copyPublicMCPURL
        )
    }

    func updateExperimentalRemoteEnabled(_ isEnabled: Bool) {
        var updatedSettings = experimentalRemoteSettings
        updatedSettings.isEnabled = isEnabled
        if isEnabled,
           updatedSettings.authMode == .apiKey,
           updatedSettings.apiKey.isEmpty {
            updatedSettings.apiKey = Self.generateExperimentalRemoteAPIKey()
        }
        if !isEnabled {
            experimentalRemoteRecoveryIssue = nil
            experimentalRemoteHasSeenRemoteSuccess = false
            experimentalRemoteProbeIssue = nil
        }
        saveExperimentalRemoteSettings(updatedSettings)
    }

    func updateExperimentalRemoteAuthMode(_ authMode: ExperimentalMCPHTTPAuthMode) {
        var updatedSettings = experimentalRemoteSettings
        updatedSettings.authMode = authMode
        if authMode == .apiKey, updatedSettings.apiKey.isEmpty {
            updatedSettings.apiKey = Self.generateExperimentalRemoteAPIKey()
        }
        if authMode != .oauth {
            experimentalRemoteRecoveryIssue = nil
            experimentalRemoteHasSeenRemoteSuccess = false
        }
        experimentalRemoteProbeIssue = nil
        saveExperimentalRemoteSettings(updatedSettings)
    }

    @discardableResult
    func updateExperimentalRemotePort(_ rawValue: String) -> Bool {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedPort = UInt16(trimmedValue), parsedPort > 0 else {
            return false
        }

        var updatedSettings = experimentalRemoteSettings
        updatedSettings.port = parsedPort
        experimentalRemoteHasSeenRemoteSuccess = false
        experimentalRemoteProbeIssue = nil
        saveExperimentalRemoteSettings(updatedSettings)
        return true
    }

    @discardableResult
    func updateExperimentalRemoteAPIKey(_ rawValue: String) -> Bool {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return false
        }

        var updatedSettings = experimentalRemoteSettings
        updatedSettings.apiKey = trimmedValue
        experimentalRemoteProbeIssue = nil
        saveExperimentalRemoteSettings(updatedSettings)
        return true
    }

    func generateExperimentalRemoteAPIKey() {
        var updatedSettings = experimentalRemoteSettings
        updatedSettings.apiKey = Self.generateExperimentalRemoteAPIKey()
        experimentalRemoteProbeIssue = nil
        saveExperimentalRemoteSettings(updatedSettings)
    }

    @discardableResult
    func updateExperimentalRemotePublicBaseURL(_ rawValue: String) -> Bool {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              (url.path.isEmpty || url.path == "/"),
              url.host != nil else {
            return false
        }

        var updatedSettings = experimentalRemoteSettings
        updatedSettings.publicBaseURL = Self.normalizedExperimentalRemotePublicBaseURL(url)
        experimentalRemoteHasSeenRemoteSuccess = false
        experimentalRemoteProbeIssue = nil
        saveExperimentalRemoteSettings(updatedSettings)
        return true
    }

    func copyExperimentalRemoteEndpoint() {
        copy(experimentalRemoteLocalEndpoint)
    }

    func copyExperimentalRemotePublicEndpoint() {
        copy(experimentalRemotePublicEndpoint)
    }

    func copyExperimentalRemoteRecommendedTunnelCommand() {
        copy(experimentalRemoteRecommendedTunnelCommand)
    }

    func copyExperimentalRemoteAPIKey() {
        copy(experimentalRemoteSettings.apiKey)
    }

    @discardableResult
    func launchExperimentalRemoteRecommendedTunnelInTerminal() -> Bool {
        terminalLauncher.launchInTerminal(command: experimentalRemoteRecommendedTunnelCommand)
    }

    func openExperimentalRemoteTunnelDocumentation() {
        workspace.open(Self.experimentalRemoteTunnelDocumentationURL)
    }

    @discardableResult
    func resetExperimentalRemoteOAuthState() -> Bool {
        guard let experimentalRemoteOAuthStateFileURL else {
            notificationCenter.post(name: .experimentalMCPHTTPOAuthResetRequested, object: self)
            return false
        }

        let didRemoveExistingState: Bool
        if fileManager.fileExists(atPath: experimentalRemoteOAuthStateFileURL.path) {
            do {
                try fileManager.removeItem(at: experimentalRemoteOAuthStateFileURL)
                didRemoveExistingState = true
            } catch {
                NSLog(
                    "MCPConnectorSettingsModel failed to remove OAuth state at %@: %@",
                    experimentalRemoteOAuthStateFileURL.path,
                    error.localizedDescription
                )
                didRemoveExistingState = false
            }
        } else {
            didRemoveExistingState = false
        }

        notificationCenter.post(name: .experimentalMCPHTTPOAuthResetRequested, object: self)
        experimentalRemoteRecoveryIssue = nil
        experimentalRemoteHasSeenRemoteSuccess = false
        experimentalRemoteProbeIssue = nil
        return didRemoveExistingState
    }

    func setExperimentalRemoteRuntimeState(_ state: ExperimentalMCPHTTPRuntimeState) {
        experimentalRemoteRuntimeState = state
        experimentalRemoteProbeIssue = nil
    }

    func refreshExperimentalRemoteProbe() {
        experimentalRemoteProbeTask?.cancel()
        experimentalRemoteProbeTask = nil

        guard experimentalRemoteSettings.isEnabled,
              experimentalRemoteRuntimeState == .running else {
            experimentalRemoteProbeIssue = nil
            return
        }

        let port = experimentalRemoteSettings.port
        let authMode = experimentalRemoteSettings.authMode
        let publicBaseURL = experimentalRemotePublicBaseURL
        experimentalRemoteProbeIssue = nil

        experimentalRemoteProbeTask = Task { [experimentalRemoteProbe] in
            let issue = await experimentalRemoteProbe.probe(
                port: port,
                authMode: authMode,
                publicBaseURL: publicBaseURL
            )
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self.experimentalRemoteProbeTask = nil
                guard self.experimentalRemoteSettings.isEnabled,
                      self.experimentalRemoteRuntimeState == .running,
                      self.experimentalRemoteSettings.port == port,
                      self.experimentalRemoteSettings.authMode == authMode,
                      self.experimentalRemotePublicBaseURL == publicBaseURL else {
                    return
                }

                self.experimentalRemoteProbeIssue = issue
            }
        }
    }

    func refreshExperimentalRemoteTunnelDetection() {
        experimentalRemoteTunnelDetectionTask?.cancel()
        experimentalRemoteTunnelDetectionTask = nil

        guard experimentalRemoteSettings.isEnabled,
              experimentalRemoteConfiguredPublicBaseURL == nil else {
            experimentalRemoteDetectedPublicBaseURL = nil
            return
        }

        let port = experimentalRemoteSettings.port
        experimentalRemoteTunnelDetectionTask = Task { [experimentalRemoteTunnelDetector] in
            let detectedURL = await experimentalRemoteTunnelDetector.detectedPublicBaseURL(for: port)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self.experimentalRemoteTunnelDetectionTask = nil
                guard self.experimentalRemoteSettings.isEnabled,
                      self.experimentalRemoteSettings.port == port,
                      self.experimentalRemoteConfiguredPublicBaseURL == nil else {
                    return
                }

                self.experimentalRemoteDetectedPublicBaseURL = detectedURL
            }
        }
    }

    func retryExperimentalRemote() {
        experimentalRemoteProbeIssue = nil
        notificationCenter.post(name: .experimentalMCPHTTPRetryRequested, object: self)
    }

    func performExperimentalRemoteStatusAction(_ action: ExperimentalMCPHTTPStatusAction) {
        switch action {
        case .launchTunnel:
            _ = launchExperimentalRemoteRecommendedTunnelInTerminal()
        case .installTunnel:
            openExperimentalRemoteTunnelDocumentation()
        case .copyPublicMCPURL:
            copyExperimentalRemotePublicEndpoint()
        case .resetLocalState:
            _ = resetExperimentalRemoteOAuthState()
        case .retry:
            retryExperimentalRemote()
        }
    }

    func recordExperimentalRemoteHelperLog(_ chunk: String) {
        let lowercasedChunk = chunk.lowercased()
        if lowercasedChunk.contains("token exchange rejected: invalid_client")
            || lowercasedChunk.contains("token exchange rejected: invalid_grant") {
            experimentalRemoteRecoveryIssue = .staleChatGPTGrant
            experimentalRemoteHasSeenRemoteSuccess = false
            experimentalRemoteProbeIssue = nil
        }

        if lowercasedChunk.contains("served protected remote request method=") {
            experimentalRemoteRecoveryIssue = nil
            experimentalRemoteHasSeenRemoteSuccess = true
            experimentalRemoteProbeIssue = nil
        }
    }

    func verificationState(for client: MCPConnectorClientStatus) -> MCPServerConnectionState {
        clientConnectionStates[client.client] ?? .idle
    }

    func clientSetupTitle(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "CLI not found"
        }

        if client.hasConfiguredScope {
            return "Set up"
        }

        return "Needs setup"
    }

    func clientScopeTitle(for client: MCPConnectorClientStatus) -> String? {
        if let configuredScope = client.configuredScope {
            return configuredScope.title
        }

        if client.hasOtherConfigFiles {
            return "Other config found"
        }

        return nil
    }

    func clientVerificationTitle(for client: MCPConnectorClientStatus) -> String? {
        guard client.hasConfiguredScope else {
            return nil
        }

        switch verificationState(for: client) {
        case .idle:
            return "Not verified"
        case .running:
            return "Testing"
        case .passed:
            return "Local server OK"
        case .failed:
            return "Needs attention"
        }
    }

    func clientSummary(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "Install \(client.client.title) on this Mac first, then come back to set up Backtick."
        }

        if !client.hasConfiguredScope {
            if client.client.usesDirectConfig {
                return "Click Connect to add Backtick to \(client.client.title) automatically."
            }

            if client.client.supportsTerminalSetupAutomation {
                if client.hasOtherConfigFiles {
                    switch client.client {
                    case .claudeCode:
                        return "Backtick is not in Claude Code yet. Click Connect to run the global setup command, or use the config-file fallback."
                    case .codex:
                        return "Backtick is not in Codex yet. Click Connect to run the setup command, or use the config-file fallback."
                    case .claudeDesktop:
                        break
                    }
                }

                switch client.client {
                case .claudeCode:
                    return "Click Connect and Backtick will open Terminal to add itself to Claude Code globally."
                case .codex:
                    return "Click Connect and Backtick will open Terminal to add itself to Codex."
                case .claudeDesktop:
                    break
                }
            }

            if client.hasOtherConfigFiles {
                return "Backtick is not in this client's config yet. Add it to your project or home config."
            }

            return "Add Backtick to a project or home config before using this connector."
        }

        switch verificationState(for: client) {
        case .idle:
            return "Backtick is set up here. Run a local test before relying on it in another client."
        case .running:
            return "The local server test is running now."
        case .passed:
            if client.client == .claudeCode {
                return "Backtick is set up and the local server responds. Non-interactive Claude runs still need an explicit allowed tool list."
            }

            return "Backtick is set up and the local server responds."
        case .failed:
            return "Backtick is set up, but the latest local server test failed. Fix the issue, then run the test again."
        }
    }

    func clientProgressSummary(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "\(client.client.title) is required before Backtick can connect here."
        }

        if !client.hasConfiguredScope {
            if client.hasOtherConfigFiles {
                return "A config file already exists here, but Backtick has not been added yet."
            }

            return "Backtick is not added to \(client.client.title) yet."
        }

        let location = client.configuredScope?.title ?? "Unknown"

        switch verificationState(for: client) {
        case .idle:
            return "Backtick is configured in \(location), but not verified yet."
        case .running:
            return "Backtick is configured in \(location). Local verification is running now."
        case .passed:
            return "Backtick is configured in \(location) and verified locally."
        case .failed:
            return "Backtick is configured in \(location), but local verification failed."
        }
    }

    func clientNextStepTitle(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "Install \(client.client.title)"
        }

        if !client.hasConfiguredScope {
            if client.client.usesDirectConfig {
                return "Connect to \(client.client.title)"
            }

            if client.client.supportsTerminalSetupAutomation {
                return "Connect to \(client.client.title)"
            }

            return "Add Backtick to \(client.client.title)"
        }

        switch verificationState(for: client) {
        case .idle:
            return "Verify the setup"
        case .running:
            return "Verifying setup"
        case .passed:
            return "Backtick is ready"
        case .failed:
            return "Fix the setup and verify again"
        }
    }

    func clientNextStepDetail(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "Backtick works through \(client.client.title). Install it first, then come back here to finish setup."
        }

        if !client.hasConfiguredScope {
            if client.client.usesDirectConfig {
                return "Click Connect and Backtick will write the config file automatically. Restart \(client.client.title) to pick up the change."
            }

            if client.client.supportsTerminalSetupAutomation {
                switch client.client {
                case .claudeCode:
                    return "Click Connect and Backtick will open Terminal and run the global Claude Code setup command. Then return here and verify."
                case .codex:
                    return "Click Connect and Backtick will open Terminal and run the Codex setup command. Then return here and verify."
                case .claudeDesktop:
                    break
                }
            }

            if client.hasOtherConfigFiles {
                return "Open setup steps, then either run the terminal command or add Backtick manually in the config file."
            }

            return "Open setup steps, paste the command into Terminal, then come back here."
        }

        switch verificationState(for: client) {
        case .idle:
            return "Run one local verification before you rely on Backtick inside \(client.client.title)."
        case .running:
            return "Backtick is launching its local MCP helper and checking the tool surface now."
        case .passed:
            if client.client == .claudeCode {
                return "Setup is verified locally. If you automate Claude with `--permission-mode dontAsk`, keep Backtick tools in `--allowedTools`."
            }

            return "Setup is verified locally. You can use Backtick from \(client.client.title) now."
        case .failed:
            return "Read the fix below, correct the issue, then run verification again."
        }
    }

    func primaryActionTitle(for client: MCPConnectorClientStatus) -> String? {
        switch primaryAction(for: client) {
        case .writeConfig:
            return "Connect"
        case .launchTerminalSetup:
            return "Connect"
        case .copyAddCommand:
            return "Set Up"
        case .openDocumentation:
            return "Install \(client.client.title)"
        case .runServerTest:
            if clientFailureDetail(for: client) != nil {
                return "Verify Again"
            }

            return "Verify Setup"
        case nil:
            return nil
        }
    }

    func configButtonTitle(for client: MCPConnectorClientStatus) -> String {
        if client.hasConfiguredScope || client.hasOtherConfigFiles {
            return "Open Config File"
        }

        return "Show Config Location"
    }

    func troubleshootingTitle(for client: MCPConnectorClientStatus) -> String {
        if clientFailureDetail(for: client) != nil {
            return "Fix This"
        }

        if client.hasOtherConfigFiles, !client.hasConfiguredScope {
            return "Fix This"
        }

        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "Install Help"
        }

        return "Troubleshooting"
    }

    func clientFailureDetail(for client: MCPConnectorClientStatus) -> String? {
        guard client.hasConfiguredScope else {
            return nil
        }

        guard case .failed(let failure) = verificationState(for: client) else {
            return nil
        }

        return failure.detail
    }

    func connectedToolNames(for client: MCPConnectorClientStatus) -> [String] {
        guard client.hasConfiguredScope else {
            return []
        }

        guard case .passed(let report) = verificationState(for: client) else {
            return []
        }

        return report.toolNames
    }

    func primaryAction(for client: MCPConnectorClientStatus) -> MCPConnectorPrimaryAction? {
        if client.client.usesDirectConfig {
            if !client.hasConfiguredScope {
                return inspection.launchSpec == nil ? nil : .writeConfig
            }

            if case .passed = verificationState(for: client) {
                return nil
            }

            return .runServerTest
        }

        if !client.hasDetectedCLI {
            return .openDocumentation
        }

        if !client.hasConfiguredScope {
            guard inspection.status(for: client.client).addCommand != nil else {
                return nil
            }

            if client.client.supportsTerminalSetupAutomation {
                return .launchTerminalSetup
            }

            return .copyAddCommand
        }

        if case .passed = verificationState(for: client) {
            return nil
        }

        return .runServerTest
    }

    @discardableResult
    func performPrimaryAction(_ action: MCPConnectorPrimaryAction, for client: MCPConnectorClientStatus) -> Bool {
        switch action {
        case .writeConfig:
            writeDirectConfig(for: client.client)
            return true
        case .launchTerminalSetup:
            return launchAddCommandInTerminal(for: client.client)
        case .copyAddCommand:
            copyAddCommand(for: client.client)
            return true
        case .openDocumentation:
            openDocumentation(for: client.client)
            return true
        case .runServerTest:
            runServerTest(for: client.client)
            return true
        }
    }

    var serverTestDetail: String {
        switch connectionState {
        case .idle:
            return "This checks the Backtick MCP launch command directly. It validates initialize/tools/list without depending on any client auth state."
        case .running:
            return "Launching Backtick MCP and waiting for initialize/tools/list…"
        case .passed(let report):
            return "\(report.detail) Protocol \(report.protocolVersion)."
        case .failed(let failure):
            return failure.detail
        }
    }

    func runServerTest(for client: MCPConnectorClient? = nil) {
        let targetClient = resolvedVerificationClient(explicitClient: client)
        connectionTask?.cancel()
        if let previousClient = connectionTaskClient,
           clientConnectionStates[previousClient] == .running {
            clientConnectionStates[previousClient] = .idle
        }
        guard let targetClient else {
            connectionState = .failed(.unavailable)
            return
        }
        connectionTaskClient = targetClient
        clientConnectionStates[targetClient] = .running
        connectionState = .running
        connectionTask = Task { [weak self] in
            await self?.performServerTest(for: targetClient)
        }
    }

    func performServerTest(for client: MCPConnectorClient? = nil) async {
        let targetClient = resolvedVerificationClient(explicitClient: client)
        guard let launchSpec = inspection.launchSpec else {
            connectionState = .failed(.unavailable)
            if let targetClient {
                clientConnectionStates[targetClient] = .failed(.unavailable)
            }
            return
        }

        if let targetClient {
            connectionTaskClient = targetClient
            clientConnectionStates[targetClient] = .running
        }
        connectionState = .running
        let result = await connectionTester.run(launchSpec: launchSpec)
        guard !Task.isCancelled else {
            return
        }

        connectionState = result
        if let targetClient {
            clientConnectionStates[targetClient] = result
        }
        connectionTaskClient = nil
        connectionTask = nil
    }

    func copyServerCommand() {
        copy(inspection.launchSpec?.commandLine)
    }

    func copyAddCommand(for client: MCPConnectorClient) {
        copy(inspection.status(for: client).addCommand)
    }

    @discardableResult
    func launchAddCommandInTerminal(for client: MCPConnectorClient) -> Bool {
        guard let addCommand = inspection.status(for: client).addCommand else {
            return false
        }

        let didLaunch = terminalLauncher.launchInTerminal(command: addCommand)
        if didLaunch {
            scheduleSetupRefresh(for: client)
        }

        return didLaunch
    }

    func writeDirectConfig(for client: MCPConnectorClient) {
        guard client.usesDirectConfig else {
            assertionFailure("writeDirectConfig called for CLI-based client \(client)")
            return
        }

        guard let launchSpec = inspection.launchSpec else { return }

        let configURL = URL(fileURLWithPath: inspection.status(for: client).homeConfig.path)

        let serverEntry: [String: Any] = [
            "command": launchSpec.command,
            "args": launchSpec.arguments,
        ]

        var root: [String: Any] = [:]

        if let existingData = try? Data(contentsOf: configURL),
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            root = existingJSON
        }

        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers["backtick"] = serverEntry
        root["mcpServers"] = servers

        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        } catch {
            NSLog("writeDirectConfig: failed to serialize config: %@", error.localizedDescription)
            return
        }

        do {
            let parentDirectory = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            try data.write(to: configURL, options: .atomic)
            directConfigSuccessClient = client
        } catch {
            NSLog("writeDirectConfig: failed to write %@: %@", configURL.path, error.localizedDescription)
        }

        refresh()
    }

    func copyConfigSnippet(for client: MCPConnectorClient) {
        copy(inspection.status(for: client).configSnippet)
    }

    func copyAutomationExample(for client: MCPConnectorClient) {
        copy(automationExample(for: client))
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

    func revealPreferredConfig(for client: MCPConnectorClient) {
        let status = inspection.status(for: client)

        if let projectConfig = status.projectConfig,
           projectConfig.presence != .missing {
            revealPath(projectConfig.path)
            return
        }

        revealPath(status.homeConfig.path)
    }

    func revealHomeConfig(for client: MCPConnectorClient) {
        revealPath(inspection.status(for: client).homeConfig.path)
    }

    func openPreferredConfig(for client: MCPConnectorClient) {
        let status = inspection.status(for: client)

        if let projectConfig = status.projectConfig {
            openConfigPath(projectConfig.path)
            return
        }

        openConfigPath(status.homeConfig.path)
    }

    func openProjectConfig(for client: MCPConnectorClient) {
        guard let projectConfig = inspection.status(for: client).projectConfig else {
            return
        }

        openConfigPath(projectConfig.path)
    }

    func openHomeConfig(for client: MCPConnectorClient) {
        openConfigPath(inspection.status(for: client).homeConfig.path)
    }

    func automationExample(for client: MCPConnectorClient) -> String? {
        switch client {
        case .claudeCode:
            let executable = inspection.status(for: client).cliPath ?? (client.executableName ?? "claude")
            let allowedTools = [
                "mcp__backtick__list_notes",
                "mcp__backtick__get_note",
                "mcp__backtick__create_note",
                "mcp__backtick__update_note",
                "mcp__backtick__mark_notes_executed",
                "mcp__backtick__delete_note",
            ].joined(separator: ",")

            return """
            \(executable) -p --permission-mode dontAsk --allowedTools "\(allowedTools)" "List active Backtick notes."
            """

        case .claudeDesktop, .codex:
            return nil
        }
    }

    private func copy(_ value: String?) {
        guard let value, !value.isEmpty else {
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func resolvedVerificationClient(explicitClient: MCPConnectorClient?) -> MCPConnectorClient? {
        if let explicitClient {
            return explicitClient
        }

        return inspection.clients.first(where: \.hasConfiguredScope)?.client
    }

    private func scheduleSetupRefresh(for client: MCPConnectorClient) {
        guard client.supportsTerminalSetupAutomation else {
            return
        }

        setupRefreshTask?.cancel()
        setupRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for attempt in 0..<self.setupRefreshMaxAttempts {
                if attempt > 0 {
                    try? await Task.sleep(nanoseconds: self.setupRefreshPollIntervalNanoseconds)
                }

                guard !Task.isCancelled else {
                    return
                }

                self.refresh()
                if self.inspection.status(for: client).hasConfiguredScope {
                    return
                }
            }
        }
    }

    private func revealPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let existingURL = fileManagerItemURL(for: url)
        workspace.activateFileViewerSelecting([existingURL])
    }

    private func openConfigPath(_ path: String) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let parentDirectoryURL = url.deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: parentDirectoryURL,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        workspace.open(url)
    }

    private func fileManagerItemURL(for url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardizedURL.path) {
            return standardizedURL
        }

        return standardizedURL.deletingLastPathComponent()
    }

    private func ensureExperimentalRemoteAPIKeyIfNeeded() {
        guard experimentalRemoteSettings.isEnabled,
              experimentalRemoteSettings.authMode == .apiKey,
              experimentalRemoteSettings.apiKey.isEmpty else {
            return
        }

        var updatedSettings = experimentalRemoteSettings
        updatedSettings.apiKey = Self.generateExperimentalRemoteAPIKey()
        saveExperimentalRemoteSettings(updatedSettings)
    }

    private func saveExperimentalRemoteSettings(_ settings: ExperimentalMCPHTTPSettings) {
        userDefaults.set(settings.isEnabled, forKey: ExperimentalRemoteDefaultsKey.isEnabled)
        userDefaults.set(Int(settings.port), forKey: ExperimentalRemoteDefaultsKey.port)
        userDefaults.set(settings.authMode.rawValue, forKey: ExperimentalRemoteDefaultsKey.authMode)
        userDefaults.set(settings.apiKey, forKey: ExperimentalRemoteDefaultsKey.apiKey)
        userDefaults.set(settings.publicBaseURL, forKey: ExperimentalRemoteDefaultsKey.publicBaseURL)
        experimentalRemoteSettings = settings
        refreshExperimentalRemoteTunnelDetection()
        notificationCenter.post(name: .experimentalMCPHTTPSettingsDidChange, object: self)
    }

    private var runningStatusReason: String {
        if experimentalRemoteSettings.authMode == .oauth {
            return "Backtick is running and ready. Copy the ChatGPT MCP URL below when you create or recreate the Backtick app in ChatGPT."
        }

        return "Backtick is running and ready. Copy the public MCP URL below and pair it with your Auth Token in the remote client."
    }

    private func statusPresentationForProbeIssue(
        _ issue: ExperimentalMCPHTTPProbeIssue
    ) -> ExperimentalMCPHTTPStatusPresentation {
        switch issue {
        case .localEndpointUnreachable:
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Needs attention",
                reason: "Backtick couldn't confirm that its local MCP endpoint is still responding. Try again, then restart Backtick if this keeps happening.",
                tone: .warning,
                action: .retry
            )
        case .publicEndpointUnreachable:
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Needs attention",
                reason: "Backtick is running locally, but the public HTTPS URL is not responding. Restart ngrok or update the public URL below.",
                tone: .warning,
                action: experimentalRemoteRecommendedTunnelPath == nil ? .installTunnel : .launchTunnel
            )
        }
    }

    private func statusPresentationForRuntimeFailure(
        detail: String
    ) -> ExperimentalMCPHTTPStatusPresentation {
        let lowercasedDetail = detail.lowercased()

        if lowercasedDetail.contains("valid public https url") {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Public URL required",
                reason: "Add a public HTTPS URL before ChatGPT can discover Backtick over OAuth.",
                tone: .warning,
                action: experimentalRemoteRecommendedTunnelPath == nil ? .installTunnel : .launchTunnel
            )
        }

        if lowercasedDetail.contains("launch spec is unavailable") {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Backtick unavailable",
                reason: "This Backtick build can't launch its local MCP helper right now. Restart Backtick, then try again.",
                tone: .danger,
                action: .retry
            )
        }

        return ExperimentalMCPHTTPStatusPresentation(
            title: "Needs attention",
            reason: "Backtick couldn't keep the local MCP endpoint running. Try again.",
            tone: .danger,
            action: .retry
        )
    }

    private static func loadExperimentalRemoteSettings(from userDefaults: UserDefaults) -> ExperimentalMCPHTTPSettings {
        let storedPort = userDefaults.integer(forKey: ExperimentalRemoteDefaultsKey.port)
        let port: UInt16
        if storedPort > 0, storedPort <= Int(UInt16.max) {
            port = UInt16(storedPort)
        } else {
            port = ExperimentalMCPHTTPSettings.defaultPort
        }
        let authMode = userDefaults.string(forKey: ExperimentalRemoteDefaultsKey.authMode)
            .flatMap(ExperimentalMCPHTTPAuthMode.init(rawValue:)) ?? .apiKey
        let apiKey = userDefaults.string(forKey: ExperimentalRemoteDefaultsKey.apiKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicBaseURL = userDefaults.string(forKey: ExperimentalRemoteDefaultsKey.publicBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ExperimentalMCPHTTPSettings(
            isEnabled: userDefaults.bool(forKey: ExperimentalRemoteDefaultsKey.isEnabled),
            port: port,
            authMode: authMode,
            apiKey: apiKey,
            publicBaseURL: publicBaseURL
        )
    }

    private static func generateExperimentalRemoteAPIKey() -> String {
        (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func normalizedExperimentalRemotePublicBaseURL(_ url: URL) -> String {
        var normalizedURL = url.absoluteString
        while normalizedURL.hasSuffix("/") {
            normalizedURL.removeLast()
        }
        return normalizedURL
    }

    private static func defaultExperimentalRemoteOAuthStateFileURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("PromptCue", isDirectory: true)
            .appendingPathComponent("BacktickMCPOAuthState.json", isDirectory: false)
    }
}

struct MCPConnectorTerminalLauncher: MCPConnectorTerminalLaunching {
    func launchInTerminal(command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\"",
            "-e", "activate",
            "-e", "do script \(appleScriptStringLiteral(command))",
            "-e", "end tell",
        ]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            NSLog("MCPConnectorTerminalLauncher failed: %@", error.localizedDescription)
            return false
        }
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

struct MCPServerSelfTester: MCPServerConnectionTesting {
    private static let expectedToolNames = [
        "list_notes",
        "get_note",
        "create_note",
        "update_note",
        "delete_note",
        "mark_notes_executed",
    ]

    func run(launchSpec: MCPServerLaunchSpec) async -> MCPServerConnectionState {
        await Task.detached(priority: .utility) {
            do {
                return try runSynchronously(launchSpec: launchSpec)
            } catch let failure as MCPServerConnectionFailure {
                return .failed(failure)
            } catch {
                return .failed(.launchFailed(error.localizedDescription))
            }
        }.value
    }

    private func runSynchronously(launchSpec: MCPServerLaunchSpec) throws -> MCPServerConnectionState {
        let fileManager = FileManager.default
        let temporaryRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("backtick-mcp-self-test-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = temporaryRootURL.appendingPathComponent("PromptCue.sqlite")
        let attachmentsURL = temporaryRootURL.appendingPathComponent("Attachments", isDirectory: true)

        try fileManager.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryRootURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchSpec.command)
        process.arguments = launchSpec.arguments + [
            "--database-path",
            databaseURL.path,
            "--attachments-path",
            attachmentsURL.path,
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw MCPServerConnectionFailure.launchFailed(error.localizedDescription)
        }

        let initializeRequest = try requestLine(
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": [
                    "name": "backtick-settings",
                    "version": "1.0",
                ],
            ]
        )
        let toolsRequest = try requestLine(id: 2, method: "tools/list")
        inputPipe.fileHandleForWriting.write(Data((initializeRequest + "\n" + toolsRequest + "\n").utf8))
        try? inputPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderr.isEmpty
                ? "Backtick MCP exited with status \(process.terminationStatus)."
                : stderr
            throw MCPServerConnectionFailure.launchFailed(detail)
        }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let responses = try parseResponses(from: stdout)

        guard let initialize = responses[1],
              let initializeResult = initialize["result"] as? [String: Any],
              let protocolVersion = initializeResult["protocolVersion"] as? String else {
            throw MCPServerConnectionFailure.invalidResponse(
                "Backtick MCP did not return a valid initialize response."
            )
        }

        guard let tools = responses[2],
              let toolsResult = tools["result"] as? [String: Any],
              let toolEntries = toolsResult["tools"] as? [[String: Any]] else {
            throw MCPServerConnectionFailure.invalidResponse(
                "Backtick MCP did not return a valid tools/list response."
            )
        }

        let toolNames = toolEntries.compactMap { $0["name"] as? String }
        let missingTools = Self.expectedToolNames.filter { !toolNames.contains($0) }
        if !missingTools.isEmpty {
            throw MCPServerConnectionFailure.missingExpectedTools(missingTools)
        }

        return .passed(
            MCPServerConnectionReport(
                protocolVersion: protocolVersion,
                toolNames: toolNames
            )
        )
    }

    private func requestLine(
        id: Int,
        method: String,
        params: [String: Any] = [:]
    ) throws -> String {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else {
            throw MCPServerConnectionFailure.invalidResponse("Failed to encode test request.")
        }

        return line
    }

    private func parseResponses(from stdout: String) throws -> [Int: [String: Any]] {
        let lines = stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        var responses: [Int: [String: Any]] = [:]

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let payload = object as? [String: Any],
                  let id = payload["id"] as? Int else {
                continue
            }

            responses[id] = payload
        }

        if responses.isEmpty {
            throw MCPServerConnectionFailure.invalidResponse(
                "Backtick MCP produced no parseable JSON-RPC output."
            )
        }

        return responses
    }
}
