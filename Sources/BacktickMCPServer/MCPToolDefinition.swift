import Foundation
import PromptCueCore

// MARK: - JSON Schema type representation

/// Represents the `"type"` field in a JSON Schema property.
/// Handles both single types (`"string"`) and nullable types (`["string", "null"]`).
enum MCPSchemaType: Sendable, Equatable {
    case single(String)
    case nullable(String)

    func toAny() -> Any {
        switch self {
        case .single(let value):
            return value
        case .nullable(let value):
            return [value, "null"]
        }
    }

    static let string = MCPSchemaType.single("string")
    static let boolean = MCPSchemaType.single("boolean")
    static let integer = MCPSchemaType.single("integer")
    static let object = MCPSchemaType.single("object")
    static let array = MCPSchemaType.single("array")
    static let nullableString = MCPSchemaType.nullable("string")
    static let nullableBoolean = MCPSchemaType.nullable("boolean")
    static let nullableArray = MCPSchemaType.nullable("array")
}

// MARK: - Schema property

/// A single property within a JSON Schema `"properties"` object.
struct MCPSchemaProperty: Sendable {
    let type: MCPSchemaType
    var format: String?
    var description: String?
    var enumValues: [String]?
    var items: MCPSchemaItems?
    var minimum: Int?
    var maximum: Int?
    var minItems: Int?

    func toDict() -> [String: Any] {
        var dict: [String: Any] = ["type": type.toAny()]
        if let format { dict["format"] = format }
        if let description { dict["description"] = description }
        if let enumValues { dict["enum"] = enumValues }
        if let items { dict["items"] = items.toDict() }
        if let minimum { dict["minimum"] = minimum }
        if let maximum { dict["maximum"] = maximum }
        if let minItems { dict["minItems"] = minItems }
        return dict
    }
}

/// Represents the `"items"` sub-schema within an array property.
struct MCPSchemaItems: Sendable {
    let type: MCPSchemaType
    var format: String?

    func toDict() -> [String: Any] {
        var dict: [String: Any] = ["type": type.toAny()]
        if let format { dict["format"] = format }
        return dict
    }
}

// MARK: - Input schema

/// Represents the `"inputSchema"` of an MCP tool definition.
struct MCPInputSchema: Sendable {
    let properties: [(String, MCPSchemaProperty)]
    var required: [String]?

    func toDict() -> [String: Any] {
        var dict: [String: Any] = ["type": "object"]
        var props: [String: Any] = [:]
        for (key, property) in properties {
            props[key] = property.toDict()
        }
        dict["properties"] = props
        if let required {
            dict["required"] = required
        }
        dict["additionalProperties"] = false
        return dict
    }
}

// MARK: - Tool annotations

/// Optional annotations for an MCP tool definition.
struct MCPToolAnnotations: Sendable {
    var readOnlyHint: Bool?

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let readOnlyHint { dict["readOnlyHint"] = readOnlyHint }
        return dict
    }
}

// MARK: - Tool definition

/// A type-safe representation of an MCP tool definition.
/// Replaces the previous `[String: Any]` dictionary literals.
struct MCPToolDefinition: Sendable {
    let name: String
    let description: String
    var annotations: MCPToolAnnotations?
    let inputSchema: MCPInputSchema

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "description": description,
            "inputSchema": inputSchema.toDict(),
        ]
        if let annotations {
            dict["annotations"] = annotations.toDict()
        }
        return dict
    }
}

// MARK: - Tool catalog

/// All MCP tool definitions used by BacktickMCPServerSession.
enum MCPToolCatalog {
    // MARK: - Reusable schemas

    private static func tagSchema() -> MCPSchemaProperty {
        MCPSchemaProperty(
            type: .nullableArray,
            items: MCPSchemaItems(type: .string)
        )
    }

    private static func uuidProperty() -> MCPSchemaProperty {
        MCPSchemaProperty(type: .string, format: "uuid")
    }

