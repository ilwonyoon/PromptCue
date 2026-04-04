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
    let configuredLaunchSpec: MCPServerLaunchSpec?
}

struct MCPServerLaunchSpec: Equatable {
    let command: String
    let arguments: [String]
    let environment: [String: String]

    init(
        command: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }

    var commandLine: String {
        ([command] + arguments).map(shellEscaped).joined(separator: " ")
    }

    var configuredClientID: String? {
        environment[MCPConnectorInspector.connectorClientEnvironmentKey]
    }

    private func shellEscaped(_ value: String) -> String {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) != nil || value.contains("\"") else {
            return value
        }

        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

enum BacktickMCPToolSurface {
    static let canonicalNames = [
        "status",
        "workflow",
        "list_notes",
        "get_note",
        "create_note",
        "update_note",
        "delete_note",
        "mark_notes_executed",
        "classify_notes",
        "group_notes",
        "list_saved_items",
        "list_documents",
        "recall_document",
        "propose_document_saves",
        "save_document",
        "update_document",
        "delete_document",
    ]

    private static let exposedNamesByCanonical = [
        "status": "backtick_status",
        "workflow": "backtick_workflow",
        "list_notes": "backtick_list_notes",
        "get_note": "backtick_get_note",
        "create_note": "backtick_create_note",
        "update_note": "backtick_update_note",
        "delete_note": "backtick_delete_note",
        "mark_notes_executed": "backtick_complete_notes",
        "classify_notes": "backtick_classify_notes",
        "group_notes": "backtick_group_notes",
        "list_saved_items": "backtick_list_saved_items",
        "list_documents": "backtick_list_docs",
        "recall_document": "backtick_recall_doc",
        "propose_document_saves": "backtick_propose_save",
        "save_document": "backtick_save_doc",
        "update_document": "backtick_update_doc",
        "delete_document": "backtick_delete_doc",
    ]

    static func exposedName(for canonicalName: String) -> String {
        exposedNamesByCanonical[canonicalName] ?? "backtick_\(canonicalName)"
    }

    static let currentExposedToolNames = Set(canonicalNames.map(exposedName))

    static let expectedCoreToolNames = [
        exposedName(for: "list_notes"),
        exposedName(for: "get_note"),
        exposedName(for: "create_note"),
        exposedName(for: "update_note"),
        exposedName(for: "delete_note"),
        exposedName(for: "mark_notes_executed"),
    ]

    static let verificationToolName = exposedName(for: "status")

    static func isLegacyAlias(_ toolName: String) -> Bool {
        canonicalNames.contains(toolName) || oldBrandedAliases.contains(toolName)
    }

    private static let oldBrandedAliases: Set<String> = Set(
        canonicalNames
            .map { "backtick_\($0)" }
            .filter { !currentExposedToolNames.contains($0) }
    )
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

    var configuredLaunchSpec: MCPServerLaunchSpec? {
        configuredLaunchSpecs.first
    }

    var configuredLaunchSpecs: [MCPServerLaunchSpec] {
        var specs: [MCPServerLaunchSpec] = []

        func appendIfNeeded(_ spec: MCPServerLaunchSpec?) {
            guard let spec, !specs.contains(spec) else {
                return
            }
            specs.append(spec)
        }

        switch configuredScope {
        case .project:
            appendIfNeeded(projectConfig?.configuredLaunchSpec)
        case .home:
            appendIfNeeded(homeConfig.configuredLaunchSpec)
        case .both:
            appendIfNeeded(projectConfig?.configuredLaunchSpec)
            appendIfNeeded(homeConfig.configuredLaunchSpec)
        case nil:
            break
        }

        return specs
    }

    /// Whether this client is ready for setup. Direct-config clients (Claude Desktop)
    /// don't need a CLI; CLI-based clients (Claude Code, Codex) do.
    var isClientAvailable: Bool {
        client.usesDirectConfig || hasDetectedCLI
    }
}

enum TunnelProvider: String, Equatable {
    case ngrok
    case cloudflare
    case none

    var displayName: String {
        switch self {
        case .ngrok: return "ngrok"
        case .cloudflare: return "Cloudflare Tunnel"
        case .none: return "tunnel"
        }
    }

    var executableName: String? {
        switch self {
        case .ngrok: return "ngrok"
        case .cloudflare: return "cloudflared"
        case .none: return nil
        }
    }
}

struct MCPConnectorInspection: Equatable {
    let repositoryRootPath: String?
    let bundledHelperPath: String?
    let launchSpec: MCPServerLaunchSpec?
    let ngrokPath: String?
    let cloudflaredPath: String?
    let clients: [MCPConnectorClientStatus]

    var detectedTunnelProvider: TunnelProvider {
        if cloudflaredPath != nil { return .cloudflare }
        if ngrokPath != nil { return .ngrok }
        return .none
    }

    var tunnelExecutablePath: String? {
        cloudflaredPath ?? ngrokPath
    }

    func status(for client: MCPConnectorClient) -> MCPConnectorClientStatus {
        guard let status = clients.first(where: { $0.client == client }) else {
            preconditionFailure("MCPConnectorInspection missing status for \(client)")
        }
        return status
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
            return "Launch Tunnel"
        case .installTunnel:
            return "Install Tunnel"
        case .copyPublicMCPURL:
            return "Copy Remote MCP URL"
        case .resetLocalState:
            return "Reconnect"
        case .retry:
            return "Try Again"
        }
    }
}

struct ExperimentalMCPHTTPStatusPresentation: Equatable {
    let title: String
    let reason: String
    let detail: String?
    let tone: ExperimentalMCPHTTPStatusTone
    let action: ExperimentalMCPHTTPStatusAction?
}

enum ExperimentalMCPHTTPProbeIssue: Equatable {
    case localEndpointUnreachable
    case publicEndpointUnreachable
}

private enum ExperimentalMCPHTTPRemoteClientSurface: String, Codable, Equatable {
    case web
    case macos
    case iphone
    case ipad
    case android
    case unknown

    var shortTitle: String {
        switch self {
        case .web:
            return "Web"
        case .macos:
            return "macOS"
        case .iphone:
            return "iPhone"
        case .ipad:
            return "iPad"
        case .android:
            return "Android"
        case .unknown:
            return "Unknown"
        }
    }

    var fullTitle: String {
        switch self {
        case .web:
            return "the web connector"
        case .macos:
            return "the macOS connector"
        case .iphone:
            return "the iPhone connector"
        case .ipad:
            return "the iPad connector"
        case .android:
            return "the Android connector"
        case .unknown:
            return "another remote connector"
        }
    }
}

private struct ExperimentalMCPHTTPRemoteRequestActivity: Codable, Equatable {
    let surface: ExperimentalMCPHTTPRemoteClientSurface
    let rpcMethod: String?
    let targetKind: String?
    let targetName: String?
    let recordedAt: Date

    var summary: String {
        var components = [surface.shortTitle]
        if let rpcMethod, !rpcMethod.isEmpty {
            components.append(rpcMethod)
        }

        if let targetName, !targetName.isEmpty {
            if targetKind == "prompt" {
                components.append("prompt:\(targetName)")
            } else if targetKind == "resource" {
                components.append("resource")
            } else {
                components.append(targetName)
            }
        }

        return components.joined(separator: " · ")
    }

    var usesLegacyToolAlias: Bool {
        guard rpcMethod == "tools/call",
              targetKind == "tool",
              let targetName,
              !targetName.isEmpty else {
            return false
        }

        return BacktickMCPToolSurface.isLegacyAlias(targetName)
    }
}

private struct ExperimentalMCPHTTPOAuthFailureActivity: Codable, Equatable {
    let errorCode: String
    let surface: ExperimentalMCPHTTPRemoteClientSurface
    let grantType: String?
    let recordedAt: Date

    var summary: String {
        var components = [surface.shortTitle, errorCode]
        if let grantType, !grantType.isEmpty {
            components.append(grantType)
        }
        return components.joined(separator: " · ")
    }
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
            return "Check Setup"
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

enum MCPConnectorReadinessState: Equatable {
    case unavailable
    case installRequired
    case needsSetup
    case configured
    case checking
    case connected
    case needsRefresh
    case needsAttention
}

struct MCPServerConnectionReport: Equatable {
    let protocolVersion: String
    let toolNames: [String]
    let verifiedToolName: String
    let verifiedLaunchSpecCount: Int

    init(
        protocolVersion: String,
        toolNames: [String],
        verifiedToolName: String,
        verifiedLaunchSpecCount: Int = 1
    ) {
        self.protocolVersion = protocolVersion
        self.toolNames = toolNames
        self.verifiedToolName = verifiedToolName
        self.verifiedLaunchSpecCount = verifiedLaunchSpecCount
    }

