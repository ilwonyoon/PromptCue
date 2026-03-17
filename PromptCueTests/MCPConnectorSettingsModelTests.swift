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
    func testModelPrefersCopyAddCommandWhenClientNeedsSetup() throws {
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
        XCTAssertEqual(model.primaryAction(for: claude), .copyAddCommand)
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Set Up")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Add Backtick to Claude Code")
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
}

private struct TestConnectionTester: MCPServerConnectionTesting {
    let state: MCPServerConnectionState

    func run(launchSpec: MCPServerLaunchSpec) async -> MCPServerConnectionState {
        state
    }
}