    private static func projectDocumentTypeSchema() -> MCPSchemaProperty {
        MCPSchemaProperty(
            type: .string,
            description: "Choose the smallest durable document shape: discussion for recap of exploration, options, and open questions; decision for settled choices and latest decisions; plan for actionable PRDs or execution briefs; and reference for durable facts, constraints, or architecture background. When a long conversation is mixed and classification is uncertain, start with one reviewed discussion doc instead of forcing a multi-doc split. None of these types are for coding-session logs, test transcripts, or git-like execution history.",
            enumValues: ProjectDocumentType.allCases.map(\.rawValue)
        )
    }

    // MARK: - Stack note tools

    static let listNotes = MCPToolDefinition(
        name: "list_notes",
        description: "List Stack notes grouped by category: pinned (permanent prompts), active (today's work), and copied (used prompts). Each group is returned separately.",
        inputSchema: MCPInputSchema(
            properties: [
                ("scope", MCPSchemaProperty(
                    type: .string,
                    description: "Optional filter for returned notes.",
                    enumValues: ["all", "active", "copied"]
                )),
            ]
        )
    )

    static let getNote = MCPToolDefinition(
        name: "get_note",
        description: "Fetch one Stack note and its copy-event history.",
        inputSchema: MCPInputSchema(
            properties: [
                ("id", uuidProperty()),
            ],
            required: ["id"]
        )
    )

    static let createNote = MCPToolDefinition(
        name: "create_note",
        description: "Create a Stack note directly in Backtick storage.",
        inputSchema: MCPInputSchema(
            properties: [
                ("text", MCPSchemaProperty(type: .string)),
                ("tags", tagSchema()),
                ("screenshotPath", MCPSchemaProperty(type: .nullableString)),
                ("isPinned", MCPSchemaProperty(
                    type: .nullableBoolean,
                    description: "Pin or unpin this note. Pinned notes never expire and sort to top."
                )),
                ("createdAt", MCPSchemaProperty(type: .string, format: "date-time")),
            ],
            required: ["text"]
        )
    )

    static let updateNote = MCPToolDefinition(
        name: "update_note",
        description: "Update Stack note text or metadata without copying it.",
        inputSchema: MCPInputSchema(
            properties: [
                ("id", uuidProperty()),
                ("text", MCPSchemaProperty(type: .nullableString)),
                ("tags", tagSchema()),
                ("screenshotPath", MCPSchemaProperty(type: .nullableString)),
                ("isPinned", MCPSchemaProperty(
                    type: .nullableBoolean,
                    description: "Pin or unpin this note. Pinned notes never expire and sort to top."
                )),
            ],
            required: ["id"]
        )
    )

    static let deleteNote = MCPToolDefinition(
        name: "delete_note",
        description: "Delete a Stack note directly from Backtick storage.",
        inputSchema: MCPInputSchema(
            properties: [
                ("id", uuidProperty()),
            ],
            required: ["id"]
        )
    )

    static let markNotesExecuted = MCPToolDefinition(
        name: "mark_notes_executed",
        description: "Mark Stack notes executed by recording copied state and CopyEvent rows.",
        inputSchema: MCPInputSchema(
            properties: [
                ("noteIDs", MCPSchemaProperty(
                    type: .array,
                    items: MCPSchemaItems(type: .string, format: "uuid"),
                    minItems: 1
                )),
                ("sessionID", MCPSchemaProperty(type: .nullableString)),
                ("copiedAt", MCPSchemaProperty(type: .string, format: "date-time")),
            ],
            required: ["noteIDs"]
        )
    )

    static let classifyNotes = MCPToolDefinition(
        name: "classify_notes",
        description: "Group Stack notes by metadata such as repository, session, or app.",
        inputSchema: MCPInputSchema(
            properties: [
                ("scope", MCPSchemaProperty(
                    type: .string,
                    description: "Filter scope. Default: active.",
                    enumValues: ["all", "active", "copied"]
                )),
                ("groupBy", MCPSchemaProperty(
                    type: .string,
                    description: "Grouping dimension. Default: repository.",
                    enumValues: ["repository", "session", "app"]
                )),
            ]
        )
    )

