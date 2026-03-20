import Foundation
import XCTest
@testable import BacktickMCPServer

final class BacktickMCPRepoDogfoodTests: XCTestCase {
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

    func testWarmDocumentFlowWithRepoCorpusForCodexSingleClientEval() async throws {
        let repoRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let executionPRD = try String(contentsOf: repoRootURL.appendingPathComponent("docs/Execution-PRD.md"))
        let implementationPlan = try String(contentsOf: repoRootURL.appendingPathComponent("docs/Implementation-Plan.md"))
        let mcpResearch = try String(contentsOf: repoRootURL.appendingPathComponent("docs/MCP-Platform-Expansion-Research.md"))
        let warmEvalPlan = try String(contentsOf: repoRootURL.appendingPathComponent("docs/Warm-MCP-Eval-Plan.md"))

        XCTAssertTrue(executionPRD.contains("Backtick"))
        XCTAssertTrue(implementationPlan.contains("Warm"))
        XCTAssertTrue(mcpResearch.contains("ProjectDocument"))
        XCTAssertTrue(warmEvalPlan.contains("list_documents"))

        let project = "Backtick-eval-codex"
        let session = await makeSession()
        _ = try await sendRequest(session: session, id: 1, method: "initialize")

        let briefContent = """
        ## Product
        - Backtick is a native macOS utility for AI coding scratchpad and thought staging, as defined in the execution PRD.
        - The product centers Capture as a frictionless dump and Stack as an execution queue instead of a note app.

        ## Current Focus
        - The implementation plan and MCP research both frame Warm Memory as durable project context stored separately from short-lived Stack cards.
        - The current execution lane prioritizes MCP storage and retrieval contracts before any visible Memory panel.

        ## Constraints
        - The product should stay minimal, Spotlight-like, and low-chrome while preserving strong MCP interoperability.
        - Warm Memory should support human-reviewed promotion instead of black-box automatic memory extraction.
        """

        let saveBriefResponse = try await sendRequest(
            session: session,
            id: 2,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": project,
                    "topic": "brief",
                    "documentType": "reference",
                    "content": briefContent,
                ],
            ]
        )
        let briefDocument = try documentPayload(from: saveBriefResponse)
        XCTAssertEqual(briefDocument["project"] as? String, project)
        XCTAssertEqual(briefDocument["topic"] as? String, "brief")
        XCTAssertEqual(briefDocument["documentType"] as? String, "reference")

        let architectureContent = """
        ## Architecture
        - MCP expansion research describes a split where stdio clients keep using the bundled BacktickMCP helper, while HTTP clients use the embedded server path.
        - PromptCueCore owns pure models and transformation logic, while the app target owns AppKit, persistence, and runtime integrations.

        ## Warm Memory Direction
        - Project documents use the key `(project, topic, documentType)` and are stored with immutable supersession.
        - Two-tier retrieval means `list_documents` is a lightweight discovery step and `recall_document` returns the full durable markdown.

        ## Constraints
        - Phase 1 prioritizes storage plus MCP tools, with UI intentionally deferred until retrieval behavior is stable.
        - Mem0 takeaways reinforce document-first storage, reviewed promotion, and ranking later rather than day-one automation.
        """

        _ = try await sendRequest(
            session: session,
            id: 3,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": project,
                    "topic": "architecture",
                    "documentType": "reference",
                    "content": architectureContent,
                ],
            ]
        )

        let decisionContent = """
        ## Latest Decisions
        - Warm project documents use the key `(project, topic, documentType)`.
        - The first Warm MCP tool set is `list_documents`, `recall_document`, `save_document`, and `update_document`.

        ## Topic and Type Discipline
        - Topics should stay flat and reusable. Fit into existing topics first before creating a new topic.
        - PRDs map to `plan`, latest decisions map to `decision`, durable summaries map to `reference`, and ongoing recap maps to `discussion`.

        ## Content Guardrails
        - Warm docs must not store coding-session logs, file-by-file change logs, shell or test-command transcripts, or git-like execution history.
        - Durable docs should preserve project context, settled decisions, plans, constraints, and concise summaries future AI sessions should remember.
        """

        let saveDecisionResponse = try await sendRequest(
            session: session,
            id: 4,
            method: "tools/call",
            params: [
                "name": "save_document",
                "arguments": [
                    "project": project,
                    "topic": "warm-memory",
                    "documentType": "decision",
                    "content": decisionContent,
                ],
            ]
        )
        let firstDecision = try documentPayload(from: saveDecisionResponse)
        let firstDecisionID = try XCTUnwrap(firstDecision["id"] as? String)

        let listResponse = try await sendRequest(
            session: session,
            id: 5,
            method: "tools/call",
            params: [
                "name": "list_documents",
                "arguments": [
                    "project": project,
                ],
            ]
        )
        let listedDocuments = try XCTUnwrap(toolPayload(from: listResponse)["documents"] as? [[String: Any]])
        XCTAssertEqual(listedDocuments.count, 3)

        let updateDecisionResponse = try await sendRequest(
            session: session,
            id: 6,
            method: "tools/call",
            params: [
                "name": "update_document",
                "arguments": [
                    "project": project,
                    "topic": "warm-memory",
                    "documentType": "decision",
                    "action": "replace_section",
                    "section": "Latest Decisions",
                    "content": """
                    - Phase 1 stays limited to storage plus `list_documents`, `recall_document`, `save_document`, and `update_document`.
                    - Narrow changes should prefer `update_document`, and recall should happen before updating an existing durable doc.
                    """,
                ],
            ]
        )
        let updatedDecision = try documentPayload(from: updateDecisionResponse)
        let updatedDecisionID = try XCTUnwrap(updatedDecision["id"] as? String)
        let updatedDecisionContent = try XCTUnwrap(updatedDecision["content"] as? String)
        XCTAssertNotEqual(updatedDecisionID, firstDecisionID)
        XCTAssertTrue(updatedDecisionContent.contains("Phase 1 stays limited"))
        XCTAssertFalse(updatedDecisionContent.contains("Warm project documents use the key"))

        let updateArchitectureResponse = try await sendRequest(
            session: session,
            id: 7,
            method: "tools/call",
            params: [
                "name": "update_document",
                "arguments": [
                    "project": project,
                    "topic": "architecture",
                    "documentType": "reference",
                    "action": "append",
                    "content": """
                    ## Retrieval Policy
                    - Repo-derived durable docs should be reviewed by a human before broad reliance.
                    - Until a visible Memory UI exists, CLI and MCP-level recall remain the fastest evaluation surface.
                    """,
                ],
            ]
        )
        let updatedArchitecture = try documentPayload(from: updateArchitectureResponse)
        let updatedArchitectureContent = try XCTUnwrap(updatedArchitecture["content"] as? String)
        XCTAssertTrue(updatedArchitectureContent.contains("## Retrieval Policy"))

        let recallDecisionResponse = try await sendRequest(
            session: session,
            id: 8,
            method: "tools/call",
            params: [
                    "name": "recall_document",
                    "arguments": [
                    "project": project,
                        "topic": "warm-memory",
                        "documentType": "decision",
                    ],
            ]
        )
        let recalledDecision = try documentPayload(from: recallDecisionResponse)
        XCTAssertEqual(recalledDecision["content"] as? String, updatedDecisionContent)

        let finalListResponse = try await sendRequest(
            session: session,
            id: 9,
            method: "tools/call",
            params: [
                    "name": "list_documents",
                    "arguments": [
                    "project": project,
                ],
            ]
        )
        let finalDocuments = try XCTUnwrap(toolPayload(from: finalListResponse)["documents"] as? [[String: Any]])
        XCTAssertEqual(finalDocuments.count, 3)
        XCTAssertEqual(
            Set(finalDocuments.compactMap { $0["topic"] as? String }),
            Set(["brief", "architecture", "warm-memory"])
        )
        XCTAssertEqual(
            Set(finalDocuments.compactMap { $0["documentType"] as? String }),
            Set(["reference", "decision"])
        )
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
        let object = try JSONSerialization.jsonObject(with: responseData)
        return try XCTUnwrap(object as? [String: Any])
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

    private func documentPayload(from response: [String: Any]) throws -> [String: Any] {
        let payload = try toolPayload(from: response)
        return try XCTUnwrap(payload["document"] as? [String: Any])
    }
}
