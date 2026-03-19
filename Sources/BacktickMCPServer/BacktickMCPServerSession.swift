import Foundation
import PromptCueCore

@MainActor
final class BacktickMCPServerSession {
    private let readService: StackReadService
    private let writeService: StackWriteService
    private let executionService: StackExecutionService
    private let groupService: StackGroupService
    private let documentStore: ProjectDocumentStore

    private static let supportedProtocolVersions = [
        "2025-03-26",
        "2024-11-05",
    ]
    private static let jsonrpcVersion = "2.0"
    private static let serverName = "backtick-stack-mcp"
    private static let serverTitle = "Backtick Stack MCP"
    private static let serverVersion = "0.1.0"
    private static let iso8601Formatter = makeDateFormatter()

    init(
        fileManager: FileManager = .default,
        databaseURL: URL? = nil,
        attachmentBaseDirectoryURL: URL? = nil
    ) {
        readService = StackReadService(
            fileManager: fileManager,
            databaseURL: databaseURL
        )
        writeService = StackWriteService(
            fileManager: fileManager,
            databaseURL: databaseURL,
            attachmentBaseDirectoryURL: attachmentBaseDirectoryURL
        )
        executionService = StackExecutionService(
            fileManager: fileManager,
            databaseURL: databaseURL
        )
        groupService = StackGroupService(
            readService: readService,
            writeService: writeService,
            executionService: executionService
        )
        documentStore = ProjectDocumentStore(
            fileManager: fileManager,
            databaseURL: databaseURL
        )
    }

    func handleLine(_ line: String) -> String? {
        guard let data = line.data(using: .utf8) else {
            return serializedResponse(
                errorResponse(
                    id: nil,
                    code: .parseError,
                    message: "Request was not valid UTF-8"
                )
            )
        }

        guard let responseData = handleRequestData(data) else {
            return nil
        }

        return String(data: responseData, encoding: .utf8)
    }

    func handleRequestData(_ data: Data) -> Data? {
        let payload: Any
        do {
            payload = try JSONSerialization.jsonObject(with: data)
        } catch {
            return serializedResponseData(
                errorResponse(
                    id: nil,
                    code: .parseError,
                    message: "Request body was not valid JSON"
                )
            )
        }

        switch payload {
        case let batch as [Any]:
            let responses = batch.compactMap { handlePayloadObject($0) }
            guard !responses.isEmpty else {
                return nil
            }
            return serializedResponseData(responses)

        case let object as [String: Any]:
            guard let response = handleObject(object) else {
                return nil
            }
            return serializedResponseData(response)

        default:
            return serializedResponseData(
                errorResponse(
                    id: nil,
                    code: .invalidRequest,
                    message: "Top-level request must be an object or batch array"
                )
            )
        }
    }

    private func handlePayloadObject(_ payload: Any) -> [String: Any]? {
        guard let object = payload as? [String: Any] else {
            return errorResponse(
                id: nil,
                code: .invalidRequest,
                message: "Batch entry must be a JSON object"
            )
        }

        return handleObject(object)
    }