    static let groupNotes = MCPToolDefinition(
        name: "group_notes",
        description: "Merge multiple Stack notes into one grouped note. Source notes remain active unless archived explicitly.",
        inputSchema: MCPInputSchema(
            properties: [
                ("noteIDs", MCPSchemaProperty(
                    type: .array,
                    description: "IDs of source notes to merge, in desired order.",
                    items: MCPSchemaItems(type: .string, format: "uuid"),
                    minItems: 1
                )),
                ("title", MCPSchemaProperty(
                    type: .string,
                    description: "Title for the grouped note."
                )),
                ("separator", MCPSchemaProperty(
                    type: .string,
                    description: "Text separator between source notes. Default: ---"
                )),
                ("archiveSources", MCPSchemaProperty(
                    type: .boolean,
                    description: "When true, marks source notes as executed after grouping. Default: false."
                )),
                ("sessionID", MCPSchemaProperty(
                    type: .nullableString,
                    description: "Optional session identifier for archived copy events."
                )),
            ],
            required: ["noteIDs", "title"]
        )
    )

    // MARK: - Utility tools

    static let status = MCPToolDefinition(
        name: "status",
        description: "Report the current Backtick MCP app version, build, helper path, and tool/prompt surface version so clients can verify they are on the latest connector surface.",
        annotations: MCPToolAnnotations(readOnlyHint: true),
        inputSchema: MCPInputSchema(properties: [])
    )

    static let getStarted = MCPToolDefinition(
        name: "get_started",
        description: "Introduction to Backtick. Call this when the user first connects or asks what Backtick can do. Returns a guide explaining all available tools and example usage.",
        annotations: MCPToolAnnotations(readOnlyHint: true),
        inputSchema: MCPInputSchema(properties: [])
    )

    static let listSavedItems = MCPToolDefinition(
        name: "list_saved_items",
        description: "Read-only overview across Backtick Memory documents and Stack notes. Use this first for generic requests like 'Backtick notes' or 'what do I have in Backtick', then follow the current client priority and clarify Memory, Stack, or both.",
        annotations: MCPToolAnnotations(readOnlyHint: true),
        inputSchema: MCPInputSchema(properties: [])
    )

    // MARK: - Document tools

    static let listDocuments = MCPToolDefinition(
        name: "list_documents",
        description: "List durable project documents for lightweight discovery, sorted by vividness (most vivid first). Dormant documents are excluded by default to keep the list focused \u{2014} set include_dormant to true when the user explicitly asks for older memories. Each document includes a vividness tier (vivid, fading, dormant) and a dormantCount showing how many documents were filtered out.",
        inputSchema: MCPInputSchema(
            properties: [
                ("project", MCPSchemaProperty(
                    type: .nullableString,
                    description: "Optional project filter. Omit to list all current documents."
                )),
                ("include_dormant", MCPSchemaProperty(
                    type: .boolean,
                    description: "Include dormant (long-unused) documents. Defaults to false."
                )),
            ]
        )
    )

    static let recallDocument = MCPToolDefinition(
        name: "recall_document",
        description: "Load one durable project document by project, topic, and documentType. Use this proactively when the current discussion likely depends on prior saved context so the user does not have to restate durable information. Recall before answering when durable context matters, and recall before save_document or update_document when you need to amend an existing doc instead of creating a duplicate or overwriting the wrong content. When deciding whether a long discussion should update an existing doc, recall first before proposing the write.",
        inputSchema: MCPInputSchema(
            properties: [
                ("project", MCPSchemaProperty(type: .string)),
                ("topic", MCPSchemaProperty(type: .string)),
                ("documentType", projectDocumentTypeSchema()),
            ],
            required: ["project", "topic", "documentType"]
        )
    )

    static let proposeDocumentSaves = MCPToolDefinition(
        name: "propose_document_saves",
        description: "Recommended before save_document or update_document when the user has not already specified the exact document structure. Draft reviewed save proposals without writing anything yet. Focus on decisions, direction changes, and topics discussed at length \u{2014} skip anything only briefly mentioned. Each proposal includes a one-line summary so the user can quickly select which to keep. Good: list_documents or recall_document when needed, then propose_document_saves, then ask the user in natural language. Skip this step when the user has already provided the exact project, topic, documentType, and content to save.",
        inputSchema: MCPInputSchema(
            properties: [
                ("project", MCPSchemaProperty(type: .string)),
                ("content", MCPSchemaProperty(type: .string)),
                ("userIntent", MCPSchemaProperty(
                    type: .nullableString,
                    description: "Optional hint such as latest_decisions, plan, architecture, or recap."
                )),
                ("preferredTopic", MCPSchemaProperty(
                    type: .nullableString,
                    description: "Optional preferred topic if the user already has a likely subject in mind."
                )),
                ("maxProposals", MCPSchemaProperty(
                    type: .integer,
                    description: "Maximum number of proposals to return. Defaults to 3.",
                    minimum: 1,
                    maximum: 3
                )),
            ],
            required: ["project", "content"]
        )
    )

