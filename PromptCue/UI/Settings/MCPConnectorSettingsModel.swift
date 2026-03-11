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

    var hasConfiguredScope: Bool {
        projectConfig?.presence == .configured || homeConfig.presence == .configured
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

struct MCPConnectorSetupStep: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
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
    @Published private(set) var connectionState: MCPServerConnectionState = .idle

    private let inspector: MCPConnectorInspector
    private let connectionTester: MCPServerConnectionTesting
    private let workspace: NSWorkspace
    private let pasteboard: NSPasteboard
    private var connectionTask: Task<Void, Never>?

    init(
        inspector: MCPConnectorInspector = MCPConnectorInspector(),
        connectionTester: MCPServerConnectionTesting = MCPServerSelfTester(),
        workspace: NSWorkspace = .shared,
        pasteboard: NSPasteboard = .general
    ) {
        self.inspector = inspector
        self.connectionTester = connectionTester
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

    var setupSteps: [MCPConnectorSetupStep] {
        [
            MCPConnectorSetupStep(
                id: "pick-client",
                title: "1. Pick a client",
                detail: "Choose Claude Code or Codex and check whether Backtick is already configured in the project or home config."
            ),
            MCPConnectorSetupStep(
                id: "install-config",
                title: "2. Install the connector",
                detail: "Use Quick Add or copy the config snippet so the client launches Backtick MCP with the exact command shown here."
            ),
            MCPConnectorSetupStep(
                id: "run-test",
                title: "3. Run the server test",
                detail: "Backtick launches the MCP server locally and verifies initialize/tools/list before you rely on it in another client."
            ),
        ]
    }

    func refresh() {
        inspection = inspector.inspect()
    }

    func clientStateTitle(for client: MCPConnectorClientStatus) -> String {
        if !client.hasConfiguredScope {
            return "Not configured"
        }

        if case .passed = connectionState {
            return "Connected"
        }

        return "Configured"
    }

    func clientStateDetail(for client: MCPConnectorClientStatus) -> String {
        if !client.hasConfiguredScope {
            return "Backtick is not present in this client's project or home config yet."
        }

        switch connectionState {
        case .idle:
            return "Backtick is configured. Run the server test to verify that the current launch command actually works."
        case .running:
            return "Backtick is configured. The local server test is running now."
        case .passed:
            if client.client == .claudeCode {
                return "Backtick is configured and the local server test passed. Claude non-interactive runs still need an explicit --allowedTools list."
            }

            return "Backtick is configured and the local server test passed."
        case .failed(let failure):
            return "Backtick is configured, but the latest local server test failed: \(failure.detail)"
        }
    }

    var serverTestDetail: String {
        switch connectionState {
        case .idle:
            return "This checks the Backtick MCP launch command directly. It validates initialize/tools/list without depending on Claude Code or Codex auth state."
        case .running:
            return "Launching Backtick MCP and waiting for initialize/tools/list…"
        case .passed(let report):
            return "\(report.detail) Protocol \(report.protocolVersion)."
        case .failed(let failure):
            return failure.detail
        }
    }

    func runServerTest() {
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            await self?.performServerTest()
        }
    }

    func performServerTest() async {
        guard let launchSpec = inspection.launchSpec else {
            connectionState = .failed(.unavailable)
            return
        }

        connectionState = .running
        let result = await connectionTester.run(launchSpec: launchSpec)
        guard !Task.isCancelled else {
            return
        }

        connectionState = result
        connectionTask = nil
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

    func revealHomeConfig(for client: MCPConnectorClient) {
        revealPath(inspection.status(for: client).homeConfig.path)
    }

    func automationExample(for client: MCPConnectorClient) -> String? {
        switch client {
        case .claudeCode:
            let executable = inspection.status(for: client).cliPath ?? client.executableName
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

        case .codex:
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
