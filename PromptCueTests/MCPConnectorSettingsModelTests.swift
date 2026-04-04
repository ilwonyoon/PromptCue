import XCTest
@testable import Prompt_Cue

final class MCPConnectorSettingsModelTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var repositoryRootURL: URL!
    private var homeDirectoryURL: URL!

    private func exposedToolName(_ canonicalName: String) -> String {
        BacktickMCPToolSurface.exposedName(for: canonicalName)
    }

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

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let attempts = max(Int(timeoutNanoseconds / pollNanoseconds), 1)
        for _ in 0..<attempts {
            if condition() {
                return
            }

            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }

        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
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
            inspection.status(for: .claudeCode).projectConfig?.configuredLaunchSpec,
            MCPServerLaunchSpec(command: executableURL.path, arguments: [])
        )
        XCTAssertEqual(
            inspection.status(for: .codex).projectConfig?.presence,
            .configured
        )
        XCTAssertEqual(
            inspection.status(for: .codex).projectConfig?.configuredLaunchSpec,
            MCPServerLaunchSpec(command: executableURL.path, arguments: [])
        )
        XCTAssertTrue(inspection.status(for: .claudeCode).addCommand?.contains("claude mcp add") == true)
        XCTAssertTrue(inspection.status(for: .claudeCode).addCommand?.contains("--scope user") == true)
        XCTAssertTrue(
            inspection.status(for: .claudeCode).addCommand?.contains(
                "BACKTICK_CONNECTOR_CLIENT=claudeCode"
            ) == true
        )
        XCTAssertTrue(inspection.status(for: .codex).addCommand?.contains("codex mcp add") == true)
        XCTAssertTrue(
            inspection.status(for: .codex).addCommand?.contains(
                "BACKTICK_CONNECTOR_CLIENT=codex"
            ) == true
        )
        XCTAssertTrue(
            inspection.status(for: .claudeCode).configSnippet?.contains(
                "\"BACKTICK_CONNECTOR_CLIENT\" : \"claudeCode\""
            ) == true
        )
        XCTAssertTrue(
            inspection.status(for: .codex).configSnippet?.contains(
                "[mcp_servers.backtick.env]"
            ) == true
        )
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
            .appendingPathComponent("Backtick.app", isDirectory: true)
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
        let stableLauncherURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Backtick/bin/BacktickMCP")
        let launcherContents = try String(contentsOf: stableLauncherURL)

        XCTAssertEqual(inspection.bundledHelperPath, bundledHelperURL.path)
        XCTAssertEqual(inspection.launchSpec?.command, stableLauncherURL.path)
        XCTAssertTrue(inspection.status(for: .claudeCode).addCommand?.contains(stableLauncherURL.path) == true)
        XCTAssertTrue(inspection.status(for: .codex).addCommand?.contains(stableLauncherURL.path) == true)
        XCTAssertTrue(inspection.status(for: .claudeCode).configSnippet?.contains("BacktickMCP") == true)
        XCTAssertTrue(inspection.status(for: .codex).configSnippet?.contains("BacktickMCP") == true)
        XCTAssertTrue(launcherContents.contains(bundledHelperURL.path))
    }

    @MainActor
    func testClaudeCodeReconnectsWhenConfiguredHelperPathIsStale() throws {
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
            .appendingPathComponent("Backtick.app", isDirectory: true)
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

        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(repoExecutableURL.path)",
              "args": [],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(applicationBundleURL: appBundleURL),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Needs attention")
        XCTAssertTrue(model.clientSummary(for: claude).contains("older Backtick MCP helper"))
        XCTAssertEqual(model.clientProgressSummary(for: claude), "Backtick is configured in Project, but that config still points to an older helper.")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Reconnect to Claude Code")
        XCTAssertTrue(model.clientNextStepDetail(for: claude).contains("current helper path"))
        XCTAssertEqual(model.primaryAction(for: claude), .launchTerminalSetup)
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Reconnect")
        XCTAssertEqual(model.troubleshootingTitle(for: claude), "Fix This")
        XCTAssertNotNil(model.clientConfigDriftDetail(for: claude))
    }

    @MainActor
    func testClaudeDesktopReconnectsWhenConfiguredHelperPathIsStale() throws {
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
            .appendingPathComponent("Backtick.app", isDirectory: true)
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

        let configURL = homeDirectoryURL
            .appendingPathComponent(MCPConnectorClient.claudeDesktop.homeConfigRelativePath)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(repoExecutableURL.path)",
              "args": [],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeDesktop"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(applicationBundleURL: appBundleURL),
            connectionTester: TestConnectionTester(state: .failed(.unavailable))
        )
        let desktop = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeDesktop }))

        XCTAssertEqual(model.clientVerificationTitle(for: desktop), "Needs attention")
        XCTAssertEqual(model.clientNextStepTitle(for: desktop), "Reconnect to Claude Desktop")
        XCTAssertTrue(model.clientNextStepDetail(for: desktop).contains("rewrite the config file"))
        XCTAssertEqual(model.primaryAction(for: desktop), .writeConfig)
        XCTAssertEqual(model.primaryActionTitle(for: desktop), "Reconnect")
        XCTAssertNotNil(model.clientConfigDriftDetail(for: desktop))
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
                  "args": ["swift", "run", "--package-path", "\(repositoryRootURL.path)", "BacktickMCP"],
                  "env": {
                    "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
                  }
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

        [mcp_servers.backtick.env]
        BACKTICK_CONNECTOR_CLIENT = "codex"
        """.write(to: codexHomeConfigURL, atomically: true, encoding: .utf8)

        let inspection = makeInspector().inspect()

        XCTAssertEqual(inspection.launchSpec?.command, "/usr/bin/env")
        XCTAssertEqual(
            inspection.launchSpec?.arguments,
            ["swift", "run", "--package-path", repositoryRootURL.path, "BacktickMCP"]
        )
        XCTAssertEqual(inspection.status(for: .claudeCode).homeConfig.presence, .configured)
        XCTAssertEqual(inspection.status(for: .codex).homeConfig.presence, .configured)
        XCTAssertEqual(
            inspection.status(for: .claudeCode).homeConfig.configuredLaunchSpec,
            MCPServerLaunchSpec(
                command: "/usr/bin/env",
                arguments: ["swift", "run", "--package-path", repositoryRootURL.path, "BacktickMCP"],
                environment: ["BACKTICK_CONNECTOR_CLIENT": "claudeCode"]
            )
        )
        XCTAssertEqual(
            inspection.status(for: .codex).homeConfig.configuredLaunchSpec,
            MCPServerLaunchSpec(
                command: "/usr/bin/env",
                arguments: ["swift", "run", "--package-path", repositoryRootURL.path, "BacktickMCP"],
                environment: ["BACKTICK_CONNECTOR_CLIENT": "codex"]
            )
        )
    }

    func testInspectorParsesCodexMultilineArgsAndEnvironmentTable() throws {
        let codexHomeConfigURL = homeDirectoryURL.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(
            at: codexHomeConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        [mcp_servers.backtick]
        command = "/usr/bin/env"
        args = [
          "swift",
          "run",
          "--package-path",
          "\(repositoryRootURL.path)",
          "BacktickMCP",
        ]

        [mcp_servers.backtick.env]
        BACKTICK_CONNECTOR_CLIENT = "codex"
        """.write(to: codexHomeConfigURL, atomically: true, encoding: .utf8)

        let inspection = makeInspector().inspect()

        XCTAssertEqual(
            inspection.status(for: .codex).homeConfig.configuredLaunchSpec,
            MCPServerLaunchSpec(
                command: "/usr/bin/env",
                arguments: ["swift", "run", "--package-path", repositoryRootURL.path, "BacktickMCP"],
                environment: ["BACKTICK_CONNECTOR_CLIENT": "codex"]
            )
        )
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

    func testInspectorIgnoresClaudeHomeProjectEntriesForDifferentRepository() throws {
        let otherRepositoryURL = tempDirectoryURL.appendingPathComponent("OtherRepo", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRepositoryURL, withIntermediateDirectories: true)

        let claudeHomeConfigURL = homeDirectoryURL.appendingPathComponent(".claude.json")
        try """
        {
          "projects": {
            "\(otherRepositoryURL.path)": {
              "mcpServers": {
                "backtick": {
                  "command": "/tmp/other/BacktickMCP",
                  "args": []
                }
              }
            }
          }
        }
        """.write(to: claudeHomeConfigURL, atomically: true, encoding: .utf8)

        let inspection = makeInspector().inspect()

        XCTAssertEqual(inspection.status(for: .claudeCode).homeConfig.presence, .presentWithoutBacktick)
        XCTAssertNil(inspection.status(for: .claudeCode).homeConfig.configuredLaunchSpec)
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
            toolNames: [
                exposedToolName("list_notes"),
                exposedToolName("get_note"),
                exposedToolName("create_note"),
                exposedToolName("update_note"),
                exposedToolName("delete_note"),
                exposedToolName("mark_notes_executed"),
            ],
            verifiedToolName: exposedToolName("status")
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .passed(expectedReport))
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientSetupTitle(for: claude), "Set up")
        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Configured")
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Check Setup")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Check the setup")

        await model.performServerTest()

        XCTAssertEqual(model.connectionState, .passed(expectedReport))
        XCTAssertEqual(model.clientSetupTitle(for: claude), "Set up")
        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Configured")
        XCTAssertTrue(model.clientSummary(for: claude).contains("local check passed"))
        XCTAssertTrue(model.serverTestDetail.contains(exposedToolName("status")))
        XCTAssertEqual(model.connectedToolNames(for: claude), expectedReport.toolNames)
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Use Backtick in Claude Code")
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
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Check Again")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Fix the setup and check again")
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
            toolNames: [
                exposedToolName("list_notes"),
                exposedToolName("get_note"),
                exposedToolName("create_note"),
            ],
            verifiedToolName: exposedToolName("status")
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .passed(expectedReport))
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))
        let codex = try XCTUnwrap(model.clients.first(where: { $0.client == .codex }))

        await model.performServerTest(for: .codex)

        XCTAssertEqual(model.clientVerificationTitle(for: codex), "Configured")
        XCTAssertEqual(model.connectedToolNames(for: codex), expectedReport.toolNames)
        XCTAssertNil(model.primaryAction(for: codex))

        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Configured")
        XCTAssertTrue(model.connectedToolNames(for: claude).isEmpty)
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Check the setup")
    }

    @MainActor
    func testPerformServerTestUsesConfiguredLaunchSpecFromSelectedClient() async throws {
        let repositoryExecutableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: repositoryExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: repositoryExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: repositoryExecutableURL.path
        )

        let configuredExecutableURL = tempDirectoryURL
            .appendingPathComponent("Configured", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: configuredExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: configuredExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: configuredExecutableURL.path
        )

        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(configuredExecutableURL.path)",
              "args": ["--stdio"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let tester = RecordingConnectionTester(state: .passed(
            MCPServerConnectionReport(
                protocolVersion: "2025-03-26",
                toolNames: [exposedToolName("list_notes")],
                verifiedToolName: exposedToolName("status")
            )
        ))
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: tester
        )

        await model.performServerTest(for: .claudeCode)

        XCTAssertEqual(
            tester.launchSpecs,
            [MCPServerLaunchSpec(
                command: configuredExecutableURL.path,
                arguments: ["--stdio"],
                environment: ["BACKTICK_CONNECTOR_CLIENT": "claudeCode"]
            )]
        )
        XCTAssertNotEqual(tester.launchSpecs.first?.command, repositoryExecutableURL.path)
    }

    @MainActor
    func testMatchingActualConnectionActivityMarksClientConnected() async throws {
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
              "args": ["--stdio"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let activity = MCPConnectorConnectionActivity(
            transport: .stdio,
            surface: nil,
            clientName: "claude-code",
            clientVersion: "1.0.0",
            sessionID: "session-1",
            toolName: exposedToolName("list_documents"),
            recordedAt: Date(timeIntervalSinceNow: -3 * 24 * 60 * 60),
            configuredClientID: "claudeCode",
            launchCommand: executableURL.path,
            launchArguments: ["--stdio"]
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            connectionActivityReader: TestConnectionActivityReader(activities: [activity])
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Connected")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Backtick is connected")
        XCTAssertNil(model.primaryAction(for: claude))
        XCTAssertEqual(model.actualConnectionActivity(for: claude)?.toolName, exposedToolName("list_documents"))
        XCTAssertTrue(model.clientSummary(for: claude).contains("Last used"))
        XCTAssertTrue(model.clientProgressSummary(for: claude).contains("Last used"))
        XCTAssertTrue(model.clientNextStepDetail(for: claude).contains("Last used"))
        XCTAssertTrue(model.clientLastUsedDetail(for: claude)?.contains("Last used") == true)
    }

    @MainActor
    func testStaleConnectionActivityWithDifferentLaunchSpecDoesNotMarkClientConnected() async throws {
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
              "args": ["--stdio"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let activity = MCPConnectorConnectionActivity(
            transport: .stdio,
            surface: nil,
            clientName: "claude-code",
            clientVersion: "1.0.0",
            sessionID: "session-2",
            toolName: exposedToolName("list_documents"),
            recordedAt: Date(),
            configuredClientID: "claudeCode",
            launchCommand: "/tmp/other/BacktickMCP",
            launchArguments: ["--stdio"]
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            connectionActivityReader: TestConnectionActivityReader(activities: [activity])
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Configured")
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
        XCTAssertNil(model.actualConnectionActivity(for: claude))
    }

    @MainActor
    func testOldConnectionActivityFallsBackToConfiguredState() async throws {
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
              "args": ["--stdio"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let activity = MCPConnectorConnectionActivity(
            transport: .stdio,
            surface: nil,
            clientName: "claude-code",
            clientVersion: "1.0.0",
            sessionID: "session-old",
            toolName: exposedToolName("list_documents"),
            recordedAt: Date(timeIntervalSinceNow: -45 * 24 * 60 * 60),
            configuredClientID: "claudeCode",
            launchCommand: executableURL.path,
            launchArguments: ["--stdio"]
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            connectionActivityReader: TestConnectionActivityReader(activities: [activity])
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Configured")
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
        XCTAssertTrue(model.clientSummary(for: claude).contains("Last used"))
        XCTAssertTrue(model.clientProgressSummary(for: claude).contains("Last used"))
        XCTAssertTrue(model.clientNextStepDetail(for: claude).contains("Last used"))
        XCTAssertEqual(model.actualConnectionActivity(for: claude)?.toolName, exposedToolName("list_documents"))
    }

    @MainActor
    func testFreshLegacyAliasActivityPromptsClaudeCodeToStartNewSession() async throws {
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
              "args": ["--stdio"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let activity = MCPConnectorConnectionActivity(
            transport: .stdio,
            surface: nil,
            clientName: "claude-code",
            clientVersion: "1.0.0",
            sessionID: "legacy-session",
            toolName: exposedToolName("list_documents"),
            requestedToolName: "list_documents",
            recordedAt: Date(),
            configuredClientID: "claudeCode",
            launchCommand: executableURL.path,
            launchArguments: ["--stdio"]
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .passed(
                MCPServerConnectionReport(
                    protocolVersion: "2025-03-26",
                    toolNames: [exposedToolName("list_notes")],
                    verifiedToolName: exposedToolName("status")
                )
            )),
            connectionActivityReader: TestConnectionActivityReader(activities: [activity])
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Needs refresh")
        XCTAssertEqual(model.clientNextStepTitle(for: claude), "Start a new Claude Code session")
        XCTAssertEqual(model.primaryAction(for: claude), nil)
        XCTAssertTrue(model.clientSummary(for: claude).contains("older Backtick tool name"))
        XCTAssertTrue(model.clientNextStepDetail(for: claude).contains("Start a new Claude Code session"))
    }

    @MainActor
    func testRefreshDropsPassedLocalCheckWhenConfiguredLaunchSpecChanges() async throws {
        let firstExecutableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        let secondExecutableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP-alt")
        try FileManager.default.createDirectory(
            at: firstExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: firstExecutableURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: secondExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: firstExecutableURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: secondExecutableURL.path
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(firstExecutableURL.path)",
              "args": ["--stdio"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let report = MCPServerConnectionReport(
            protocolVersion: "2025-03-26",
            toolNames: [exposedToolName("list_notes")],
            verifiedToolName: exposedToolName("status")
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .passed(report))
        )

        await model.performServerTest(for: .claudeCode)

        var claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))
        XCTAssertNil(model.primaryAction(for: claude))
        XCTAssertTrue(model.clientSummary(for: claude).contains("local check passed"))

        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(secondExecutableURL.path)",
              "args": ["--stdio"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        model.refresh()

        claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))
        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Configured")
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
        XCTAssertEqual(model.primaryActionTitle(for: claude), "Check Setup")
        XCTAssertFalse(model.clientSummary(for: claude).contains("local check passed"))
        XCTAssertTrue(model.clientSummary(for: claude).contains("Run Check Setup"))
    }

    @MainActor
    func testMatchingActualConnectionActivityUsesHomeLaunchSpecWhenProjectAndHomeAreBothConfigured() async throws {
        let projectExecutableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP-project")
        let homeExecutableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP-home")
        try FileManager.default.createDirectory(
            at: projectExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: projectExecutableURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: homeExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: projectExecutableURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: homeExecutableURL.path
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(projectExecutableURL.path)",
              "args": ["--project"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let claudeHomeConfigURL = homeDirectoryURL.appendingPathComponent(".claude.json")
        try """
        {
          "projects": {
            "\(repositoryRootURL.path)": {
              "mcpServers": {
                "backtick": {
                  "command": "\(homeExecutableURL.path)",
                  "args": ["--home"],
                  "env": {
                    "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
                  }
                }
              }
            }
          }
        }
        """.write(to: claudeHomeConfigURL, atomically: true, encoding: .utf8)

        let activity = MCPConnectorConnectionActivity(
            transport: .stdio,
            surface: nil,
            clientName: "claude-code",
            clientVersion: "1.0.0",
            sessionID: "session-both",
            toolName: exposedToolName("list_documents"),
            recordedAt: Date(timeIntervalSinceNow: -2 * 24 * 60 * 60),
            configuredClientID: "claudeCode",
            launchCommand: homeExecutableURL.path,
            launchArguments: ["--home"]
        )
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            connectionActivityReader: TestConnectionActivityReader(activities: [activity])
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        XCTAssertEqual(claude.configuredScope, .both)
        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Connected")
        XCTAssertEqual(model.actualConnectionActivity(for: claude)?.launchCommand, homeExecutableURL.path)
        XCTAssertTrue(model.clientSummary(for: claude).contains("Last used"))
    }

    @MainActor
    func testPerformServerTestChecksAllConfiguredLaunchSpecsWhenProjectAndHomeExist() async throws {
        let projectExecutableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP-project")
        let homeExecutableURL = repositoryRootURL
            .appendingPathComponent(".build/debug", isDirectory: true)
            .appendingPathComponent("BacktickMCP-home")
        try FileManager.default.createDirectory(
            at: projectExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: projectExecutableURL, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: homeExecutableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: projectExecutableURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: homeExecutableURL.path
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(projectExecutableURL.path)",
              "args": ["--project"],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
              }
            }
          }
        }
        """.write(
            to: repositoryRootURL.appendingPathComponent(".mcp.json"),
            atomically: true,
            encoding: .utf8
        )

        let claudeHomeConfigURL = homeDirectoryURL.appendingPathComponent(".claude.json")
        try """
        {
          "projects": {
            "\(repositoryRootURL.path)": {
              "mcpServers": {
                "backtick": {
                  "command": "\(homeExecutableURL.path)",
                  "args": ["--home"],
                  "env": {
                    "BACKTICK_CONNECTOR_CLIENT": "claudeCode"
                  }
                }
              }
            }
          }
        }
        """.write(to: claudeHomeConfigURL, atomically: true, encoding: .utf8)

        let report = MCPServerConnectionReport(
            protocolVersion: "2025-03-26",
            toolNames: [exposedToolName("list_notes")],
            verifiedToolName: exposedToolName("status")
        )
        let tester = RecordingConnectionTester(state: .passed(report))
        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: tester
        )
        let claude = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeCode }))

        await model.performServerTest(for: .claudeCode)

        XCTAssertEqual(claude.configuredScope, .both)
        XCTAssertEqual(
            tester.launchSpecs,
            [
                MCPServerLaunchSpec(
                    command: projectExecutableURL.path,
                    arguments: ["--project"],
                    environment: ["BACKTICK_CONNECTOR_CLIENT": "claudeCode"]
                ),
                MCPServerLaunchSpec(
                    command: homeExecutableURL.path,
                    arguments: ["--home"],
                    environment: ["BACKTICK_CONNECTOR_CLIENT": "claudeCode"]
                ),
            ]
        )
        XCTAssertTrue(model.serverTestDetail.contains("across 2 configured entries"))
    }

    @MainActor
    func testClaudeDesktopConnectedWhenRecentActivityUsedBundledHelperBeforeStableLauncherMigration() throws {
        let appBundleURL = tempDirectoryURL
            .appendingPathComponent("Backtick.app", isDirectory: true)
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
        let stableLauncherURL = try XCTUnwrap(inspection.launchSpec?.command)
        let configURL = homeDirectoryURL
            .appendingPathComponent(MCPConnectorClient.claudeDesktop.homeConfigRelativePath)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(stableLauncherURL)",
              "args": [],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeDesktop"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let activity = MCPConnectorConnectionActivity(
            transport: .stdio,
            surface: nil,
            clientName: "claude-ai",
            clientVersion: "0.1.0",
            sessionID: "desktop-session",
            toolName: exposedToolName("list_saved_items"),
            recordedAt: Date(),
            configuredClientID: "claudeDesktop",
            launchCommand: bundledHelperURL.path,
            launchArguments: []
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(applicationBundleURL: appBundleURL),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            connectionActivityReader: TestConnectionActivityReader(activities: [activity])
        )
        let desktop = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeDesktop }))

        XCTAssertEqual(desktop.configuredLaunchSpecs.first?.command, stableLauncherURL)
        XCTAssertEqual(model.clientVerificationTitle(for: desktop), "Connected")
        XCTAssertEqual(model.actualConnectionActivity(for: desktop)?.launchCommand, bundledHelperURL.path)
        XCTAssertTrue(model.clientSummary(for: desktop).contains("Last used"))
    }

    @MainActor
    func testClaudeDesktopIgnoresRecentActivityFromDifferentBundledHelper() throws {
        let currentAppBundleURL = tempDirectoryURL
            .appendingPathComponent("Backtick.app", isDirectory: true)
        let currentBundledHelperURL = currentAppBundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: currentBundledHelperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: currentBundledHelperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: currentBundledHelperURL.path
        )

        let otherAppBundleURL = tempDirectoryURL
            .appendingPathComponent("Other Backtick.app", isDirectory: true)
        let otherBundledHelperURL = otherAppBundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent("BacktickMCP")
        try FileManager.default.createDirectory(
            at: otherBundledHelperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: otherBundledHelperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: otherBundledHelperURL.path
        )

        let inspection = makeInspector(applicationBundleURL: currentAppBundleURL).inspect()
        let stableLauncherURL = try XCTUnwrap(inspection.launchSpec?.command)
        let configURL = homeDirectoryURL
            .appendingPathComponent(MCPConnectorClient.claudeDesktop.homeConfigRelativePath)
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "mcpServers": {
            "backtick": {
              "command": "\(stableLauncherURL)",
              "args": [],
              "env": {
                "BACKTICK_CONNECTOR_CLIENT": "claudeDesktop"
              }
            }
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let activity = MCPConnectorConnectionActivity(
            transport: .stdio,
            surface: nil,
            clientName: "claude-ai",
            clientVersion: "0.1.0",
            sessionID: "desktop-session",
            toolName: exposedToolName("list_saved_items"),
            recordedAt: Date(),
            configuredClientID: "claudeDesktop",
            launchCommand: otherBundledHelperURL.path,
            launchArguments: []
        )

        let model = MCPConnectorSettingsModel(
            inspector: makeInspector(applicationBundleURL: currentAppBundleURL),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            connectionActivityReader: TestConnectionActivityReader(activities: [activity])
        )
        let desktop = try XCTUnwrap(model.clients.first(where: { $0.client == .claudeDesktop }))

        XCTAssertEqual(model.clientVerificationTitle(for: desktop), "Configured")
        XCTAssertNil(model.actualConnectionActivity(for: desktop))
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
        XCTAssertTrue(example?.contains("mcp__backtick__list_saved_items") == true)
        XCTAssertTrue(example?.contains("mcp__backtick__mark_notes_executed") == true)
        XCTAssertTrue(
            example?.contains("Backtick overview across current Stack notes and saved Memory items") == true
        )
        XCTAssertTrue(
            example?.range(of: "mcp__backtick__list_saved_items,mcp__backtick__list_notes") != nil
        )
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

        let cmd = launcher.commands[0]
        if let nameRange = cmd.range(of: "backtick"),
           let transportRange = cmd.range(of: "--transport"),
           let scopeRange = cmd.range(of: "--scope") {
            XCTAssertTrue(nameRange.lowerBound < transportRange.lowerBound, "name must come before --transport")
            XCTAssertTrue(nameRange.lowerBound < scopeRange.lowerBound, "name must come before --scope")
        } else {
            XCTFail("Expected 'backtick', '--transport', and '--scope' in command: \(cmd)")
        }
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

        let cmd = launcher.commands[0]
        if let nameRange = cmd.range(of: "backtick"),
           let separatorRange = cmd.range(of: "-- ") {
            XCTAssertTrue(nameRange.lowerBound < separatorRange.lowerBound, "name must come before -- separator")
        } else {
            XCTFail("Expected 'backtick' and '-- ' in command: \(cmd)")
        }
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
    func testExperimentalRemoteReconnectActionResetsStateAndCopiesPublicURL() throws {
        let userDefaults = makeUserDefaults()
        let notificationCenter = NotificationCenter()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
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
            pasteboard: pasteboard,
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

        model.updateExperimentalRemoteEnabled(true)
        model.updateExperimentalRemoteAuthMode(.oauth)
        _ = model.updateExperimentalRemotePublicBaseURL("https://backtick.test")

        model.performExperimentalRemoteStatusAction(.resetLocalState)

        wait(for: [expectation], timeout: 1)
        notificationCenter.removeObserver(observer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oauthStateURL.path))
        XCTAssertEqual(pasteboard.string(forType: .string), "https://backtick.test/mcp")
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
            "Backtick MCP HTTP OAuth token request rejected error=invalid_grant surface=iphone path=/oauth/token grantType=refresh_token clientID=abc123"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Reconnect needed")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .warning)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .resetLocalState)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("older Backtick OAuth grant"))
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("copy the current Remote MCP URL"))
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("connector list"))
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.detail?.contains("iPhone · invalid_grant · refresh_token") == true)
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
        await waitUntil {
            model.experimentalRemotePublicEndpoint == "https://example-tunnel.ngrok-free.dev/mcp"
        }

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
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("Claude app custom connector"))
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("macOS uses the same app"))
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
            "Backtick MCP HTTP served protected remote request surface=web path=/mcp bodyBytes=312 rpcMethod=tools/call targetKind=tool targetName=backtick_list_docs"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Connected on Web")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .success)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .copyPublicMCPURL)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("web remote MCP client"))
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.detail?.contains("Web · tools/call · backtick_list_docs") == true)

        _ = model.updateExperimentalRemotePublicBaseURL("https://new-backtick.test")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Ready to connect")
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationRestoresConnectedStateAfterReload() {
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
            "Backtick MCP HTTP served protected remote request surface=macos path=/mcp bodyBytes=188 rpcMethod=tools/call targetKind=tool targetName=backtick_list_saved_items"
        )

        let reloadedModel = MCPConnectorSettingsModel(
            inspector: makeInspector(),
            connectionTester: TestConnectionTester(state: .failed(.unavailable)),
            userDefaults: userDefaults
        )
        reloadedModel.setExperimentalRemoteRuntimeState(.running)

        XCTAssertEqual(reloadedModel.experimentalRemoteStatusPresentation.title, "Connected on macOS")
        XCTAssertEqual(reloadedModel.experimentalRemoteStatusPresentation.tone, .success)
        XCTAssertTrue(
            reloadedModel.experimentalRemoteStatusPresentation.detail?.contains("macOS · tools/call · backtick_list_saved_items") == true
        )
    }

    @MainActor
    func testExperimentalRemoteStatusPresentationShowsRefreshNeededWhenRemoteUsesLegacyToolName() {
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
            "Backtick MCP HTTP served protected remote request surface=web path=/mcp bodyBytes=312 rpcMethod=tools/call targetKind=tool targetName=list_documents"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Refresh needed")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .warning)
        XCTAssertNil(model.experimentalRemoteStatusPresentation.action)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("older tool name `list_documents`"))
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("connector list"))
        XCTAssertTrue(model.experimentalRemoteShouldShowInlineChatGPTMCPURL)
        XCTAssertFalse(model.experimentalRemoteIsConnected)
    }

    @MainActor
    func testExperimentalRemoteSuccessfulRemoteLogKeepsReconnectGuidanceWhenDifferentSurfaceIsStale() {
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
            "Backtick MCP HTTP OAuth token request rejected error=invalid_grant surface=iphone path=/oauth/token grantType=refresh_token"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Reconnect needed")

        model.recordExperimentalRemoteHelperLog(
            "Backtick MCP HTTP served protected remote request surface=web path=/mcp bodyBytes=288 rpcMethod=tools/call targetKind=tool targetName=backtick_recall_doc"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Some remote surfaces need reconnect")
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.tone, .warning)
        XCTAssertEqual(model.experimentalRemoteStatusPresentation.action, .resetLocalState)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("copy the current Remote MCP URL"))
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.reason.contains("connector list"))
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.detail?.contains("Web · tools/call · backtick_recall_doc") == true)
        XCTAssertTrue(model.experimentalRemoteStatusPresentation.detail?.contains("iPhone · invalid_grant · refresh_token") == true)
    }

    @MainActor
    func testExperimentalRemoteSuccessfulRemoteLogClearsStaleGrantRecoveryIssueForSameSurface() {
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
            "Backtick MCP HTTP OAuth token request rejected error=invalid_grant surface=web path=/oauth/token grantType=refresh_token"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Reconnect needed")

        model.recordExperimentalRemoteHelperLog(
            "Backtick MCP HTTP served protected remote request surface=web path=/mcp bodyBytes=244 rpcMethod=tools/call targetKind=tool targetName=backtick_list_docs"
        )

        XCTAssertEqual(model.experimentalRemoteStatusPresentation.title, "Connected on Web")
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
        await waitUntil {
            model.experimentalRemoteStatusPresentation.title == "Needs attention"
        }

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
            "Backtick MCP HTTP served protected remote request surface=web path=/mcp bodyBytes=188 rpcMethod=tools/call targetKind=tool targetName=backtick_list_docs"
        )
        model.refreshExperimentalRemoteProbe()
        await waitUntil {
            model.experimentalRemoteStatusPresentation.title == "Needs attention"
        }

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
        await waitUntil {
            model.experimentalRemoteStatusPresentation.title == "Needs attention"
        }

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
            .appendingPathComponent("Backtick.app", isDirectory: true)
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
        XCTAssertEqual(
            backtick["env"] as? [String: String],
            ["BACKTICK_CONNECTOR_CLIENT": "claudeDesktop"]
        )
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
        XCTAssertEqual(
            (servers["backtick"] as? [String: Any])?["env"] as? [String: String],
            ["BACKTICK_CONNECTOR_CLIENT": "claudeDesktop"]
        )
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

private final class RecordingConnectionTester: MCPServerConnectionTesting {
    private(set) var launchSpecs: [MCPServerLaunchSpec] = []
    let state: MCPServerConnectionState

    init(state: MCPServerConnectionState) {
        self.state = state
    }

    func run(launchSpec: MCPServerLaunchSpec) async -> MCPServerConnectionState {
        launchSpecs.append(launchSpec)
        return state
    }
}

private struct TestConnectionActivityReader: MCPConnectorConnectionActivityReading {
    let activities: [MCPConnectorConnectionActivity]

    func loadActivities() -> [MCPConnectorConnectionActivity] {
        activities
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
