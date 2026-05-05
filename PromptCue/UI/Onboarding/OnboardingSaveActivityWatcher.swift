import Foundation

/// Polls the BacktickMCP connection activity log for the first save-related
/// tool call after onboarding starts watching. Surfaces a one-shot signal so
/// the UI can transition to a celebratory state without re-firing.
@MainActor
final class OnboardingSaveActivityWatcher: ObservableObject {
    @Published private(set) var detectedSave: DetectedSave?
    @Published private(set) var isWatching = false

    struct DetectedSave: Equatable {
        let toolName: String
        let clientName: String?
        let recordedAt: Date
    }

    private let store: MCPConnectorConnectionActivityReading
    private var timer: Timer?
    private var startedAt: Date?

    private static let saveToolNames: Set<String> = [
        "backtick_save_doc",
        "backtick_propose_save",
        "backtick_update_doc",
    ]

    init(store: MCPConnectorConnectionActivityReading = MCPConnectorConnectionActivityStore()) {
        self.store = store
    }

    func start() {
        guard !isWatching else { return }
        isWatching = true
        detectedSave = nil
        startedAt = Date()

        // Fire once immediately, then every 3s.
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isWatching = false
    }

    private func poll() {
        guard let startedAt else { return }

        let activities = store.loadActivities()
        let match = activities.first { activity in
            activity.recordedAt >= startedAt
                && Self.saveToolNames.contains(activity.toolName)
        }

        if let match {
            detectedSave = DetectedSave(
                toolName: match.toolName,
                clientName: match.clientName,
                recordedAt: match.recordedAt
            )
            stop()
        }
    }

    deinit {
        timer?.invalidate()
    }
}
