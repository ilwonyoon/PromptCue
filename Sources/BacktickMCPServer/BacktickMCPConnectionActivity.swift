import Foundation

struct BacktickMCPConnectionActivity: Codable, Equatable {
    enum TargetKind: String, Codable {
        case tool
        case prompt
    }

    enum Transport: String, Codable {
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
}

struct BacktickMCPConnectionActivityState: Codable, Equatable {
    let schemaVersion: Int
    let activities: [BacktickMCPConnectionActivity]
}

struct BacktickMCPConnectionContext: Equatable {
    let transport: BacktickMCPConnectionActivity.Transport
    let surface: String?

    static let stdio = BacktickMCPConnectionContext(
        transport: .stdio,
        surface: nil
    )

    static func remoteHTTP(surface: String?) -> BacktickMCPConnectionContext {
        BacktickMCPConnectionContext(
            transport: .remoteHTTP,
            surface: surface
        )
    }
}

final class BacktickMCPConnectionActivityStore {
    private static let schemaVersion = 1
    private static let maxActivityCount = 50

    private let fileManager: FileManager
    private let fileURL: URL?
    private let isEnabled: Bool

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        isEnabled: Bool = true
    ) {
        self.fileManager = fileManager
        self.isEnabled = isEnabled
        self.fileURL = isEnabled ? (fileURL ?? Self.defaultFileURL(fileManager: fileManager)) : nil
    }

    func recordSuccessfulToolCall(
        context: BacktickMCPConnectionContext,
        clientName: String?,
        clientVersion: String?,
        sessionID: String?,
        toolName: String,
        requestedToolName: String?,
        configuredClientID: String?,
        launchCommand: String?,
        launchArguments: [String]
    ) {
        recordSuccessfulTargetCall(
            context: context,
            clientName: clientName,
            clientVersion: clientVersion,
            sessionID: sessionID,
            targetKind: .tool,
            targetName: toolName,
            requestedTargetName: requestedToolName,
            toolName: toolName,
            requestedToolName: requestedToolName,
            configuredClientID: configuredClientID,
            launchCommand: launchCommand,
            launchArguments: launchArguments
        )
    }

    func recordSuccessfulPromptCall(
        context: BacktickMCPConnectionContext,
        clientName: String?,
        clientVersion: String?,
        sessionID: String?,
        promptName: String,
        configuredClientID: String?,
        launchCommand: String?,
        launchArguments: [String]
    ) {
        recordSuccessfulTargetCall(
            context: context,
            clientName: clientName,
            clientVersion: clientVersion,
            sessionID: sessionID,
            targetKind: .prompt,
            targetName: promptName,
            requestedTargetName: promptName,
            toolName: "prompt:\(promptName)",
            requestedToolName: promptName,
            configuredClientID: configuredClientID,
            launchCommand: launchCommand,
            launchArguments: launchArguments
        )
    }

    private func recordSuccessfulTargetCall(
        context: BacktickMCPConnectionContext,
        clientName: String?,
        clientVersion: String?,
        sessionID: String?,
        targetKind: BacktickMCPConnectionActivity.TargetKind,
        targetName: String,
        requestedTargetName: String?,
        toolName: String,
        requestedToolName: String?,
        configuredClientID: String?,
        launchCommand: String?,
        launchArguments: [String]
    ) {
        guard let fileURL else {
            return
        }

        let sanitizedArgs = launchArguments.map { arg in
            if arg.hasPrefix("--api-key") || arg.contains("api-key=") {
                return "--api-key=<redacted>"
            }
            return arg
        }

        let activity = BacktickMCPConnectionActivity(
            transport: context.transport,
            surface: context.surface,
            clientName: clientName,
            clientVersion: clientVersion,
            sessionID: sessionID,
            targetKind: targetKind,
            targetName: targetName,
            toolName: toolName,
            requestedToolName: requestedToolName,
            recordedAt: Date(),
            configuredClientID: configuredClientID,
            launchCommand: launchCommand,
            launchArguments: sanitizedArgs
        )

        var activities = loadState(from: fileURL)?.activities ?? []
        activities.insert(activity, at: 0)
        if activities.count > Self.maxActivityCount {
            activities = Array(activities.prefix(Self.maxActivityCount))
        }

        persist(
            BacktickMCPConnectionActivityState(
                schemaVersion: Self.schemaVersion,
                activities: activities
            ),
            to: fileURL
        )
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("PromptCue", isDirectory: true)
            .appendingPathComponent("BacktickMCPConnectionActivity.json", isDirectory: false)
    }

    private func persist(_ state: BacktickMCPConnectionActivityState, to fileURL: URL) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if #available(macOS 13.0, *) {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            } else {
                encoder.outputFormatting = [.prettyPrinted]
            }
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("BacktickMCPConnectionActivityStore persist failed: %@", error.localizedDescription)
        }
    }

    private func loadState(from fileURL: URL) -> BacktickMCPConnectionActivityState? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(BacktickMCPConnectionActivityState.self, from: data)
        } catch {
            NSLog("BacktickMCPConnectionActivityStore load failed: %@", error.localizedDescription)
            return nil
        }
    }
}
