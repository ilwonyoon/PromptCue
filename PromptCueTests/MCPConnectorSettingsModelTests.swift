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

    private func makeInspector() -> MCPConnectorInspector {
        MCPConnectorInspector(
            environment: [:],
            homeDirectoryURL: homeDirectoryURL,
            repositoryRootURL: repositoryRootURL
        )
    }
}
