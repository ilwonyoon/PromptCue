import Foundation
import XCTest
@testable import BacktickMCPServer

final class BacktickMCPServerTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var databaseURL: URL!
    private var attachmentsURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        attachmentsURL = tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        tempDirectoryURL = nil
        databaseURL = nil
        attachmentsURL = nil
        try super.tearDownWithError()
    }

    func testInitializeAndToolsListExposeExpectedToolSurface() async throws {
        let session = await makeSession()

        let initializeResponse = try await sendRequest(
            session: session,
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": [
                    "name": "test",
                    "version": "0.0.1",
                ],
            ]
        )
        let result = try XCTUnwrap(initializeResponse["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")

        let toolsResponse = try await sendRequest(session: session, id: 2, method: "tools/list")
        let toolsResult = try XCTUnwrap(toolsResponse["result"] as? [String: Any])
        let tools = try XCTUnwrap(toolsResult["tools"] as? [[String: Any]])
        XCTAssertEqual(
            tools.compactMap { $0["name"] as? String },
            ["list_notes", "get_note", "create_note", "update_note", "delete_note", "mark_notes_executed"]
        )
    }

    func testCreateReadUpdateExecuteAndDeleteNotesThroughJsonRPC() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")
        let externalScreenshotURL = tempDirectoryURL.appendingPathComponent("test-shot.png", isDirectory: false)
        try Data("png".utf8).write(to: externalScreenshotURL)

        let createResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Ship Stack MCP",
                    "suggestedTarget": [
                        "appName": "Cursor",
                        "bundleIdentifier": "com.todesktop.230313mzl4w4u92",
                        "repositoryName": "PromptCue",
                        "branch": "main",
                    ],
                ],
            ]
        )
        let createdNote = try notePayload(from: createResponse)
        let createdID = try XCTUnwrap(createdNote["id"] as? String)

        let listResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "list_notes",
                "arguments": [
                    "scope": "active",
                ],
            ]
        )
        let listedNotes = try notesPayload(from: listResponse)
        XCTAssertEqual(listedNotes.count, 1)
        XCTAssertEqual(listedNotes.first?["id"] as? String, createdID)

        let getResponse = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "get_note",
                "arguments": [
                    "id": createdID,
                ],
            ]
        )
        let getPayload = try toolPayload(from: getResponse)
        XCTAssertEqual((getPayload["copyEvents"] as? [Any])?.count, 0)

        let updateResponse = try await sendRequest(
            session: session,
            id: 5,
            method: "tools/call",
            params: [
                "name": "update_note",
                "arguments": [
                    "id": createdID,
                    "text": "Ship Stack MCP for real",
                    "screenshotPath": externalScreenshotURL.path,
                ],
            ]
        )
        let updatedNote = try notePayload(from: updateResponse)
        XCTAssertEqual(updatedNote["text"] as? String, "Ship Stack MCP for real")
        let updatedScreenshotPath = try XCTUnwrap(updatedNote["screenshotPath"] as? String)
        XCTAssertNotEqual(updatedScreenshotPath, externalScreenshotURL.path)
        XCTAssertTrue(updatedScreenshotPath.hasPrefix(attachmentsURL.path))

        let executeResponse = try await sendRequest(
            session: session,
            id: 6,
            method: "tools/call",
            params: [
                "name": "mark_notes_executed",
                "arguments": [
                    "noteIDs": [createdID],
                    "sessionID": "run-99",
                    "copiedAt": "2026-03-11T16:00:00.000Z",
                ],
            ]
        )
        let executePayload = try toolPayload(from: executeResponse)
        XCTAssertEqual(executePayload["count"] as? Int, 1)
        XCTAssertEqual((executePayload["copyEvents"] as? [[String: Any]])?.count, 1)

        let copiedResponse = try await sendRequest(
            session: session,
            id: 7,
            method: "tools/call",
            params: [
                "name": "list_notes",
                "arguments": [
                    "scope": "copied",
                ],
            ]
        )
        let copiedNotes = try notesPayload(from: copiedResponse)
        XCTAssertEqual(copiedNotes.count, 1)
        XCTAssertEqual(copiedNotes.first?["isCopied"] as? Bool, true)

        let deleteResponse = try await sendRequest(
            session: session,
            id: 8,
            method: "tools/call",
            params: [
                "name": "delete_note",
                "arguments": [
                    "id": createdID,
                ],
            ]
        )
        let deletePayload = try toolPayload(from: deleteResponse)
        XCTAssertEqual(deletePayload["deleted"] as? Bool, true)
    }

    func testUnsupportedMethodsReturnJsonRPCError() async throws {
        let session = await makeSession()
        let response = try await sendRequest(session: session, id: 1, method: "stack/unknown")
        let error = try XCTUnwrap(response["error"] as? [String: Any])

        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    private func makeSession() async -> BacktickMCPServerSession {
        let databaseURL = self.databaseURL
        let attachmentsURL = self.attachmentsURL

        return await MainActor.run {
            return BacktickMCPServerSession(
                databaseURL: databaseURL,
                attachmentBaseDirectoryURL: attachmentsURL
            )
        }
    }

    private func sendRequest(
        session: BacktickMCPServerSession,
        id: Any,
        method: String,
        params: [String: Any] = [:]
    ) async throws -> [String: Any] {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        let line = try XCTUnwrap(String(data: data, encoding: .utf8))
        let responseLine = try await MainActor.run {
            try XCTUnwrap(session.handleLine(line))
        }
        let responseData = try XCTUnwrap(responseLine.data(using: .utf8))
        let responseObject = try JSONSerialization.jsonObject(with: responseData)
        return try XCTUnwrap(responseObject as? [String: Any])
    }

    private func toolPayload(from response: [String: Any]) throws -> [String: Any] {
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let payloadData = try XCTUnwrap(text.data(using: .utf8))
        let payload = try JSONSerialization.jsonObject(with: payloadData)
        return try XCTUnwrap(payload as? [String: Any])
    }

    private func notePayload(from response: [String: Any]) throws -> [String: Any] {
        let payload = try toolPayload(from: response)
        return try XCTUnwrap(payload["note"] as? [String: Any])
    }

    private func notesPayload(from response: [String: Any]) throws -> [[String: Any]] {
        let payload = try toolPayload(from: response)
        return try XCTUnwrap(payload["notes"] as? [[String: Any]])
    }
}
