import Foundation
import PromptCueCore

enum BacktickMCPToolNaming {
    static let canonicalNames = [
        "status",
        "list_notes",
        "get_note",
        "create_note",
        "update_note",
        "delete_note",
        "mark_notes_executed",
        "classify_notes",
        "group_notes",
        "get_started",
        "list_saved_items",
        "list_documents",
        "recall_document",
        "propose_document_saves",
        "save_document",
        "update_document",
        "delete_document",
    ]

    private static let brandedPrefix = "backtick_"
    private static let exposedNamesByCanonical = [
        "status": "backtick_status",
        "list_notes": "backtick_list_notes",
        "get_note": "backtick_get_note",
        "create_note": "backtick_create_note",
        "update_note": "backtick_update_note",
        "delete_note": "backtick_delete_note",
        "mark_notes_executed": "backtick_complete_notes",
        "classify_notes": "backtick_classify_notes",
        "group_notes": "backtick_group_notes",
        "get_started": "backtick_get_started",
        "list_saved_items": "backtick_list_saved_items",
        "list_documents": "backtick_list_docs",
        "recall_document": "backtick_recall_doc",
        "propose_document_saves": "backtick_propose_save",
        "save_document": "backtick_save_doc",
        "update_document": "backtick_update_doc",
        "delete_document": "backtick_delete_doc",
    ]
    private static let canonicalNamesByExposed = Dictionary(
        uniqueKeysWithValues: exposedNamesByCanonical.map { ($1, $0) }
    )

    static func exposedName(_ canonicalName: String) -> String {
        exposedNamesByCanonical[canonicalName] ?? "\(brandedPrefix)\(canonicalName)"
    }

    static func canonicalName(for requestedName: String) -> String {
        if canonicalNames.contains(requestedName) {
            return requestedName
        }

        if let canonicalName = canonicalNamesByExposed[requestedName] {
            return canonicalName
        }

        guard requestedName.hasPrefix(brandedPrefix) else {
            return requestedName
        }

        let strippedName = String(requestedName.dropFirst(brandedPrefix.count))
        guard canonicalNames.contains(strippedName) else {
            return requestedName
        }

        return strippedName
    }

    static func title(for canonicalName: String) -> String {
        let brandedName = exposedName(canonicalName)
        let suffix = brandedName.hasPrefix(brandedPrefix)
            ? String(brandedName.dropFirst(brandedPrefix.count))
            : brandedName
        let words = suffix
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        return "Backtick \(words)"
    }

    static func brandToolReferences(in text: String) -> String {
        canonicalNames.reduce(text) { partialResult, canonicalName in
            let pattern = "(?<!\(brandedPrefix))\\b\(NSRegularExpression.escapedPattern(for: canonicalName))\\b"
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return partialResult
            }

            let range = NSRange(partialResult.startIndex..., in: partialResult)
            return expression.stringByReplacingMatches(
                in: partialResult,
                range: range,
                withTemplate: exposedName(canonicalName)
            )
        }
    }
}

@MainActor
final class BacktickMCPServerSession {
    private static let connectorClientEnvironmentKey = "BACKTICK_CONNECTOR_CLIENT"
    private static let disableConnectionActivityEnvironmentKey = "BACKTICK_MCP_CONNECTION_ACTIVITY_DISABLED"

    private let readService: StackReadService
    private let writeService: StackWriteService
    private let executionService: StackExecutionService
    private let groupService: StackGroupService
    private let documentStore: ProjectDocumentStore
    private let connectionActivityStore: BacktickMCPConnectionActivityStore
    private let configuredClientID: String?
    private let launchCommand: String?
    private let launchArguments: [String]

    private var clientName: String?
    private var clientVersion: String?
    private var currentActivityContext: BacktickMCPConnectionContext = .stdio

    private static let supportedProtocolVersions = [
        "2025-03-26",
        "2024-11-05",
    ]
    private static let jsonrpcVersion = "2.0"
    private static let serverName = "backtick-stack-mcp"
    private static let serverTitle = "Backtick Stack MCP"
    private static let serverVersion = "0.2.0"
    private static let surfaceVersion = "2026-04-03.1"
    private static let iso8601Formatter = makeDateFormatter()

