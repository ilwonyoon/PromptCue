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
}

struct MCPConnectorInspection: Equatable {
    let repositoryRootPath: String?
    let bundledHelperPath: String?
    let launchSpec: MCPServerLaunchSpec?
    let clients: [MCPConnectorClientStatus]

    func status(for client: MCPConnectorClient) -> MCPConnectorClientStatus {
        clients.first(where: { $0.client == client })!
    }
}

enum MCPConnectorPrimaryAction: Equatable {
    case copyAddCommand
    case openDocumentation
    case runServerTest

    var title: String {
        switch self {
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
            return "Backtick is already built into this app. Choose Claude Code or Codex below to finish setup."
        }

        if inspection.repositoryRootPath != nil {
            return "Backtick can launch its MCP helper from this source checkout. Choose Claude Code or Codex below to finish setup."
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
            return "Backtick itself is unavailable right now. Open the fix section below before trying Claude Code or Codex."
        }

        if hasConfiguredClients {
            return "Backtick is ready in this build. Each client below will tell you whether to verify setup or fix a problem."
        }

        return "Backtick is ready in this build. Pick Claude Code or Codex below and follow the next step shown there."
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
        inspection = inspector.inspect()
    }

    func clientSetupTitle(for client: MCPConnectorClientStatus) -> String {
        if !client.hasDetectedCLI {
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

        switch connectionState {
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
        if !client.hasDetectedCLI {
            return "Install \(client.client.title) on this Mac first, then come back to set up Backtick."
        }

        if !client.hasConfiguredScope {
            if client.hasOtherConfigFiles {
                return "Backtick is not in this client's config yet. Add it to your project or home config."
            }

            return "Add Backtick to a project or home config before using this connector."
        }

        switch connectionState {
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
        if !client.hasDetectedCLI {
            return "\(client.client.title) is required before Backtick can connect here."
        }

        if !client.hasConfiguredScope {
            if client.hasOtherConfigFiles {
                return "A config file already exists here, but Backtick has not been added yet."
            }

            return "Backtick is not added to \(client.client.title) yet."
        }

        let location = client.configuredScope?.title ?? "Unknown"

        switch connectionState {
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
        if !client.hasDetectedCLI {
            return "Install \(client.client.title)"
        }

        if !client.hasConfiguredScope {
            return "Add Backtick to \(client.client.title)"
        }

        switch connectionState {
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
        if !client.hasDetectedCLI {
            return "Backtick works through \(client.client.title). Install it first, then come back here to finish setup."
        }

        if !client.hasConfiguredScope {
            if client.hasOtherConfigFiles {
                return "Open setup steps, then either run the terminal command or add Backtick manually in the config file."
            }

            return "Open setup steps, paste the command into Terminal, then come back here."
        }

        switch connectionState {
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

        if !client.hasDetectedCLI {
            return "Install Help"
        }

        return "Troubleshooting"
    }

    func clientFailureDetail(for client: MCPConnectorClientStatus) -> String? {
        guard client.hasConfiguredScope else {
            return nil
        }

        guard case .failed(let failure) = connectionState else {
            return nil
        }

        return failure.detail
    }

    func connectedToolNames(for client: MCPConnectorClientStatus) -> [String] {
        guard client.hasConfiguredScope else {
            return []
        }

        guard case .passed(let report) = connectionState else {
            return []
        }

        return report.toolNames
    }

    func primaryAction(for client: MCPConnectorClientStatus) -> MCPConnectorPrimaryAction? {
        if !client.hasDetectedCLI {
            return .openDocumentation
        }

        if !client.hasConfiguredScope {
            return inspection.status(for: client.client).addCommand == nil ? nil : .copyAddCommand
        }

        if case .passed = connectionState {
            return nil
        }

        return .runServerTest
    }

    func performPrimaryAction(_ action: MCPConnectorPrimaryAction, for client: MCPConnectorClientStatus) {
        switch action {
        case .copyAddCommand:
            copyAddCommand(for: client.client)
        case .openDocumentation:
            openDocumentation(for: client.client)
        case .runServerTest:
            runServerTest()
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
