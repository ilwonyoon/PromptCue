import Foundation
import XCTest
@testable import BacktickMCPServer
import PromptCueCore

final class BacktickMCPServerTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var databaseURL: URL!
    private var attachmentsURL: URL!
    private var connectionActivityFileURL: URL!

    private func exposedToolName(_ canonicalName: String) -> String {
        BacktickMCPToolNaming.exposedName(canonicalName)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        databaseURL = tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")
        attachmentsURL = tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
        connectionActivityFileURL = tempDirectoryURL.appendingPathComponent("BacktickMCPConnectionActivity.json")
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        tempDirectoryURL = nil
        databaseURL = nil
        attachmentsURL = nil
        connectionActivityFileURL = nil
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
        let instructions = try XCTUnwrap(result["instructions"] as? String)
        XCTAssertTrue(instructions.contains("Backtick"))
        XCTAssertTrue(instructions.contains("백틱"))
        XCTAssertTrue(instructions.contains("Do not save silently"))
        XCTAssertTrue(instructions.contains("Good examples"))
        XCTAssertTrue(instructions.contains("Bad examples"))
        XCTAssertTrue(instructions.contains("list_saved_items"))
        XCTAssertTrue(instructions.contains("ChatGPT and Claude app clients"))
        XCTAssertTrue(instructions.contains("Claude Code or Codex"))
        XCTAssertTrue(instructions.contains("Stack first, then Memory"))
        XCTAssertTrue(instructions.contains("Memory, Stack, or both"))

        let toolsResponse = try await sendRequest(session: session, id: 2, method: "tools/list")
        let toolsResult = try XCTUnwrap(toolsResponse["result"] as? [String: Any])
        let tools = try XCTUnwrap(toolsResult["tools"] as? [[String: Any]])
        XCTAssertEqual(
            tools.compactMap { $0["name"] as? String },
            [
                exposedToolName("list_notes"),
                exposedToolName("get_note"),
                exposedToolName("create_note"),
                exposedToolName("update_note"),
                exposedToolName("delete_note"),
                exposedToolName("mark_notes_executed"),
                exposedToolName("classify_notes"),
                exposedToolName("group_notes"),
                exposedToolName("get_started"),
                exposedToolName("list_saved_items"),
                exposedToolName("list_documents"),
                exposedToolName("recall_document"),
                exposedToolName("propose_document_saves"),
                exposedToolName("save_document"),
                exposedToolName("update_document"),
                exposedToolName("delete_document"),
            ]
        )
        let proposeTool = try XCTUnwrap(
            tools.first(where: { ($0["name"] as? String) == exposedToolName("propose_document_saves") })
        )
        let inputSchema = try XCTUnwrap(proposeTool["inputSchema"] as? [String: Any])
        XCTAssertEqual(inputSchema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(inputSchema["required"] as? [String], ["project", "content"])
        XCTAssertTrue((proposeTool["description"] as? String ?? "").contains("propose"))
        let saveTool = try XCTUnwrap(
            tools.first(where: { ($0["name"] as? String) == exposedToolName("save_document") })
        )
        XCTAssertTrue((saveTool["description"] as? String ?? "").contains("Save a durable project document"))
        let updateTool = try XCTUnwrap(
            tools.first(where: { ($0["name"] as? String) == exposedToolName("update_document") })
        )
        XCTAssertTrue((updateTool["description"] as? String ?? "").contains("Good:"))
        XCTAssertTrue((updateTool["description"] as? String ?? "").contains("Bad:"))
        let savedItemsTool = try XCTUnwrap(
            tools.first(where: { ($0["name"] as? String) == exposedToolName("list_saved_items") })
        )
        let savedItemsAnnotations = try XCTUnwrap(savedItemsTool["annotations"] as? [String: Any])
        XCTAssertEqual(savedItemsAnnotations["readOnlyHint"] as? Bool, true)
        let getStartedTool = try XCTUnwrap(
            tools.first(where: { ($0["name"] as? String) == exposedToolName("get_started") })
        )
        let getStartedAnnotations = try XCTUnwrap(getStartedTool["annotations"] as? [String: Any])
        XCTAssertEqual(getStartedAnnotations["readOnlyHint"] as? Bool, true)
        let properties = try XCTUnwrap(inputSchema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["userIntent"])
        XCTAssertNotNil(properties["preferredTopic"])
        XCTAssertNotNil(properties["maxProposals"])

        let getStartedResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "get_started",
                "arguments": [:],
            ]
        )
        let getStartedPayload = try toolPayload(from: getStartedResponse)
        XCTAssertNotNil(getStartedPayload["welcome"] as? String)
        let getStartedTools = try XCTUnwrap(getStartedPayload["tools"] as? [[String: Any]])
        XCTAssertTrue(
            getStartedTools.contains(where: { ($0["name"] as? String) == exposedToolName("list_saved_items") })
        )
        XCTAssertTrue((getStartedPayload["tryIt"] as? String ?? "").contains("What do I have in Backtick?"))

        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["prompts"])
        XCTAssertNotNil(capabilities["resources"])

        let resourcesResponse = try await sendRequest(session: session, id: 4, method: "resources/list")
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

    func testListSavedItemsReturnsStackFirstCompactOverviewForCLIClients() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Pinned prompt for release review",
                    "isPinned": true,
                    "createdAt": "2026-03-20T09:00:00.000Z",
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
                    "text": "Active item for pricing sync",
                    "createdAt": "2026-03-20T10:00:00.000Z",
                ],
            ]
        )
        let copiedNoteResponse = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Copied item for launch checklist",
                    "createdAt": "2026-03-20T11:00:00.000Z",
                ],
            ]
        )
        let copiedNote = try notePayload(from: copiedNoteResponse)
        let copiedNoteID = try XCTUnwrap(copiedNote["id"] as? String)
        _ = try await sendRequest(
            session: session,
            id: 5,
            method: "tools/call",
            params: [
                "name": "mark_notes_executed",
                "arguments": [
                    "noteIDs": [copiedNoteID],
                    "copiedAt": "2026-03-20T11:30:00.000Z",
                ],
            ]
        )

        let content = """
        ## Decision
        We agreed that generic Backtick inventory requests in ChatGPT and Claude should show Memory first and only go Stack-first when the user explicitly asks for stack, prompts, pinned, copied, or the current queue. The overview should stay compact and should encourage a Memory vs Stack vs both clarification when the request is still ambiguous.

        ## Impact
        This avoids hiding durable project context behind Stack-only assumptions and keeps the assistant's first follow-up grounded in the full Backtick surface instead of whichever lane happened to be easier to query.
        """
        _ = try await sendRequest(
            session: session,
            id: 6,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "promptcue",
                    "topic": "inventory-routing",
                    "documentType": "decision",
                    "content": content,
                ],
            ]
        )

        let response = try await sendRequest(
            session: session,
            id: 7,
            method: "tools/call",
            params: [
                "name": "list_saved_items",
                "arguments": [:],
            ]
        )
        let payload = try toolPayload(from: response)

        XCTAssertEqual(payload["preferredFirst"] as? String, "stack")
        XCTAssertEqual(payload["presentationOrder"] as? [String], ["stack", "memory"])

        let memory = try XCTUnwrap(payload["memory"] as? [String: Any])
        XCTAssertEqual(memory["count"] as? Int, 1)
        let recentDocuments = try XCTUnwrap(memory["recentDocuments"] as? [[String: Any]])
        XCTAssertEqual(recentDocuments.first?["topic"] as? String, "inventory-routing")

        let stack = try XCTUnwrap(payload["stack"] as? [String: Any])
        XCTAssertEqual(stack["count"] as? Int, 3)
        XCTAssertEqual(stack["pinnedCount"] as? Int, 1)
        XCTAssertEqual(stack["activeCount"] as? Int, 1)
        XCTAssertEqual(stack["copiedCount"] as? Int, 1)
        let pinned = try XCTUnwrap(stack["pinned"] as? [[String: Any]])
        XCTAssertEqual(pinned.first?["previewText"] as? String, "Pinned prompt for release review")

        let nextStep = try XCTUnwrap(payload["recommendedNextStep"] as? String)
        XCTAssertTrue(nextStep.contains("Stack first"))
        XCTAssertTrue(nextStep.contains("Memory, Stack, or both"))
    }

    func testListSavedItemsReturnsMemoryFirstCompactOverviewForChatGPTRemote() async throws {
        let session = await makeSession(processEnvironment: [:], commandLine: ["/tmp/BacktickMCP", "--http"])
        _ = try await sendRequest(
            session: session,
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": [
                    "name": "ChatGPT",
                    "version": "1.0",
                ],
            ],
            activityContext: .remoteHTTP(surface: "web")
        )

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Active stack item for remote chat",
                    "createdAt": "2026-03-20T10:00:00.000Z",
                ],
            ],
            activityContext: .remoteHTTP(surface: "web")
        )
        _ = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "promptcue",
                    "topic": "remote-context",
                    "documentType": "decision",
                    "content": "## Decision\nUse Memory first in ChatGPT surfaces.",
                ],
            ],
            activityContext: .remoteHTTP(surface: "web")
        )

        let response = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "list_saved_items",
                "arguments": [:],
            ],
            activityContext: .remoteHTTP(surface: "web")
        )
        let payload = try toolPayload(from: response)

        XCTAssertEqual(payload["preferredFirst"] as? String, "memory")
        XCTAssertEqual(payload["presentationOrder"] as? [String], ["memory", "stack"])
        let nextStep = try XCTUnwrap(payload["recommendedNextStep"] as? String)
        XCTAssertTrue(nextStep.contains("Memory first"))
        XCTAssertTrue(nextStep.contains("Memory, Stack, or both"))
    }

    func testProposeDocumentSavesReturnsCreateProposalThroughJsonRPC() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "preferredTopic": "memory-save-flow",
                    "userIntent": "latest_decisions",
                    "content": """
                    We agreed to stop doing direct whole-thread saves by default. Instead, every meaningful memory write should go through proposal, review, confirm, and then write. We also agreed to keep user-facing wording as Backtick or 백틱 rather than generic memory, and to default uncertain long discussions into one reviewed discussion doc instead of forcing a split too early.
                    """,
                ],
            ]
        )

        XCTAssertEqual(response["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(response["id"] as? Int, 2)
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let contentItems = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(contentItems.count, 1)
        XCTAssertEqual(contentItems.first?["type"] as? String, "text")

        let payload = try toolPayload(from: response)
        XCTAssertEqual(payload["project"] as? String, "backtick")
        XCTAssertEqual(payload["count"] as? Int, 1)
        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        XCTAssertEqual(proposals.count, 1)
        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal["topic"] as? String, "memory-save-flow")
        XCTAssertEqual(proposal["documentType"] as? String, "decision")
        XCTAssertEqual(proposal["operation"] as? String, "create")
        XCTAssertFalse((proposal["rationale"] as? String ?? "").isEmpty)
        XCTAssertTrue((proposal["preview"] as? String ?? "").hasPrefix("## "))
        XCTAssertTrue(proposal["existingDocument"] is NSNull)
        let review = try XCTUnwrap(proposal["review"] as? [String: Any])
        XCTAssertEqual(review["displayTopic"] as? String, "memory save flow")
        let confirmPrompt = try XCTUnwrap(review["confirmPrompt"] as? String)
        XCTAssertTrue(confirmPrompt.contains("Backtick"))
        XCTAssertFalse(confirmPrompt.isEmpty)
        XCTAssertEqual(review["hideInternalFieldsByDefault"] as? Bool, true)
        let recommendation = try XCTUnwrap(proposal["recommendation"] as? [String: Any])
        XCTAssertEqual(recommendation["tool"] as? String, exposedToolName("save_document"))
        XCTAssertEqual(recommendation["needsRecall"] as? Bool, false)

        let listResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "list_documents",
                "arguments": ["project": "backtick"],
            ]
        )
        let listPayload = try toolPayload(from: listResponse)
        XCTAssertEqual(listPayload["count"] as? Int, 0)
    }

    func testProposeDocumentSavesReturnsUpdateProposalThroughJsonRPC() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let existingContent = """
        ## Decision
        - Save proposal and review should happen before final Backtick writes.
        - Backtick should ask before writing whenever the user has not yet confirmed the exact subject and document shape.

        ## Naming
        - Use Backtick or 백틱 in user-facing save prompts.
        - Avoid generic memory wording so users do not confuse Backtick with built-in assistant memory.

        ## Follow-on
        - The first implementation should keep review in chat before adding a native approval surface.
        - Long mixed discussions should prefer one reviewed discussion document before any broader split.
        """

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "memory-save-flow",
                    "documentType": "decision",
                    "content": existingContent,
                ],
            ]
        )

        let response = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "preferredTopic": "memory-save-flow",
                    "userIntent": "latest_decisions",
                    "content": """
                    We should keep the save flow review-first and extend the same document rather than creating a duplicate. The new part is that propose_document_saves should be the read-only first step when the topic or document type is unclear, and silent writes should stay disallowed.
                    """,
                ],
            ]
        )

        let payload = try toolPayload(from: response)
        XCTAssertEqual(payload["project"] as? String, "backtick")
        XCTAssertEqual(payload["count"] as? Int, 1)
        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal["topic"] as? String, "memory-save-flow")
        XCTAssertEqual(proposal["documentType"] as? String, "decision")
        XCTAssertEqual(proposal["operation"] as? String, "update")
        XCTAssertTrue((proposal["preview"] as? String ?? "").hasPrefix("## "))
        let existingDocument = try XCTUnwrap(proposal["existingDocument"] as? [String: Any])
        XCTAssertEqual(existingDocument["topic"] as? String, "memory-save-flow")
        XCTAssertEqual(existingDocument["documentType"] as? String, "decision")
        let review = try XCTUnwrap(proposal["review"] as? [String: Any])
        XCTAssertEqual(review["displayTopic"] as? String, "memory save flow")
        let confirmPrompt = try XCTUnwrap(review["confirmPrompt"] as? String)
        XCTAssertTrue(confirmPrompt.contains("Backtick"))
        XCTAssertTrue(confirmPrompt.localizedCaseInsensitiveContains("existing"))
        XCTAssertEqual(review["hideInternalFieldsByDefault"] as? Bool, true)
        let recommendation = try XCTUnwrap(proposal["recommendation"] as? [String: Any])
        XCTAssertEqual(recommendation["tool"] as? String, exposedToolName("update_document"))
        XCTAssertEqual(recommendation["needsRecall"] as? Bool, true)

        let listResponse = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "list_documents",
                "arguments": ["project": "backtick"],
            ]
        )
        let listPayload = try toolPayload(from: listResponse)
        XCTAssertEqual(listPayload["count"] as? Int, 1)
    }

    func testProposeDocumentSavesKeepsPreferredTopicForStructuredMarkdownUpdates() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let existingContent = """
        ## Decision
        - Full markdown rendering should support the main block types we rely on in coding conversations.
        - The first pass should render headings, paragraphs, lists, fenced code blocks, and tables inside the Backtick memory viewer.
        - Links should remain tappable so stored references are still actionable.

        ## Follow-on
        - Add screenshot-backed visual QA before widening the surface.
        - Keep the renderer local and deterministic instead of embedding a web view.
        - Prefer update-in-place for future rendering tweaks instead of creating duplicate docs for the same extension topic.
        """

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "markdown-rendering-extension",
                    "documentType": "decision",
                    "content": existingContent,
                ],
            ]
        )

        let response = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "preferredTopic": "markdown-rendering-extension",
                    "userIntent": "latest_decisions",
                    "content": """
                    ## Latest Changes
                    - Inline emphasis and code-span polish are the next rendering follow-up.
                    - Table spacing should improve without changing the topic or document type.
                    - This should extend the existing markdown rendering extension doc instead of creating a new one.

                    ## Constraints
                    - Keep the rendering native and deterministic.
                    - Avoid introducing a web view just to support markdown.
                    - Reuse the same project topic for follow-on updates.
                    """,
                ],
            ]
        )

        let payload = try toolPayload(from: response)
        XCTAssertEqual(payload["count"] as? Int, 1)
        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal["topic"] as? String, "markdown-rendering-extension")
        XCTAssertEqual(proposal["documentType"] as? String, "decision")
        XCTAssertEqual(proposal["operation"] as? String, "update")
        let existingDocument = try XCTUnwrap(proposal["existingDocument"] as? [String: Any])
        XCTAssertEqual(existingDocument["topic"] as? String, "markdown-rendering-extension")
        XCTAssertEqual(existingDocument["documentType"] as? String, "decision")
        let recommendation = try XCTUnwrap(proposal["recommendation"] as? [String: Any])
        XCTAssertEqual(recommendation["tool"] as? String, exposedToolName("update_document"))
        XCTAssertEqual(recommendation["needsRecall"] as? Bool, true)
    }

    func testProposeDocumentSavesDoesNotInferPlanFromRepoPlanFileReferences() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "preferredTopic": "memory-save-contract",
                    "content": """
                    ## Backtick Memory Save Contract

                    The durable rule is that Memory writes go through proposal, review, confirm, and then write.

                    ## Rules

                    - Ask first and do not save silently.
                    - One reviewed discussion can be better than a forced split.
                    - Shell and test transcripts do not belong in Memory.

                    ## Repo Grounding

                    This contract is described in docs/MCP-Polish-Plan.md and docs/MCP-Polish-Eval-Plan.md, but those file references should not turn this into an execution plan.
                    """,
                ],
            ]
        )

        let payload = try toolPayload(from: response)
        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal["topic"] as? String, "memory-save-contract")
        XCTAssertNotEqual(proposal["documentType"] as? String, "plan")
    }

    func testProposeDocumentSavesReusesExistingTopicWhenTypeInferenceWouldOtherwiseDrift() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let existingContent = """
        ## Contract
        - Backtick Memory writes should go through proposal, review, confirm, and then write.
        - Silent saves are disallowed.

        ## Rules
        - One reviewed discussion can be better than several forced splits.
        - Follow-on amendments should update the same durable subject when possible.

        ## Why
        - Future sessions should reuse one stable contract document instead of creating sibling docs for narrow deltas.
        """

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "memory-save-contract",
                    "documentType": "decision",
                    "content": existingContent,
                ],
            ]
        )

        let response = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "preferredTopic": "memory-save-contract",
                    "content": """
                    ## Amendment

                    This adds one durable clarification from docs/MCP-Polish-Plan.md and docs/MCP-Polish-Eval-Plan.md.

                    ## Clarification

                    - Proposal count is not the goal.
                    - Mixed engineering input should be lifted into product-level meaning before saving.
                    """,
                ],
            ]
        )

        let payload = try toolPayload(from: response)
        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal["topic"] as? String, "memory-save-contract")
        XCTAssertEqual(proposal["documentType"] as? String, "decision")
        XCTAssertEqual(proposal["operation"] as? String, "update")
        let existingDocument = try XCTUnwrap(proposal["existingDocument"] as? [String: Any])
        XCTAssertEqual(existingDocument["topic"] as? String, "memory-save-contract")
        XCTAssertEqual(existingDocument["documentType"] as? String, "decision")
    }

    func testProposeDocumentSavesReturnsNoProposalForExplicitNoSaveContent() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "content": """
                    Do not save this yet.
                    xcodebuild -project PromptCue.xcodeproj
                    swift test
                    git status
                    """,
                ],
            ]
        )

        let payload = try toolPayload(from: response)
        XCTAssertEqual(payload["count"] as? Int, 0)
        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        XCTAssertTrue(proposals.isEmpty)
        XCTAssertEqual(payload["recommendedNextStep"] as? String, "do_not_write")

        let listResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "list_documents",
                "arguments": ["project": "backtick"],
            ]
        )
        let listPayload = try toolPayload(from: listResponse)
        XCTAssertEqual(listPayload["count"] as? Int, 0)
    }

    func testProposeDocumentSavesReturnsNoProposalForRoutineExecutionStatusWithoutExplicitNoSaveMarker() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "content": """
                    xcodegen generate, swift test, xcodebuild build all passed, and I reopened the app bundle to check the latest helper.
                    This is just routine execution status from today's run and does not include any lasting decision, constraint, scope lock, or release milestone.
                    """,
                ],
            ]
        )

        let payload = try toolPayload(from: response)
        XCTAssertEqual(payload["count"] as? Int, 0)
        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        XCTAssertTrue(proposals.isEmpty)
        XCTAssertEqual(payload["recommendedNextStep"] as? String, "do_not_write")
    }

    func testProposeDocumentSavesFlagsWarningsAndFallsBackToDiscussionForMixedNoisyContent() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let repeatedNoise = Array(repeating: "xcodebuild -project PromptCue.xcodeproj\nswift test\nSources/PromptCueCore/ProjectDocument.swift", count: 30)
            .joined(separator: "\n")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "preferredTopic": "memory",
                    "content": """
                    We reached a decision about save review, but the same discussion also covered architecture constraints and next steps for implementation.

                    ## Working Notes
                    The decision is that users should review before a write. The architecture still needs a read-only proposal tool. The next steps include tightening prompts, warnings, and save review behavior.

                    ## Mixed Content
                    This conversation mixes decision, next steps, timeline, and architecture background in one place, so classification is unclear and should default to one reviewed discussion doc first.

                    \(repeatedNoise)
                    """,
                ],
            ]
        )

        let payload = try toolPayload(from: response)
        // With multi-proposal support, segments split by ## headers generate separate proposals.
        // The noisy segment may be filtered, leaving up to 2-3 proposals from the meaningful sections.
        let count = try XCTUnwrap(payload["count"] as? Int)
        XCTAssertGreaterThanOrEqual(count, 1)
        XCTAssertLessThanOrEqual(count, 3)
        let globalWarnings = try XCTUnwrap(payload["globalWarnings"] as? [String])
        XCTAssertTrue(globalWarnings.contains("topic_too_broad"))

        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        XCTAssertFalse(proposals.isEmpty)
        // At least one proposal should exist with a non-empty topic
        let firstProposal = try XCTUnwrap(proposals.first)
        let firstTopic = try XCTUnwrap(firstProposal["topic"] as? String)
        XCTAssertFalse(firstTopic.isEmpty)
    }

    func testProposeDocumentSavesInfersTopicFromFirstMarkdownHeadingWhenHintsAreMissing() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "content": """
                    ## Pricing Direction

                    We should keep pricing flexible for the first release and avoid locking a final tier structure too early. This is still mostly exploratory context, but the heading should be a good topic candidate for future memory review.

                    ## Current Thinking

                    The main tension is simplicity versus room for expansion later.
                    """,
                ],
            ]
        )

        let payload = try toolPayload(from: response)
        let proposals = try XCTUnwrap(payload["proposals"] as? [[String: Any]])
        let proposal = try XCTUnwrap(proposals.first)
        XCTAssertEqual(proposal["topic"] as? String, "pricing-direction")
    }

    func testProposeDocumentSavesRejectsInvalidMaxProposals() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "propose_document_saves",
                "arguments": [
                    "project": "backtick",
                    "content": "A reviewed summary that is long enough to be considered content for proposal generation.",
                    "maxProposals": 4,
                ],
            ]
        )

        let payload = try toolErrorPayload(from: response)
        XCTAssertEqual(payload["error"] as? String, "maxProposals must be between 1 and 3")
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

    func testDeleteDocumentRemovesActiveDocumentThroughJsonRPC() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let content = """
        ## Decision
        - Delete document should soft-delete the active project document row.
        - The delete tool should target the exact project, topic, and document type.

        ## Cleanup
        - List documents should stop returning the deleted document.
        - Follow-up test runs should be able to recreate the same key without conflicts.
        """

        let saveResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "delete-flow",
                    "documentType": "decision",
                    "content": content,
                ],
            ]
        )
        let savedDocument = try documentPayload(from: saveResponse)
        XCTAssertEqual(savedDocument["topic"] as? String, "delete-flow")

        let deleteResponse = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "delete_document",
                "arguments": [
                    "project": "backtick",
                    "topic": "delete-flow",
                    "documentType": "decision",
                ],
            ]
        )
        let deletePayload = try toolPayload(from: deleteResponse)
        XCTAssertEqual(deletePayload["deleted"] as? Bool, true)
        let deletedDocument = try XCTUnwrap(deletePayload["document"] as? [String: Any])
        XCTAssertEqual(deletedDocument["topic"] as? String, "delete-flow")
        XCTAssertEqual(deletedDocument["documentType"] as? String, "decision")

        let listResponse = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "list_documents",
                "arguments": [
                    "project": "backtick",
                ],
            ]
        )
        let listPayload = try toolPayload(from: listResponse)
        XCTAssertEqual(listPayload["count"] as? Int, 0)
    }

    func testCreateNotePostsStackDidChangeNotification() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let expectation = expectation(description: "stack change notification")
        let center = DistributedNotificationCenter.default()
        let expectedToolName = exposedToolName("create_note")
        let observer = center.addObserver(
            forName: .backtickStackDidChange,
            object: nil,
            queue: .main
        ) { notification in
            let tool = notification.userInfo?["tool"] as? String
            if tool == expectedToolName {
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

    func testCreateNoteAcceptsMixedScriptTags() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let response = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "create_note",
                "arguments": [
                    "text": "Should succeed",
                    "tags": ["bug", "ㅠㅕbug"],
                ],
            ]
        )
        let note = try notePayload(from: response)

        XCTAssertEqual(note["text"] as? String, "Should succeed")
        XCTAssertEqual(note["tags"] as? [String], ["bug", "ㅠㅕbug"])
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

    func testPromptsListReturnsMemoryAndStackTemplates() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let promptsResponse = try await sendRequest(session: session, id: 2, method: "prompts/list")
        let result = try XCTUnwrap(promptsResponse["result"] as? [String: Any])
        let prompts = try XCTUnwrap(result["prompts"] as? [[String: Any]])
        XCTAssertEqual(prompts.count, 6)
        XCTAssertEqual(
            prompts.compactMap { $0["name"] as? String },
            ["workflow", "memory_workflow", "save_review", "triage", "diagnose", "execute"]
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

        XCTAssertTrue(text.contains(exposedToolName("list_saved_items")))
        XCTAssertTrue(text.contains("ChatGPT or Claude app"))
        XCTAssertTrue(text.contains("Claude Code or Codex"))
        XCTAssertTrue(text.contains("Stack first, then Memory"))
        XCTAssertTrue(text.contains("Memory, Stack, or both"))
        XCTAssertTrue(text.contains(exposedToolName("classify_notes")))
        XCTAssertTrue(text.contains(exposedToolName("mark_notes_executed")))
        XCTAssertTrue(text.contains("per task group after that group's verification passes"))
        XCTAssertTrue(text.contains("Do not call `\(exposedToolName("mark_notes_executed"))` during planning"))
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

        XCTAssertTrue(text.contains(exposedToolName("mark_notes_executed")))
        XCTAssertTrue(text.contains("noteIDs that belong to this task group"))
        XCTAssertTrue(text.contains("Do not continue to the next task group"))
    }

    func testPromptsGetMemoryWorkflowRendersSaveReviewPlaybook() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let getResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "prompts/get",
            params: ["name": "memory_workflow"]
        )
        let result = try XCTUnwrap(getResponse["result"] as? [String: Any])
        let messages = try XCTUnwrap(result["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [String: Any])
        let text = try XCTUnwrap(content["text"] as? String)

        XCTAssertTrue(text.contains(exposedToolName("list_saved_items")))
        XCTAssertTrue(text.contains("ChatGPT or Claude app"))
        XCTAssertTrue(text.contains("Claude Code or Codex"))
        XCTAssertTrue(text.contains("Memory, Stack, or both"))
        XCTAssertTrue(text.contains(exposedToolName("list_documents")))
        XCTAssertTrue(text.contains(exposedToolName("recall_document")))
        XCTAssertTrue(text.contains(exposedToolName("propose_document_saves")))
        XCTAssertTrue(text.contains("Never save silently"))
        XCTAssertTrue(text.contains("Save this to Backtick?"))
    }

    func testPromptsGetSaveReviewRendersWithoutToolJargonInstructions() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let getResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "prompts/get",
            params: [
                "name": "save_review",
                "arguments": [
                    "project": "aido",
                    "contentSummary": "We agreed to keep user-facing wording as Backtick and to ask before saving any meaningful decision.",
                    "topicHint": "memory-save-flow",
                ],
            ]
        )
        let result = try XCTUnwrap(getResponse["result"] as? [String: Any])
        let messages = try XCTUnwrap(result["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [String: Any])
        let text = try XCTUnwrap(content["text"] as? String)

        XCTAssertTrue(text.contains("aido"))
        XCTAssertTrue(text.contains("memory-save-flow"))
        XCTAssertTrue(text.contains(exposedToolName("propose_document_saves")))
        XCTAssertTrue(text.contains("Save this to Backtick?"))
        XCTAssertTrue(text.contains("Do not mention internal tool names or schema fields"))
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

    func testInitializeAndToolsListDoNotRecordConnectionActivity() async throws {
        let session = await makeSession()
        _ = try await sendRequest(
            session: session,
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": [
                    "name": "claude-code",
                    "version": "1.0.0",
                ],
            ]
        )
        _ = try await sendRequest(session: session, id: 2, method: "tools/list")

        XCTAssertFalse(FileManager.default.fileExists(atPath: connectionActivityFileURL.path))
    }

    func testSuccessfulToolCallRecordsStdioConnectionActivity() async throws {
        let session = await makeSession()
        _ = try await sendRequest(
            session: session,
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": [
                    "name": "claude-code",
                    "version": "1.0.0",
                ],
            ]
        )

        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "get_started",
                "arguments": [:],
            ]
        )

        let state = try loadConnectionActivityState()
        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(state.activities.count, 1)
        let activity = try XCTUnwrap(state.activities.first)
        XCTAssertEqual(activity.transport, .stdio)
        XCTAssertNil(activity.surface)
        XCTAssertEqual(activity.clientName, "claude-code")
        XCTAssertEqual(activity.clientVersion, "1.0.0")
        XCTAssertEqual(activity.toolName, exposedToolName("get_started"))
        XCTAssertNil(activity.sessionID)
        XCTAssertEqual(activity.configuredClientID, "claudeCode")
        XCTAssertEqual(activity.launchCommand, "/tmp/BacktickMCP")
        XCTAssertEqual(activity.launchArguments ?? [], ["--stdio"])
    }

    func testFailedToolCallDoesNotRecordConnectionActivity() async throws {
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")
        _ = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "does_not_exist",
                "arguments": [:],
            ]
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: connectionActivityFileURL.path))
    }

    func testHTTPHandlerServesInitializeOverPost() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(apiKey: "secret-token")
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
                "x-api-key": "secret-token",
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

    func testHTTPHandlerRejectsAPIKeyModeWhenKeyIsMissing() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(apiKey: nil)
        )
        let request = BacktickMCPHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: [
                "x-api-key": "secret-token",
                "content-length": "2",
                "content-type": "application/json",
            ],
            body: Data("{}".utf8)
        )

        let response = await handler.response(for: request)
        XCTAssertEqual(response.statusCode, 401)
    }

    func testHTTPHandlerRejectsAPIKeyModeWhenKeyIsEmpty() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(apiKey: "   ")
        )
        let request = BacktickMCPHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: [
                "authorization": "Bearer secret-token",
                "content-length": "2",
                "content-type": "application/json",
            ],
            body: Data("{}".utf8)
        )

        let response = await handler.response(for: request)
        XCTAssertEqual(response.statusCode, 401)
    }

    func testHTTPHandlerReturnsOKForEmptyPostProbeWithoutAuthorization() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: tempDirectoryURL.appendingPathComponent("oauth-empty-probe.json")
            )
        )
        let request = BacktickMCPHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: [
                "content-length": "0",
                "content-type": "application/json",
            ],
            body: Data()
        )

        let response = await handler.response(for: request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertTrue(response.body.isEmpty)
    }

    func testHTTPHandlerAddsMcpSessionIDHeaderAfterInitialize() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(apiKey: "secret-token")
        )
        let initializeBody = try requestBody(
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
        let initializeRequest = BacktickMCPHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: [
                "x-api-key": "secret-token",
                "content-length": "\(initializeBody.count)",
                "content-type": "application/json",
            ],
            body: initializeBody
        )

        let initializeResponse = await handler.response(for: initializeRequest)
        XCTAssertEqual(initializeResponse.statusCode, 200)
        XCTAssertNil(initializeResponse.headers["Mcp-Session-Id"])

        let notificationBody = Data(
            #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#.utf8
        )
        let notificationRequest = BacktickMCPHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: [
                "x-api-key": "secret-token",
                "content-length": "\(notificationBody.count)",
                "content-type": "application/json",
            ],
            body: notificationBody
        )

        let notificationResponse = await handler.response(for: notificationRequest)
        XCTAssertEqual(notificationResponse.statusCode, 202)
        XCTAssertNil(notificationResponse.headers["Mcp-Session-Id"])
    }

    func testOAuthProtectedEndpointsSupportPathScopedDiscoveryVariants() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: tempDirectoryURL.appendingPathComponent("oauth-path-scoped.json")
            )
        )

        let paths = [
            "/mcp/.well-known/oauth-protected-resource",
            "/.well-known/oauth-protected-resource/mcp",
            "/.well-known/oauth-authorization-server/mcp",
            "/.well-known/openid-configuration/mcp",
        ]

        for path in paths {
            let response = await handler.response(
                for: BacktickMCPHTTPRequest(
                    method: "GET",
                    path: path,
                    headers: [:],
                    body: Data()
                )
            )
            XCTAssertEqual(response.statusCode, 200, "Expected 200 for \(path)")
        }
    }

    func testOAuthUnauthorizedResponseAdvertisesPathScopedResourceMetadataURL() async throws {
        let session = await makeSession()
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: tempDirectoryURL.appendingPathComponent("oauth-unauthorized.json")
            )
        )
        let body = try requestBody(id: 1, method: "initialize")
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
        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(
            response.headers["WWW-Authenticate"],
            #"Bearer resource_metadata="https://backtick.test/.well-known/oauth-protected-resource/mcp""#
        )
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

    func testOAuthProtectedToolCallRecordsRemoteConnectionActivityAndLogsOnlySuccessfulToolCalls() async throws {
        let session = await makeSession()
        let oauthStateFileURL = tempDirectoryURL.appendingPathComponent("oauth-activity-state.json", isDirectory: false)
        var logMessages: [String] = []
        let handler = BacktickMCPHTTPHandler(
            session: session,
            configuration: BacktickMCPHTTPConfiguration(
                authMode: .oauth,
                apiKey: nil,
                publicBaseURL: URL(string: "https://backtick.test")!,
                oauthStateFileURL: oauthStateFileURL
            ),
            logger: { logMessages.append($0) }
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
            "client_id=\(clientID)&redirect_uri=https%3A%2F%2Fchat.openai.com%2Faip%2Fcallback&response_type=code&scope=backtick.mcp&state=activity123&code_challenge=C4o_XQvR65ONsuHQv0djlsMDYgPVB63jJiXd_a4GETw&code_challenge_method=S256&decision=approve".utf8
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

        let initializeBody = try requestBody(
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": "2025-03-26",
                "capabilities": [:],
                "clientInfo": [
                    "name": "ChatGPT",
                    "version": "web",
                ],
            ]
        )
        let initializeResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(accessToken)",
                    "content-length": "\(initializeBody.count)",
                    "content-type": "application/json",
                    "user-agent": "Mozilla/5.0",
                ],
                body: initializeBody
            )
        )
        XCTAssertEqual(initializeResponse.statusCode, 200)
        XCTAssertTrue(logMessages.isEmpty)

        let toolCallBody = try requestBody(
            id: 2,
            method: "tools/call",
            params: [
                "name": "get_started",
                "arguments": [:],
            ]
        )
        let toolCallResponse = await handler.response(
            for: BacktickMCPHTTPRequest(
                method: "POST",
                path: "/mcp",
                headers: [
                    "authorization": "Bearer \(accessToken)",
                    "content-length": "\(toolCallBody.count)",
                    "content-type": "application/json",
                    "user-agent": "Mozilla/5.0",
                ],
                body: toolCallBody
            )
        )
        XCTAssertEqual(toolCallResponse.statusCode, 200)

        let state = try loadConnectionActivityState()
        XCTAssertEqual(state.activities.count, 1)
        let activity = try XCTUnwrap(state.activities.first)
        XCTAssertEqual(activity.transport, .remoteHTTP)
        XCTAssertEqual(activity.surface, "web")
        XCTAssertEqual(activity.clientName, "ChatGPT")
        XCTAssertEqual(activity.clientVersion, "web")
        XCTAssertEqual(activity.toolName, exposedToolName("get_started"))

        XCTAssertEqual(logMessages.count, 1)
        XCTAssertTrue(logMessages[0].contains("served protected remote request"))
        XCTAssertTrue(logMessages[0].contains("rpcMethod=tools/call"))
        XCTAssertTrue(logMessages[0].contains("targetName=get_started"))
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

    private func makeSession(
        processEnvironment: [String: String] = ["BACKTICK_CONNECTOR_CLIENT": "claudeCode"],
        commandLine: [String] = ["/tmp/BacktickMCP", "--stdio"]
    ) async -> BacktickMCPServerSession {
        let databaseURL = self.databaseURL
        let attachmentsURL = self.attachmentsURL
        let connectionActivityFileURL = self.connectionActivityFileURL

        return await MainActor.run {
            BacktickMCPServerSession(
                databaseURL: databaseURL,
                attachmentBaseDirectoryURL: attachmentsURL,
                connectionActivityFileURL: connectionActivityFileURL,
                processEnvironment: processEnvironment,
                commandLine: commandLine
            )
        }
    }

    private func sendRequest(
        session: BacktickMCPServerSession,
        id: Any,
        method: String,
        params: [String: Any] = [:],
        activityContext: BacktickMCPConnectionContext = .stdio
    ) async throws -> [String: Any] {
        let data = try requestBody(id: id, method: method, params: params)
        let responseData = try await MainActor.run {
            try XCTUnwrap(session.handleRequestData(data, activityContext: activityContext))
        }
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

    private func loadConnectionActivityState() throws -> BacktickMCPConnectionActivityState {
        let data = try Data(contentsOf: connectionActivityFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BacktickMCPConnectionActivityState.self, from: data)
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