    init(
        fileManager: FileManager = .default,
        databaseURL: URL? = nil,
        attachmentBaseDirectoryURL: URL? = nil,
        connectionActivityFileURL: URL? = nil,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        commandLine: [String] = CommandLine.arguments
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
        configuredClientID = processEnvironment[Self.connectorClientEnvironmentKey]
        launchCommand = commandLine.first
        launchArguments = Array(commandLine.dropFirst())
        connectionActivityStore = BacktickMCPConnectionActivityStore(
            fileManager: fileManager,
            fileURL: connectionActivityFileURL,
            isEnabled: processEnvironment[Self.disableConnectionActivityEnvironmentKey] != "1"
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

        guard let responseData = handleRequestData(data, activityContext: .stdio) else {
            return nil
        }

        return String(data: responseData, encoding: .utf8)
    }

    func handleRequestData(
        _ data: Data,
        activityContext: BacktickMCPConnectionContext
    ) -> Data? {
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
            let responses = batch.compactMap { handlePayloadObject($0, activityContext: activityContext) }
            guard !responses.isEmpty else {
                return nil
            }
            return serializedResponseData(responses)

        case let object as [String: Any]:
            guard let response = handleObject(object, activityContext: activityContext) else {
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

    private func handlePayloadObject(
        _ payload: Any,
        activityContext: BacktickMCPConnectionContext
    ) -> [String: Any]? {
        guard let object = payload as? [String: Any] else {
            return errorResponse(
                id: nil,
                code: .invalidRequest,
                message: "Batch entry must be a JSON object"
            )
        }

        return handleObject(object, activityContext: activityContext)
    }

    private func handleObject(
        _ request: [String: Any],
        activityContext: BacktickMCPConnectionContext
    ) -> [String: Any]? {
        currentActivityContext = activityContext
        defer { currentActivityContext = .stdio }

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
            let canonicalToolName = BacktickMCPToolNaming.canonicalName(for: toolName)
            let toolResult = callTool(name: canonicalToolName, arguments: arguments)
            if (toolResult["isError"] as? Bool) == false {
                recordSuccessfulToolCall(
                    requestedToolName: toolName,
                    toolName: BacktickMCPToolNaming.exposedName(canonicalToolName),
                    activityContext: activityContext
                )
            }
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

        let clientInfo = params["clientInfo"] as? [String: Any]
        clientName = clientInfo?["name"] as? String
        clientVersion = clientInfo?["version"] as? String
        return [
            "protocolVersion": protocolVersion,
            "instructions": serverInstructions(),
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

    private func recordSuccessfulToolCall(
        requestedToolName: String?,
        toolName: String,
        activityContext: BacktickMCPConnectionContext
    ) {
        connectionActivityStore.recordSuccessfulToolCall(
            context: activityContext,
            clientName: clientName,
            clientVersion: clientVersion,
            sessionID: nil,
            toolName: toolName,
            requestedToolName: requestedToolName,
            configuredClientID: configuredClientID,
            launchCommand: launchCommand,
            launchArguments: launchArguments
        )
    }

    private func serverInstructions() -> String {
        BacktickMCPToolNaming.brandToolReferences(in: """
        Backtick is project memory shared across AI tools. It is separate from any built-in assistant memory.

        When speaking to the user, refer to this memory as Backtick, or 백틱 in Korean conversations. Do not call it generic memory when asking whether to save or recall something.

        Recall behavior:
        1. For generic requests like "Backtick notes", "load my notes", or "what do I have in Backtick", call list_saved_items first.
        2. For ChatGPT and Claude app clients, present Memory first, then Stack, unless the user explicitly asked for stack, prompts, pinned, copied, or the current queue.
        3. For CLI clients like Claude Code or Codex, present Stack first, then Memory, unless the user explicitly asked for Memory, documents, project context, prior decisions, architecture, or plans.
        4. If the user is still ambiguous after list_saved_items, ask whether they want Memory, Stack, or both before drilling deeper.
        5. When the user mentions a known project, topic, or ongoing work that likely depends on prior Backtick context, call list_documents or recall_document first.
        6. Do not wait to be asked when prior Backtick context is likely relevant to the current answer.

        Save behavior:
        1. Call propose_document_saves before saving when the user has not already specified the exact document structure. Skip the proposal when the user has already provided the project, topic, documentType, and content explicitly — save directly to minimize round-trips.
        2. When calling propose_document_saves, organize the content by topic before sending — separate distinct decisions or discussion threads into their own ## sections so the server can generate focused proposals. Focus on decisions, direction changes, and topics discussed at length. Skip anything only briefly mentioned.
        3. Do not save silently. Wait for the user to confirm which proposals to save before writing anything.
        4. Before writing, list or recall existing docs so you can update the right document instead of creating a duplicate.
        5. If a long discussion is mixed and classification is uncertain, default to one reviewed discussion doc instead of forcing a multi-document split.
        6. When asking the user, use short natural language in the current conversation language. Any confirmPrompt text returned by tools is fallback example copy, not fixed UI wording.
        7. Good examples:
           - "Save this to Backtick?"
           - "Should I add this to the existing Backtick memo?"
           - "이 내용을 백틱에 저장할까요?"
        8. Bad examples:
           - "I already saved this to memory."
           - "Should I create a decision document with operation update?"
           - "This went into generic memory."

        Content rules:
        - Save durable context, decisions, plans, constraints, and structured summaries that will help a future AI session resume work.
        - Do not save coding-session logs, file-by-file change logs, shell or test-command transcripts, or git-like execution history.
        """)
    }

    private func toolDefinitions() -> [[String: Any]] {
        MCPToolCatalog.all.map { brandedToolDefinition($0.toDict()) }
    }

    private func brandedToolDefinition(_ definition: [String: Any]) -> [String: Any] {
        guard let canonicalName = definition["name"] as? String else {
            return definition
        }

        var branded = definition
        branded["name"] = BacktickMCPToolNaming.exposedName(canonicalName)
        branded["title"] = BacktickMCPToolNaming.title(for: canonicalName)
        if let description = branded["description"] as? String {
            branded["description"] = BacktickMCPToolNaming.brandToolReferences(in: description)
        }
        return branded
    }


    private func callTool(name: String, arguments: [String: Any]) -> [String: Any] {
        do {
            let value: Any
            let mutatesStack: Bool
            switch name {
            case "status":
                mutatesStack = false
                value = status()
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
            case "list_saved_items":
                mutatesStack = false
                value = try listSavedItems(arguments: arguments)
            case "list_documents":
                mutatesStack = false
                value = try listDocuments(arguments: arguments)
            case "recall_document":
                mutatesStack = false
                value = try recallDocument(arguments: arguments)
            case "propose_document_saves":
                mutatesStack = false
                value = try proposeDocumentSaves(arguments: arguments)
            case "save_document":
                mutatesStack = false
                value = try saveDocument(arguments: arguments)
            case "update_document":
                mutatesStack = false
                value = try updateDocument(arguments: arguments)
            case "delete_document":
                mutatesStack = false
                value = try deleteDocument(arguments: arguments)
            default:
                return toolErrorResult("Unsupported tool \(name)")
            }

            if mutatesStack {
                notifyStackDidChange(toolName: BacktickMCPToolNaming.exposedName(name))
            }

            return toolSuccessResult(value)
        } catch let error as BacktickMCPToolError {
            return toolErrorResult(error.message)
        } catch {
            return toolErrorResult(error.localizedDescription)
        }
    }

    private func status() -> [String: Any] {
        let helperURL = Bundle.main.executableURL ?? URL(fileURLWithPath: launchCommand ?? CommandLine.arguments[0])
        let appBundleURL = inferredAppBundleURL(from: helperURL)
        let appBundle = appBundleURL.flatMap(Bundle.init(url:))
        let appVersion = appBundle?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let appBuild = appBundle?
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return [
            "product": "Backtick",
            "server": [
                "name": Self.serverName,
                "title": Self.serverTitle,
                "version": Self.serverVersion,
                "surfaceVersion": Self.surfaceVersion,
            ],
            "app": [
                "path": appBundleURL?.path as Any? ?? NSNull(),
                "version": appVersion as Any? ?? NSNull(),
                "build": appBuild as Any? ?? NSNull(),
            ],
            "helper": [
                "path": helperURL.path,
                "launchCommand": launchCommand as Any? ?? NSNull(),
                "launchArguments": launchArguments,
            ],
            "surface": [
                "toolCount": MCPToolCatalog.all.count,
                "promptCount": MCPPromptCatalog.all.count,
                "toolNames": MCPToolCatalog.all.map { BacktickMCPToolNaming.exposedName($0.name) },
                "promptNames": MCPPromptCatalog.all.map(\.name),
            ],
        ]
    }

    private func inferredAppBundleURL(from helperURL: URL) -> URL? {
        let standardizedURL = helperURL.standardizedFileURL
        let helperDirectory = standardizedURL.deletingLastPathComponent()
        let contentsDirectory = helperDirectory.deletingLastPathComponent()
        let appBundleURL = contentsDirectory.deletingLastPathComponent()
        guard appBundleURL.pathExtension == "app" else {
            return nil
        }
        return appBundleURL
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
            screenshotPath: try parseStringUpdate(arguments, key: "screenshotPath"),
            isPinned: try parseBoolUpdate(arguments, key: "isPinned")
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
        let documentCount = (try? documentStore.list(project: nil).count) ?? 0

        return [
            "welcome": "Backtick keeps your reviewed Memory documents and Stack capture cards available across AI tools.",
            "concepts": [
                "Memory": "Your durable reviewed documents. App clients usually lead with Memory, while CLI clients usually lead with Stack unless the user clearly asked for saved context.",
                "Stack": "Your prompt queue. Capture ideas, tasks, and context. Notes auto-expire after 8 hours unless pinned.",
                "Pinned": "Permanent prompts that never expire. Pin your most-used prompts, project context, or reusable instructions.",
                "Copied": "Notes you've already used. They move to the Copied section so your active stack stays clean.",
            ],
            "tools": [
                ["name": BacktickMCPToolNaming.exposedName("status"), "use": "Report the current Backtick MCP app version, build, helper path, and tool surface version so you can verify a client is on the latest connector surface."],
                ["name": BacktickMCPToolNaming.exposedName("list_saved_items"), "use": "Start here for generic Backtick inventory requests. For ChatGPT and Claude app clients, show Memory first. For CLI clients like Claude Code or Codex, show Stack first. Then clarify whether the user wants Memory, Stack, or both if it is still ambiguous."],
                ["name": BacktickMCPToolNaming.exposedName("list_notes"), "use": "See all your notes grouped by pinned, active, and copied."],
                ["name": BacktickMCPToolNaming.exposedName("create_note"), "use": "Save a new prompt or context to your stack. Set isPinned: true for permanent notes."],
                ["name": BacktickMCPToolNaming.exposedName("update_note"), "use": "Edit a note's text, tags, or pin status."],
                ["name": BacktickMCPToolNaming.exposedName("mark_notes_executed"), "use": "Mark notes as used after you've acted on them."],
                ["name": BacktickMCPToolNaming.exposedName("get_note"), "use": "Fetch a single note with its full copy history."],
                ["name": BacktickMCPToolNaming.exposedName("classify_notes"), "use": "Group notes by repository, session, or app for organized context."],
                ["name": BacktickMCPToolNaming.exposedName("list_documents"), "use": "Discover reviewed Memory documents without loading their full content."],
                ["name": BacktickMCPToolNaming.exposedName("recall_document"), "use": "Load one durable project document when a discussion needs prior context."],
                ["name": BacktickMCPToolNaming.exposedName("propose_document_saves"), "use": "Draft reviewed save proposals before anything is written to Backtick Memory."],
                ["name": BacktickMCPToolNaming.exposedName("save_document"), "use": "Save a reviewed markdown document for durable context across AI sessions after the user confirms what to keep."],
                ["name": BacktickMCPToolNaming.exposedName("update_document"), "use": "Append, replace, or delete one ## section without rewriting the whole document."],
            ],
            "warmExamples": [
                "Load my Backtick notes.",
                "What do I have in Backtick right now?",
                "We just settled an important decision. Propose how to save it to Backtick first.",
                "Turn this conversation into a PRD and save it for later.",
                "Document only the latest decisions we made about pricing.",
                "Update our architecture summary with what we just decided.",
                "Before answering, load the current pricing decisions.",
            ],
            "tryIt": noteCount + documentCount > 0
                ? "You have \(documentCount) Memory documents and \(noteCount) Stack notes. Try: \"What do I have in Backtick?\""
                : "Backtick is empty right now. Try: \"What do I have in Backtick?\" or \"Create a Backtick note: remember to review PR before merge\"",
            "tip": "Capture with Cmd+` from anywhere on your Mac. Your notes appear here instantly.",
        ]
    }

    private func listSavedItems(arguments: [String: Any]) throws -> [String: Any] {
        _ = arguments

        let notes = try readService.listNotes(scope: .all)
        let pinned = notes.filter { $0.isPinned }
        let active = notes.filter { !$0.isPinned && !$0.isCopied }
        let copied = notes.filter { !$0.isPinned && $0.isCopied }
        let documents = try documentStore.list(project: nil)
            .sorted(by: { $0.updatedAt > $1.updatedAt })
        let preferredPresentation = preferredSavedItemsPresentation()

        return [
            "preferredFirst": preferredPresentation.primaryLane,
            "presentationOrder": preferredPresentation.order,
            "memory": [
                "count": documents.count,
                "recentDocuments": Array(documents.prefix(5)).map(documentSummaryDictionary),
            ],
            "stack": [
                "count": notes.count,
                "pinnedCount": pinned.count,
                "activeCount": active.count,
                "copiedCount": copied.count,
                "pinned": Array(pinned.prefix(3)).map(savedItemNotePreview),
                "active": Array(active.prefix(3)).map(savedItemNotePreview),
                "copied": Array(copied.prefix(3)).map(savedItemNotePreview),
            ],
            "recommendedNextStep": preferredPresentation.recommendedNextStep,
        ]
    }

    private func listDocuments(arguments: [String: Any]) throws -> [String: Any] {
        let project = try parseOptionalString(arguments["project"])
        let includeDormant = (arguments["include_dormant"] as? Bool) ?? false
        let allDocuments = try documentStore.list(project: project)

        let sorted = allDocuments.sorted { lhs, rhs in
            lhs.retrievability() > rhs.retrievability()
        }

        if includeDormant {
            return [
                "count": sorted.count,
                "documents": sorted.map(documentSummaryDictionary),
            ]
        }

        let active = sorted.filter { $0.vividnessTier() != .dormant }
        let dormantCount = sorted.count - active.count

        var result: [String: Any] = [
            "count": active.count,
            "documents": active.map(documentSummaryDictionary),
        ]
        if dormantCount > 0 {
            result["dormantCount"] = dormantCount
        }
        return result
    }

    private func recallDocument(arguments: [String: Any]) throws -> [String: Any] {
        let key = try requiredProjectDocumentKey(arguments)
        let document = try documentStore.currentDocument(
            project: key.project,
            topic: key.topic,
            documentType: key.documentType
        )

        if document != nil {
            try documentStore.recordRecall(
                project: key.project,
                topic: key.topic,
                documentType: key.documentType
            )
        }

        return [
            "document": document.map(documentDictionary) ?? NSNull(),
        ]
    }

    private func proposeDocumentSaves(arguments: [String: Any]) throws -> [String: Any] {
        let project = try requiredString(arguments, key: "project")
        let content = try requiredString(arguments, key: "content", allowEmpty: true)
        let userIntent = try parseOptionalString(arguments["userIntent"])
        let preferredTopic = try parseOptionalString(arguments["preferredTopic"])
        let maxProposals = try parseOptionalProposalCount(arguments["maxProposals"])
        let globalWarnings = proposalWarnings(
            project: project,
            topic: preferredTopic ?? "",
            documentType: .discussion,
            content: content,
            userIntent: userIntent
        )

        if shouldSkipSaveProposal(content: content, userIntent: userIntent) {
            return [
                "project": project,
                "count": 0,
                "warnings": globalWarnings,
                "proposals": [],
                "globalWarnings": globalWarnings,
                "recommendedNextStep": "do_not_write",
            ]
        }

        let rawSegments = splitContentIntoSegments(content)
        let meaningfulSegments = rawSegments.filter { seg in
            !shouldSkipSaveProposal(content: seg.body, userIntent: nil)
        }

        // Fall back to whole content if no meaningful segments survive filtering
        let segments: [(heading: String?, body: String)]
        if meaningfulSegments.isEmpty {
            segments = [(heading: nil, body: content)]
        } else {
            segments = meaningfulSegments
        }

        // Group segments by inferred topic first, merging content for duplicates
        var segmentContentByTopic: [String: String] = [:]
        var topicOrder: [String] = []

        for segment in segments {
            let segmentDocumentType = inferredDocumentType(content: segment.body, userIntent: userIntent)
            // Respect an explicit preferred topic so structured markdown can still
            // target one existing document. Fall back to per-section headings only
            // when the caller did not supply a topic hint.
            let effectivePreferredTopic = preferredTopic ?? segment.heading
            let segmentTopic = inferredProposalTopic(
                content: segment.body,
                userIntent: userIntent,
                preferredTopic: effectivePreferredTopic,
                documentType: segmentDocumentType
            )

            if segmentContentByTopic[segmentTopic] != nil {
                // Merge content from duplicate-topic segments
                segmentContentByTopic[segmentTopic] = (segmentContentByTopic[segmentTopic] ?? "") + "\n\n" + segment.body
            } else {
                segmentContentByTopic[segmentTopic] = segment.body
                topicOrder.append(segmentTopic)
            }
        }

        // Build one proposal per unique topic using its merged content
        var proposalsByTopic: [String: [String: Any]] = [:]

        for segmentTopic in topicOrder {
            let mergedContent = segmentContentByTopic[segmentTopic] ?? ""
            let inferredType = inferredDocumentType(content: mergedContent, userIntent: userIntent)

            let exactExistingDocument = try documentStore.currentDocument(
                project: project,
                topic: segmentTopic,
                documentType: inferredType
            )
            let sameTopicDocuments = exactExistingDocument == nil && !isBroadProposalTopic(segmentTopic)
                ? try documentStore.currentDocuments(project: project, topic: segmentTopic)
                : []
            let fallbackExistingDocument = exactExistingDocument == nil && sameTopicDocuments.count == 1
                ? sameTopicDocuments[0]
                : nil
            let segmentDocumentType = fallbackExistingDocument?.documentType ?? inferredType

            let segmentWarnings = proposalWarnings(
                project: project,
                topic: segmentTopic,
                documentType: segmentDocumentType,
                content: mergedContent,
                userIntent: userIntent
            )
            let existingDocumentSummary = exactExistingDocument.map(documentSummaryDictionary)
                ?? fallbackExistingDocument.map(documentSummaryDictionary)

            let recommendationTool = existingDocumentSummary == nil
                ? BacktickMCPToolNaming.exposedName("save_document")
                : BacktickMCPToolNaming.exposedName("update_document")
            let operation = existingDocumentSummary == nil ? "create" : "update"
            let needsRecall = existingDocumentSummary != nil
            let proposalID = UUID().uuidString.lowercased()
            let filteredBody = filterNoisyLines(mergedContent)
            let preview = proposalPreview(
                content: filteredBody,
                topic: segmentTopic,
                documentType: segmentDocumentType
            )
            let oneLiner = proposalOneLiner(filteredBody, topic: segmentTopic)
            let review = proposalReview(
                topic: segmentTopic,
                existingDocument: existingDocumentSummary != nil,
                summary: oneLiner
            )

            let proposal: [String: Any] = [
                "proposalID": proposalID,
                "topic": segmentTopic,
                "documentType": segmentDocumentType.rawValue,
                "confidence": segmentWarnings.contains("classification_uncertain") ? "medium" : "high",
                "operation": operation,
                "rationale": proposalRationale(
                    topic: segmentTopic,
                    documentType: segmentDocumentType,
                    existingDocument: existingDocumentSummary != nil,
                    userIntent: userIntent
                ),
                "preview": preview,
                "existingDocument": existingDocumentSummary ?? NSNull(),
                "warnings": segmentWarnings,
                "review": review,
                "recommendation": [
                    "kind": operation,
                    "tool": recommendationTool,
                    "needsRecall": needsRecall,
                ] as [String: Any],
            ]

            proposalsByTopic[segmentTopic] = proposal
        }

        let orderedProposals = topicOrder.compactMap { proposalsByTopic[$0] }
        let limitedProposals = Array(orderedProposals.prefix(maxProposals))
        let nextStep = limitedProposals.count == 1 ? "confirm_one_proposal" : "review_proposals"

        return [
            "project": project,
            "count": limitedProposals.count,
            "warnings": globalWarnings,
            "proposals": limitedProposals,
            "globalWarnings": globalWarnings,
            "recommendedNextStep": nextStep,
        ]
    }

    private func splitContentIntoSegments(_ content: String) -> [(heading: String?, body: String)] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split by ## headers if present
        if normalized.contains("\n## ") || normalized.hasPrefix("## ") {
            var segments: [(heading: String?, body: String)] = []
            let lines = normalized.components(separatedBy: "\n")
            var currentHeading: String? = nil
            var currentLines: [String] = []

            for line in lines {
                if line.hasPrefix("## ") {
                    if !currentLines.isEmpty {
                        let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !body.isEmpty {
                            segments.append((heading: currentHeading, body: body))
                        }
                    }
                    currentHeading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    currentLines = [line]
                } else {
                    currentLines.append(line)
                }
            }

            if !currentLines.isEmpty {
                let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    segments.append((heading: currentHeading, body: body))
                }
            }

            return segments.isEmpty ? [(heading: nil, body: normalized)] : segments
        }

        // Fall back: split by double-newline paragraphs
        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count <= 1 {
            return [(heading: nil, body: normalized)]
        }

        return paragraphs.map { (heading: nil, body: $0) }
    }

    private func filterNoisyLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            let isNoisy = value.contains("```")
                || value.hasPrefix("$ ")
                || value.contains("xcodebuild")
                || value.contains("swift test")
                || (value.hasPrefix("git ") || value.contains(" git "))
                || (value.contains("/") && value.contains(".swift"))
                || value.hasPrefix("error: ")
                || value.hasPrefix("warning: ")
                || value.hasPrefix("Build complete")
                || value.hasPrefix("Compiling ")
                || value.hasPrefix("Linking ")
            return !isNoisy
        }
        return filtered.joined(separator: "\n")
    }

    private func proposalOneLiner(_ segment: String, topic: String) -> String {
        let lines = segment
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("```") && !$0.hasPrefix("- ") }

        // Find first sentence-like line with substance (>20 chars)
        if let firstSubstantiveLine = lines.first(where: { $0.count > 20 }) {
            let truncated = firstSubstantiveLine.count > 120
                ? String(firstSubstantiveLine.prefix(117)) + "..."
                : firstSubstantiveLine
            return truncated
        }

        let displayTopic = topic
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "Notes on \(displayTopic)"
    }