    private func handleObject(_ request: [String: Any]) -> [String: Any]? {
        let id = request["id"]

        guard request["jsonrpc"] as? String == Self.jsonrpcVersion else {
            return errorResponse(
                id: id,
                code: .invalidRequest,
                message: "Only JSON-RPC 2.0 is supported"
            )
        }

        guard let method = request["method"] as? String, !method.isEmpty else {
            return errorResponse(
                id: id,
                code: .invalidRequest,
                message: "Request method was missing"
            )
        }

        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return successResponse(id: id, result: initializeResult(params: params))

        case "notifications/initialized":
            return nil

        case "ping":
            return successResponse(id: id, result: [:])

        case "tools/list":
            return successResponse(id: id, result: ["tools": toolDefinitions()])

        case "resources/list":
            return successResponse(id: id, result: ["resources": []])

        case "prompts/list":
            return successResponse(id: id, result: promptsList())

        case "prompts/get":
            return promptsGet(id: id, params: params)

        case "tools/call":
            guard let toolName = params["name"] as? String, !toolName.isEmpty else {
                return errorResponse(
                    id: id,
                    code: .invalidParams,
                    message: "tools/call requires a tool name"
                )
            }

            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let toolResult = callTool(name: toolName, arguments: arguments)
            return successResponse(id: id, result: toolResult)

        default:
            return errorResponse(
                id: id,
                code: .methodNotFound,
                message: "Unsupported method \(method)"
            )
        }
    }

    private func initializeResult(params: [String: Any]) -> [String: Any] {
        let requestedVersion = params["protocolVersion"] as? String
        let protocolVersion = requestedVersion
            .flatMap { version in
                Self.supportedProtocolVersions.first(where: { $0 == version })
            } ?? Self.supportedProtocolVersions[0]

        return [
            "protocolVersion": protocolVersion,
            "capabilities": [
                "tools": [
                    "listChanged": false,
                ],
                "resources": [
                    "listChanged": false,
                ],
                "prompts": [
                    "listChanged": false,
                ],
            ],
            "serverInfo": [
                "name": Self.serverName,
                "title": Self.serverTitle,
                "version": Self.serverVersion,
            ],
        ]
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "list_notes",
                "description": "List Stack notes grouped by category: pinned (permanent prompts), active (today's work), and copied (used prompts). Each group is returned separately.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "scope": [
                            "type": "string",
                            "enum": ["all", "active", "copied"],
                            "description": "Optional filter for returned notes.",
                        ],
                    ],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "get_note",
                "description": "Fetch one Stack note and its copy-event history.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "format": "uuid",
                        ],
                    ],
                    "required": ["id"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "create_note",
                "description": "Create a Stack note directly in Backtick storage.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "text": ["type": "string"],
                        "tags": tagSchema(),
                        "suggestedTarget": suggestedTargetSchema(),
                        "screenshotPath": ["type": ["string", "null"]],
                        "isPinned": ["type": ["boolean", "null"], "description": "Pin or unpin this note. Pinned notes never expire and sort to top."],
                        "createdAt": [
                            "type": "string",
                            "format": "date-time",
                        ],
                    ],
                    "required": ["text"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "update_note",
                "description": "Update Stack note text or metadata without copying it.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "format": "uuid",
                        ],
                        "text": ["type": ["string", "null"]],
                        "tags": tagSchema(),
                        "suggestedTarget": suggestedTargetSchema(),
                        "screenshotPath": ["type": ["string", "null"]],
                        "isPinned": ["type": ["boolean", "null"], "description": "Pin or unpin this note. Pinned notes never expire and sort to top."],
                        "lastCopiedAt": [
                            "type": ["string", "null"],
                            "format": "date-time",
                            "description": "Set null to move note back to Active, or ISO-8601 date to mark as copied.",
                        ],
                    ],
                    "required": ["id"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "delete_note",
                "description": "Delete a Stack note directly from Backtick storage.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "format": "uuid",
                        ],
                    ],
                    "required": ["id"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "mark_notes_executed",
                "description": "Mark Stack notes executed by recording copied state and CopyEvent rows.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "noteIDs": [
                            "type": "array",
                            "items": [
                                "type": "string",
                                "format": "uuid",
                            ],
                            "minItems": 1,
                        ],
                        "sessionID": [
                            "type": ["string", "null"],
                        ],
                        "copiedAt": [
                            "type": "string",
                            "format": "date-time",
                        ],
                    ],
                    "required": ["noteIDs"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "classify_notes",
                "description": "Group Stack notes by metadata such as repository, session, or app.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "scope": [
                            "type": "string",
                            "enum": ["all", "active", "copied"],
                            "description": "Filter scope. Default: active.",
                        ],
                        "groupBy": [
                            "type": "string",
                            "enum": ["repository", "session", "app"],
                            "description": "Grouping dimension. Default: repository.",
                        ],
                    ],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "group_notes",
                "description": "Merge multiple Stack notes into one grouped note. Source notes remain active unless archived explicitly.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "noteIDs": [
                            "type": "array",
                            "items": [
                                "type": "string",
                                "format": "uuid",
                            ],
                            "minItems": 1,
                            "description": "IDs of source notes to merge, in desired order.",
                        ],
                        "title": [
                            "type": "string",
                            "description": "Title for the grouped note.",
                        ],
                        "separator": [
                            "type": "string",
                            "description": "Text separator between source notes. Default: ---",
                        ],
                        "archiveSources": [
                            "type": "boolean",
                            "description": "When true, marks source notes as executed after grouping. Default: false.",
                        ],
                        "sessionID": [
                            "type": ["string", "null"],
                            "description": "Optional session identifier for archived copy events.",
                        ],
                    ],
                    "required": ["noteIDs", "title"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "get_started",
                "description": "Introduction to Backtick. Call this when the user first connects or asks what Backtick can do. Returns a guide explaining all available tools and example usage.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "list_documents",
                "description": "List reviewed Warm documents for lightweight discovery. Use this before recall_document or save_document to find matching project/topic/documentType entries without loading full content.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "project": [
                            "type": ["string", "null"],
                            "description": "Optional project filter. Omit to list all current documents.",
                        ],
                    ],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "recall_document",
                "description": "Load one reviewed Warm document by project, topic, and documentType. Call proactively when a project or durable decision is relevant so the user does not have to restate it.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "project": ["type": "string"],
                        "topic": ["type": "string"],
                        "documentType": projectDocumentTypeSchema(),
                    ],
                    "required": ["project", "topic", "documentType"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "save_document",
                "description": "Save a reviewed Warm document by project, topic, and documentType. Recall before save, fit into an existing topic when possible, and store structured markdown with ## headers rather than a raw transcript.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "project": ["type": "string"],
                        "topic": ["type": "string"],
                        "documentType": projectDocumentTypeSchema(),
                        "content": ["type": "string"],
                    ],
                    "required": ["project", "topic", "documentType", "content"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "update_document",
                "description": "Partially update an existing Warm document by appending a new ## section, replacing one ## section, or deleting one ## section. Prefer this over save_document for small changes. Always list or recall first so you update the right project/topic/documentType document.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "project": ["type": "string"],
                        "topic": ["type": "string"],
                        "documentType": projectDocumentTypeSchema(),
                        "action": [
                            "type": "string",
                            "enum": ProjectDocumentUpdateAction.allCases.map(\.rawValue),
                        ],
                        "section": [
                            "type": ["string", "null"],
                            "description": "Required for replace_section and delete_section. Use the exact ## header text without the leading ##.",
                        ],
                        "content": [
                            "type": ["string", "null"],
                            "description": "For append, provide a markdown fragment that starts with a ## header. For replace_section, provide the new section body or a full ## section block.",
                        ],
                    ],
                    "required": ["project", "topic", "documentType", "action"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }

    private func projectDocumentTypeSchema() -> [String: Any] {
        [
            "type": "string",
            "enum": ProjectDocumentType.allCases.map(\.rawValue),
        ]
    }

    private func suggestedTargetSchema() -> [String: Any] {
        [
            "type": ["object", "null"],
            "properties": [
                "appName": ["type": "string"],
                "bundleIdentifier": ["type": "string"],
                "windowTitle": ["type": ["string", "null"]],
                "sessionIdentifier": ["type": ["string", "null"]],
                "terminalTTY": ["type": ["string", "null"]],
                "currentWorkingDirectory": ["type": ["string", "null"]],
                "repositoryRoot": ["type": ["string", "null"]],
                "repositoryName": ["type": ["string", "null"]],
                "branch": ["type": ["string", "null"]],
                "capturedAt": [
                    "type": "string",
                    "format": "date-time",
                ],
                "confidence": [
                    "type": "string",
                    "enum": ["high", "low"],
                ],
            ],
            "required": ["appName", "bundleIdentifier"],
            "additionalProperties": false,
        ]
    }

    private func tagSchema() -> [String: Any] {
        [
            "type": ["array", "null"],
            "items": [
                "type": "string",
            ],
        ]
    }

    private func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        do {
            let value: Any
            let mutatesStack: Bool
            switch name {
            case "list_notes":
                mutatesStack = false
                value = try listNotes(arguments: arguments)
            case "get_note":
                mutatesStack = false
                value = try getNote(arguments: arguments)
            case "create_note":
                mutatesStack = true
                value = try createNote(arguments: arguments)
            case "update_note":
                mutatesStack = true
                value = try updateNote(arguments: arguments)
            case "delete_note":
                mutatesStack = true
                value = try deleteNote(arguments: arguments)
            case "mark_notes_executed":
                mutatesStack = true
                value = try markNotesExecuted(arguments: arguments)
            case "classify_notes":
                mutatesStack = false
                value = try classifyNotes(arguments: arguments)
            case "group_notes":
                mutatesStack = true
                value = try groupNotes(arguments: arguments)
            case "get_started":
                mutatesStack = false
                value = getStartedGuide()
            case "list_documents":
                mutatesStack = false
                value = try listDocuments(arguments: arguments)
            case "recall_document":
                mutatesStack = false
                value = try recallDocument(arguments: arguments)
            case "save_document":
                mutatesStack = false
                value = try saveDocument(arguments: arguments)
            case "update_document":
                mutatesStack = false
                value = try updateDocument(arguments: arguments)
            default:
                return toolErrorResult("Unsupported tool \(name)")
            }

            if mutatesStack {
                notifyStackDidChange(toolName: name)
            }

            return toolSuccessResult(value)
        } catch let error as BacktickMCPToolError {
            return toolErrorResult(error.message)
        } catch {
            return toolErrorResult(error.localizedDescription)
        }
    }

    private func listNotes(arguments: [String: Any]) throws -> [String: Any] {
        let scope = try parseScope(arguments["scope"])
        let notes = try readService.listNotes(scope: scope)

        let pinned = notes.filter { $0.isPinned }
        let active = notes.filter { !$0.isPinned && !$0.isCopied }
        let copied = notes.filter { !$0.isPinned && $0.isCopied }

        return [
            "scope": scope.serializedValue,
            "count": notes.count,
            "pinned": [
                "count": pinned.count,
                "notes": pinned.map(noteDictionary),
            ],
            "active": [
                "count": active.count,
                "notes": active.map(noteDictionary),
            ],
            "copied": [
                "count": copied.count,
                "notes": copied.map(noteDictionary),
            ],
        ]
    }

    private func getNote(arguments: [String: Any]) throws -> [String: Any] {
        let id = try requiredUUID(arguments, key: "id")
        let detail = try readService.noteDetail(id: id)

        return [
            "note": detail.map { noteDictionary($0.note) } ?? NSNull(),
            "copyEvents": detail?.copyEvents.map(copyEventDictionary) ?? [],
        ]
    }

    private func createNote(arguments: [String: Any]) throws -> [String: Any] {
        let request = StackNoteCreateRequest(
            text: try requiredString(arguments, key: "text", allowEmpty: true),
            tags: try parseTags(arguments["tags"]),
            suggestedTarget: try parseSuggestedTarget(arguments["suggestedTarget"]),
            screenshotPath: try parseOptionalString(arguments["screenshotPath"]),
            createdAt: try parseDate(arguments["createdAt"]) ?? Date(),
            isPinned: (arguments["isPinned"] as? Bool) ?? false
        )
        let note = try writeService.createNote(request)

        return [
            "note": noteDictionary(note),
        ]
    }

    private func updateNote(arguments: [String: Any]) throws -> [String: Any] {
        let id = try requiredUUID(arguments, key: "id")
        let changes = StackNoteUpdate(
            text: try parseTextUpdate(arguments, key: "text"),
            tags: try parseTagsUpdate(arguments, key: "tags"),
            suggestedTarget: try parseSuggestedTargetUpdate(arguments, key: "suggestedTarget"),
            screenshotPath: try parseStringUpdate(arguments, key: "screenshotPath"),
            isPinned: try parseBoolUpdate(arguments, key: "isPinned"),
            lastCopiedAt: try parseDateUpdate(arguments, key: "lastCopiedAt")
        )
        let note = try writeService.updateNote(id: id, changes: changes)

        return [
            "updated": note != nil,
            "note": note.map(noteDictionary) ?? NSNull(),
        ]
    }

    private func deleteNote(arguments: [String: Any]) throws -> [String: Any] {
        let id = try requiredUUID(arguments, key: "id")
        let deleted = try writeService.deleteNote(id: id)

        return [
            "deleted": deleted,
            "id": id.uuidString.lowercased(),
        ]
    }

    private func markNotesExecuted(arguments: [String: Any]) throws -> [String: Any] {
        let noteIDs = try requiredUUIDArray(arguments, key: "noteIDs")
        let sessionID = try parseOptionalString(arguments["sessionID"])
        let copiedAt = try parseDate(arguments["copiedAt"]) ?? Date()
        let result = try executionService.markExecuted(
            noteIDs: noteIDs,
            sessionID: sessionID,
            copiedAt: copiedAt
        )

        return [
            "count": result.notes.count,
            "notes": result.notes.map(noteDictionary),
            "copyEvents": result.copyEvents.map(copyEventDictionary),
        ]
    }

    private func classifyNotes(arguments: [String: Any]) throws -> [String: Any] {
        let scope = try parseScope(arguments["scope"] ?? "active")
        let groupBy = try parseGroupBy(arguments["groupBy"])
        let classifications = try readService.classifyNotes(scope: scope, groupBy: groupBy)

        return [
            "groupBy": groupBy.rawValue,
            "scope": scope.serializedValue,
            "groupCount": classifications.count,
            "totalNotes": classifications.reduce(0) { $0 + $1.noteIDs.count },
            "groups": classifications.map { classification in
                [
                    "groupKey": classification.groupKey,
                    "repositoryName": classification.repositoryName ?? NSNull(),
                    "branch": classification.branch ?? NSNull(),
                    "appName": classification.appName ?? NSNull(),
                    "sessionIdentifier": classification.sessionIdentifier ?? NSNull(),
                    "tags": classification.tags.map(\.name),
                    "noteCount": classification.noteIDs.count,
                    "noteIDs": classification.noteIDs.map { $0.uuidString.lowercased() },
                    "previewTexts": classification.previewTexts,
                ] as [String: Any]
            },
        ]
    }

    private func groupNotes(arguments: [String: Any]) throws -> [String: Any] {
        let noteIDs = try requiredUUIDArray(arguments, key: "noteIDs")
        let title = try requiredString(arguments, key: "title")
        let separator = try parseOptionalString(arguments["separator"]) ?? "---"
        let archiveSources = (arguments["archiveSources"] as? Bool) ?? false
        let sessionID = try parseOptionalString(arguments["sessionID"])
        let result = try groupService.groupNotes(
            StackGroupRequest(
                sourceNoteIDs: noteIDs,
                title: title,
                separator: separator,
                archiveSources: archiveSources,
                sessionID: sessionID
            )
        )

        return [
            "groupedNote": noteDictionary(result.groupedNote),
            "archivedCount": result.archivedNotes.count,
            "archivedNotes": result.archivedNotes.map(noteDictionary),
            "copyEvents": result.copyEvents.map(copyEventDictionary),
        ]
    }

    private func getStartedGuide() -> [String: Any] {
        let noteCount = (try? readService.listNotes(scope: .all).count) ?? 0

        return [
            "welcome": "Backtick is your AI-connected prompt stack — capture thoughts with Cmd+`, organize them in Stack, and access them from any AI tool.",
            "concepts": [
                "Stack": "Your prompt queue. Capture ideas, tasks, and context. Notes auto-expire after 8 hours unless pinned.",
                "Pinned": "Permanent prompts that never expire. Pin your most-used prompts, project context, or reusable instructions.",
                "Copied": "Notes you've already used. They move to the Copied section so your active stack stays clean.",
            ],
            "tools": [
                ["name": "list_notes", "use": "See all your notes grouped by pinned, active, and copied."],
                ["name": "create_note", "use": "Save a new prompt or context to your stack. Set isPinned: true for permanent notes."],
                ["name": "update_note", "use": "Edit a note's text, tags, or pin status."],
                ["name": "mark_notes_executed", "use": "Mark notes as used after you've acted on them."],
                ["name": "get_note", "use": "Fetch a single note with its full copy history."],
                ["name": "classify_notes", "use": "Group notes by repository, session, or app for organized context."],
                ["name": "list_documents", "use": "Discover reviewed Warm documents without loading their full content."],
                ["name": "recall_document", "use": "Load one durable project document when a discussion needs prior context."],
                ["name": "save_document", "use": "Save a reviewed markdown document for durable context across AI sessions."],
                ["name": "update_document", "use": "Append, replace, or delete one ## section without rewriting the whole document."],
            ],
            "tryIt": noteCount > 0
                ? "You have \(noteCount) notes. Try: \"List my Backtick notes\" or \"Show my pinned prompts\""
                : "Your stack is empty. Try: \"Create a Backtick note: remember to review PR before merge\"",
            "tip": "Capture with Cmd+` from anywhere on your Mac. Your notes appear here instantly.",
        ]
    }

    private func listDocuments(arguments: [String: Any]) throws -> [String: Any] {
        let project = try parseOptionalString(arguments["project"])
        let documents = try documentStore.list(project: project)

        return [
            "count": documents.count,
            "documents": documents.map(documentSummaryDictionary),
        ]
    }

    private func recallDocument(arguments: [String: Any]) throws -> [String: Any] {
        let key = try requiredProjectDocumentKey(arguments)
        let document = try documentStore.currentDocument(
            project: key.project,
            topic: key.topic,
            documentType: key.documentType
        )

        return [
            "document": document.map(documentDictionary) ?? NSNull(),
        ]
    }

    private func saveDocument(arguments: [String: Any]) throws -> [String: Any] {
        let key = try requiredProjectDocumentKey(arguments)
        let content = try requiredString(arguments, key: "content", allowEmpty: true)
        try validateProjectDocumentContent(content)
        let document = try documentStore.saveDocument(
            project: key.project,
            topic: key.topic,
            documentType: key.documentType,
            content: content
        )

        return [
            "document": documentDictionary(document),
        ]
    }

    private func updateDocument(arguments: [String: Any]) throws -> [String: Any] {
        let key = try requiredProjectDocumentKey(arguments)
        let action = try requiredProjectDocumentUpdateAction(arguments["action"])
        let section = try parseOptionalString(arguments["section"])
        let content = try parseOptionalString(arguments["content"])

        let document = try documentStore.updateDocument(
            project: key.project,
            topic: key.topic,
            documentType: key.documentType,
            action: action,
            section: section,
            content: content
        )
        try validateProjectDocumentContent(document.content)

        return [
            "document": documentDictionary(document),
        ]
    }

    private func promptsList() -> [String: Any] {
        [
            "prompts": MCPPromptCatalog.all.map { template in
                [
                    "name": template.name,
                    "description": template.description,
                    "arguments": template.arguments.map { argument in
                        [
                            "name": argument.name,
                            "description": argument.description,
                            "required": argument.required,
                        ] as [String: Any]
                    },
                ] as [String: Any]
            },
        ]
    }

    private func promptsGet(id: Any?, params: [String: Any]) -> [String: Any] {
        guard let promptName = params["name"] as? String, !promptName.isEmpty else {
            return errorResponse(
                id: id,
                code: .invalidParams,
                message: "prompts/get requires a prompt name"
            )
        }

        guard let template = MCPPromptCatalog.template(named: promptName) else {
            return errorResponse(
                id: id,
                code: .invalidParams,
                message: "Unknown prompt: \(promptName)"
            )
        }

        let promptArguments: [String: String]
        if let rawArguments = params["arguments"] as? [String: Any] {
            promptArguments = rawArguments.reduce(into: [String: String]()) { result, item in
                if let value = item.value as? String {
                    result[item.key] = value
                }
            }
        } else {
            promptArguments = [:]
        }

        do {
            let rendered = try MCPPromptRenderer.render(
                template: template,
                arguments: promptArguments
            )
            return successResponse(
                id: id,
                result: [
                    "description": template.description,
                    "messages": [
                        [
                            "role": "user",
                            "content": [
                                "type": "text",
                                "text": rendered,
                            ],
                        ],
                    ],
                ]
            )
        } catch let error as BacktickMCPToolError {
            return errorResponse(id: id, code: .invalidParams, message: error.message)
        } catch {
            return errorResponse(id: id, code: .invalidParams, message: error.localizedDescription)
        }
    }

    private func noteDictionary(_ note: CaptureCard) -> [String: Any] {
        [
            "id": note.id.uuidString.lowercased(),
            "text": note.text,
            "tags": note.tags.map(\.name),
            "createdAt": Self.iso8601Formatter.string(from: note.createdAt),
            "screenshotPath": note.screenshotPath ?? NSNull(),
            "lastCopiedAt": note.lastCopiedAt.map { Self.iso8601Formatter.string(from: $0) } ?? NSNull(),
            "isCopied": note.isCopied,
            "isPinned": note.isPinned,
            "sortOrder": note.sortOrder,
            "suggestedTarget": note.suggestedTarget.map(suggestedTargetDictionary) ?? NSNull(),
        ]
    }

    private func documentSummaryDictionary(_ summary: ProjectDocumentSummary) -> [String: Any] {
        [
            "id": summary.id.uuidString.lowercased(),
            "project": summary.project,
            "topic": summary.topic,
            "documentType": summary.documentType.rawValue,
            "updatedAt": Self.iso8601Formatter.string(from: summary.updatedAt),
        ]
    }

    private func documentDictionary(_ document: ProjectDocument) -> [String: Any] {
        [
            "id": document.id.uuidString.lowercased(),
            "project": document.project,
            "topic": document.topic,
            "documentType": document.documentType.rawValue,
            "content": document.content,
            "createdAt": Self.iso8601Formatter.string(from: document.createdAt),
            "updatedAt": Self.iso8601Formatter.string(from: document.updatedAt),
            "supersededByID": document.supersededByID?.uuidString.lowercased() ?? NSNull(),
        ]
    }

    private func copyEventDictionary(_ copyEvent: CopyEvent) -> [String: Any] {
        [
            "id": copyEvent.id.uuidString.lowercased(),
            "noteID": copyEvent.noteID.uuidString.lowercased(),
            "sessionID": copyEvent.sessionID ?? NSNull(),
            "copiedAt": Self.iso8601Formatter.string(from: copyEvent.copiedAt),
            "copiedVia": copyEvent.copiedVia.rawValue,
            "copiedBy": copyEvent.copiedBy.rawValue,
        ]
    }

    private func suggestedTargetDictionary(_ target: CaptureSuggestedTarget) -> [String: Any] {
        [
            "appName": target.appName,
            "bundleIdentifier": target.bundleIdentifier,
            "windowTitle": target.windowTitle ?? NSNull(),
            "sessionIdentifier": target.sessionIdentifier ?? NSNull(),
            "terminalTTY": target.terminalTTY ?? NSNull(),
            "currentWorkingDirectory": target.currentWorkingDirectory ?? NSNull(),
            "repositoryRoot": target.repositoryRoot ?? NSNull(),
            "repositoryName": target.repositoryName ?? NSNull(),
            "branch": target.branch ?? NSNull(),
            "capturedAt": Self.iso8601Formatter.string(from: target.capturedAt),
            "confidence": target.confidence.rawValue,
        ]
    }

    private func notifyStackDidChange(toolName: String) {
        DistributedNotificationCenter.default().postNotificationName(
            .backtickStackDidChange,
            object: Self.serverName,
            userInfo: [
                "tool": toolName,
                "timestamp": Self.iso8601Formatter.string(from: Date()),
            ],
            options: [.deliverImmediately]
        )
    }

    private func parseScope(_ value: Any?) throws -> StackReadScope {
        guard let rawScope = value as? String else {
            return .all
        }

        switch rawScope {
        case "all":
            return .all
        case "active":
            return .active
        case "copied":
            return .copied
        default:
            throw BacktickMCPToolError(message: "scope must be one of all, active, copied")
        }
    }

    private func parseGroupBy(_ value: Any?) throws -> StackClassifyGroupBy {
        guard let rawValue = value as? String else {
            return .repository
        }

        guard let groupBy = StackClassifyGroupBy(rawValue: rawValue) else {
            throw BacktickMCPToolError(message: "groupBy must be one of repository, session, app")
        }

        return groupBy
    }

    private func requiredUUID(_ arguments: [String: Any], key: String) throws -> UUID {
        let rawValue = try requiredString(arguments, key: key)
        guard let id = UUID(uuidString: rawValue) else {
            throw BacktickMCPToolError(message: "\(key) must be a valid UUID")
        }

        return id
    }

    private func requiredProjectDocumentKey(_ arguments: [String: Any]) throws -> ProjectDocumentKey {
        let project = try requiredString(arguments, key: "project")
        let topic = try requiredString(arguments, key: "topic")
        let documentType = try requiredProjectDocumentType(arguments["documentType"])

        return ProjectDocumentKey(
            project: project,
            topic: topic,
            documentType: documentType
        )
    }

    private func requiredProjectDocumentType(_ value: Any?) throws -> ProjectDocumentType {
        guard let rawValue = value as? String,
              let documentType = ProjectDocumentType(rawValue: rawValue) else {
            throw BacktickMCPToolError(
                message: "documentType must be one of \(ProjectDocumentType.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        return documentType
    }

    private func requiredProjectDocumentUpdateAction(_ value: Any?) throws -> ProjectDocumentUpdateAction {
        guard let rawValue = value as? String,
              let action = ProjectDocumentUpdateAction(rawValue: rawValue) else {
            throw BacktickMCPToolError(
                message: "action must be one of \(ProjectDocumentUpdateAction.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        return action
    }

    private func requiredUUIDArray(_ arguments: [String: Any], key: String) throws -> [UUID] {
        guard let rawValues = arguments[key] as? [String], !rawValues.isEmpty else {
            throw BacktickMCPToolError(message: "\(key) must be a non-empty array of UUID strings")
        }

        return try rawValues.map { rawValue in
            guard let id = UUID(uuidString: rawValue) else {
                throw BacktickMCPToolError(message: "\(key) must contain valid UUID strings")
            }
            return id
        }
    }

    private func requiredString(
        _ arguments: [String: Any],
        key: String,
        allowEmpty: Bool = false
    ) throws -> String {
        guard let rawValue = arguments[key] as? String else {
            throw BacktickMCPToolError(message: "\(key) is required")
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowEmpty && trimmedValue.isEmpty {
            throw BacktickMCPToolError(message: "\(key) cannot be empty")
        }

        return allowEmpty ? rawValue : trimmedValue
    }

    private func parseOptionalString(_ value: Any?) throws -> String? {
        guard let value else {
            return nil
        }
        if value is NSNull {
            return nil
        }
        guard let stringValue = value as? String else {
            throw BacktickMCPToolError(message: "Expected string or null")
        }

        let trimmedValue = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func parseDate(_ value: Any?) throws -> Date? {
        guard let stringValue = try parseOptionalString(value) else {
            return nil
        }
        guard let date = Self.iso8601Formatter.date(from: stringValue) else {
            throw BacktickMCPToolError(message: "Expected ISO-8601 date-time string")
        }

        return date
    }

    private func validateProjectDocumentContent(_ content: String) throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw BacktickMCPToolError(message: "content cannot be empty")
        }

        guard trimmedContent.count >= 200 else {
            throw BacktickMCPToolError(message: "content must be at least 200 characters of structured markdown")
        }

        guard trimmedContent.contains("\n## ") || trimmedContent.hasPrefix("## ") else {
            throw BacktickMCPToolError(message: "content must be markdown with ## section headers")
        }
    }

    private func parseSuggestedTarget(_ value: Any?) throws -> CaptureSuggestedTarget? {
        guard let value else {
            return nil
        }
        if value is NSNull {
            return nil
        }
        guard let dictionary = value as? [String: Any] else {
            throw BacktickMCPToolError(message: "suggestedTarget must be an object or null")
        }

        let appName = try requiredString(dictionary, key: "appName")
        let bundleIdentifier = try requiredString(dictionary, key: "bundleIdentifier")

        return CaptureSuggestedTarget(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: try parseOptionalString(dictionary["windowTitle"]),
            sessionIdentifier: try parseOptionalString(dictionary["sessionIdentifier"]),
            terminalTTY: try parseOptionalString(dictionary["terminalTTY"]),
            currentWorkingDirectory: try parseOptionalString(dictionary["currentWorkingDirectory"]),
            repositoryRoot: try parseOptionalString(dictionary["repositoryRoot"]),
            repositoryName: try parseOptionalString(dictionary["repositoryName"]),
            branch: try parseOptionalString(dictionary["branch"]),
            capturedAt: try parseDate(dictionary["capturedAt"]) ?? Date(),
            confidence: try parseConfidence(dictionary["confidence"])
        )
    }

    private func parseTags(_ value: Any?) throws -> [CaptureTag] {
        guard let value else {
            return []
        }
        if value is NSNull {
            return []
        }
        guard let rawTags = value as? [String] else {
            throw BacktickMCPToolError(message: "tags must be an array of strings or null")
        }

        let tags = rawTags.compactMap(CaptureTag.init(rawValue:))
        guard tags.count == rawTags.count else {
            throw BacktickMCPToolError(message: "tags must contain valid tag names")
        }

        return CaptureTag.deduplicatePreservingOrder(tags)
    }

    private func parseConfidence(_ value: Any?) throws -> CaptureSuggestedTargetConfidence {
        guard let confidence = try parseOptionalString(value) else {
            return .high
        }
        guard let parsedConfidence = CaptureSuggestedTargetConfidence(rawValue: confidence) else {
            throw BacktickMCPToolError(message: "confidence must be high or low")
        }

        return parsedConfidence
    }

    private func parseTextUpdate(
        _ arguments: [String: Any],
        key: String
    ) throws -> String? {
        guard arguments.keys.contains(key) else {
            return nil
        }
        if arguments[key] is NSNull {
            return ""
        }
        guard let textValue = arguments[key] as? String else {
            throw BacktickMCPToolError(message: "\(key) must be a string or null")
        }
        return textValue
    }

    private func parseStringUpdate(
        _ arguments: [String: Any],
        key: String
    ) throws -> StackOptionalUpdate<String> {
        guard arguments.keys.contains(key) else {
            return .keep
        }
        if arguments[key] is NSNull {
            return .clear
        }
        guard let stringValue = arguments[key] as? String else {
            throw BacktickMCPToolError(message: "\(key) must be a string or null")
        }
        return .set(stringValue)
    }

    private func parseSuggestedTargetUpdate(
        _ arguments: [String: Any],
        key: String
    ) throws -> StackOptionalUpdate<CaptureSuggestedTarget> {
        guard arguments.keys.contains(key) else {
            return .keep
        }
        if arguments[key] is NSNull {
            return .clear
        }
        guard let value = arguments[key] else {
            return .keep
        }
        guard let target = try parseSuggestedTarget(value) else {
            return .clear
        }
        return .set(target)
    }

    private func parseBoolUpdate(
        _ arguments: [String: Any],
        key: String
    ) throws -> StackOptionalUpdate<Bool> {
        guard arguments.keys.contains(key) else {
            return .keep
        }
        if arguments[key] is NSNull {
            return .keep
        }
        guard let boolValue = arguments[key] as? Bool else {
            throw BacktickMCPToolError(message: "\(key) must be a boolean or null")
        }
        return .set(boolValue)
    }

    private func parseDateUpdate(
        _ arguments: [String: Any],
        key: String
    ) throws -> StackOptionalUpdate<Date> {
        guard arguments.keys.contains(key) else {
            return .keep
        }
        if arguments[key] is NSNull {
            return .clear
        }
        guard let dateValue = try parseDate(arguments[key]) else {
            throw BacktickMCPToolError(message: "\(key) must be an ISO-8601 date string or null")
        }
        return .set(dateValue)
    }

    private func parseTagsUpdate(
        _ arguments: [String: Any],
        key: String
    ) throws -> StackOptionalUpdate<[CaptureTag]> {
        guard arguments.keys.contains(key) else {
            return .keep
        }
        if arguments[key] is NSNull {
            return .clear
        }
        return .set(try parseTags(arguments[key]))
    }

    private func toolSuccessResult(_ value: Any) -> [String: Any] {
        [
            "content": [
                [
                    "type": "text",
                    "text": Self.jsonString(for: value),
                ],
            ],
            "isError": false,
        ]
    }

    private func toolErrorResult(_ message: String) -> [String: Any] {
        toolSuccessResult(
            [
                "error": message,
            ]
        )
        .merging(["isError": true]) { _, replacement in
            replacement
        }
    }

    private func successResponse(id: Any?, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": Self.jsonrpcVersion,
            "id": id ?? NSNull(),
            "result": result,
        ]
    }

    private func errorResponse(
        id: Any?,
        code: JSONRPCErrorCode,
        message: String
    ) -> [String: Any] {
        [
            "jsonrpc": Self.jsonrpcVersion,
            "id": id ?? NSNull(),
            "error": [
                "code": code.rawValue,
                "message": message,
            ],
        ]
    }

    private func serializedResponse(_ object: Any) -> String {
        Self.jsonString(for: object)
    }

    private func serializedResponseData(_ object: Any) -> Data {
        Self.jsonData(for: object)
    }

    private static func jsonString(for object: Any) -> String {
        let data = jsonData(for: object)
        guard let string = String(data: data, encoding: .utf8) else {
            return #"{"error":"Failed to serialize JSON response"}"#
        }

        return string
    }

    private static func jsonData(for object: Any) -> Data {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return Data(#"{"error":"Failed to serialize JSON response"}"#.utf8)
        }

        return data
    }
}

private enum JSONRPCErrorCode: Int {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
}

private extension StackReadScope {
    var serializedValue: String {
        switch self {
        case .all:
            return "all"
        case .active:
            return "active"
        case .copied:
            return "copied"
        }
    }
}

private func makeDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds,
    ]
    return formatter
}
