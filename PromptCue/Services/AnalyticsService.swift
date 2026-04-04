import Foundation
import TelemetryDeck
import PromptCueCore

private let bundledTelemetryDeckAppID = "F4233BDD-165C-4AB1-A88A-E883D8201965"

/// Minimal privacy-first KPI bridge for the first DMG launch.
///
/// Analytics stay fully disabled until a valid TelemetryDeck App ID is present.
/// MCP usage is bridged from the existing connection-activity log so the helper
/// does not need its own analytics dependency.
@MainActor
final class AnalyticsService {
    enum CopyMode: String {
        case single
        case raw
        case multi
    }

    enum MemorySaveMode: String {
        case create
        case update
    }

    enum MemorySaveSource: String {
        case app
        case mcp
    }

    static let shared = AnalyticsService()

    private static let telemetryAppIDInfoKey = "BacktickTelemetryDeckAppID"
    private static let telemetryAppIDEnvironmentKey = "PROMPTCUE_TELEMETRYDECK_APP_ID"
    private static let enabledAtDefaultsKey = "analytics.telemetry.enabledAt"
    private static let seenMCPConnectionKeysDefaultsKey = "analytics.telemetry.seenMCPConnections"
    private static let seenMCPActivityFingerprintsDefaultsKey = "analytics.telemetry.seenMCPActivities"
    private static let maxRememberedConnectionKeys = 32
    private static let maxRememberedActivityFingerprints = 200
    private static let iso8601Formatter = makeDateFormatter()

    private let infoDictionaryProvider: () -> [String: Any]
    private let environmentProvider: () -> [String: String]
    private let bundledAppID: String?
    private let userDefaults: UserDefaults
    private let nowProvider: () -> Date
    private let initializeTelemetryDeck: (String) -> Void
    private let sendSignal: (String, [String: String]) -> Void

    private(set) var isConfigured = false

    init(
        infoDictionaryProvider: @escaping () -> [String: Any] = { Bundle.main.infoDictionary ?? [:] },
        environmentProvider: @escaping () -> [String: String] = { ProcessInfo.processInfo.environment },
        bundledAppID: String? = bundledTelemetryDeckAppID,
        userDefaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = Date.init,
        initializeTelemetryDeck: @escaping (String) -> Void = { appID in
            let config = TelemetryDeck.Config(appID: appID)
            TelemetryDeck.initialize(config: config)
        },
        sendSignal: @escaping (String, [String: String]) -> Void = { name, parameters in
            TelemetryDeck.signal(name, parameters: parameters)
        }
    ) {
        self.infoDictionaryProvider = infoDictionaryProvider
        self.environmentProvider = environmentProvider
        self.bundledAppID = bundledAppID
        self.userDefaults = userDefaults
        self.nowProvider = nowProvider
        self.initializeTelemetryDeck = initializeTelemetryDeck
        self.sendSignal = sendSignal
    }

    func configure() {
        guard !isConfigured, let telemetryAppID = resolvedTelemetryAppID() else {
            return
        }

        initializeTelemetryDeck(telemetryAppID)
        if userDefaults.object(forKey: Self.enabledAtDefaultsKey) == nil {
            userDefaults.set(nowProvider(), forKey: Self.enabledAtDefaultsKey)
        }
        isConfigured = true
    }

    func trackCaptureSubmitted(hasScreenshot: Bool, isEdit: Bool, textLength: Int) {
        send(
            "capture.submitted",
            with: [
                "hasScreenshot": "\(hasScreenshot)",
                "isEdit": "\(isEdit)",
                "textLengthBucket": textLengthBucket(textLength),
            ]
        )
    }

    func trackStackOpened(promptCount: Int) {
        send(
            "stack.opened",
            with: [
                "promptCountBucket": promptCountBucket(promptCount),
            ]
        )
    }

    func trackPromptCopied(copyMode: CopyMode, cardCount: Int) {
        send(
            "prompt.copied",
            with: [
                "copyMode": copyMode.rawValue,
                "cardCountBucket": cardCountBucket(cardCount),
            ]
        )
    }

    func trackMemorySaved(
        documentType: ProjectDocumentType,
        saveMode: MemorySaveMode,
        source: MemorySaveSource
    ) {
        send(
            "memory.saved",
            with: [
                "documentType": documentType.rawValue,
                "saveMode": saveMode.rawValue,
                "source": source.rawValue,
            ]
        )
    }

    func syncMCPActivitySignals(
        activityReader: MCPConnectorConnectionActivityReading = MCPConnectorConnectionActivityStore()
    ) {
        syncMCPActivitySignals(activityReader.loadActivities())
    }