    var detail: String {
        if verifiedLaunchSpecCount > 1 {
            return "Backtick MCP launched, answered initialize/tools/list for \(toolNames.count) tools, and completed tools/call for \(verifiedToolName) across \(verifiedLaunchSpecCount) configured entries."
        }

        return "Backtick MCP launched, answered initialize/tools/list for \(toolNames.count) tools, and completed tools/call for \(verifiedToolName)."
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
    case toolCallFailed(toolName: String, message: String)

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
        case .toolCallFailed(let toolName, let message):
            return "Backtick MCP launched and listed tools, but the verification tool call for \(toolName) failed: \(message)"
        }
    }
}

protocol MCPServerConnectionTesting {
    func run(launchSpec: MCPServerLaunchSpec) async -> MCPServerConnectionState
}

struct MCPConnectorInspector {
    static let connectorClientEnvironmentKey = "BACKTICK_CONNECTOR_CLIENT"
    private static let stableLauncherRelativePath = ".local/bin/BacktickMCP"

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
        let stableLauncherURL = bundledHelperURL.flatMap(syncStableLauncher)
        let launchSpec = launchSpecification(
            stableLauncherURL: stableLauncherURL,
            bundledHelperURL: bundledHelperURL
        )

        return MCPConnectorInspection(
            repositoryRootPath: repositoryRootURL?.path,
            bundledHelperPath: bundledHelperURL?.path,
            launchSpec: launchSpec,
            ngrokPath: locateExecutable(named: "ngrok"),
            cloudflaredPath: locateExecutable(named: "cloudflared"),
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

    private func launchSpecification(
        stableLauncherURL: URL?,
        bundledHelperURL: URL?
    ) -> MCPServerLaunchSpec? {
        if let stableLauncherURL {
            return MCPServerLaunchSpec(
                command: stableLauncherURL.path,
                arguments: []
            )
        }

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

    private func stableLauncherURL() -> URL {
        homeDirectoryURL
            .appendingPathComponent(Self.stableLauncherRelativePath, isDirectory: false)
    }

    private func syncStableLauncher(for bundledHelperURL: URL) -> URL? {
        let launcherURL = stableLauncherURL()
        let launcherContents = stableLauncherScript(targetPath: bundledHelperURL.path)

        do {
            try fileManager.createDirectory(
                at: launcherURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if let existingContents = try? String(contentsOf: launcherURL),
               existingContents == launcherContents,
               isExecutableFile(launcherURL) {
                return launcherURL.standardizedFileURL
            }

            try launcherContents.write(to: launcherURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: launcherURL.path
            )
            return launcherURL.standardizedFileURL
        } catch {
            return nil
        }
    }

    private func stableLauncherScript(targetPath: String) -> String {
        let escapedTargetPath = targetPath.replacingOccurrences(of: "'", with: "'\"'\"'")
        return """
        #!/bin/sh
        exec '\(escapedTargetPath)' "$@"
        """
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
        let statusLaunchSpec: MCPServerLaunchSpec?
        if !fileManager.fileExists(atPath: url.path) {
            presence = .missing
            statusLaunchSpec = nil
        } else if let resolvedLaunchSpec = configuredLaunchSpec(for: client, url: url) {
            presence = .configured
            statusLaunchSpec = resolvedLaunchSpec
        } else {
            presence = .presentWithoutBacktick
            statusLaunchSpec = nil
        }

        return MCPConnectorConfigLocationStatus(
            path: url.path,
            presence: presence,
            configuredLaunchSpec: statusLaunchSpec
        )
    }

    private func configuredLaunchSpec(
        for client: MCPConnectorClient,
        url: URL
    ) -> MCPServerLaunchSpec? {
        switch client {
        case .claudeDesktop, .claudeCode:
            return configuredLaunchSpecInClaudeJSON(url: url)
        case .codex:
            return configuredLaunchSpecInCodexTOML(url: url)
        }
    }

    private func configuredLaunchSpecInClaudeJSON(url: URL) -> MCPServerLaunchSpec? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let repositoryRootURL,
           let projects = json["projects"] as? [String: Any],
           let projectEntry = projects[repositoryRootURL.path] as? [String: Any],
           let servers = projectEntry["mcpServers"] as? [String: Any],
           let launchSpec = configuredLaunchSpecInClaudeServerMap(servers) {
            return launchSpec
        }

        if let servers = json["mcpServers"] as? [String: Any] {
            return configuredLaunchSpecInClaudeServerMap(servers)
        }

        return nil
    }

    private func configuredLaunchSpecInClaudeServerMap(_ servers: [String: Any]) -> MCPServerLaunchSpec? {
        if let namedDefinition = servers.first(where: { $0.key.lowercased() == "backtick" })?.value,
           let launchSpec = launchSpecFromJSONServerDefinition(namedDefinition) {
            return launchSpec
        }

        for definition in servers.values {
            guard let launchSpec = launchSpecFromJSONServerDefinition(definition),
                  launchSpecLooksLikeBacktick(launchSpec) else {
                continue
            }
            return launchSpec
        }

        return nil
    }

    private func launchSpecFromJSONServerDefinition(_ value: Any) -> MCPServerLaunchSpec? {
        guard let dictionary = value as? [String: Any],
              let command = dictionary["command"] as? String else {
            return nil
        }

        let arguments = (dictionary["args"] as? [Any])?.compactMap { $0 as? String } ?? []
        let environment = (dictionary["env"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        return MCPServerLaunchSpec(
            command: command,
            arguments: arguments,
            environment: environment
        )
    }

    private func launchSpecLooksLikeBacktick(_ launchSpec: MCPServerLaunchSpec) -> Bool {
        if launchSpec.command.contains("BacktickMCP") || launchSpec.command.contains("PromptCue") {
            return true
        }

        return launchSpec.arguments.contains {
            $0.contains("BacktickMCP") || $0.contains("PromptCue")
        }
    }

    private func configuredLaunchSpecInCodexTOML(url: URL) -> MCPServerLaunchSpec? {
        guard let contents = try? String(contentsOf: url) else {
            return nil
        }

        let lines = contents.components(separatedBy: .newlines)
        var currentSection: String?
        var command: String?
        var arguments: [String] = []
        var environment: [String: String] = [:]
        var arrayKey: String?
        var arrayLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = normalizedTOMLSectionName(trimmed)
                arrayKey = nil
                arrayLines.removeAll(keepingCapacity: true)
                continue
            }

            guard currentSection == "mcp_servers.backtick" || currentSection == "mcp_servers.backtick.env" else {
                continue
            }

            if let currentArrayKey = arrayKey {
                arrayLines.append(trimmed)
                if trimmed.contains("]") {
                    let combinedValue = arrayLines.joined(separator: " ")
                    if currentArrayKey == "args" {
                        arguments = parseTOMLStringArray(combinedValue) ?? []
                    }
                    arrayKey = nil
                    arrayLines.removeAll(keepingCapacity: true)
                }
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            if currentSection == "mcp_servers.backtick.env" {
                environment[key] = parseTOMLStringLiteral(value)
                continue
            }

            switch key {
            case "command":
                command = parseTOMLStringLiteral(value)
            case "args":
                if value.contains("[") && !value.contains("]") {
                    arrayKey = key
                    arrayLines = [value]
                } else {
                    arguments = parseTOMLStringArray(value) ?? []
                }
            default:
                break
            }
        }

        guard let command else {
            return nil
        }

        return MCPServerLaunchSpec(
            command: command,
            arguments: arguments,
            environment: environment
        )
    }

    private func normalizedTOMLSectionName(_ rawValue: String) -> String? {
        let trimmed = rawValue
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed.replacingOccurrences(of: "\"", with: "")
    }

    private func parseTOMLStringLiteral(_ rawValue: String) -> String? {
        let trimmed = trimmedTOMLComment(from: rawValue)
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let data = trimmed.data(using: .utf8),
           let string = try? JSONDecoder().decode(String.self, from: data) {
            return string
        }

        if trimmed.hasPrefix("'"), trimmed.hasSuffix("'"), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast())
        }

        return nil
    }

    private func parseTOMLStringArray(_ rawValue: String) -> [String]? {
        let trimmed = trimmedTOMLComment(from: rawValue)
            .trimmingCharacters(in: .whitespaces)
        guard let data = trimmed.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }

        return values
    }

