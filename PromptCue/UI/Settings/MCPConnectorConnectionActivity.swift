import Foundation

struct MCPConnectorConnectionActivity: Decodable, Equatable {
    enum TargetKind: String, Decodable {
        case tool
        case prompt
    }

    enum Transport: String, Decodable {
        case stdio
        case remoteHTTP = "remote_http"
    }

    let transport: Transport
    let surface: String?
    let clientName: String?
    let clientVersion: String?
    let sessionID: String?
    let targetKind: TargetKind?
    let targetName: String?
    let toolName: String
    let requestedToolName: String?
    let recordedAt: Date
    let configuredClientID: String?
    let launchCommand: String?
    let launchArguments: [String]?

    init(
        transport: Transport,
        surface: String?,
        clientName: String?,
        clientVersion: String?,
        sessionID: String?,
        targetKind: TargetKind? = nil,
        targetName: String? = nil,
        toolName: String,
        requestedToolName: String? = nil,
        recordedAt: Date,
        configuredClientID: String?,
        launchCommand: String?,
        launchArguments: [String]?
    ) {
        self.transport = transport
        self.surface = surface
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.sessionID = sessionID
        self.targetKind = targetKind
        self.targetName = targetName
        self.toolName = toolName
        self.requestedToolName = requestedToolName
        self.recordedAt = recordedAt
        self.configuredClientID = configuredClientID
        self.launchCommand = launchCommand
        self.launchArguments = launchArguments
    }

    var usesLegacyToolAlias: Bool {
        if targetKind == .prompt {
            return false
        }

        let requestedName = requestedToolName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let requestedName, !requestedName.isEmpty {
            return BacktickMCPToolSurface.isLegacyAlias(requestedName)
        }

        return BacktickMCPToolSurface.isLegacyAlias(toolName)
    }
}

private struct MCPConnectorConnectionActivityState: Decodable {
    let schemaVersion: Int
    let activities: [MCPConnectorConnectionActivity]
}

protocol MCPConnectorConnectionActivityReading {
    func loadActivities() -> [MCPConnectorConnectionActivity]
}

struct MCPConnectorConnectionActivityStore: MCPConnectorConnectionActivityReading {
    private let fileManager: FileManager
    private let fileURL: URL?

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func loadActivities() -> [MCPConnectorConnectionActivity] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MCPConnectorConnectionActivityState.self, from: data).activities
        } catch {
            return []
        }
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("PromptCue", isDirectory: true)
            .appendingPathComponent("BacktickMCPConnectionActivity.json", isDirectory: false)
    }
}