    private func proposalReview(topic: String, existingDocument: Bool, summary: String? = nil) -> [String: Any] {
        let displayTopic = topic
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if existingDocument {
            let resolvedSummary = summary ?? "This fits the existing \(displayTopic) Backtick memo."
            return [
                "displayTopic": displayTopic,
                "summary": resolvedSummary,
                "confirmPrompt": "Should I add this to the existing Backtick memo?",
                "hideInternalFieldsByDefault": true,
            ]
        }

        let resolvedSummary = summary ?? "This looks worth keeping in Backtick as \(displayTopic)."
        return [
            "displayTopic": displayTopic,
            "summary": resolvedSummary,
            "confirmPrompt": "Save this to Backtick?",
            "hideInternalFieldsByDefault": true,
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

    private func deleteDocument(arguments: [String: Any]) throws -> [String: Any] {
        let key = try requiredProjectDocumentKey(arguments)
        let document = try documentStore.deleteDocument(
            project: key.project,
            topic: key.topic,
            documentType: key.documentType
        )

        return [
            "deleted": true,
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
        ]
    }

    private func savedItemNotePreview(_ note: CaptureCard) -> [String: Any] {
        [
            "id": note.id.uuidString.lowercased(),
            "previewText": compactPreview(note.text),
            "tags": note.tags.map(\.name),
            "createdAt": Self.iso8601Formatter.string(from: note.createdAt),
        ]
    }

    private func compactPreview(_ text: String, maxLength: Int = 120) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxLength else {
            return normalized
        }
        return String(normalized.prefix(maxLength - 1)) + "…"
    }

    private func preferredSavedItemsPresentation() -> (
        primaryLane: String,
        order: [String],
        recommendedNextStep: String
    ) {
        switch defaultSavedItemsPreference() {
        case .memoryFirst:
            return (
                primaryLane: "memory",
                order: ["memory", "stack"],
                recommendedNextStep: "For this client, present Memory first, then Stack. If the user explicitly asked for stack, prompts, pinned, copied, or the current queue, switch to Stack first instead. If the request is still ambiguous, ask whether they want Memory, Stack, or both."
            )
        case .stackFirst:
            return (
                primaryLane: "stack",
                order: ["stack", "memory"],
                recommendedNextStep: "For this client, present Stack first, then Memory. If the user explicitly asked for Memory, documents, project context, prior decisions, architecture, or plans, switch to Memory first instead. If the request is still ambiguous, ask whether they want Memory, Stack, or both."
            )
        }
    }

    private func defaultSavedItemsPreference() -> SavedItemsPreference {
        switch inferredSessionClientKind() {
        case .chatGPT, .claudeApp:
            return .memoryFirst
        case .claudeCode, .codex, .otherCLI:
            return .stackFirst
        case .unknown:
            return currentActivityContext.transport == .remoteHTTP ? .memoryFirst : .stackFirst
        }
    }

    private func inferredSessionClientKind() -> SessionClientKind {
        if currentActivityContext.transport == .remoteHTTP {
            return .chatGPT
        }

        if let configuredClientID {
            let normalizedConfiguredClientID = normalizedRoutingToken(configuredClientID)
            switch normalizedConfiguredClientID {
            case "claudecode":
                return .claudeCode
            case "codex":
                return .codex
            case "claudedesktop":
                return .claudeApp
            default:
                break
            }
        }

        guard let clientName else {
            return currentActivityContext.transport == .stdio ? .otherCLI : .unknown
        }

        let normalizedClientName = normalizedRoutingToken(clientName)
        if normalizedClientName.contains("codex") {
            return .codex
        }
        if normalizedClientName.contains("claudecode") {
            return .claudeCode
        }
        if normalizedClientName.contains("chatgpt") {
            return .chatGPT
        }
        if normalizedClientName.contains("claude") {
            return .claudeApp
        }

        return currentActivityContext.transport == .stdio ? .otherCLI : .unknown
    }

    private func normalizedRoutingToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private enum SavedItemsPreference {
        case memoryFirst
        case stackFirst
    }

    private enum SessionClientKind {
        case chatGPT
        case claudeApp
        case claudeCode
        case codex
        case otherCLI
        case unknown
    }

    private func documentSummaryDictionary(_ summary: ProjectDocumentSummary) -> [String: Any] {
        [
            "id": summary.id.uuidString.lowercased(),
            "project": summary.project,
            "topic": summary.topic,
            "documentType": summary.documentType.rawValue,
            "updatedAt": Self.iso8601Formatter.string(from: summary.updatedAt),
            "vividness": summary.vividnessTier().rawValue,
        ]
    }

    private func documentSummaryDictionary(_ document: ProjectDocument) -> [String: Any] {
        [
            "id": document.id.uuidString.lowercased(),
            "project": document.project,
            "topic": document.topic,
            "documentType": document.documentType.rawValue,
            "updatedAt": Self.iso8601Formatter.string(from: document.updatedAt),
            "vividness": document.vividnessTier().rawValue,
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
            "vividness": document.vividnessTier().rawValue,
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

    private func parseOptionalProposalCount(_ value: Any?) throws -> Int {
        guard let value else {
            return 3
        }

        if let count = value as? Int {
            guard (1...3).contains(count) else {
                throw BacktickMCPToolError(message: "maxProposals must be between 1 and 3")
            }
            return count
        }

        throw BacktickMCPToolError(message: "maxProposals must be an integer between 1 and 3")
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

    private func inferredDocumentType(
        content: String,
        userIntent: String?
    ) -> ProjectDocumentType {
        let normalizedIntent = (userIntent ?? "").lowercased()
        let normalizedContent = normalizedClassificationContent(content)

        if normalizedIntent.contains("decision") || normalizedIntent.contains("latest_decisions") {
            return .decision
        }
        if normalizedIntent.contains("plan") || normalizedIntent.contains("prd") || normalizedIntent.contains("implementation") {
            return .plan
        }
        if normalizedIntent.contains("reference") || normalizedIntent.contains("architecture") || normalizedIntent.contains("background") {
            return .reference
        }
        if normalizedIntent.contains("discussion") || normalizedIntent.contains("recap") {
            return .discussion
        }

        let decisionScore = keywordScore(in: normalizedContent, keywords: [
            "latest decisions", "we decided", "decision", "decisions", "settled", "agreed",
            "current direction", "contract", "rule", "rules", "policy", "default",
            "locked decision", "ask first", "silent save",
        ])
        let planScore = keywordScore(in: normalizedContent, keywords: [
            "next steps", "timeline", "roadmap", "requirements", "goal", "goals",
            "tasks", "milestone", "milestones", "execution plan", "implementation plan", "phase 1",
        ])
        let referenceScore = keywordScore(in: normalizedContent, keywords: [
            "architecture", "background", "constraints", "reference", "overview",
            "principles", "vocabulary", "product boundary", "what it is", "what it is not", "mental model",
        ])

        let strongSignals = [decisionScore, planScore, referenceScore].filter { $0 > 0 }.count
        if normalizedIntent.isEmpty && strongSignals >= 2 {
            return .discussion
        }

        let scores: [(ProjectDocumentType, Int)] = [
            (.decision, decisionScore),
            (.plan, planScore),
            (.reference, referenceScore),
        ]

        let maxScore = scores.map(\.1).max() ?? 0
        guard maxScore > 0 else {
            return .discussion
        }

        let topMatches = scores.filter { $0.1 == maxScore }
        if topMatches.count == 1 {
            return topMatches[0].0
        }

        return .discussion
    }

    private func inferredProposalTopic(
        content: String,
        userIntent: String?,
        preferredTopic: String?,
        documentType: ProjectDocumentType
    ) -> String {
        if let preferredTopic {
            return slugifiedTopic(preferredTopic)
        }

        if let userIntent {
            let slug = slugifiedTopic(userIntent)
            if !slug.isEmpty && !isBroadProposalTopic(slug) {
                return slug
            }
        }

        if let firstHeading = firstMarkdownHeading(in: content) {
            let slug = slugifiedTopic(firstHeading)
            if !slug.isEmpty && !isBroadProposalTopic(slug) {
                return slug
            }
        }

        switch documentType {
        case .decision:
            return "latest-decisions"
        case .plan:
            return "execution-plan"
        case .reference:
            return "reference-summary"
        case .discussion:
            return "session-summary"
        }
    }

    private func proposalWarnings(
        project: String,
        topic: String,
        documentType: ProjectDocumentType,
        content: String,
        userIntent: String?
    ) -> [String] {
        var warnings: [String] = []
        let normalizedContent = content.lowercased()
        let normalizedIntent = (userIntent ?? "").lowercased()

        if isBroadProposalTopic(topic) {
            warnings.append("topic_too_broad")
        }

        if looksTechnicallyNoisy(content) {
            warnings.append("too_much_technical_noise")
        }

        let mixedSignals = [
            normalizedContent.contains("decision"),
            normalizedContent.contains("next steps") || normalizedContent.contains("timeline"),
            normalizedContent.contains("architecture") || normalizedContent.contains("background"),
        ].filter { $0 }.count
        if mixedSignals >= 2 && normalizedIntent.isEmpty {
            warnings.append("mixed_content")
            warnings.append("classification_uncertain")
        }

        if content.count > 2500 {
            warnings.append("preview_needs_trimming")
        }

        if topic == "latest-decisions" && documentType != .decision {
            warnings.append("classification_uncertain")
        }

        var deduplicated: [String] = []
        for warning in warnings where !deduplicated.contains(warning) {
            deduplicated.append(warning)
        }
        return deduplicated
    }

    private func proposalPreview(
        content: String,
        topic: String,
        documentType: ProjectDocumentType
    ) -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmedContent.replacingOccurrences(of: "\r\n", with: "\n")

        if normalized.hasPrefix("## ") || normalized.contains("\n## ") {
            return String(normalized.prefix(1200))
        }

        let excerpt = normalized
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .prefix(800)

        return """
        ## \(proposalPreviewTitle(for: topic, documentType: documentType))

        \(excerpt)

        ## Review Notes
        - Confirm the proposed topic and document type before saving to Backtick.
        """
    }

    private func proposalPreviewTitle(
        for topic: String,
        documentType: ProjectDocumentType
    ) -> String {
        switch documentType {
        case .decision:
            return "\(humanizedTopic(topic)) Decision"
        case .plan:
            return "\(humanizedTopic(topic)) Plan"
        case .reference:
            return humanizedTopic(topic)
        case .discussion:
            return "\(humanizedTopic(topic)) Discussion"
        }
    }

    private func proposalRationale(
        topic: String,
        documentType: ProjectDocumentType,
        existingDocument: Bool,
        userIntent: String?
    ) -> String {
        let action = existingDocument
            ? "An active Backtick document already exists for this topic and type, so updating it is safer than creating a duplicate."
            : "No active Backtick document exists for this topic and type, so creating a new one is the cleanest starting point."
        let intent = userIntent?.isEmpty == false
            ? " The user intent hint nudged this toward \(documentType.rawValue)."
            : ""

        return "Proposed topic `\(topic)` as the most likely subject bucket. \(action)\(intent)"
    }

    private func keywordScore(in content: String, keywords: [String]) -> Int {
        keywords.reduce(into: 0) { score, keyword in
            if content.contains(keyword) {
                score += 1
            }
        }
    }

    private func normalizedClassificationContent(_ content: String) -> String {
        var normalized = content.lowercased()
        let replacements: [(String, String)] = [
            (#"\b(?:docs|sources|promptcue|tests)/[^\s,)]+(?:\.[a-z0-9]+)?\b"#, " "),
            (#"\b[a-z0-9._-]+\.md\b"#, " "),
            (#"\b[a-z0-9._-]+\.swift\b"#, " "),
            (#"`[^`]+`"#, " "),
        ]

        for (pattern, replacement) in replacements {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return normalized
    }

    private func looksTechnicallyNoisy(_ content: String) -> Bool {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let noisyLineCount = lines.filter { line in
            let value = String(line)
            return value.contains("```")
                || value.contains("$ ")
                || value.contains("xcodebuild")
                || value.contains("swift test")
                || value.contains("git ")
                || value.contains("/") && value.contains(".swift")
        }.count

        return noisyLineCount >= 2
    }

    private func shouldSkipSaveProposal(
        content: String,
        userIntent: String?
    ) -> Bool {
        let normalizedContent = content.lowercased()
        let normalizedIntent = (userIntent ?? "").lowercased()

        if normalizedIntent.contains("do_not_save") || normalizedIntent.contains("no_save") {
            return true
        }

        let noSaveMarkers = [
            "do not save this",
            "don't save",
            "not ready to save",
            "skip saving this",
            "do not store this",
        ]
        if noSaveMarkers.contains(where: normalizedContent.contains) {
            return true
        }

        if normalizedContent.count < 120 && looksTechnicallyNoisy(content) {
            return true
        }

        if looksRoutineExecutionStatus(content)
            && (!hasDurableMemorySignals(content) || containsNegatedDurableStatement(content)) {
            return true
        }

        return false
    }

    private func looksRoutineExecutionStatus(_ content: String) -> Bool {
        let normalizedContent = content.lowercased()
        let routineSignals = [
            "xcodegen generate",
            "swift test",
            "xcodebuild",
            "build passed",
            "tests passed",
            "all tests passed",
            "app reopened",
            "reopened the app",
            "restarted the app",
            "opened the app",
            "앱 번들",
            "앱 다시 켰",
            "앱을 다시 켰",
            "테스트 통과",
            "빌드 통과",
            "다 통과",
        ]

        let routineHitCount = routineSignals.reduce(into: 0) { count, signal in
            if normalizedContent.contains(signal) {
                count += 1
            }
        }

        return routineHitCount >= 2
    }

    private func hasDurableMemorySignals(_ content: String) -> Bool {
        let normalizedContent = normalizedClassificationContent(content)
        let durableSignals = [
            "we decided", "decision is", "decisions are", "agreed", "settled", "contract", "rules",
            "policy", "scope lock", "priorities", "current direction", "must not regress",
            "architecture", "principles", "vocabulary", "product boundary", "release gate",
            "backtick memory", "memory save", "ask first", "silent save", "product model",
        ]

        return durableSignals.contains(where: normalizedContent.contains)
    }

    private func containsNegatedDurableStatement(_ content: String) -> Bool {
        let normalizedContent = normalizedClassificationContent(content)
        let negatedSignals = [
            "routine execution status",
            "just routine status",
            "does not include any lasting decision",
            "does not include any durable decision",
            "does not include any lasting",
            "no lasting decision",
            "no durable decision",
            "단순 상태 보고",
            "지속될 결정은 없다",
        ]

        return negatedSignals.contains(where: normalizedContent.contains)
    }

    private func firstMarkdownHeading(in content: String) -> String? {
        content
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("## ") })
            .map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func slugifiedTopic(_ text: String) -> String {
        let lowercased = text.lowercased()
        let replaced = lowercased.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let slug = String(replaced)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return slug.isEmpty ? "session-summary" : slug
    }

    private func humanizedTopic(_ topic: String) -> String {
        topic
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func isBroadProposalTopic(_ topic: String) -> Bool {
        [
            "backtick",
            "memory",
            "prompt",
            "discussion",
            "decision",
            "plan",
            "reference",
            "summary",
            "context",
            "general",
            "warm-memory",
            "latest-decisions",
        ].contains(topic)
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