    private func trimmedTOMLComment(from rawValue: String) -> String {
        var result = ""
        var isInsideDoubleQuotes = false
        var isInsideSingleQuotes = false

        for character in rawValue {
            switch character {
            case "\"" where !isInsideSingleQuotes:
                isInsideDoubleQuotes.toggle()
            case "'" where !isInsideDoubleQuotes:
                isInsideSingleQuotes.toggle()
            case "#" where !isInsideDoubleQuotes && !isInsideSingleQuotes:
                return result
            default:
                break
            }

            result.append(character)
        }

        return result
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
                    homeDirectoryURL.appendingPathComponent(".npm-global/bin").path,
                    homeDirectoryURL.appendingPathComponent(".nvm/current/bin").path,
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
        let configuredLaunchSpec = instrumentedLaunchSpec(launchSpec, for: client)
        let cliCommand = MCPServerLaunchSpec(
            command: cliPath ?? (client.executableName ?? client.rawValue),
            arguments: ["mcp", "add"]
        ).commandLine

        switch client {
        case .claudeDesktop:
            return nil
        case .claudeCode:
            let envFlags = configuredLaunchSpec.environment
                .sorted(by: { $0.key < $1.key })
                .map { "-e \(shellEscapedEnvPair(key: $0.key, value: $0.value))" }
                .joined(separator: " ")
            let envSegment = envFlags.isEmpty ? "" : "\(envFlags) "
            return "\(cliCommand) backtick --transport stdio --scope user \(envSegment)-- \(configuredLaunchSpec.commandLine)"
        case .codex:
            let envFlags = configuredLaunchSpec.environment
                .sorted(by: { $0.key < $1.key })
                .map { "--env \(shellEscapedEnvPair(key: $0.key, value: $0.value))" }
                .joined(separator: " ")
            let envSegment = envFlags.isEmpty ? "" : "\(envFlags) "
            return "\(cliCommand) backtick \(envSegment)-- \(configuredLaunchSpec.commandLine)"
        }
    }

    private func configSnippet(
        for client: MCPConnectorClient,
        launchSpec: MCPServerLaunchSpec
    ) -> String {
        let configuredLaunchSpec = instrumentedLaunchSpec(launchSpec, for: client)
        switch client {
        case .claudeDesktop, .claudeCode:
            let object: [String: Any] = [
                "mcpServers": [
                    "backtick": [
                        "command": configuredLaunchSpec.command,
                        "args": configuredLaunchSpec.arguments,
                        "env": configuredLaunchSpec.environment,
                    ],
                ],
            ]
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            return String(data: data ?? Data(), encoding: .utf8) ?? "{}"

        case .codex:
            let arguments = configuredLaunchSpec.arguments
                .map { argument in
                    "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
                }
                .joined(separator: ", ")
            let environment = configuredLaunchSpec.environment
                .sorted(by: { $0.key < $1.key })
                .map { key, value in
                    "\(key) = \"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
                }
                .joined(separator: "\n")

            var snippet = """
            [mcp_servers.backtick]
            command = "\(configuredLaunchSpec.command.replacingOccurrences(of: "\"", with: "\\\""))"
            args = [\(arguments)]
            """

            if !environment.isEmpty {
                snippet += """

                [mcp_servers.backtick.env]
                \(environment)
                """
            }

            return snippet
        }
    }

    private func instrumentedLaunchSpec(
        _ launchSpec: MCPServerLaunchSpec,
        for client: MCPConnectorClient
    ) -> MCPServerLaunchSpec {
        var environment = launchSpec.environment
        environment[Self.connectorClientEnvironmentKey] = client.rawValue
        return MCPServerLaunchSpec(
            command: launchSpec.command,
            arguments: launchSpec.arguments,
            environment: environment
        )
    }

    private func shellEscapedEnvPair(key: String, value: String) -> String {
        MCPServerLaunchSpec(command: "/usr/bin/env", arguments: ["\(key)=\(value)"]).commandLine
            .replacingOccurrences(of: "/usr/bin/env ", with: "")
    }
}

@MainActor
final class MCPConnectorSettingsModel: ObservableObject {
    deinit {
        experimentalRemotePeriodicProbeTimer?.invalidate()
    }

    static let chatGPTSetupGuideURL = URL(string: "https://github.com/ilwonyoon/Backtick/blob/main/docs/ChatGPT-Setup-Guide.md")!
    private static let ngrokDocumentationURL = URL(string: "https://ngrok.com/download")!
    private static let cloudflaredDocumentationURL = URL(string: "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/")!
    private static let connectedActivityFreshnessWindow: TimeInterval = 30 * 24 * 60 * 60
    private static let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private enum ExperimentalRemoteDefaultsKey {
        static let isEnabled = "Backtick.ExperimentalMCPHTTP.Enabled"
        static let port = "Backtick.ExperimentalMCPHTTP.Port"
        static let authMode = "Backtick.ExperimentalMCPHTTP.AuthMode"
        static let apiKey = "Backtick.ExperimentalMCPHTTP.APIKey"
        static let publicBaseURL = "Backtick.ExperimentalMCPHTTP.PublicBaseURL"
        static let lastSuccessfulRequest = "Backtick.ExperimentalMCPHTTP.LastSuccessfulRequest"
        static let lastOAuthFailure = "Backtick.ExperimentalMCPHTTP.LastOAuthFailure"
    }

    @Published private(set) var inspection: MCPConnectorInspection
    @Published private(set) var connectionState: MCPServerConnectionState = .idle
    @Published private(set) var clientConnectionStates: [MCPConnectorClient: MCPServerConnectionState] = [:]
    @Published private(set) var clientConnectionActivities: [MCPConnectorClient: MCPConnectorConnectionActivity] = [:]
    @Published private(set) var experimentalRemoteSettings: ExperimentalMCPHTTPSettings
    @Published private(set) var experimentalRemoteRuntimeState: ExperimentalMCPHTTPRuntimeState = .stopped
    @Published var directConfigSuccessClient: MCPConnectorClient?
    private var experimentalRemoteLastOAuthFailure: ExperimentalMCPHTTPOAuthFailureActivity?
    private var experimentalRemoteLastSuccessfulRequest: ExperimentalMCPHTTPRemoteRequestActivity?

    private let inspector: MCPConnectorInspector
    private let connectionTester: MCPServerConnectionTesting
    private let connectionActivityReader: MCPConnectorConnectionActivityReading
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
    private var clientTestedLaunchSpecs: [MCPConnectorClient: [MCPServerLaunchSpec]] = [:]
    private var connectionTask: Task<Void, Never>?
    private var connectionTaskClient: MCPConnectorClient?
    private var setupRefreshTask: Task<Void, Never>?
    private var experimentalRemoteProbeTask: Task<Void, Never>?
    private var experimentalRemotePeriodicProbeTimer: Timer?
    private var experimentalRemoteTunnelDetectionTask: Task<Void, Never>?
    private var experimentalRemoteProbeIssue: ExperimentalMCPHTTPProbeIssue?
    private var experimentalRemoteDetectedPublicBaseURL: URL?

    init(
        inspector: MCPConnectorInspector = MCPConnectorInspector(),
        connectionTester: MCPServerConnectionTesting = MCPServerSelfTester(),
        connectionActivityReader: MCPConnectorConnectionActivityReading? = nil,
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
        self.connectionActivityReader = connectionActivityReader ?? MCPConnectorConnectionActivityStore(
            fileManager: fileManager
        )
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
        let initialInspection = inspector.inspect()
        let initialExperimentalRemoteSettings = Self.loadExperimentalRemoteSettings(from: userDefaults)
        self.inspection = initialInspection
        self.experimentalRemoteSettings = initialExperimentalRemoteSettings
        self.clientConnectionActivities = resolvedClientConnectionActivities(from: initialInspection)
        self.experimentalRemoteLastSuccessfulRequest = Self.loadPersistedRemoteRequestActivity(from: userDefaults)
        self.experimentalRemoteLastOAuthFailure = Self.loadPersistedRemoteOAuthFailure(from: userDefaults)
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
            return "Local check passed"
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
            return "Backtick is ready in this build. Each client below will tell you whether it is configured, connected, or needs attention."
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
        clientConnectionActivities = resolvedClientConnectionActivities(from: updatedInspection)
        experimentalRemoteSettings = Self.loadExperimentalRemoteSettings(from: userDefaults)
        ensureExperimentalRemoteAPIKeyIfNeeded()
        refreshExperimentalRemoteTunnelDetection()
        let configuredClients = Set(
            updatedInspection.clients
                .filter(\.hasConfiguredScope)
                .map(\.client)
        )
        var filteredStates: [MCPConnectorClient: MCPServerConnectionState] = [:]
        var filteredTestedLaunchSpecs: [MCPConnectorClient: [MCPServerLaunchSpec]] = [:]

        for clientStatus in updatedInspection.clients where configuredClients.contains(clientStatus.client) {
            let client = clientStatus.client
            guard let state = clientConnectionStates[client] else {
                continue
            }

            if state.isRunning {
                filteredStates[client] = state
                continue
            }

            guard let testedLaunchSpecs = clientTestedLaunchSpecs[client],
                  sameLaunchSpecs(testedLaunchSpecs, clientStatus.configuredLaunchSpecs) else {
                continue
            }

            filteredStates[client] = state
            filteredTestedLaunchSpecs[client] = testedLaunchSpecs
        }

        clientConnectionStates = filteredStates
        clientTestedLaunchSpecs = filteredTestedLaunchSpecs
    }

