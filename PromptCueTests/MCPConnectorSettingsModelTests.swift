import XCTest
@testable import Prompt_Cue

final class MCPConnectorSettingsModelTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var repositoryRootURL: URL!
    private var homeDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)

        repositoryRootURL = tempDirectoryURL.appendingPathComponent("Repo", isDirectory: true)
        homeDirectoryURL = tempDirectoryURL.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDirectoryURL, withIntermediateDirectories: true)

        try Data().write(to: repositoryRootURL.appendingPathComponent("Package.swift"))
        try FileManager.default.createDirectory(
            at: repositoryRootURL.appendingPathComponent("PromptCue.xcodeproj", isDirectory: true),
            withIntermediateDirectories: true
        )

        try installClientExecutable(named: "claude")
        try installClientExecutable(named: "codex")
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        tempDirectoryURL = nil
        repositoryRootURL = nil
        homeDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testInspectorPrefersBuiltExecutableAndDetectsProjectConfigs() throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(executableURL.path)",
              "args": []
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let codexConfigURL = repositoryRootURL.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(
            at: codexConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        [mcp_servers.backtick]
        command = "\(executableURL.path)"
        args = []
        """.write(to: codexConfigURL, atomically: true, encoding: .utf8)

        let inspection = makeInspector().inspect()

        XCTAssertEqual(inspection.launchSpec?.command, executableURL.path)
        XCTAssertEqual(
            inspection.status(for: .claudeCode).projectConfig?.presence,
            .configured
        )
        XCTAssertEqual(
            inspection.status(for: .codex).projectConfig?.presence,
            .configured
        )
        XCTAssertTrue(inspection.status(for: .claudeCode).addCommand?.contains("claude mcp add") == true)
        XCTAssertTrue(inspection.status(for: .claudeCode).addCommand?.contains("--scope user") == true)
        XCTAssertTrue(inspection.status(for: .codex).addCommand?.contains("codex mcp add") == true)
    }

    func testInspectorPrefersBundledHelperOverRepositoryCheckout() throws {
        let repoExecutableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: repoExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: repoExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: repoExecutableURL.path
        )

        let appBundleURL = tempDirectoryURL
            .appendingPathComponent("Prompt Cue.app", isDirectory: true)
        let bundledHelperURL = appBundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: bundledHelperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: bundledHelperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bundledHelperURL.path
        )

        let inspection = makeInspector(applicationBundleURL: appBundleURL).inspect()

        XCTAssertEqual(inspection.bundledHelperPath, bundledHelperURL.path)
        XCTAssertEqual(inspection.launchSpec?.command, bundledHelperURL.path)
        XCTAssertTrue(inspection.status(for: .claudeCode).addCommand?.contains(bundledHelperURL.path) == true)
        XCTAssertTrue(inspection.status(for: .codex).addCommand?.contains(bundledHelperURL.path) == true)
        XCTAssertTrue(inspection.status(for: .claudeCode).configSnippet?.contains("BacktickMCP") == true)
        XCTAssertTrue(inspection.status(for: .codex).configSnippet?.contains("BacktickMCP") == true)
    }

    func testInspectorFallsBackToSwiftRunAndDetectsHomeConfigs() throws {
        let claudeHomeConfigURL = homeDirectoryURL.appendingPathComponent(".claude.json")
        try """
        {
          "projects": {
            "\(repositoryRootURL.path)": {
              "mcpServers": {
                "backtick": {
                  "command": "/usr/bin/env",
                  "args": ["swift", "run", "--package-path", "\(repositoryRootURL.path)", "BacktickMCP"]
                }
              }
            }
          }
        }
        """.write(to: claudeHomeConfigURL, atomically: true, encoding: .utf8)

        let codexHomeConfigURL = homeDirectoryURL.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(
            at: codexHomeConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        [mcp_servers.backtick]
        command = "/usr/bin/env"
        args = ["swift", "run", "--package-path", "\(repositoryRootURL.path)", "BacktickMCP"]
        """.write(to: codexHomeConfigURL, atomically: true, encoding: .utf8)

        let inspection = makeInspector().inspect()

        XCTAssertEqual(inspection.launchSpec?.command, "/usr/bin/env")
        XCTAssertEqual(
            inspection.launchSpec?.arguments,
            ["swift", "run", "--package-path", repositoryRootURL.path, "BacktickMCP"]
        )
        XCTAssertEqual(inspection.status(for: .claudeCode).homeConfig.presence, .configured)
        XCTAssertEqual(inspection.status(for: .codex).homeConfig.presence, .configured)
    }

    func testInspectorMarksPresentButMissingBacktickConfiguration() throws {
        try """
        { "mcpServers": { "somethingElse": { "command": "node", "args": ["server.js"] } } }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let codexConfigURL = homeDirectoryURL.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(
            at: codexConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        [mcp_servers.other]
        command = "node"
        args = ["server.js"]
        """.write(to: codexConfigURL, atomically: true, encoding: .utf8)

        let inspection = makeInspector().inspect()

        XCTAssertEqual(
            inspection.status(for: .claudeCode).projectConfig?.presence,
            .presentWithoutBacktick
        )
        XCTAssertEqual(
            inspection.status(for: .codex).homeConfig.presence,
            .presentWithoutBacktick
        )
    }

    @MainActor
    func testModelShowsSetupAndLocalServerVerificationAfterServerTestPasses() async throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(executableURL.path)",
              "args": []
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let expectedReport = MCPServerConnectionReport(
            protocolVersion: "2025-03-26",
            toolNames: ["list_notes", "get_note", "create_note", "update_note", "delete_note", "mark_notes_executed"]
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .passed(expectedReport))
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientSetupTitle(for: claude), "Set up")
        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Not verified")
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Verify Setup")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Verify the setup")

        await model.performServerTest()

        XCTAssertEqual(model.connectionState, .passed(expectedReport))
        XCTAssertEqual(model.clientSetupTitle(for: claude), "Set up")
        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Local server OK")
        XCTAssertTrue(model.clientSummary(for: claude).contains("allowed tool list"))
        XCTAssertEqual(model.connectedToolNames(for: claude), expectedReport.toolNames)
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Backtick is ready")
        XCTAssertNil(model.primaryAction(for: claude))
    }

    @MainActor
    func testModelSurfacesConnectionFailureDetail() async throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(executableURL.path)",
              "args": []
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.launchFailed("boom")))
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        await model.performServerTest()

        XCTAssertEqual(model.connectionState, .failed(.launchFailed("boom")))
        XCTAssertEqual(model.serverTestDetail, "boom")
        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Needs attention")
        XCTAssertEqual(model.clientFailureDetail(for: claude), "boom")
        XCTAssertTrue(model.connectedToolNames(for: claude).isEmpty)
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Verify Again")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Fix the setup and verify again")
    }

    @MainActor
    func testVerifyingCodexDoesNotMarkClaudeClientsConnected() async throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(executableURL.path)",
              "args": []
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )
        let codexConfigURL = homeDirectoryURL.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(
            at: codexConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        [mcp_servers.backtick]
        command = "\(executableURL.path)"
        args = []
        """.write(to: codexConfigURL, atomically: true, encoding: .utf8)

        let expectedReport = MCPServerConnectionReport(
            protocolVersion: "2025-03-26",
            toolNames: ["list_notes", "get_note", "create_note"]
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .passed(expectedReport))
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))
        let codex = try XCTUnwrap(model.clients.first(where: { $0.client == .codex }))

        await model.performServerTest(for: .codex)

        XCTAssertEqual(model.clientVerificationTitle(for: codex), "Local server OK")
        XCTAssertEqual(model.connectedToolNames(for: codex), expectedReport.toolNames)
        XCTAssertNil(model.primaryAction(for: codex))

        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Not verified")
        XCTAssertTrue(model.connectedToolNames(for: claude).isEmpty)
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Verify the setup")
    }

    @MainActor
    func testClaudeAutomationExampleIncludesAllowList() {
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )

        let example = model.automationExample(for: .claudeCode)

        XCTAssertEqual(model.automationExample(for: .codex), nil)
        XCTAssertTrue(example?.contains("--permission-mode dontAsk") == true)
        XCTAssertTrue(example?.contains("--allowedTools") == true)
        XCTAssertTrue(example?.contains("mcp__backtick__mark_notes_executed") == true)
    }

    @MainActor
    func testModelPrefersTerminalSetupWhenClaudeCodeNeedsSetup() throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientSetupTitle(for: claude), "Needs setup")
        XCTAssertEqual(model.clientScopeTitle(for: claude), nil)
        XCTAssertEqual(model.primaryAction(for: claude), .launchTerminalSetup)
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Connect")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Connect to Claude Code")
    }

    @MainActor
    func testModelPrefersTerminalSetupWhenCodexNeedsSetup() throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )
        let codex = try XCTUnwrap(model.clients.first(where: { $0.client == .codex }))

        XCTAssertEqual(model.clientSetupTitle(for: codex), "Needs setup")
        XCTAssertEqual(model.clientScopeTitle(for: codex), nil)
        XCTAssertEqual(model.primaryAction(for: codex), .launchTerminalSetup)
        XCTAssertEqual(model.primaryActionTitle(for: codex), "Connect")
        XCTAssertEqual(model.clientNextStepTitle(for: codex), "Connect to Codex")
    }

    @MainActor
    func testLaunchAddCommandInTerminalUsesClaudeCodeUserScopeCommand() throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let launcher = TestTerminalLauncher()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            terminalLauncher: launcher
        )

        let didLaunch = model.launchAddCommandInTerminal(for: .claudeCode)

        XCTAssertTrue(didLaunch)
        XCTAssertEqual(launcher.commands.count, 1)
        XCTAssertTrue(launcher.commands[0].contains("claude mcp add"))
        XCTAssertTrue(launcher.commands[0].contains("--scope user"))
        XCTAssertTrue(launcher.commands[0].contains(executableURL.path))
    }

    @MainActor
    func testLaunchAddCommandInTerminalUsesCodexCommand() throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let launcher = TestTerminalLauncher()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            terminalLauncher: launcher
        )

        let didLaunch = model.launchAddCommandInTerminal(for: .codex)

        XCTAssertTrue(didLaunch)
        XCTAssertEqual(launcher.commands.count, 1)
        XCTAssertTrue(launcher.commands[0].contains("codex mcp add"))
        XCTAssertTrue(launcher.commands[0].contains("backtick --"))
        XCTAssertTrue(launcher.commands[0].contains(executableURL.path))
    }

    @MainActor
    func testLaunchAddCommandInTerminalRefreshesConfiguredScopeSoonAfterCodexSetupAppears() async throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let codexConfigURL = homeDirectoryURL.appendingPathComponent(".codex/config.toml")
        let launcher = TestTerminalLauncher()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            terminalLauncher: launcher,
            setupRefreshPollIntervalNanoseconds: 10_000_000,
            setupRefreshMaxAttempts: 20
        )

        XCTAssertFalse(model.clients.contains(where: { $0.client == .codex && $0.hasConfiguredScope }))

        let didLaunch = model.launchAddCommandInTerminal(for: .codex)
        XCTAssertTrue(didLaunch)

        try await Task.sleep(nanoseconds: 15_000_000)
        try FileManager.default.createDirectory(
            at: codexConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        [mcp_servers.backtick]
        command = "\(executableURL.path)"
        args = []
        """.write(to: codexConfigURL, atomically: true, encoding: .utf8)

        try await Task.sleep(nanoseconds: 80_000_000)

        let codex = try XCTUnwrap(model.clients.first(where: { $0.client == .codex }))
        XCTAssertTrue(codex.hasConfiguredScope)
        XCTAssertEqual(model.primaryAction(for: codex), .runServerTest)
    }

    @MainActor
    func testModelShowsCLIUnavailableWhenClientBinaryIsMissing() throws {
        let freshHomeDirectoryURL = tempDirectoryURL.appendingPathComponent("FreshHome", isDirectory: true)
        try FileManager.default.createDirectory(at: freshHomeDirectoryURL, withIntermediateDirectories: true)

        let model = MCPConnectorSettingsModel(
            inspector: MCPConnectorInspector(
                environment: [:],
                homeDirectoryURL: freshHomeDirectoryURL,
                repositoryRootURL: repositoryRootURL
            ),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientSetupTitle(for: claude), "CLI not found")
        XCTAssertEqual(model.primaryAction(for: claude), .openDocumentation)
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Install Claude Code")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Install Claude Code")
        XCTAssertTrue(model.clientSummary(for: claude).contains("Install"))
    }

    private func makeInspector(applicationBundleURL: URL? = nil) -> MCPConnectorInspector {
        MCPConnectorInspector(
            environment: [:],
            homeDirectoryURL: homeDirectoryURL,
            applicationBundleURL: applicationBundleURL,
            repositoryRootURL: repositoryRootURL
        )
    }

    @MainActor
    func testExperimentalRemoteSettingsPersistAndRegenerateAPIKey() {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )

        XCTAssertFalse(model.experimentalRemoteSettings.isEnabled)
        XCTAssertEqual(model.experimentalRemoteSettings.port, ExperimentalMCPHTTPSettings.defaultPort)
        XCTAssertEqual(model.experimentalRemoteSettings.authMode, .apiKey)
        XCTAssertTrue(model.experimentalRemoteSettings.publicBaseURL.isEmpty)

        model.updateExperimentalRemoteEnabled(true)
        let generatedAPIKey = model.experimentalRemoteSettings.apiKey

        XCTAssertTrue(model.experimentalRemoteSettings.isEnabled)
        XCTAssertFalse(generatedAPIKey.isEmpty)

        XCTAssertTrue(model.updateExperimentalRemotePort("9123"))
        XCTAssertTrue(model.updateExperimentalRemoteAPIKey("  custom-secret  "))
        XCTAssertTrue(model.updateExperimentalRemotePublicBaseURL(" https://backtick.test/ "))
        model.updateExperimentalRemoteAuthMode(.oauth)
        XCTAssertEqual(model.experimentalRemoteSettings.port, 9123)
        XCTAssertEqual(model.experimentalRemoteSettings.authMode, .oauth)
        XCTAssertEqual(model.experimentalRemoteSettings.apiKey, "custom-secret")
        XCTAssertEqual(model.experimentalRemoteSettings.publicBaseURL, "https://backtick.test")
        XCTAssertEqual(model.experimentalRemoteLocalEndpoint, "http://127.0.0.1:9123/mcp")
        XCTAssertEqual(model.experimentalRemotePublicEndpoint, "https://backtick.test/mcp")

        model.generateExperimentalRemoteAPIKey()

        XCTAssertNotEqual(model.experimentalRemoteSettings.apiKey, "custom-secret")

        let reloadedModel = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )

        XCTAssertTrue(reloadedModel.experimentalRemoteSettings.isEnabled)
        XCTAssertEqual(reloadedModel.experimentalRemoteSettings.port, 9123)
        XCTAssertEqual(reloadedModel.experimentalRemoteSettings.authMode, .oauth)
        XCTAssertEqual(reloadedModel.experimentalRemoteSettings.publicBaseURL, "https://backtick.test")
        XCTAssertEqual(
            reloadedModel.experimentalRemoteSettings.apiKey,
            model.experimentalRemoteSettings.apiKey
        )
    }

    @MainActor
    func testExperimentalRemoteSettingsPostChangeNotification() {
        let userDefaults = makeUserDefaults()
        let notificationCenter = NotificationCenter()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults,
            notificationCenter: notificationCenter
        )
        let expectation = expectation(description: "experimental remote settings changed")

        let observer = notificationCenter.addObserver(
            forName: .experimentalMCPHTTPSettingsDidChange,
            object: model,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }

        model.updateExperimentalRemoteEnabled(true)

        wait(for: [expectation], timeout: 1)
        notificationCenter.removeObserver(observer)
    }

    @MainActor
    func testExperimentalRemoteRetryPostsRetryNotification() {
        let userDefaults = makeUserDefaults()
        let notificationCenter = NotificationCenter()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults,
            notificationCenter: notificationCenter
        )
        let expectation = expectation(description: "experimental remote retry requested")

        let observer = notificationCenter.addObserver(
            forName: .experimentalMCPHTTPRetryRequested,
            object: model,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }

        model.retryExperimentalRemote()

        wait(for: [expectation], timeout: 1)
        notificationCenter.removeObserver(observer)
    }

    @MainActor
    func testExperimentalRemoteRecommendedTunnelUsesDetectedNgrokAndCurrentPort() throws {
        try installClientExecutable(named: "ngrok")
        let launcher = TestTerminalLauncher()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            terminalLauncher: launcher
        )

        XCTAssertTrue(model.updateExperimentalRemotePort("8844"))
        let ngrokPath = try XCTUnwrap(model.experimentalRemoteRecommendedTunnelPath)
        XCTAssertEqual(
            model.experimentalRemoteRecommendedTunnelCommand,
            "\(ngrokPath) http 8844"
        )
        XCTAssertTrue(model.experimentalRemoteRecommendedTunnelSummary.contains(ngrokPath))

        XCTAssertTrue(model.launchExperimentalRemoteRecommendedTunnelInTerminal())
        XCTAssertEqual(launcher.commands, ["\(ngrokPath) http 8844"])
    }

    @MainActor
    func testExperimentalRemoteOAuthStateResetRemovesStateFileAndPostsNotification() throws {
        let userDefaults = makeUserDefaults()
        let notificationCenter = NotificationCenter()
        let oauthStateURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support/PromptCue/BacktickMCPOAuthState.json")
        try FileManager.default.createDirectory(
            at: oauthStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {"dynamicClients":{},"refreshTokens":{},"accessTokens":{}}
        """.write(to: oauthStateURL, atomically: true, encoding: .utf8)

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults,
            notificationCenter: notificationCenter,
            experimentalRemoteOAuthStateFileURL: oauthStateURL
        )
        let expectation = expectation(description: "oauth reset requested")
        let observer = notificationCenter.addObserver(
            forName: .experimentalMCPHTTPOAuthResetRequested,
            object: model,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }

        XCTAssertTrue(model.experimentalRemoteOAuthStateExists)
        XCTAssertTrue(model.resetExperimentalRemoteOAuthState())
        XCTAssertFalse(FileManager.default.fileExists(atPath: oauthStateURL.path))

        wait(for: [expectation], timeout: 1)
        notificationCenter.removeObserver(observer)
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationRequiresPublicURLForOAuth() {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Public URL required")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .warning)
        XCTAssertTrue(
            model.experimentalRemoteStatusPresentation.action == .launchTunnel
                || model.experimentalRemoteStatusPresentation.action == .installTunnel
        )
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("public HTTPS tunnel"))
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationShowsReconnectNeededAfterStaleGrantLog() {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://backtick.test")
        model.setExperimentalRemoteRuntimeState(.running)
        model.recordExperimentalRemoteHelperLog(
            "BacktickMCPOAuthProvider token exchange rejected: invalid_grant clientID=abc refreshToken=def"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Reconnect needed")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .warning)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .resetLocalState)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("recreate the Backtick app"))
    }

    @MainActor
    func testExperimentalRemoteAutoDetectsNgrokURLWhenConfiguredURLIsEmpty() async {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults,
            experimentalRemoteTunnelDetector: TestExperimentalRemoteTunnelDetector(
                url: URL(string: "https://example-tunnel.ngrok-free.dev")
            )
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(
            model.experimentalRemotePublicEndpoint,
            "https://example-tunnel.ngrok-free.dev/mcp"
        )
        XCTAssertFalse(model.experimentalRemoteShouldShowInlinePublicBaseURL)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Ready to connect")
    }

    @MainActor
    func testExperimentalRemoteConfiguredURLWinsOverAutoDetectedNgrokURL() async {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults,
            experimentalRemoteTunnelDetector: TestExperimentalRemoteTunnelDetector(
                url: URL(string: "https://detected.ngrok-free.dev")
            )
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://manual.example")
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(model.experimentalRemotePublicEndpoint, "https://manual.example/mcp")
        XCTAssertEqual(model.experimentalRemoteConfiguredPublicBaseURL?.absoluteString, "https://manual.example")
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationReadyToConnectUsesCopyPublicURLAction() {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://backtick.test")
        model.setExperimentalRemoteRuntimeState(.running)

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Ready to connect")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .success)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .copyPublicMCPURL)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("ChatGPT MCP URL"))
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationShowsConnectedAfterSuccessfulRemoteLog() {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://backtick.test")
        model.setExperimentalRemoteRuntimeState(.running)
        model.recordExperimentalRemoteHelperLog(
            "Backtick MCP HTTP served protected remote request method=tools/call"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Connected")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .success)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .copyPublicMCPURL)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("current app setup"))

        _ = model.updateExperimentalRemotePublicBaseURL("https://new-backtick.test")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Ready to connect")
    }

    @MainActor
    func testExperimentalRemoteSuccessfulRemoteLogClearsStaleGrantRecoveryIssue() {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://backtick.test")
        model.setExperimentalRemoteRuntimeState(.running)
        model.recordExperimentalRemoteHelperLog(
            "BacktickMCPOAuthProvider token exchange rejected: invalid_grant clientID=abc refreshToken=def"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Reconnect needed")

        model.recordExperimentalRemoteHelperLog(
            "Backtick MCP HTTP served protected remote request method=tools/call"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Connected")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .copyPublicMCPURL)
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationShowsNeedsAttentionWhenPublicProbeFails() async {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults,
            experimentalRemoteProbe: TestExperimentalRemoteProbe(issue: .publicEndpointUnreachable)
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://backtick.test")
        model.setExperimentalRemoteRuntimeState(.running)
        model.refreshExperimentalRemoteProbe()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Needs attention")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .warning)
        XCTAssertTrue(
            model.experimentalRemoteStatusPresentation.action == .installTunnel
                || model.experimentalRemoteStatusPresentation.action == .launchTunnel
        )
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("public HTTPS URL"))
        XCTAssertTrue(model.experimentalRemoteShouldShowInlinePublicBaseURL)
    }

    @MainActor
    func testExperimentalRemotePublicProbeFailureOverridesConnectedState() async {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults,
            experimentalRemoteProbe: TestExperimentalRemoteProbe(issue: .publicEndpointUnreachable)
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://backtick.test")
        model.setExperimentalRemoteRuntimeState(.running)
        model.recordExperimentalRemoteHelperLog(
            "Backtick MCP HTTP served protected remote request method=tools/call"
        )
        model.refreshExperimentalRemoteProbe()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(model.experimentalRemoteIsConnected)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Needs attention")
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("same local port"))
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationShowsNeedsAttentionWhenLocalProbeFails() async {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults,
            experimentalRemoteProbe: TestExperimentalRemoteProbe(issue: .localEndpointUnreachable)
        )

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://backtick.test")
        model.setExperimentalRemoteRuntimeState(.running)
        model.refreshExperimentalRemoteProbe()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Needs attention")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .warning)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .retry)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("local MCP endpoint"))
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationGenericFailureMapsToRetry() {
        let userDefaults = makeUserDefaults()
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )

        model.updateExperimentalRemoteEnabled(true)
        model.setExperimentalRemoteRuntimeState(.failed("boom"))

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Needs attention")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .danger)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .retry)
    }

    @MainActor
    func testModelSurfacesBundledHelperSourceWhenAppBundleContainsHelper() throws {
        let appBundleURL = tempDirectoryURL
            .appendingPathComponent("Prompt Cue.app", isDirectory: true)
        let bundledHelperURL = appBundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: bundledHelperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: bundledHelperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bundledHelperURL.path
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(applicationBundleURL: appBundleURL),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )

        XCTAssertTrue(model.isServerAvailable)
        XCTAssertEqual(model.serverSourceLabel, "Bundled helper")
        XCTAssertEqual(model.serverSourcePath, bundledHelperURL.path)
        XCTAssertTrue(model.serverSummary.contains("already built into this app"))
        XCTAssertEqual(model.serverOverviewTitle, "Start with a client below")
        XCTAssertTrue(model.serverStatusFootnote.contains(bundledHelperURL.path))
    }

    func testInspectorDetectsClaudeDesktopConfiguredStatus() throws {
        let claudeDesktopConfigURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        try FileManager.default.createDirectory(
            at: claudeDesktopConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "/Applications/Backtick.app/Contents/Helpers/BacktickMCP",
              "args": []
            }
          }
        }
        """.write(to: claudeDesktopConfigURL, atomically: true, encoding: .utf8)

        let inspection = makeInspector().inspect()

        XCTAssertEqual(inspection.status(for: .claudeDesktop).homeConfig.presence, .configured)
        XCTAssertNil(inspection.status(for: .claudeDesktop).projectConfig)
        XCTAssertNil(inspection.status(for: .claudeDesktop).cliPath)
        XCTAssertNil(inspection.status(for: .claudeDesktop).addCommand)
        XCTAssertTrue(inspection.status(for: .claudeDesktop).configSnippet?.contains("BacktickMCP") == true)
    }

    func testInspectorDetectsClaudeDesktopMissingConfig() throws {
        let inspection = makeInspector().inspect()

        XCTAssertEqual(inspection.status(for: .claudeDesktop).homeConfig.presence, .missing)
        XCTAssertNil(inspection.status(for: .claudeDesktop).projectConfig)
    }

    func testInspectorDetectsClaudeDesktopPresentWithoutBacktick() throws {
        let claudeDesktopConfigURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        try FileManager.default.createDirectory(
            at: claudeDesktopConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "mcpServers": {
            "somethingElse": { "command": "node", "args": ["server.js"] }
          }
        }
        """.write(to: claudeDesktopConfigURL, atomically: true, encoding: .utf8)

        let inspection = makeInspector().inspect()

        XCTAssertEqual(inspection.status(for: .claudeDesktop).homeConfig.presence, .presentWithoutBacktick)
    }

    @MainActor
    func testClaudeDesktopIsClientAvailableWithoutCLI() throws {
        let freshHomeDirectoryURL = tempDirectoryURL.appendingPathComponent("FreshHome", isDirectory: true)
        try FileManager.default.createDirectory(at: freshHomeDirectoryURL, withIntermediateDirectories: true)

        let model = MCPConnectorSettingsModel(
            inspector: MCPConnectorInspector(
                environment: [:],
                homeDirectoryURL: freshHomeDirectoryURL,
                repositoryRootURL: repositoryRootURL
            ),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )
        let desktop = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeDesktop }))

        XCTAssertNil(desktop.cliPath)
        XCTAssertTrue(desktop.isClientAvailable)
        XCTAssertNotEqual(model.clientSetupTitle(for: desktop), "CLI not found")
        XCTAssertEqual(model.clientNextStepTitle(for: desktop), "Connect to Claude Desktop")
    }

    @MainActor
    func testClaudeDesktopPrimaryActionIsWriteConfigWhenNotConfigured() throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )
        let desktop = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeDesktop }))

        XCTAssertEqual(model.primaryAction(for: desktop), .writeConfig)
        XCTAssertEqual(model.primaryActionTitle(for: desktop), "Connect")
    }

    @MainActor
    func testClaudeDesktopWriteConfigCreatesFile() throws {
        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )

        model.writeDirectConfig(for: .claudeDesktop)

        let configURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        let data = try Data(contentsOf: configURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(json["mcpServers"] as? [String: Any])
        let backtick = try XCTUnwrap(servers["backtick"] as? [String: Any])

        XCTAssertEqual(backtick["command"] as? String, executableURL.path)
        XCTAssertEqual(backtick["args"] as? [String], [])
    }

    @MainActor
    func testClaudeDesktopWriteConfigPreservesExistingServers() throws {
        let claudeDesktopConfigURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        try FileManager.default.createDirectory(
            at: claudeDesktopConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "mcpServers": {
            "other-server": { "command": "node", "args": ["server.js"] }
          }
        }
        """.write(to: claudeDesktopConfigURL, atomically: true, encoding: .utf8)

        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )

        model.writeDirectConfig(for: .claudeDesktop)

        let data = try Data(contentsOf: claudeDesktopConfigURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(json["mcpServers"] as? [String: Any])

        XCTAssertNotNil(servers["other-server"], "Existing server entries should be preserved")
        XCTAssertNotNil(servers["backtick"], "Backtick server entry should be added")
    }

    @MainActor
    func testClaudeDesktopWriteConfigDoesNotCrashOnInvalidPath() throws {
        // Use a home directory pointing to a non-writable location
        let readOnlyURL = tempDirectoryURL.appendingPathComponent("ReadOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnlyURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: readOnlyURL.path
        )

        let executableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        let inspector = MCPConnectorInspector(
            environment: ["PATH": homeDirectoryURL.appendingPathComponent(".local/bin").path],
            homeDirectoryURL: readOnlyURL,
            repositoryRootURL: repositoryRootURL
        )
        let model = MCPConnectorSettingsModel(
            inspector: inspector,
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )

        // Should not crash — failure is logged, not thrown
        model.writeDirectConfig(for: .claudeDesktop)

        // Restore permissions for cleanup
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: readOnlyURL.path
        )
    }

    private func installClientExecutable(named executableName: String) throws {
        let executableURL = homeDirectoryURL
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent(executableName)
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "MCPConnectorSettingsModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }
}

private struct TestConnectionTester: MCPServerConnectionTesting {
    let state: MCPServerConnectionState

    func run(launchSpec: MCPServerLaunchSpec) async -> MCPServerConnectionState {
        state
    }
}

private final class TestTerminalLauncher: MCPConnectorTerminalLaunching {
    var commands: [String] = []
    var result = true

    func launchInTerminal(command: String) -> Bool {
        commands.append(command)
        return result
    }
}

private struct TestExperimentalRemoteProbe: ExperimentalMCPHTTPProbing {
    let issue: ExperimentalMCPHTTPProbeIssue?

    func probe(
        port: UInt16,
        authMode: ExperimentalMCPHTTPAuthMode,
        publicBaseURL: URL?
    ) async -> ExperimentalMCPHTTPProbeIssue? {
        issue
    }
}

private struct TestExperimentalRemoteTunnelDetector: ExperimentalMCPHTTPTunnelDetecting {
    let url: URL?

    func detectedPublicBaseURL(for port: UInt16) async -> URL? {
        url
    }
}