    static let saveDocument = MCPToolDefinition(
        name: "save_document",
        description: "Save a durable project document. Prefer calling propose_document_saves first when the user has not specified the exact structure, but skip the proposal step when the user has already provided the project, topic, documentType, and content explicitly. List or recall existing docs first to update instead of creating duplicates. Store structured markdown with ## headers (at least two sections, 200+ characters). Map actionable PRDs to plan, settled choices to decision, exploration recaps to discussion, durable facts to reference. Do not save coding-session logs, file-by-file change logs, shell or test-command transcripts, or git-like execution history.",
        inputSchema: MCPInputSchema(
            properties: [
                ("project", MCPSchemaProperty(type: .string)),
                ("topic", MCPSchemaProperty(type: .string)),
                ("documentType", projectDocumentTypeSchema()),
                ("content", MCPSchemaProperty(type: .string)),
            ],
            required: ["project", "topic", "documentType", "content"]
        )
    )

    static let updateDocument = MCPToolDefinition(
        name: "update_document",
        description: "Partially update an existing durable project document by appending a new ## section, replacing one ## section, or deleting one ## section. Prefer this over save_document for small changes such as latest-decision deltas or one section of an existing plan, decision, discussion, or reference doc. Good: recall the current doc, propose the update, wait for confirmation, then update_document. Bad: update_document directly because an old doc probably exists. Always list or recall first so you update the right project/topic/documentType document. When summarizing a long discussion, do not jump straight into updating multiple docs unless the user has confirmed the proposed split; under uncertainty, prefer one reviewed discussion doc first. Do not use this to append coding-session logs, file-by-file change logs, shell or test-command transcripts, or git-like execution history; use it only for durable context changes that future AI sessions should remember.",
        inputSchema: MCPInputSchema(
            properties: [
                ("project", MCPSchemaProperty(type: .string)),
                ("topic", MCPSchemaProperty(type: .string)),
                ("documentType", projectDocumentTypeSchema()),
                ("action", MCPSchemaProperty(
                    type: .string,
                    enumValues: ProjectDocumentUpdateAction.allCases.map(\.rawValue)
                )),
                ("section", MCPSchemaProperty(
                    type: .nullableString,
                    description: "Required for replace_section and delete_section. Use the exact ## header text without the leading ##."
                )),
                ("content", MCPSchemaProperty(
                    type: .nullableString,
                    description: "For append, provide a markdown fragment that starts with a ## header. For replace_section, provide either only the new body text for the named section (without the ## header) or a full replacement ## section block; both replace the matched section."
                )),
            ],
            required: ["project", "topic", "documentType", "action"]
        )
    )

    static let deleteDocument = MCPToolDefinition(
        name: "delete_document",
        description: "Permanently delete a durable project document. Use this to remove documents that are no longer needed, such as test data or obsolete decisions. Requires the exact project, topic, and documentType to identify the document. List documents first if unsure which document to delete.",
        inputSchema: MCPInputSchema(
            properties: [
                ("project", MCPSchemaProperty(type: .string)),
                ("topic", MCPSchemaProperty(type: .string)),
                ("documentType", projectDocumentTypeSchema()),
            ],
            required: ["project", "topic", "documentType"]
        )
    )

    // MARK: - Full catalog

    static let all: [MCPToolDefinition] = [
        status,
        listNotes,
        getNote,
        createNote,
        updateNote,
        deleteNote,
        markNotesExecuted,
        classifyNotes,
        groupNotes,
        getStarted,
        listSavedItems,
        listDocuments,
        recallDocument,
        proposeDocumentSaves,
        saveDocument,
        updateDocument,
        deleteDocument,
    ]
}
