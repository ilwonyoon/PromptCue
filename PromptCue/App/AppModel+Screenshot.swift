import Foundation

extension AppModel {
    var showsRecentScreenshotSlot: Bool {
        switch recentScreenshotState {
        case .detected, .previewReady:
            return true
        case .idle, .expired, .consumed:
            return false
        }
    }

    var showsRecentScreenshotPlaceholder: Bool {
        switch recentScreenshotState {
        case .detected, .previewReady(_, _, .loading):
            return true
        case .idle, .previewReady(_, _, .ready), .expired, .consumed:
            return false
        }
    }

    var recentScreenshotPreviewURL: URL? {
        switch recentScreenshotState {
        case .previewReady(_, let cacheURL, .ready):
            return cacheURL
        case .idle, .detected, .previewReady(_, _, .loading), .expired, .consumed:
            return nil
        }
    }

    func refreshPendingScreenshot() {
        if hasSeededCaptureSession {
            draftRecentScreenshotStateOverride = nil
        }
        ensureRecentScreenshotCoordinatorStarted()
        recentScreenshotCoordinator.prepareForCaptureSession()
        recentScreenshotCoordinator.suspendExpiration()
        syncRecentScreenshotState()
    }

    func dismissPendingScreenshot() {
        if draftRecentScreenshotStateOverride != nil {
            draftRecentScreenshotStateOverride = .idle
            syncRecentScreenshotState()
            return
        }

        recentScreenshotCoordinator.dismissCurrent()
        syncRecentScreenshotState()
    }

    func ensureRecentScreenshotCoordinatorStarted() {
        guard !hasStartedRecentScreenshotCoordinator else {
            return
        }

        recentScreenshotCoordinator.start()
        hasStartedRecentScreenshotCoordinator = true
        applyRecentScreenshotState(recentScreenshotCoordinator.state)
    }

    func syncRecentScreenshotState() {
        applyRecentScreenshotState(draftRecentScreenshotStateOverride ?? recentScreenshotCoordinator.state)
    }

    func applyRecentScreenshotState(_ state: RecentScreenshotState) {
        recentScreenshotState = state
    }
}
