import AppKit
import Foundation
import Sparkle

@MainActor
final class UpdateCoordinator: NSObject {
    struct Configuration: Equatable {
        let isEnabled: Bool
        let feedURL: URL?
        let publicEDKey: String?

        var canStartUpdater: Bool {
            isEnabled && feedURL != nil && !(publicEDKey?.isEmpty ?? true)
        }
    }

    enum Availability: Equatable {
        case unavailable
        case available
    }

    private let configuration: Configuration
    private let updaterController: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        let configuration = Self.configuration(from: bundle)
        self.configuration = configuration
        if configuration.canStartUpdater {
            self.updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            self.updaterController = nil
        }
        super.init()
    }

    var availability: Availability {
        updaterController == nil ? .unavailable : .available
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    static func configuration(from bundle: Bundle) -> Configuration {
        let info = bundle.infoDictionary ?? [:]
        let enabled = boolValue(for: "BacktickSparkleEnabled", in: info)
        let feedURL = urlValue(for: "SUFeedURL", in: info)
        let publicEDKey = stringValue(for: "SUPublicEDKey", in: info)

        return Configuration(
            isEnabled: enabled,
            feedURL: feedURL,
            publicEDKey: publicEDKey
        )
    }

    private static func stringValue(for key: String, in info: [String: Any]) -> String? {
        guard let rawValue = info[key] as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func urlValue(for key: String, in info: [String: Any]) -> URL? {
        guard let value = stringValue(for: key, in: info) else {
            return nil
        }
        return URL(string: value)
    }

    private static func boolValue(for key: String, in info: [String: Any]) -> Bool {
        if let number = info[key] as? NSNumber {
            return number.boolValue
        }

        guard let string = info[key] as? String else {
            return false
        }

        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes", "true", "1":
            return true
        default:
            return false
        }
    }
}