    private func resolvedClientConnectionActivities(
        from inspection: MCPConnectorInspection
    ) -> [MCPConnectorClient: MCPConnectorConnectionActivity] {
        let activities = connectionActivityReader.loadActivities()
        var resolved = [MCPConnectorClient: MCPConnectorConnectionActivity]()

        for client in inspection.clients where client.hasConfiguredScope {
            let launchSpecs = client.configuredLaunchSpecs
            guard !launchSpecs.isEmpty else {
                continue
            }

            let matchedActivity = activities
                .filter { $0.transport == .stdio }
                .filter { activity in
                    launchSpecs.contains { launchSpec in
                        activityMatches(activity, client: client.client, launchSpec: launchSpec)
                    }
                }
                .sorted(by: { $0.recordedAt > $1.recordedAt })
                .first

            if let matchedActivity {
                resolved[client.client] = matchedActivity
            }
        }

        return resolved
    }

    private func activityMatches(
        _ activity: MCPConnectorConnectionActivity,
        client: MCPConnectorClient,
        launchSpec: MCPServerLaunchSpec
    ) -> Bool {
        if let launchCommand = activity.launchCommand,
           !equivalentBacktickManagedLaunchCommands(launchCommand, launchSpec.command) {
            return false
        }

        if let launchArguments = activity.launchArguments,
           launchArguments != launchSpec.arguments {
            return false
        }

        if let configuredClientID = activity.configuredClientID, !configuredClientID.isEmpty {
            return configuredClientID == (launchSpec.configuredClientID ?? client.rawValue)
        }

        return inferredClient(from: activity.clientName) == client
    }

    private func equivalentBacktickManagedLaunchCommands(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        let normalizedLHS = URL(fileURLWithPath: lhs).standardizedFileURL.path
        let normalizedRHS = URL(fileURLWithPath: rhs).standardizedFileURL.path
        if normalizedLHS == normalizedRHS {
            return true
        }

        guard let managedPair = currentBacktickManagedLaunchCommandPair() else {
            return false
        }

        return Set([normalizedLHS, normalizedRHS]) == managedPair
    }

    private func currentBacktickManagedLaunchCommandPair() -> Set<String>? {
        guard let bundledHelperPath = inspection.bundledHelperPath else {
            return nil
        }

        let normalizedBundledHelper = URL(fileURLWithPath: bundledHelperPath).standardizedFileURL.path
        guard let launchSpec = inspection.launchSpec else {
            return nil
        }

        let normalizedLaunchCommand = URL(fileURLWithPath: launchSpec.command).standardizedFileURL.path
        guard normalizedLaunchCommand.hasSuffix("/Library/Application Support/Backtick/bin/BacktickMCP")
           || normalizedLaunchCommand.hasSuffix(".app/Contents/Helpers/BacktickMCP")
           || normalizedLaunchCommand.hasSuffix("/.local/bin/BacktickMCP") else {
            return nil
        }

        return [normalizedLaunchCommand, normalizedBundledHelper]
    }

