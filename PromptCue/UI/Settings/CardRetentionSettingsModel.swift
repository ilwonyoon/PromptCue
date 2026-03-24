import Foundation
import PromptCueCore

struct CardRetentionState: Equatable {
    var isAutoExpireEnabled: Bool

    var effectiveTTL: TimeInterval? {
        isAutoExpireEnabled ? PromptCueConstants.defaultTTL : nil
    }
}

enum CardRetentionPreferences {
    private static let autoExpireEnabledKey = "cardRetention.autoExpireEnabled"

    static func load(defaults: UserDefaults = .standard) -> CardRetentionState {
        CardRetentionState(
            isAutoExpireEnabled: defaults.object(forKey: autoExpireEnabledKey) as? Bool ?? true
        )
    }

    static func save(_ state: CardRetentionState, defaults: UserDefaults = .standard) {
        defaults.set(state.isAutoExpireEnabled, forKey: autoExpireEnabledKey)
    }
}

@MainActor
final class CardRetentionSettingsModel: ObservableObject {
    @Published var isAutoExpireEnabled = false

    init() {
        refresh()
    }

    func refresh() {
        isAutoExpireEnabled = CardRetentionPreferences.load().isAutoExpireEnabled
    }

    func updateAutoExpireEnabled(_ isEnabled: Bool) {
        isAutoExpireEnabled = isEnabled
        CardRetentionPreferences.save(
            CardRetentionState(isAutoExpireEnabled: isEnabled)
        )
    }
}