    func syncMCPActivitySignals(_ activities: [MCPConnectorConnectionActivity]) {
        guard isConfigured,
              let enabledAt = userDefaults.object(forKey: Self.enabledAtDefaultsKey) as? Date else {
            return
        }

        var seenConnectionKeys = Set(userDefaults.stringArray(forKey: Self.seenMCPConnectionKeysDefaultsKey) ?? [])
        var seenActivityFingerprints = Set(
            userDefaults.stringArray(forKey: Self.seenMCPActivityFingerprintsDefaultsKey) ?? []
        )

        let unseenActivities = activities
            .filter { $0.recordedAt >= enabledAt }
            .reversed()
            .filter { activity in
                !seenActivityFingerprints.contains(activityFingerprint(for: activity))
            }

        guard !unseenActivities.isEmpty else {
            return
        }

        for activity in unseenActivities {
            let activityFingerprint = activityFingerprint(for: activity)
            let connectionKey = connectionKey(for: activity)
            let surface = surfaceName(for: activity)
            let transport = transportName(for: activity)

            if !seenConnectionKeys.contains(connectionKey) {
                send(
                    "mcp.connected",
                    with: [
                        "surface": surface,
                        "transport": transport,
                    ]
                )
                seenConnectionKeys.insert(connectionKey)
            }

            send(
                "mcp.toolCallSucceeded",
                with: [
                    "surface": surface,
                    "transport": transport,
                    "toolFamily": toolFamily(for: activity.toolName),
                ]
            )

            if let memorySaveMode = memorySaveMode(for: activity.toolName) {
                send(
                    "memory.saved",
                    with: [
                        "documentType": "unknown",
                        "saveMode": memorySaveMode.rawValue,
                        "source": MemorySaveSource.mcp.rawValue,
                    ]
                )
            }

            seenActivityFingerprints.insert(activityFingerprint)
        }

        persist(
            Array(seenConnectionKeys),
            forKey: Self.seenMCPConnectionKeysDefaultsKey,
            limit: Self.maxRememberedConnectionKeys
        )
        persist(
            Array(seenActivityFingerprints),
            forKey: Self.seenMCPActivityFingerprintsDefaultsKey,
            limit: Self.maxRememberedActivityFingerprints
        )
    }

    private func send(_ signalName: String, with parameters: [String: String] = [:]) {
        guard isConfigured else {
            return
        }

        sendSignal(signalName, parameters)
    }

    private func resolvedTelemetryAppID() -> String? {
        let environmentValues = environmentProvider()
        let infoDictionary = infoDictionaryProvider()
        let candidates = [
            environmentValues[Self.telemetryAppIDEnvironmentKey],
            infoDictionary[Self.telemetryAppIDInfoKey] as? String,
            bundledAppID,
        ]

        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  UUID(uuidString: trimmed) != nil else {
                continue
            }
            return trimmed
        }

        return nil
    }

    private func textLengthBucket(_ length: Int) -> String {
        switch length {
        case 0: return "empty"
        case 1..<50: return "short"
        case 50..<200: return "medium"
        case 200..<500: return "long"
        default: return "veryLong"
        }
    }

    private func promptCountBucket(_ count: Int) -> String {
        switch count {
        case 0: return "empty"
        case 1: return "1"
        case 2...5: return "2to5"
        case 6...20: return "6to20"
        default: return "21plus"
        }
    }

    private func cardCountBucket(_ count: Int) -> String {
        switch count {
        case 1: return "1"
        case 2...3: return "2to3"
        case 4...10: return "4to10"
        default: return "11plus"
        }
    }

    private func connectionKey(for activity: MCPConnectorConnectionActivity) -> String {
        "\(transportName(for: activity))|\(surfaceName(for: activity))"
    }

    private func activityFingerprint(for activity: MCPConnectorConnectionActivity) -> String {
        [
            Self.iso8601Formatter.string(from: activity.recordedAt),
            activity.transport.rawValue,
            activity.surface ?? "",
            activity.clientName ?? "",
            activity.configuredClientID ?? "",
            activity.launchCommand ?? "",
            activity.launchArguments?.joined(separator: "\u{1f}") ?? "",
            activity.toolName,
            activity.requestedToolName ?? "",
        ].joined(separator: "|")
    }

    private func transportName(for activity: MCPConnectorConnectionActivity) -> String {
        activity.transport.rawValue
    }

    private func surfaceName(for activity: MCPConnectorConnectionActivity) -> String {
        switch activity.transport {
        case .remoteHTTP:
            switch activity.surface?.lowercased() {
            case "web": return "chatgpt_web"
            case "macos": return "chatgpt_macos"
            case "iphone": return "chatgpt_iphone"
            case "ipad": return "chatgpt_ipad"
            case "android": return "chatgpt_android"
            default: return "chatgpt_unknown"
            }
        case .stdio:
            let configuredClient = activity.configuredClientID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if configuredClient == "codex" {
                return "codex"
            }
            if configuredClient == "claudecode" {
                return "claude_code"
            }
            if configuredClient == "claudedesktop" {
                return "claude_desktop"
            }

            let normalizedClientName = activity.clientName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalizedClientName?.contains("codex") == true {
                return "codex"
            }
            if normalizedClientName?.contains("claude-code") == true
                || normalizedClientName?.contains("claude code") == true {
                return "claude_code"
            }
            if normalizedClientName?.contains("claude") == true {
                return "claude_desktop"
            }

            return "stdio_unknown"
        }
    }

    private func toolFamily(for toolName: String) -> String {
        let normalizedToolName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalizedToolName {
        case "backtick_list_docs", "backtick_recall_doc", "backtick_propose_save", "backtick_save_doc", "backtick_update_doc", "backtick_delete_doc",
            "list_documents", "recall_document", "propose_document_saves", "save_document", "update_document", "delete_document":
            return "memory"
        case "backtick_status", "status", "backtick_workflow", "workflow":
            return "connector"
        case "backtick_list_notes", "backtick_get_note", "backtick_create_note", "backtick_update_note", "backtick_delete_note",
            "backtick_complete_notes", "backtick_classify_notes", "backtick_group_notes",
            "list_notes", "get_note", "create_note", "update_note", "delete_note", "mark_notes_executed", "classify_notes", "group_notes":
            return "stack"
        default:
            return "other"
        }
    }

    private func memorySaveMode(for toolName: String) -> MemorySaveMode? {
        let normalizedToolName = toolName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalizedToolName {
        case "backtick_save_doc", "save_document":
            return .create
        case "backtick_update_doc", "update_document":
            return .update
        default:
            return nil
        }
    }

    private func persist(_ values: [String], forKey key: String, limit: Int) {
        let limitedValues = Array(values.sorted().suffix(limit))
        userDefaults.set(limitedValues, forKey: key)
    }

    private static func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