    private func inferredClient(from clientName: String?) -> MCPConnectorClient? {
        guard let normalizedName = clientName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalizedName.isEmpty else {
            return nil
        }

        if normalizedName.contains("codex") {
            return .codex
        }
        if normalizedName.contains("claude-code") || normalizedName.contains("claude code") {
            return .claudeCode
        }
        if normalizedName.contains("claude") {
            return .claudeDesktop
        }

        return nil
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

    var detectedTunnelProvider: TunnelProvider {
        inspection.detectedTunnelProvider
    }

    var experimentalRemoteRecommendedTunnelPath: String? {
        inspection.tunnelExecutablePath
    }

    var experimentalRemoteRecommendedTunnelCommand: String {
        switch detectedTunnelProvider {
        case .ngrok, .none:
            return MCPServerLaunchSpec(
                command: inspection.ngrokPath ?? "ngrok",
                arguments: ["http", "\(experimentalRemoteSettings.port)"]
            ).commandLine
        case .cloudflare:
            return MCPServerLaunchSpec(
                command: inspection.cloudflaredPath ?? "cloudflared",
                arguments: ["tunnel", "--url", "http://localhost:\(experimentalRemoteSettings.port)"]
            ).commandLine
        }
    }

    var experimentalRemoteRecommendedTunnelSummary: String {
        switch detectedTunnelProvider {
        case .ngrok:
            return "Recommended for advanced users. ngrok is installed at \(inspection.ngrokPath ?? "ngrok"). Run it against port \(experimentalRemoteSettings.port) to get a public HTTPS URL, then paste that base URL below."
        case .cloudflare:
            return "Recommended for advanced users. cloudflared is installed at \(inspection.cloudflaredPath ?? "cloudflared"). Run it against port \(experimentalRemoteSettings.port) to get a public HTTPS URL, then paste that base URL below."
        case .none:
            return "Recommended for advanced users. Install a tunnel provider (ngrok or cloudflared), then run it against port \(experimentalRemoteSettings.port) to get a public HTTPS URL for this Mac."
        }
    }

    func tunnelActionTitle(for action: ExperimentalMCPHTTPStatusAction) -> String {
        switch action {
        case .launchTunnel:
            return "Launch \(detectedTunnelProvider.displayName)"
        case .installTunnel:
            if detectedTunnelProvider == .none {
                return "Install ngrok"  // default recommendation
            }
            return "Install \(detectedTunnelProvider.displayName)"
        default:
            return action.title
        }
    }

    var experimentalRemoteTunnelDocumentationURL: URL {
        switch detectedTunnelProvider {
        case .cloudflare:
            return Self.cloudflaredDocumentationURL
        case .ngrok, .none:
            return Self.ngrokDocumentationURL
        }
    }

    var experimentalRemoteOAuthStateExists: Bool {
        guard let experimentalRemoteOAuthStateFileURL else {
            return false
        }

        return fileManager.fileExists(atPath: experimentalRemoteOAuthStateFileURL.path)
    }

    var experimentalRemoteIsConnected: Bool {
        experimentalRemoteLastOAuthFailure == nil
            && recentExperimentalRemoteRequestActivity != nil
            && !experimentalRemoteNeedsSchemaRefresh
            && experimentalRemoteRuntimeState == .running
            && experimentalRemoteProbeIssue == nil
    }

    var experimentalRemoteNeedsSchemaRefresh: Bool {
        guard experimentalRemoteLastOAuthFailure == nil,
              experimentalRemoteRuntimeState == .running,
              experimentalRemoteProbeIssue == nil,
              let request = recentExperimentalRemoteRequestActivity else {
            return false
        }

        return request.usesLegacyToolAlias
    }

    var experimentalRemoteShouldShowInlinePublicBaseURL: Bool {
        guard experimentalRemoteSettings.isEnabled else {
            return false
        }

        if experimentalRemoteLastOAuthFailure != nil {
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
                detail: nil,
                tone: .neutral,
                action: nil
            )
        }

        if let experimentalRemoteLastOAuthFailure {
            return statusPresentationForOAuthFailure(experimentalRemoteLastOAuthFailure)
        }

        switch experimentalRemoteRuntimeState {
        case .starting:
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Starting",
                reason: "Backtick is starting the local MCP endpoint now.",
                detail: nil,
                tone: .accent,
                action: nil
            )
        case .restarting:
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Restarting",
                reason: "Backtick is restarting the local MCP endpoint with your latest settings.",
                detail: nil,
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
                detail: nil,
                tone: .warning,
                action: experimentalRemoteRecommendedTunnelPath == nil ? .installTunnel : .launchTunnel
            )
        }

        if let experimentalRemoteProbeIssue,
           experimentalRemoteRuntimeState == .running {
            return statusPresentationForProbeIssue(experimentalRemoteProbeIssue)
        }

        if experimentalRemoteNeedsSchemaRefresh,
           let requestActivity = recentExperimentalRemoteRequestActivity {
            return statusPresentationForSchemaRefresh(requestActivity)
        }

        if experimentalRemoteIsConnected {
            let connectedSurface = recentExperimentalRemoteRequestActivity?.surface
            return ExperimentalMCPHTTPStatusPresentation(
                title: connectedSurface.map(connectedTitle(for:)) ?? "Connected",
                reason: connectedSurface.map(connectedReason(for:)) ?? "ChatGPT has already reached this Backtick endpoint with your current app setup.",
                detail: recentExperimentalRemoteRequestActivity.map { "Recent request: \($0.summary)." },
                tone: .success,
                action: .copyPublicMCPURL
            )
        }

        return ExperimentalMCPHTTPStatusPresentation(
            title: "Ready to connect",
            reason: runningStatusReason,
            detail: nil,
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
            stopPeriodicRemoteProbe()
            resetExperimentalRemoteDiagnostics()
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
        resetExperimentalRemoteDiagnostics()
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
        resetExperimentalRemoteDiagnostics()
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
        resetExperimentalRemoteDiagnostics()
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
        let tunnelCommand = experimentalRemoteRecommendedTunnelCommand
        switch detectedTunnelProvider {
        case .ngrok, .none:
            // tunnelCommand is shell-safe: path is shell-escaped via MCPServerLaunchSpec.commandLine,
            // port is UInt16 (numeric only). Using pkill -f to target only ngrok HTTP tunnels.
            return terminalLauncher.launchInTerminal(command: "pkill -f 'ngrok http' 2>/dev/null; sleep 1; \(tunnelCommand)")
        case .cloudflare:
            // tunnelCommand is shell-safe: path is shell-escaped via MCPServerLaunchSpec.commandLine,
            // port is UInt16 (numeric only). Using pkill -f to target only cloudflared tunnels.
            return terminalLauncher.launchInTerminal(
                command: "pkill -f 'cloudflared tunnel' 2>/dev/null; sleep 1; \(tunnelCommand)"
            )
        }
    }

    func openExperimentalRemoteTunnelDocumentation() {
        workspace.open(experimentalRemoteTunnelDocumentationURL)
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
        resetExperimentalRemoteDiagnostics()
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

    func startPeriodicRemoteProbe() {
        stopPeriodicRemoteProbe()
        guard experimentalRemoteSettings.isEnabled,
              experimentalRemotePublicBaseURL != nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshExperimentalRemoteProbe()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        experimentalRemotePeriodicProbeTimer = timer
    }

    func stopPeriodicRemoteProbe() {
        experimentalRemotePeriodicProbeTimer?.invalidate()
        experimentalRemotePeriodicProbeTimer = nil
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
            switch detectedTunnelProvider {
            case .cloudflare:
                _ = terminalLauncher.launchInTerminal(
                    command: "brew install cloudflare/cloudflare/cloudflared && cloudflared tunnel --url http://localhost:\(experimentalRemoteSettings.port)"
                )
            case .ngrok, .none:
                _ = terminalLauncher.launchInTerminal(
                    command: "brew install ngrok && ngrok http \(experimentalRemoteSettings.port)"
                )
            }
        case .copyPublicMCPURL:
            copyExperimentalRemotePublicEndpoint()
        case .resetLocalState:
            _ = resetExperimentalRemoteOAuthState()
            copyExperimentalRemotePublicEndpoint()
        case .retry:
            retryExperimentalRemote()
        }
    }

    func recordExperimentalRemoteHelperLog(_ chunk: String) {
        for rawLine in chunk.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if let failureActivity = experimentalRemoteOAuthFailureActivity(from: line) {
                experimentalRemoteLastOAuthFailure = failureActivity
                persistExperimentalRemoteDiagnostics()
                experimentalRemoteProbeIssue = nil
                continue
            }

            if let requestActivity = experimentalRemoteRequestActivity(from: line) {
                experimentalRemoteLastSuccessfulRequest = requestActivity
                if let failureActivity = experimentalRemoteLastOAuthFailure,
                   shouldClearRemoteOAuthFailure(failureActivity, after: requestActivity) {
                    experimentalRemoteLastOAuthFailure = nil
                }
                persistExperimentalRemoteDiagnostics()
                experimentalRemoteProbeIssue = nil
            }
        }
    }

    func verificationState(for client: MCPConnectorClientStatus) -> MCPServerConnectionState {
        clientConnectionStates[client.client] ?? .idle
    }

    func actualConnectionActivity(for client: MCPConnectorClientStatus) -> MCPConnectorConnectionActivity? {
        clientConnectionActivities[client.client]
    }

    private func recentConnectionActivity(for client: MCPConnectorClientStatus) -> MCPConnectorConnectionActivity? {
        guard let activity = actualConnectionActivity(for: client),
              isFreshConnectionActivity(activity) else {
            return nil
        }

        return activity
    }

    func readinessState(for client: MCPConnectorClientStatus) -> MCPConnectorReadinessState {
        if !isServerAvailable {
            return .unavailable
        }

        if !client.isClientAvailable {
            return .installRequired
        }

        guard client.hasConfiguredScope else {
            return .needsSetup
        }

        if hasStaleLocalToolSurface(for: client) {
            return .needsRefresh
        }

        if recentConnectionActivity(for: client) != nil {
            return .connected
        }

        if verificationState(for: client).isRunning {
            return .checking
        }

        if case .failed = verificationState(for: client) {
            return .needsAttention
        }

        return .configured
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

        if hasConfiguredHelperDrift(for: client) {
            return "Needs attention"
        }

        switch readinessState(for: client) {
        case .connected:
            return "Connected"
        case .checking:
            return "Checking"
        case .configured:
            return "Configured"
        case .needsRefresh:
            return "Needs refresh"
        case .needsAttention:
            return "Needs attention"
        case .unavailable, .installRequired, .needsSetup:
            return nil
        }
    }

    func clientSummary(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "Install \(client.client.title) on this Mac first, then come back to set up Backtick."
        }

        if hasConfiguredHelperDrift(for: client) {
            return "This \(client.client.title) config still points to an older Backtick MCP helper. Click Connect to rewrite it to the current helper, then restart \(client.client.title)."
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

        switch readinessState(for: client) {
        case .checking:
            return "The local setup check is running now."
        case .connected:
            if client.client == .claudeCode {
                return appendLastUsedDetail(
                    "Backtick is connected in Claude Code. Non-interactive Claude runs still need an explicit allowed tool list.",
                    for: client
                )
            }

            return appendLastUsedDetail("Backtick is connected in \(client.client.title).", for: client)
        case .configured:
            let staleLastUsedDetail = lastUsedDetail(for: client)
            switch verificationState(for: client) {
            case .passed:
                var message = "Backtick is configured here. The local check passed. Use Backtick once in \(client.client.title) to confirm it as connected."
                if let staleLastUsedDetail, actualConnectionActivity(for: client) != nil {
                    message += " \(staleLastUsedDetail)"
                }
                return message
            case .idle, .running, .failed:
                var message = "Backtick is configured here. Run Check Setup, then use Backtick once in \(client.client.title) to confirm the connection."
                if let staleLastUsedDetail, actualConnectionActivity(for: client) != nil {
                    message += " \(staleLastUsedDetail)"
                }
                return message
            }
        case .needsRefresh:
            return "This \(client.client.title) session is still calling an older Backtick tool name. Restart the client or begin a fresh session so it reloads the current Backtick tool surface."
        case .needsAttention:
            return "Backtick is set up, but the latest local server test failed. Fix the issue, then run the test again."
        case .unavailable, .installRequired, .needsSetup:
            return "Backtick is configured here."
        }
    }

    func clientProgressSummary(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "\(client.client.title) is required before Backtick can connect here."
        }

        if hasConfiguredHelperDrift(for: client) {
            let location = client.configuredScope?.title ?? "Unknown"
            return "Backtick is configured in \(location), but that config still points to an older helper."
        }

        if !client.hasConfiguredScope {
            if client.hasOtherConfigFiles {
                return "A config file already exists here, but Backtick has not been added yet."
            }

            return "Backtick is not added to \(client.client.title) yet."
        }

        let location = client.configuredScope?.title ?? "Unknown"

        switch readinessState(for: client) {
        case .configured:
            var message = "Backtick is configured in \(location), but it still needs one real client tool call before it counts as connected."
            if let lastUsedDetail = lastUsedDetail(for: client),
               actualConnectionActivity(for: client) != nil {
                message += " \(lastUsedDetail)"
            }
            return message
        case .checking:
            return "Backtick is configured in \(location). The local setup check is running now."
        case .connected:
            return appendLastUsedDetail("Backtick is connected in \(location).", for: client)
        case .needsRefresh:
            return "Backtick is configured in \(location), but the most recent client session is still using an older Backtick tool name."
        case .needsAttention:
            return "Backtick is configured in \(location), but the last local check failed."
        case .unavailable, .installRequired, .needsSetup:
            return "Backtick is configured in \(location)."
        }
    }

    func clientNextStepTitle(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "Install \(client.client.title)"
        }

        if hasConfiguredHelperDrift(for: client) {
            return "Reconnect to \(client.client.title)"
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

        switch readinessState(for: client) {
        case .configured:
            switch verificationState(for: client) {
            case .passed:
                return "Use Backtick in \(client.client.title)"
            case .idle, .running, .failed:
                return "Check the setup"
            }
        case .checking:
            return "Checking setup"
        case .connected:
            return "Backtick is connected"
        case .needsRefresh:
            switch client.client {
            case .claudeDesktop:
                return "Restart Claude Desktop"
            case .claudeCode:
                return "Start a new Claude Code session"
            case .codex:
                return "Start a new Codex session"
            }
        case .needsAttention:
            return "Fix the setup and check again"
        case .unavailable, .installRequired, .needsSetup:
            return "Add Backtick to \(client.client.title)"
        }
    }

    func clientNextStepDetail(for client: MCPConnectorClientStatus) -> String {
        if !client.client.usesDirectConfig, !client.hasDetectedCLI {
            return "Backtick works through \(client.client.title). Install it first, then come back here to finish setup."
        }

        if hasConfiguredHelperDrift(for: client) {
            if client.client.usesDirectConfig {
                return "Click Connect and Backtick will rewrite the config file to the current bundled helper. Restart \(client.client.title) after the rewrite."
            }

            return "Click Connect and Backtick will rerun the setup command so \(client.client.title) uses the current helper path. Restart \(client.client.title) after reconnecting."
        }

        if !client.hasConfiguredScope {
            if client.client.usesDirectConfig {
                return "Click Connect and Backtick will write the config file automatically. Restart \(client.client.title) to pick up the change."
            }

            if client.client.supportsTerminalSetupAutomation {
                switch client.client {
                case .claudeCode:
                    return "Click Connect and Backtick will open Terminal and run the global Claude Code setup command. Then return here to check it, or use Backtick once in Claude Code."
                case .codex:
                    return "Click Connect and Backtick will open Terminal and run the Codex setup command. Then return here to check it, or use Backtick once in Codex."
                case .claudeDesktop:
                    break
                }
            }

            if client.hasOtherConfigFiles {
                return "Open setup steps, then either run the terminal command or add Backtick manually in the config file."
            }

            return "Open setup steps, paste the command into Terminal, then come back here."
        }

        switch readinessState(for: client) {
        case .configured:
            switch verificationState(for: client) {
            case .passed:
                var message = "The local helper check passed. Ask \(client.client.title) to call one Backtick tool to promote this connector to Connected."
                if let lastUsedDetail = lastUsedDetail(for: client),
                   actualConnectionActivity(for: client) != nil {
                    message += " \(lastUsedDetail)"
                }
                return message
            case .idle, .running, .failed:
                var message = "Run a local setup check here first. After that, use Backtick once inside \(client.client.title) to confirm the real connection."
                if let lastUsedDetail = lastUsedDetail(for: client),
                   actualConnectionActivity(for: client) != nil {
                    message += " \(lastUsedDetail)"
                }
                return message
            }
        case .checking:
            return "Backtick is launching the configured MCP helper, checking the tool surface, and running a safe tool call now."
        case .connected:
            if client.client == .claudeCode {
                return appendLastUsedDetail(
                    "Claude Code has already completed a Backtick tool call here. If you automate Claude with `--permission-mode dontAsk`, keep Backtick tools in `--allowedTools`.",
                    for: client
                )
            }

            return appendLastUsedDetail(
                "\(client.client.title) has already completed a Backtick tool call here.",
                for: client
            )
        case .needsRefresh:
            switch client.client {
            case .claudeDesktop:
                return "Claude Desktop is still using an older Backtick tool name from the current session. Quit and reopen Claude Desktop so it reloads the latest Backtick tool surface."
            case .claudeCode:
                return "The current Claude Code session is still using an older Backtick tool name. Start a new Claude Code session so it reloads the latest Backtick tool surface."
            case .codex:
                return "The current Codex session is still using an older Backtick tool name. Start a new Codex session so it reloads the latest Backtick tool surface."
            }
        case .needsAttention:
            return "Read the fix below, correct the issue, then run the local setup check again."
        case .unavailable, .installRequired, .needsSetup:
            return "Open setup steps, paste the command into Terminal, then come back here."
        }
    }

    func clientLastUsedDetail(for client: MCPConnectorClientStatus) -> String? {
        lastUsedDetail(for: client)
    }

    func primaryActionTitle(for client: MCPConnectorClientStatus) -> String? {
        switch primaryAction(for: client) {
        case .writeConfig:
            return hasConfiguredHelperDrift(for: client) ? "Reconnect" : "Connect"
        case .launchTerminalSetup:
            return hasConfiguredHelperDrift(for: client) ? "Reconnect" : "Connect"
        case .copyAddCommand:
            return hasConfiguredHelperDrift(for: client) ? "Reconnect" : "Set Up"
        case .openDocumentation:
            return "Install \(client.client.title)"
        case .runServerTest:
            if clientFailureDetail(for: client) != nil {
                return "Check Again"
            }

            return "Check Setup"
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
        if hasConfiguredHelperDrift(for: client) {
            return "Fix This"
        }

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

    func clientConfigDriftDetail(for client: MCPConnectorClientStatus) -> String? {
        guard hasConfiguredHelperDrift(for: client) else {
            return nil
        }

        return "This config is still pointing at an older Backtick MCP helper path. Reconnect Backtick so this client picks up the current helper and tool descriptions."
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
            if hasConfiguredHelperDrift(for: client) {
                return inspection.launchSpec == nil ? nil : .writeConfig
            }

            if !client.hasConfiguredScope {
                return inspection.launchSpec == nil ? nil : .writeConfig
            }

            switch readinessState(for: client) {
            case .connected, .needsRefresh:
                return .runServerTest
            case .configured, .checking, .needsAttention:
                if case .passed = verificationState(for: client) {
                    return nil
                }
                return .runServerTest
            case .unavailable, .installRequired, .needsSetup:
                return nil
            }
        }

        if !client.hasDetectedCLI {
            return .openDocumentation
        }

        if hasConfiguredHelperDrift(for: client) {
            guard inspection.status(for: client.client).addCommand != nil else {
                return nil
            }

            if client.client.supportsTerminalSetupAutomation {
                return .launchTerminalSetup
            }

            return .copyAddCommand
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

        switch readinessState(for: client) {
        case .connected, .needsRefresh:
            return .runServerTest
        case .configured, .checking, .needsAttention:
            if case .passed = verificationState(for: client) {
                return nil
            }
            return .runServerTest
        case .unavailable, .installRequired, .needsSetup:
            return nil
        }
    }

    private func hasStaleLocalToolSurface(for client: MCPConnectorClientStatus) -> Bool {
        guard !hasConfiguredHelperDrift(for: client),
              let activity = recentConnectionActivity(for: client) else {
            return false
        }

        return activity.usesLegacyToolAlias
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
            return "This checks the exact Backtick launch command configured for the selected client. It validates initialize, tools/list, and a safe read-only tool call against that entry."
        case .running:
            return "Launching the configured Backtick command and waiting for initialize/tools/list plus a safe tool call…"
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
        let launchSpecs: [MCPServerLaunchSpec]
        if let targetClient {
            let configuredLaunchSpecs = inspection.status(for: targetClient).configuredLaunchSpecs
            guard !configuredLaunchSpecs.isEmpty else {
                connectionState = .failed(.unavailable)
                clientConnectionStates[targetClient] = .failed(.unavailable)
                return
            }
            launchSpecs = configuredLaunchSpecs
        } else if let availableLaunchSpec = inspection.launchSpec {
            launchSpecs = [availableLaunchSpec]
        } else {
            connectionState = .failed(.unavailable)
            return
        }

        if let targetClient {
            connectionTaskClient = targetClient
            clientConnectionStates[targetClient] = .running
        }
        connectionState = .running
        let result = await runConnectionTests(for: launchSpecs)
        guard !Task.isCancelled else {
            return
        }

        if let targetClient, !result.isRunning {
            clientTestedLaunchSpecs[targetClient] = launchSpecs
        }
        connectionState = result
        if let targetClient {
            clientConnectionStates[targetClient] = result
        }
        connectionTaskClient = nil
        connectionTask = nil
    }

    private func runConnectionTests(for launchSpecs: [MCPServerLaunchSpec]) async -> MCPServerConnectionState {
        var reports: [MCPServerConnectionReport] = []

        for launchSpec in launchSpecs {
            let result = await connectionTester.run(launchSpec: launchSpec)
            if case .passed(let report) = result {
                reports.append(report)
                continue
            }
            return result
        }

        guard let firstReport = reports.first else {
            return .failed(.unavailable)
        }

        guard reports.count > 1 else {
            return .passed(firstReport)
        }

        var toolNames: [String] = []
        for report in reports {
            for toolName in report.toolNames where !toolNames.contains(toolName) {
                toolNames.append(toolName)
            }
        }
        return .passed(
            MCPServerConnectionReport(
                protocolVersion: firstReport.protocolVersion,
                toolNames: toolNames,
                verifiedToolName: firstReport.verifiedToolName,
                verifiedLaunchSpecCount: reports.count
            )
        )
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
        let configuredLaunchSpec = configuredLaunchSpec(for: client, launchSpec: launchSpec)

        let configURL = URL(fileURLWithPath: inspection.status(for: client).homeConfig.path)

        let serverEntry: [String: Any] = [
            "command": configuredLaunchSpec.command,
            "args": configuredLaunchSpec.arguments,
            "env": configuredLaunchSpec.environment,
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
                "mcp__backtick__list_saved_items",
                "mcp__backtick__list_notes",
                "mcp__backtick__get_note",
                "mcp__backtick__create_note",
                "mcp__backtick__update_note",
                "mcp__backtick__mark_notes_executed",
                "mcp__backtick__delete_note",
            ].joined(separator: ",")

            return """
            \(executable) -p --permission-mode dontAsk --allowedTools "\(allowedTools)" "Give me a quick Backtick overview across current Stack notes and saved Memory items."
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

    private func appendLastUsedDetail(
        _ message: String,
        for client: MCPConnectorClientStatus
    ) -> String {
        guard let lastUsedDetail = lastUsedDetail(for: client) else {
            return message
        }

        return "\(message) \(lastUsedDetail)"
    }

    private func lastUsedDetail(for client: MCPConnectorClientStatus) -> String? {
        guard let recordedAt = actualConnectionActivity(for: client)?.recordedAt else {
            return nil
        }

        return "Last used \(Self.relativeDateTimeFormatter.localizedString(for: recordedAt, relativeTo: Date()))."
    }

    private func isFreshConnectionActivity(_ activity: MCPConnectorConnectionActivity) -> Bool {
        activity.recordedAt >= Date().addingTimeInterval(-Self.connectedActivityFreshnessWindow)
    }

    private var recentExperimentalRemoteRequestActivity: ExperimentalMCPHTTPRemoteRequestActivity? {
        guard let activity = experimentalRemoteLastSuccessfulRequest,
              isFreshExperimentalRemoteRequestActivity(activity) else {
            return nil
        }

        return activity
    }

    private func isFreshExperimentalRemoteRequestActivity(
        _ activity: ExperimentalMCPHTTPRemoteRequestActivity
    ) -> Bool {
        activity.recordedAt >= Date().addingTimeInterval(-Self.connectedActivityFreshnessWindow)
    }

    private func persistExperimentalRemoteDiagnostics() {
        if let requestData = try? JSONEncoder().encode(experimentalRemoteLastSuccessfulRequest) {
            userDefaults.set(requestData, forKey: ExperimentalRemoteDefaultsKey.lastSuccessfulRequest)
        } else {
            userDefaults.removeObject(forKey: ExperimentalRemoteDefaultsKey.lastSuccessfulRequest)
        }

        if let failureData = try? JSONEncoder().encode(experimentalRemoteLastOAuthFailure) {
            userDefaults.set(failureData, forKey: ExperimentalRemoteDefaultsKey.lastOAuthFailure)
        } else {
            userDefaults.removeObject(forKey: ExperimentalRemoteDefaultsKey.lastOAuthFailure)
        }
    }

    private static func loadPersistedRemoteRequestActivity(
        from userDefaults: UserDefaults
    ) -> ExperimentalMCPHTTPRemoteRequestActivity? {
        guard let data = userDefaults.data(forKey: ExperimentalRemoteDefaultsKey.lastSuccessfulRequest),
              let activity = try? JSONDecoder().decode(ExperimentalMCPHTTPRemoteRequestActivity.self, from: data),
              activity.recordedAt >= Date().addingTimeInterval(-connectedActivityFreshnessWindow) else {
            return nil
        }

        return activity
    }

    private static func loadPersistedRemoteOAuthFailure(
        from userDefaults: UserDefaults
    ) -> ExperimentalMCPHTTPOAuthFailureActivity? {
        guard let data = userDefaults.data(forKey: ExperimentalRemoteDefaultsKey.lastOAuthFailure),
              let activity = try? JSONDecoder().decode(ExperimentalMCPHTTPOAuthFailureActivity.self, from: data) else {
            return nil
        }

        return activity
    }

    private func sameLaunchSpecs(_ lhs: [MCPServerLaunchSpec], _ rhs: [MCPServerLaunchSpec]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        return lhs.allSatisfy(rhs.contains)
    }

    private func configuredLaunchSpec(
        for client: MCPConnectorClient,
        launchSpec: MCPServerLaunchSpec
    ) -> MCPServerLaunchSpec {
        MCPServerLaunchSpec(
            command: launchSpec.command,
            arguments: launchSpec.arguments,
            environment: launchSpec.environment.merging(
                [MCPConnectorInspector.connectorClientEnvironmentKey: client.rawValue]
            ) { _, newValue in newValue }
        )
    }

    private func hasConfiguredHelperDrift(for client: MCPConnectorClientStatus) -> Bool {
        guard inspection.bundledHelperPath != nil,
              let launchSpec = inspection.launchSpec else {
            return false
        }

        let expectedLaunchSpec = normalizedLaunchSpecForDriftComparison(
            configuredLaunchSpec(for: client.client, launchSpec: launchSpec)
        )
        let configuredLaunchSpecs = client.configuredLaunchSpecs
        guard !configuredLaunchSpecs.isEmpty else {
            return false
        }

        return !configuredLaunchSpecs.contains { configuredLaunchSpec in
            normalizedLaunchSpecForDriftComparison(configuredLaunchSpec) == expectedLaunchSpec
        }
    }

    private func normalizedLaunchSpecForDriftComparison(
        _ launchSpec: MCPServerLaunchSpec
    ) -> MCPServerLaunchSpec {
        var environment = launchSpec.environment
        environment.removeValue(forKey: MCPConnectorInspector.connectorClientEnvironmentKey)
        return MCPServerLaunchSpec(
            command: launchSpec.command,
            arguments: launchSpec.arguments,
            environment: environment
        )
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
            return "Backtick is running and ready for a remote MCP client. Use this URL in ChatGPT web or in a Claude app custom connector. ChatGPT macOS uses the same app as web."
        }

        return "Backtick is running and ready. Copy the public MCP URL below and pair it with your Auth Token in the remote client."
    }

    private func connectedTitle(for surface: ExperimentalMCPHTTPRemoteClientSurface) -> String {
        switch surface {
        case .unknown:
            return "Connected"
        default:
            return "Connected on \(surface.shortTitle)"
        }
    }

    private func connectedReason(for surface: ExperimentalMCPHTTPRemoteClientSurface) -> String {
        switch surface {
        case .unknown:
            return "A remote MCP client has already reached this Backtick endpoint with your current app setup."
        case .web:
            return "A web remote MCP client has already reached this Backtick endpoint. If you are using ChatGPT, ChatGPT macOS uses the same app as web."
        default:
            return "\(surface.fullTitle.capitalized) has already reached this Backtick endpoint with your current app setup."
        }
    }

    private func resetExperimentalRemoteDiagnostics() {
        experimentalRemoteLastOAuthFailure = nil
        experimentalRemoteLastSuccessfulRequest = nil
        persistExperimentalRemoteDiagnostics()
    }

    private func statusPresentationForOAuthFailure(
        _ failureActivity: ExperimentalMCPHTTPOAuthFailureActivity
    ) -> ExperimentalMCPHTTPStatusPresentation {
        let detail = failureStatusDetail(for: failureActivity)

        if let successActivity = recentExperimentalRemoteRequestActivity,
           successActivity.surface != .unknown,
           failureActivity.surface != .unknown,
           successActivity.surface != failureActivity.surface {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Some remote surfaces need reconnect",
                reason: "Backtick recently worked from \(successActivity.surface.fullTitle), but \(failureActivity.surface.fullTitle) is still presenting an older Backtick OAuth grant. Click Reconnect here to reset Backtick's local OAuth state and copy the current Remote MCP URL, then return to the connector list in that client and approve again if it offers re-authorization. Recreate the connector only if the client still fails or only reopens the connector details.",
                detail: detail,
                tone: .warning,
                action: .resetLocalState
            )
        }

        return ExperimentalMCPHTTPStatusPresentation(
            title: "Reconnect needed",
            reason: "\(failureActivity.surface.fullTitle.capitalized) is still presenting an older Backtick OAuth grant. Click Reconnect here to reset Backtick's local OAuth state and copy the current Remote MCP URL, then return to the connector list in that client and approve again if it offers re-authorization. Recreate the connector only if the client still fails or only reopens the connector details.",
            detail: detail,
            tone: .warning,
            action: .resetLocalState
        )
    }

    private func statusPresentationForProbeIssue(
        _ issue: ExperimentalMCPHTTPProbeIssue
    ) -> ExperimentalMCPHTTPStatusPresentation {
        switch issue {
        case .localEndpointUnreachable:
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Needs attention",
                reason: "Backtick couldn't confirm that its local MCP endpoint is still responding. Try again, then restart Backtick if this keeps happening.",
                detail: nil,
                tone: .warning,
                action: .retry
            )
        case .publicEndpointUnreachable:
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Needs attention",
                reason: "Backtick is running locally, but the public HTTPS URL is not serving Backtick's MCP/OAuth endpoints. Restart the tunnel on the same local port Backtick is using, or update the public URL below.",
                detail: nil,
                tone: .warning,
                action: experimentalRemoteRecommendedTunnelPath == nil ? .installTunnel : .launchTunnel
            )
        }
    }

    private func statusPresentationForSchemaRefresh(
        _ requestActivity: ExperimentalMCPHTTPRemoteRequestActivity
    ) -> ExperimentalMCPHTTPStatusPresentation {
        let surfaceTitle = requestActivity.surface.fullTitle
        let toolName = requestActivity.targetName ?? "a legacy Backtick tool"

        return ExperimentalMCPHTTPStatusPresentation(
            title: "Refresh needed",
            reason: "\(surfaceTitle.capitalized) is still calling Backtick with the older tool name `\(toolName)`. Return to the connector list in that client and refresh or re-authorize it if the client offers that flow. Recreate the connector only if the client still fails or only reopens the connector details.",
            detail: "Recent request: \(requestActivity.summary).",
            tone: .warning,
            action: nil
        )
    }

    private func statusPresentationForRuntimeFailure(
        detail: String
    ) -> ExperimentalMCPHTTPStatusPresentation {
        let lowercasedDetail = detail.lowercased()

        if lowercasedDetail.contains("valid public https url") {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Public URL required",
                reason: "Add a public HTTPS URL before ChatGPT can discover Backtick over OAuth.",
                detail: nil,
                tone: .warning,
                action: experimentalRemoteRecommendedTunnelPath == nil ? .installTunnel : .launchTunnel
            )
        }

        if lowercasedDetail.contains("launch spec is unavailable") {
            return ExperimentalMCPHTTPStatusPresentation(
                title: "Backtick unavailable",
                reason: "This Backtick build can't launch its local MCP helper right now. Restart Backtick, then try again.",
                detail: nil,
                tone: .danger,
                action: .retry
            )
        }

        return ExperimentalMCPHTTPStatusPresentation(
            title: "Needs attention",
            reason: "Backtick couldn't keep the local MCP endpoint running. Try again.",
            detail: nil,
            tone: .danger,
            action: .retry
        )
    }

    private func failureStatusDetail(
        for failureActivity: ExperimentalMCPHTTPOAuthFailureActivity
    ) -> String {
        if let successActivity = recentExperimentalRemoteRequestActivity {
            return "Recent success: \(successActivity.summary). Latest rejected OAuth exchange: \(failureActivity.summary)."
        }

        return "Latest rejected OAuth exchange: \(failureActivity.summary)."
    }

    private func shouldClearRemoteOAuthFailure(
        _ failureActivity: ExperimentalMCPHTTPOAuthFailureActivity,
        after successActivity: ExperimentalMCPHTTPRemoteRequestActivity
    ) -> Bool {
        failureActivity.surface == .unknown
            || successActivity.surface == .unknown
            || failureActivity.surface == successActivity.surface
    }

    private func experimentalRemoteOAuthFailureActivity(
        from line: String
    ) -> ExperimentalMCPHTTPOAuthFailureActivity? {
        if let metadata = logMetadata(
            withPrefix: "Backtick MCP HTTP OAuth token request rejected",
            in: line
        ) {
            let errorCode = metadata["error"] ?? "invalid_grant"
            guard errorCode == "invalid_client" || errorCode == "invalid_grant" else {
                return nil
            }

            return ExperimentalMCPHTTPOAuthFailureActivity(
                errorCode: errorCode,
                surface: ExperimentalMCPHTTPRemoteClientSurface(rawValue: metadata["surface"] ?? "") ?? .unknown,
                grantType: metadata["grantType"],
                recordedAt: Date()
            )
        }

        let lowercasedLine = line.lowercased()
        if lowercasedLine.contains("token exchange rejected: invalid_client") {
            return ExperimentalMCPHTTPOAuthFailureActivity(
                errorCode: "invalid_client",
                surface: .unknown,
                grantType: nil,
                recordedAt: Date()
            )
        }
        if lowercasedLine.contains("token exchange rejected: invalid_grant") {
            return ExperimentalMCPHTTPOAuthFailureActivity(
                errorCode: "invalid_grant",
                surface: .unknown,
                grantType: nil,
                recordedAt: Date()
            )
        }

        return nil
    }

    private func experimentalRemoteRequestActivity(
        from line: String
    ) -> ExperimentalMCPHTTPRemoteRequestActivity? {
        guard let metadata = logMetadata(
            withPrefix: "Backtick MCP HTTP served protected remote request",
            in: line
        ) else {
            return nil
        }

        return ExperimentalMCPHTTPRemoteRequestActivity(
            surface: ExperimentalMCPHTTPRemoteClientSurface(rawValue: metadata["surface"] ?? "") ?? .unknown,
            rpcMethod: metadata["rpcMethod"],
            targetKind: metadata["targetKind"],
            targetName: metadata["targetName"],
            recordedAt: Date()
        )
    }

    private func logMetadata(withPrefix prefix: String, in line: String) -> [String: String]? {
        guard let prefixRange = line.range(of: prefix) else {
            return nil
        }

        let suffix = String(line[prefixRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else {
            return [:]
        }

        return suffix.split(separator: " ").reduce(into: [String: String]()) { result, pair in
            let pairString = String(pair)
            guard let separator = pairString.firstIndex(of: "=") else {
                return
            }

            let key = String(pairString[..<separator])
            let valueStart = pairString.index(after: separator)
            result[key] = String(pairString[valueStart...])
        }
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
    private static let expectedToolNames = BacktickMCPToolSurface.expectedCoreToolNames
    private static let verificationToolName = BacktickMCPToolSurface.verificationToolName

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
        var processEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in launchSpec.environment {
            processEnvironment[key] = value
        }
        processEnvironment["BACKTICK_MCP_CONNECTION_ACTIVITY_DISABLED"] = "1"
        process.environment = processEnvironment

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
        let initializedNotification = try notificationLine(method: "notifications/initialized")
        let toolsRequest = try requestLine(id: 2, method: "tools/list")
        let toolCallRequest = try requestLine(
            id: 3,
            method: "tools/call",
            params: [
                "name": Self.verificationToolName,
                "arguments": [:] as [String: Any],
            ]
        )
        inputPipe.fileHandleForWriting.write(
            Data(
                (
                    initializeRequest
                    + "\n"
                    + initializedNotification
                    + "\n"
                    + toolsRequest
                    + "\n"
                    + toolCallRequest
                    + "\n"
                ).utf8
            )
        )
        try? inputPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(10)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw MCPServerConnectionFailure.launchFailed(
                    "Backtick MCP did not respond within 10 seconds."
                )
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

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

        guard let toolCall = responses[3],
              let toolCallResult = toolCall["result"] as? [String: Any] else {
            throw MCPServerConnectionFailure.invalidResponse(
                "Backtick MCP did not return a valid tools/call response for \(Self.verificationToolName)."
            )
        }

        if (toolCallResult["isError"] as? Bool) == true {
            throw MCPServerConnectionFailure.toolCallFailed(
                toolName: Self.verificationToolName,
                message: toolCallErrorMessage(from: toolCallResult)
            )
        }

        guard let content = toolCallResult["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] != nil else {
            throw MCPServerConnectionFailure.invalidResponse(
                "Backtick MCP did not return a valid tools/call payload for \(Self.verificationToolName)."
            )
        }

        return .passed(
            MCPServerConnectionReport(
                protocolVersion: protocolVersion,
                toolNames: toolNames,
                verifiedToolName: Self.verificationToolName
            )
        )
    }

    private func requestLine(
        id: Int,
        method: String,
        params: [String: Any] = [:]
    ) throws -> String {
        try payloadLine(
            [
                "jsonrpc": "2.0",
                "id": id,
                "method": method,
                "params": params,
            ]
        )
    }

    private func notificationLine(
        method: String,
        params: [String: Any] = [:]
    ) throws -> String {
        try payloadLine(
            [
                "jsonrpc": "2.0",
                "method": method,
                "params": params,
            ]
        )
    }

    private func payloadLine(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else {
            throw MCPServerConnectionFailure.invalidResponse("Failed to encode test request.")
        }

        return line
    }

    private func toolCallErrorMessage(from result: [String: Any]) -> String {
        guard let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let data = text.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let error = payload["error"] as? String,
              !error.isEmpty else {
            return "Unknown tool error."
        }

        return error
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
