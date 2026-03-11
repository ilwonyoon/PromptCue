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

        await model.performServerTest()

        XCTAssertEqual(model.connectionState, .passed(expectedReport))
        XCTAssertEqual(model.clientSetupTitle(for: claude), "Set up")
        XCTAssertEqual(model.clientVerificationTitle(for: claude), "Local server OK")
        XCTAssertTrue(model.clientSummary(for: claude).contains("allowed tool list"))
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
        XCTAssertEqual(model.primaryAction(for: claude), .runServerTest)
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
        XCTAssertTrue(model.clientSummary(for: claude).contains("Install"))
    }

    private func makeInspector() -> MCPConnectorInspector {
        MCPConnectorInspector(
            environment: [:],
            homeDirectoryURL: homeDirectoryURL,
            repositoryRootURL: repositoryRootURL
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
