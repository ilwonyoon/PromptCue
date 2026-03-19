import Foundation
import XCTest
@testable import BacktickMCPServer
import PromptCueCore

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
            [
                "list_notes",
                "get_note",
                "create_note",
                "update_note",
                "delete_note",
                "mark_notes_executed",
                "classify_notes",
                "group_notes",
                "get_started",
                "list_documents",
                "recall_document",
                "save_document",
                "update_document",
            ]
        )

        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["prompts"])
        XCTAssertNotNil(capabilities["resources"])

        let resourcesResponse = try await sendRequest(session: session, id: 3, method: "resources/list")
        let resourcesResult = try XCTUnwrap(resourcesResponse["result"] as? [String: Any])
        let resources = try XCTUnwrap(resourcesResult["resources"] as? [Any])
        XCTAssertTrue(resources.isEmpty)
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
                    "tags": ["bug", "#mcp"],
                ],
            ]
        )
        let createdNote = try notePayload(from: createResponse)
        let createdID = try XCTUnwrap(createdNote["id"] as? String)
        XCTAssertEqual(createdNote["tags"] as? [String], ["bug", "mcp"])

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
                    "tags": ["release", "mcp"],
                    "screenshotPath": externalScreenshotURL.path,
                ],
            ]
        )
        let updatedNote = try notePayload(from: updateResponse)
        XCTAssertEqual(updatedNote["text"] as? String, "Ship Stack MCP for real")
        XCTAssertEqual(updatedNote["tags"] as? [String], ["release", "mcp"])
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

    func testSaveListAndRecallDocumentsThroughJsonRPC() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let firstContent = """
        ## Decision
        - Freemium + $9/mo premium remains the current recommendation because the pricing discussion converged on a low-friction paid tier.

        ## Reasoning
        - Users comparing Backtick with clipboard tools still need a clear upgrade path.
        - The discussion repeatedly rejected heavier enterprise packaging for the first launch.
        """

        let saveFirstResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "pricing",
                    "documentType": "decision",
                    "content": firstContent,
                ],
            ]
        )
        let firstDocument = try documentPayload(from: saveFirstResponse)
        let firstID = try XCTUnwrap(firstDocument["id"] as? String)
        XCTAssertEqual(firstDocument["topic"] as? String, "pricing")
        XCTAssertEqual(firstDocument["documentType"] as? String, "decision")

        let listResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "list_documents",
                "arguments": [
                    "project": "backtick",
                ],
            ]
        )
        let listPayload = try toolPayload(from: listResponse)
        let listedDocuments = try XCTUnwrap(listPayload["documents"] as? [[String: Any]])
        XCTAssertEqual(listedDocuments.count, 1)
        XCTAssertEqual(listedDocuments.first?["id"] as? String, firstID)

        let secondContent = """
        ## Decision
        - Freemium + $9/mo premium remains the current recommendation, with direct download shipping before any managed distribution.

        ## Reasoning
        - Pricing stayed aligned with the latest ChatGPT and Claude discussion.
        - The reviewed document should supersede the earlier decision version without creating duplicate active docs.
        """

        let saveSecondResponse = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "pricing",
                    "documentType": "decision",
                    "content": secondContent,
                ],
            ]
        )
        let secondDocument = try documentPayload(from: saveSecondResponse)
        let secondID = try XCTUnwrap(secondDocument["id"] as? String)
        XCTAssertNotEqual(secondID, firstID)

        let recallResponse = try await sendRequest(
            session: session,
            id: 5,
            method: "tools/call",
            params: [
                "name": "recall_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "pricing",
                    "documentType": "decision",
                ],
            ]
        )
        let recalledDocument = try documentPayload(from: recallResponse)
        XCTAssertEqual(recalledDocument["id"] as? String, secondID)
        XCTAssertEqual(recalledDocument["content"] as? String, secondContent)

        let listAfterSecondSaveResponse = try await sendRequest(
            session: session,
            id: 6,
            method: "tools/call",
            params: [
                "name": "list_documents",
                "arguments": [
                    "project": "backtick",
                ],
            ]
        )
        let listAfterSecondSavePayload = try toolPayload(from: listAfterSecondSaveResponse)
        let listedAfterSecondSave = try XCTUnwrap(listAfterSecondSavePayload["documents"] as? [[String: Any]])
        XCTAssertEqual(listedAfterSecondSave.count, 1)
        XCTAssertEqual(listedAfterSecondSave.first?["id"] as? String, secondID)
    }

    func testSaveDocumentRejectsShortUnstructuredContent() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "pricing",
                    "documentType": "decision",
                    "content": "Too short",
                ],
            ]
        )

        let payload = try toolErrorPayload(from: response)
        XCTAssertEqual(
            payload["error"] as? String,
            "content must be at least 200 characters of structured markdown"
        )
    }

    func testUpdateDocumentAppendsReplacesAndDeletesSectionsThroughJsonRPC() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let initialContent = """
        ## Decision
        - Use a self-hosted OAuth MCP bridge for ChatGPT.

        ## Open Questions
        - Decide whether ngrok remains the only supported tunnel for the experimental release.

        ## Notes
        - Keep the first pass focused on a single-user workflow.
        """

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "mcp",
                    "documentType": "plan",
                    "content": initialContent,
                ],
            ]
        )

        let appendResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "update_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "mcp",
                    "documentType": "plan",
                    "action": "append",
                    "content": """
                    ## Next Slice
                    - Add update_document before introducing a visible Memory panel.
                    - Keep the document workflow AI-first and review-aware.
                    """,
                ],
            ]
        )
        let appendedDocument = try documentPayload(from: appendResponse)
        let appendedContent = try XCTUnwrap(appendedDocument["content"] as? String)
        XCTAssertTrue(appendedContent.contains("## Next Slice"))

        let replaceResponse = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "update_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "mcp",
                    "documentType": "plan",
                    "action": "replace_section",
                    "section": "Open Questions",
                    "content": """
                    - Ngrok stays in the experimental path for now.
                    - Hosted distribution remains explicitly out of scope.
                    """,
                ],
            ]
        )
        let replacedDocument = try documentPayload(from: replaceResponse)
        let replacedContent = try XCTUnwrap(replacedDocument["content"] as? String)
        XCTAssertTrue(replacedContent.contains("## Open Questions\n- Ngrok stays in the experimental path for now."))
        XCTAssertFalse(replacedContent.contains("Decide whether ngrok remains the only supported tunnel"))

        let deleteResponse = try await sendRequest(
            session: session,
            id: 5,
            method: "tools/call",
            params: [
                "name": "update_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "mcp",
                    "documentType": "plan",
                    "action": "delete_section",
                    "section": "Notes",
                ],
            ]
        )
        let deletedDocument = try documentPayload(from: deleteResponse)
        let deletedContent = try XCTUnwrap(deletedDocument["content"] as? String)
        XCTAssertFalse(deletedContent.contains("## Notes"))
        XCTAssertTrue(deletedContent.contains("## Decision"))
        XCTAssertTrue(deletedContent.contains("## Next Slice"))

        let listResponse = try await sendRequest(
            session: session,
            id: 6,
            method: "tools/call",
            params: [
                "name": "list_documents",
                "arguments": [
                    "project": "backtick",
                ],
            ]
        )
        let listPayload = try toolPayload(from: listResponse)
        let documents = try XCTUnwrap(listPayload["documents"] as? [[String: Any]])
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?["documentType"] as? String, "plan")
    }

    func testUpdateDocumentRejectsUnknownSection() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let content = """
        ## Decision
        - Use reviewed documents for durable memory instead of raw transcripts.

        ## Notes
        - The first implementation only needs storage and MCP tools.
        - Memory UI can wait until the retrieval contract is stable.
        """

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "memory",
                    "documentType": "discussion",
                    "content": content,
                ],
            ]
        )

        let updateResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "update_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "memory",
                    "documentType": "discussion",
                    "action": "replace_section",
                    "section": "Missing Section",
                    "content": "- This should fail.",
                ],
            ]
        )
        let errorPayload = try toolErrorPayload(from: updateResponse)
        XCTAssertEqual(errorPayload["error"] as? String, "Section not found: Missing Section")
    }

    func testCreateNotePostsStackDidChangeNotification() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let expectation = expectation(description: "stack change notification")
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(
            forName: .backtickStackDidChange,
            object: nil,
            queue: .main
        ) { notification in
            let tool = notification.userInfo?["tool"] as? String
            if tool == "create_note" {
                expectation.fulfill()
            }
        }
        defer { center.removeObserver(observer) }

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Created via MCP",
                ],
            ]
        )

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testCreateNoteRejectsMixedScriptTags() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Should fail",
                    "tags": ["bug", "ㅠㅕbug"],
                ],
            ]
        )
        let payload = try toolErrorPayload(from: response)

        XCTAssertEqual(payload["error"] as? String, "tags must contain valid tag names")
    }

    func testClassifyNotesGroupsByRepository() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Fix MCP parser",
                    "tags": ["bug", "parser"],
                ],
            ]
        )
        _ = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Add classify tool",
                    "tags": ["mcp", "parser"],
                ],
            ]
        )
        _ = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Update README",
                    "tags": ["docs"],
                ],
            ]
        )

        let classifyResponse = try await sendRequest(
            session: session,
            id: 5,
            method: "tools/call",
            params: [
                "name": "classify_notes",
                "arguments": [
                    "scope": "active",
                    "groupBy": "repository",
                ],
            ]
        )
        let payload = try toolPayload(from: classifyResponse)
        XCTAssertGreaterThanOrEqual(payload["groupCount"] as? Int ?? 0, 1)
        XCTAssertEqual(payload["totalNotes"] as? Int, 3)
    }

    func testClassifyNotesEmptyStack() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let classifyResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "classify_notes",
                "arguments": [:],
            ]
        )
        let payload = try toolPayload(from: classifyResponse)
        XCTAssertEqual(payload["groupCount"] as? Int, 0)
        XCTAssertEqual(payload["totalNotes"] as? Int, 0)
    }

    func testGroupNotesCreatesMergedCard() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let create1 = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Note A",
                    "tags": ["bug", "ui"],
                ],
            ]
        )
        let id1 = try XCTUnwrap(notePayload(from: create1)["id"] as? String)

        let create2 = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Note B",
                    "tags": ["mcp", "bug"],
                ],
            ]
        )
        let id2 = try XCTUnwrap(notePayload(from: create2)["id"] as? String)

        let groupResponse = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "group_notes",
                "arguments": [
                    "noteIDs": [id1, id2],
                    "title": "Merged Notes",
                ],
            ]
        )
        let payload = try toolPayload(from: groupResponse)
        let groupedNote = try XCTUnwrap(payload["groupedNote"] as? [String: Any])
        let mergedText = try XCTUnwrap(groupedNote["text"] as? String)

        XCTAssertTrue(mergedText.contains("# Merged Notes"))
        XCTAssertTrue(mergedText.contains("- Note A"))
        XCTAssertTrue(mergedText.contains("- Note B"))
        XCTAssertFalse(mergedText.contains("\n\n---\n\n"))
        XCTAssertEqual(groupedNote["tags"] as? [String], ["bug", "ui", "mcp"])
        XCTAssertEqual(payload["archivedCount"] as? Int, 0)

        let listResponse = try await sendRequest(
            session: session,
            id: 5,
            method: "tools/call",
            params: [
                "name": "list_notes",
                "arguments": ["scope": "active"],
            ]
        )
        let activeNotes = try notesPayload(from: listResponse)
        XCTAssertEqual(activeNotes.count, 3)
    }

    func testGroupNotesMergedTextOmitsSourceMetadataMarkers() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let createResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": ["text": "Source note one"],
            ]
        )
        let id = try XCTUnwrap(notePayload(from: createResponse)["id"] as? String)

        let groupResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "group_notes",
                "arguments": [
                    "noteIDs": [id],
                    "title": "Single Group",
                ],
            ]
        )
        let payload = try toolPayload(from: groupResponse)
        let groupedNote = try XCTUnwrap(payload["groupedNote"] as? [String: Any])
        let mergedText = try XCTUnwrap(groupedNote["text"] as? String)

        XCTAssertTrue(mergedText.contains("# Single Group"))
        XCTAssertTrue(mergedText.contains("- Source note one"))
        XCTAssertFalse(mergedText.contains("[note:"))
    }

    func testGroupNotesInvalidIDReturnsToolError() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let groupResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "group_notes",
                "arguments": [
                    "noteIDs": ["00000000-0000-0000-0000-000000000000"],
                    "title": "Bad Group",
                ],
            ]
        )
        let result = try XCTUnwrap(groupResponse["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testPromptsListReturnsFourTemplates() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let promptsResponse = try await sendRequest(session: session, id: 2, method: "prompts/list")
        let result = try XCTUnwrap(promptsResponse["result"] as? [String: Any])
        let prompts = try XCTUnwrap(result["prompts"] as? [[String: Any]])
        XCTAssertEqual(prompts.count, 4)
        XCTAssertEqual(
            prompts.compactMap { $0["name"] as? String },
            ["workflow", "triage", "diagnose", "execute"]
        )
    }

    func testPromptsGetWorkflowRendersWithoutArguments() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let getResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "prompts/get",
            params: ["name": "workflow"]
        )
        let result = try XCTUnwrap(getResponse["result"] as? [String: Any])
        let messages = try XCTUnwrap(result["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [String: Any])
        let text = try XCTUnwrap(content["text"] as? String)

        XCTAssertTrue(text.contains("classify_notes"))
        XCTAssertTrue(text.contains("mark_notes_executed"))
        XCTAssertTrue(text.contains("before the final response"))
        XCTAssertTrue(text.contains("Do not call `mark_notes_executed` during planning"))
    }

    func testPromptsGetExecuteRequiresMarkingCompletedNotesExecuted() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let getResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "prompts/get",
            params: [
                "name": "execute",
                "arguments": [
                    "noteText": "Polish settings sidebar",
                    "repositoryName": "PromptCue",
                    "branch": "main",
                ],
            ]
        )
        let result = try XCTUnwrap(getResponse["result"] as? [String: Any])
        let messages = try XCTUnwrap(result["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [String: Any])
        let text = try XCTUnwrap(content["text"] as? String)

        XCTAssertTrue(text.contains("mark_notes_executed"))
        XCTAssertTrue(text.contains("before returning the final result"))
        XCTAssertTrue(text.contains("leave the rest active"))
    }

    func testPromptsGetDiagnoseRendersTemplate() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let getResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "prompts/get",
            params: [
                "name": "diagnose",
                "arguments": [
                    "noteText": "App crashes on launch",
                    "repositoryName": "PromptCue",
                    "branch": "main",
                ],
            ]
        )
        let result = try XCTUnwrap(getResponse["result"] as? [String: Any])
        let messages = try XCTUnwrap(result["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [String: Any])
        let text = try XCTUnwrap(content["text"] as? String)

        XCTAssertTrue(text.contains("App crashes on launch"))
        XCTAssertTrue(text.contains("PromptCue"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("root cause"))
    }

    func testUnsupportedMethodsReturnJsonRPCError() async throws {
        let session = await makeSession()
        let response = try await sendRequest(session: session, id: 1, method: "stack/unknown")
        let error = try XCTUnwrap(response["error"] as? [String: Any])

        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    func testHTTPHandlerServesInitializeOverPost() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration()
        )
        let body = try requestBody(
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": [
                    "name": "http-test",
                    "version": "0.1.0",
                ],
            ]
        )
        let request = BacktickMCPHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: [
                "content-length": "\(body.count)",
                "content-type": "application/json",
            ],
            body: body
        )

        let response = await handler.response(for: request)
        XCTAssertEqual(response.statusCode, 200)
        let payload = try jsonObject(from: response.body)
        let result = try XCTUnwrap(payload["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
    }

    func testHTTPHandlerRequiresBearerTokenWhenConfigured() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(apiKey: "secret-token")
        )
        let request = BacktickMCPHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: [
                "content-length": "2",
                "content-type": "application/json",
            ],
            body: Data("{}".utf8)
        )

        let response = await handler.response(for: request)
        XCTAssertEqual(response.statusCode, 401)
    }

    func testOAuthMetadataAndAuthorizationCodeFlowIssueAccessToken() async throws {
        let session = await makeSession()
        let oauthStateFileURL = tempDirectoryURL.appendingPathComponent("oauth-state.json", isDirectory: false)
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL
            )
        )

        let protectedResourceResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "GET",
                path: "/.well-known/oauth-protected-resource",
                headers: [:],
                body: Data()
            )
        )
        XCTAssertEqual(protectedResourceResponse.statusCode, 200)
        let protectedResourcePayload = try jsonObject(from: protectedResourceResponse.body)
        let protectedScopes = try XCTUnwrap(protectedResourcePayload["scopes_supported"] as? [String])
        XCTAssertTrue(protectedScopes.contains("backtick.mcp"))
        XCTAssertTrue(protectedScopes.contains("offline_access"))

        let openIDConfigurationResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "GET",
                path: "/.well-known/openid-configuration",
                headers: [:],
                body: Data()
            )
        )
        XCTAssertEqual(openIDConfigurationResponse.statusCode, 200)
        let openIDConfigurationPayload = try jsonObject(from: openIDConfigurationResponse.body)
        let openIDScopes = try XCTUnwrap(openIDConfigurationPayload["scopes_supported"] as? [String])
        XCTAssertTrue(openIDScopes.contains("backtick.mcp"))
        XCTAssertTrue(openIDScopes.contains("offline_access"))

        let registrationBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "ChatGPT",
            "redirect_uris": ["https://chat.openai.com/aip/callback"],
            "token_endpoint_auth_method": "none",
        ], options: [.sortedKeys])
        let registrationResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/register",
                headers: [
                    "content-length": "\(registrationBody.count)",
                    "content-type": "application/json",
                ],
                body: registrationBody
            )
        )
        XCTAssertEqual(registrationResponse.statusCode, 201)
        let registrationPayload = try jsonObject(from: registrationResponse.body)
        let clientID = try XCTUnwrap(registrationPayload["client_id"] as? String)

        let authorizePageResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "GET",
                path: "/oauth/authorize?client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&response_type=code&scope=backtick.mcp&state=abc123&code_challenge=C4o_XQvR65ONsuHQv0djlsMDYgPVB63jJiXd_a4GETw&code_challenge_method=S256",
                headers: [:],
                body: Data()
            )
        )
        XCTAssertEqual(authorizePageResponse.statusCode, 200)

        let authorizeForm = Data(
            "client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&response_type=code&scope=backtick.mcp&state=abc123&code_challenge=C4o_XQvR65ONsuHQv0djlsMDYgPVB63jJiXd_a4GETw&code_challenge_method=S256&decision=approve".utf8
        )
        let authorizeResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/authorize",
                headers: [
                    "content-length": "\(authorizeForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: authorizeForm
            )
        )
        XCTAssertEqual(authorizeResponse.statusCode, 302)
        let redirectLocation = try XCTUnwrap(authorizeResponse.headers["Location"])
        let redirectComponents = try XCTUnwrap(URLComponents(string: redirectLocation))
        let authorizationCode = try XCTUnwrap(
            redirectComponents.queryItems?.first(where: { $0.name == "code" })?.value
        )

        let tokenForm = Data(
            "grant_type=authorization_code&code=\(authorizationCode)&client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&code_verifier=backtick-verifier".utf8
        )
        let tokenResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(tokenForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: tokenForm
            )
        )
        XCTAssertEqual(tokenResponse.statusCode, 200)
        let tokenPayload = try jsonObject(from: tokenResponse.body)
        let accessToken = try XCTUnwrap(tokenPayload["access_token"] as? String)
        let refreshToken = try XCTUnwrap(tokenPayload["refresh_token"] as? String)

        let body = try requestBody(id: 1, method: "initialize")
        let protectedResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(accessToken)",
                    "content-length": "\(body.count)",
                    "content-type": "application/json",
                ],
                body: body
            )
        )
        XCTAssertEqual(protectedResponse.statusCode, 200)

        let restartedHandler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL
            )
        )

        let authorizeAfterRestartResponse = await restartedHandler.response(
            for: BacktickMCPHTTPRequest(
                method: "GET",
                path: "/oauth/authorize?client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&response_type=code&scope=backtick.mcp&state=restart123&code_challenge=C4o_XQvR65ONsuHQv0djlsMDYgPVB63jJiXd_a4GETw&code_challenge_method=S256",
                headers: [:],
                body: Data()
            )
        )
        XCTAssertEqual(authorizeAfterRestartResponse.statusCode, 200)

        let persistedTokenResponse = await restartedHandler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(accessToken)",
                    "content-length": "\(body.count)",
                    "content-type": "application/json",
                ],
                body: body
            )
        )
        XCTAssertEqual(persistedTokenResponse.statusCode, 200)

        let refreshForm = Data(
            "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)".utf8
        )
        let refreshResponse = await restartedHandler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(refreshForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: refreshForm
            )
        )
        XCTAssertEqual(refreshResponse.statusCode, 200)
        let refreshPayload = try jsonObject(from: refreshResponse.body)
        XCTAssertNotNil(refreshPayload["access_token"] as? String)
        XCTAssertEqual(refreshPayload["refresh_token"] as? String, refreshToken)
    }

    func testOAuthTokenEndpointRejectsCodeReuseAndInvalidRefreshToken() async throws {
        let session = await makeSession()
        let oauthStateFileURL = tempDirectoryURL.appendingPathComponent("oauth-state-rejections.json", isDirectory: false)
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL
            )
        )

        let registrationBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "ChatGPT",
            "redirect_uris": ["https://chat.openai.com/aip/callback"],
            "token_endpoint_auth_method": "none",
        ], options: [.sortedKeys])
        let registrationResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/register",
                headers: [
                    "content-length": "\(registrationBody.count)",
                    "content-type": "application/json",
                ],
                body: registrationBody
            )
        )
        XCTAssertEqual(registrationResponse.statusCode, 201)
        let registrationPayload = try jsonObject(from: registrationResponse.body)
        let clientID = try XCTUnwrap(registrationPayload["client_id"] as? String)

        let authorizeForm = Data(
            "client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&response_type=code&scope=backtick.mcp&state=reuse123&code_challenge=C4o_XQvR65ONsuHQv0djlsMDYgPVB63jJiXd_a4GETw&code_challenge_method=S256&decision=approve".utf8
        )
        let authorizeResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/authorize",
                headers: [
                    "content-length": "\(authorizeForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: authorizeForm
            )
        )
        XCTAssertEqual(authorizeResponse.statusCode, 302)
        let redirectLocation = try XCTUnwrap(authorizeResponse.headers["Location"])
        let redirectComponents = try XCTUnwrap(URLComponents(string: redirectLocation))
        let authorizationCode = try XCTUnwrap(
            redirectComponents.queryItems?.first(where: { $0.name == "code" })?.value
        )

        let tokenForm = Data(
            "grant_type=authorization_code&code=\(authorizationCode)&client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&code_verifier=backtick-verifier".utf8
        )
        let firstTokenResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(tokenForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: tokenForm
            )
        )
        XCTAssertEqual(firstTokenResponse.statusCode, 200)

        let reusedCodeResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(tokenForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: tokenForm
            )
        )
        XCTAssertEqual(reusedCodeResponse.statusCode, 400)
        let reusedCodePayload = try jsonObject(from: reusedCodeResponse.body)
        XCTAssertEqual(reusedCodePayload["error"] as? String, "invalid_grant")

        let invalidRefreshForm = Data(
            "grant_type=refresh_token&refresh_token=stale-refresh-token&client_id=\(clientID)".utf8
        )
        let invalidRefreshResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(invalidRefreshForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: invalidRefreshForm
            )
        )
        XCTAssertEqual(invalidRefreshResponse.statusCode, 400)
        let invalidRefreshPayload = try jsonObject(from: invalidRefreshResponse.body)
        XCTAssertEqual(invalidRefreshPayload["error"] as? String, "invalid_grant")
    }

    func testOAuthTokenEndpointRejectsStaleClientIDAfterLocalStateReset() async throws {
        let session = await makeSession()
        let oauthStateFileURL = tempDirectoryURL.appendingPathComponent("oauth-state-invalid-client.json", isDirectory: false)
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL
            )
        )

        let registrationBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "ChatGPT",
            "redirect_uris": ["https://chat.openai.com/aip/callback"],
            "token_endpoint_auth_method": "none",
        ], options: [.sortedKeys])
        let registrationResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/register",
                headers: [
                    "content-length": "\(registrationBody.count)",
                    "content-type": "application/json",
                ],
                body: registrationBody
            )
        )
        XCTAssertEqual(registrationResponse.statusCode, 201)
        let registrationPayload = try jsonObject(from: registrationResponse.body)
        let clientID = try XCTUnwrap(registrationPayload["client_id"] as? String)

        try FileManager.default.removeItem(at: oauthStateFileURL)

        let restartedHandler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL
            )
        )

        let staleClientTokenForm = Data(
            "grant_type=refresh_token&refresh_token=does-not-matter&client_id=\(clientID)".utf8
        )
        let staleClientResponse = await restartedHandler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(staleClientTokenForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: staleClientTokenForm
            )
        )
        XCTAssertEqual(staleClientResponse.statusCode, 400)
        let staleClientPayload = try jsonObject(from: staleClientResponse.body)
        XCTAssertEqual(staleClientPayload["error"] as? String, "invalid_client")
    }

    func testExpiredPersistedAccessTokenCanRecoverViaRefreshTokenAfterRestart() async throws {
        let session = await makeSession()
        let oauthStateFileURL = tempDirectoryURL.appendingPathComponent("oauth-state-expired-access.json", isDirectory: false)
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL
            )
        )

        let registrationBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "ChatGPT",
            "redirect_uris": ["https://chat.openai.com/aip/callback"],
            "token_endpoint_auth_method": "none",
        ], options: [.sortedKeys])
        let registrationResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/register",
                headers: [
                    "content-length": "\(registrationBody.count)",
                    "content-type": "application/json",
                ],
                body: registrationBody
            )
        )
        XCTAssertEqual(registrationResponse.statusCode, 201)
        let registrationPayload = try jsonObject(from: registrationResponse.body)
        let clientID = try XCTUnwrap(registrationPayload["client_id"] as? String)

        let authorizeForm = Data(
            "client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&response_type=code&scope=backtick.mcp&state=expired123&code_challenge=C4o_XQvR65ONsuHQv0djlsMDYgPVB63jJiXd_a4GETw&code_challenge_method=S256&decision=approve".utf8
        )
        let authorizeResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/authorize",
                headers: [
                    "content-length": "\(authorizeForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: authorizeForm
            )
        )
        XCTAssertEqual(authorizeResponse.statusCode, 302)
        let redirectLocation = try XCTUnwrap(authorizeResponse.headers["Location"])
        let redirectComponents = try XCTUnwrap(URLComponents(string: redirectLocation))
        let authorizationCode = try XCTUnwrap(
            redirectComponents.queryItems?.first(where: { $0.name == "code" })?.value
        )

        let tokenForm = Data(
            "grant_type=authorization_code&code=\(authorizationCode)&client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&code_verifier=backtick-verifier".utf8
        )
        let tokenResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(tokenForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: tokenForm
            )
        )
        XCTAssertEqual(tokenResponse.statusCode, 200)
        let tokenPayload = try jsonObject(from: tokenResponse.body)
        let accessToken = try XCTUnwrap(tokenPayload["access_token"] as? String)
        let refreshToken = try XCTUnwrap(tokenPayload["refresh_token"] as? String)

        try expirePersistedAccessToken(accessToken, in: oauthStateFileURL)

        let restartedHandler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL
            )
        )

        let body = try requestBody(id: 1, method: "initialize")
        let expiredAccessResponse = await restartedHandler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(accessToken)",
                    "content-length": "\(body.count)",
                    "content-type": "application/json",
                ],
                body: body
            )
        )
        XCTAssertEqual(expiredAccessResponse.statusCode, 401)

        let refreshForm = Data(
            "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)".utf8
        )
        let refreshResponse = await restartedHandler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(refreshForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: refreshForm
            )
        )
        XCTAssertEqual(refreshResponse.statusCode, 200)
        let refreshPayload = try jsonObject(from: refreshResponse.body)
        let refreshedAccessToken = try XCTUnwrap(refreshPayload["access_token"] as? String)
        XCTAssertEqual(refreshPayload["refresh_token"] as? String, refreshToken)

        let recoveredResponse = await restartedHandler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(refreshedAccessToken)",
                    "content-length": "\(body.count)",
                    "content-type": "application/json",
                ],
                body: body
            )
        )
        XCTAssertEqual(recoveredResponse.statusCode, 200)
    }

    func testShortLivedAccessTokenExpiresThenRefreshRecovers() async throws {
        let session = await makeSession()
        let oauthStateFileURL = tempDirectoryURL.appendingPathComponent("oauth-state-short-ttl.json", isDirectory: false)
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL,
                accessTokenLifetime: 1
            )
        )

        let registrationBody = try JSONSerialization.data(withJSONObject: [
            "client_name": "ChatGPT",
            "redirect_uris": ["https://chat.openai.com/aip/callback"],
            "token_endpoint_auth_method": "none",
        ], options: [.sortedKeys])
        let registrationResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/register",
                headers: [
                    "content-length": "\(registrationBody.count)",
                    "content-type": "application/json",
                ],
                body: registrationBody
            )
        )
        XCTAssertEqual(registrationResponse.statusCode, 201)
        let registrationPayload = try jsonObject(from: registrationResponse.body)
        let clientID = try XCTUnwrap(registrationPayload["client_id"] as? String)

        let authorizeForm = Data(
            "client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&response_type=code&scope=backtick.mcp&state=ttl123&code_challenge=C4o_XQvR65ONsuHQv0djlsMDYgPVB63jJiXd_a4GETw&code_challenge_method=S256&decision=approve".utf8
        )
        let authorizeResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/authorize",
                headers: [
                    "content-length": "\(authorizeForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: authorizeForm
            )
        )
        XCTAssertEqual(authorizeResponse.statusCode, 302)
        let redirectLocation = try XCTUnwrap(authorizeResponse.headers["Location"])
        let redirectComponents = try XCTUnwrap(URLComponents(string: redirectLocation))
        let authorizationCode = try XCTUnwrap(
            redirectComponents.queryItems?.first(where: { $0.name == "code" })?.value
        )

        let tokenForm = Data(
            "grant_type=authorization_code&code=\(authorizationCode)&client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&code_verifier=backtick-verifier".utf8
        )
        let tokenResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(tokenForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: tokenForm
            )
        )
        XCTAssertEqual(tokenResponse.statusCode, 200)
        let tokenPayload = try jsonObject(from: tokenResponse.body)
        let accessToken = try XCTUnwrap(tokenPayload["access_token"] as? String)
        let refreshToken = try XCTUnwrap(tokenPayload["refresh_token"] as? String)

        let body = try requestBody(id: 1, method: "initialize")
        let initialProtectedResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(accessToken)",
                    "content-length": "\(body.count)",
                    "content-type": "application/json",
                ],
                body: body
            )
        )
        XCTAssertEqual(initialProtectedResponse.statusCode, 200)

        try await Task.sleep(nanoseconds: 1_300_000_000)

        let expiredProtectedResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(accessToken)",
                    "content-length": "\(body.count)",
                    "content-type": "application/json",
                ],
                body: body
            )
        )
        XCTAssertEqual(expiredProtectedResponse.statusCode, 401)

        let refreshForm = Data(
            "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)".utf8
        )
        let refreshResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/oauth/token",
                headers: [
                    "content-length": "\(refreshForm.count)",
                    "content-type": "application/x-www-form-urlencoded",
                ],
                body: refreshForm
            )
        )
        XCTAssertEqual(refreshResponse.statusCode, 200)
        let refreshPayload = try jsonObject(from: refreshResponse.body)
        let refreshedAccessToken = try XCTUnwrap(refreshPayload["access_token"] as? String)
        XCTAssertEqual(refreshPayload["refresh_token"] as? String, refreshToken)

        let recoveredResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(refreshedAccessToken)",
                    "content-length": "\(body.count)",
                    "content-type": "application/json",
                ],
                body: body
            )
        )
        XCTAssertEqual(recoveredResponse.statusCode, 200)
    }

    func testHTTPRequestParserReturnsIncompleteUntilBodyArrives() {
        let partial = Data("POST /mcp HTTP/1.1\r\nContent-Length: 18\r\n\r\n{\"jsonrpc\":\"2.0\"".utf8)
        switch BacktickMCPHTTPRequestParser.parse(partial) {
        case .incomplete:
            break
        case .failure(let message):
            XCTFail("Expected incomplete parse, got failure: \(message)")
        case .success:
            XCTFail("Expected incomplete parse result")
        }
    }

    func testHTTPRequestParserParsesPostBodyAndHeaders() throws {
        let body = try requestBody(id: 1, method: "tools/list")
        let rawRequest = Data(
            (
                "POST /mcp HTTP/1.1\r\n" +
                "Content-Type: application/json\r\n" +
                "Content-Length: \(body.count)\r\n" +
                "Authorization: Bearer test-key\r\n\r\n"
            ).utf8
        ) + body

        switch BacktickMCPHTTPRequestParser.parse(rawRequest) {
        case .success(let request):
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.path, "/mcp")
            XCTAssertEqual(request.headers["content-type"], "application/json")
            XCTAssertEqual(request.headers["authorization"], "Bearer test-key")
            XCTAssertEqual(request.body, body)
        case .incomplete:
            XCTFail("Expected parsed request")
        case .failure(let message):
            XCTFail("Unexpected parse failure: \(message)")
        }
    }

    private func makeSession() async -> BacktickMCPServerSession {
        let databaseURL = self.databaseURL
        let attachmentsURL = self.attachmentsURL

        return await MainActor.run {
            BacktickMCPServerSession(
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
        let data = try requestBody(id: id, method: method, params: params)
        let line = try XCTUnwrap(String(data: data, encoding: .utf8))
        let responseLine = try await MainActor.run {
            try XCTUnwrap(session.handleLine(line))
        }
        let responseData = try XCTUnwrap(responseLine.data(using: .utf8))
        let responseObject = try JSONSerialization.jsonObject(with: responseData)
        return try XCTUnwrap(responseObject as? [String: Any])
    }

    private func requestBody(
        id: Any,
        method: String,
        params: [String: Any] = [:]
    ) throws -> Data {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        return try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func expirePersistedAccessToken(_ token: String, in stateFileURL: URL) throws {
        let data = try Data(contentsOf: stateFileURL)
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var accessTokens = try XCTUnwrap(payload["accessTokens"] as? [String: Any])
        var accessGrant = try XCTUnwrap(accessTokens[token] as? [String: Any])
        accessGrant["expiresAt"] = 0
        accessTokens[token] = accessGrant
        payload["accessTokens"] = accessTokens

        let updatedData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try updatedData.write(to: stateFileURL, options: .atomic)
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

    private func documentPayload(from response: [String: Any]) throws -> [String: Any] {
        let payload = try toolPayload(from: response)
        return try XCTUnwrap(payload["document"] as? [String: Any])
    }

    private func toolErrorPayload(from response: [String: Any]) throws -> [String: Any] {
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let payloadData = try XCTUnwrap(text.data(using: .utf8))
        let payload = try JSONSerialization.jsonObject(with: payloadData)
        return try XCTUnwrap(payload as? [String: Any])
    }

    private func notesPayload(from response: [String: Any]) throws -> [[String: Any]] {
        let payload = try toolPayload(from: response)

        var allNotes: [[String: Any]] = []
        for group in ["pinned", "active", "copied"] {
            if let section = payload[group] as? [String: Any],
               let notes = section["notes"] as? [[String: Any]] {
                allNotes.append(contentsOf: notes)
            }
        }
        return allNotes
    }
}
