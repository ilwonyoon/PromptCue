import Foundation

enum RecentScreenshotThumbnailState: Equatable, Sendable {
    case loading
    case ready
}

enum RecentScreenshotObservationEvent: Equatable, Sendable {
    case authorizedDirectoryContentsChanged
    case authorizedDirectoryConfigurationChanged

    var impliesImmediateScreenshotSignal: Bool {
        false
    }
}

enum RecentScreenshotState: Equatable, Sendable {
    case idle
    case detected(sessionID: UUID, detectedAt: Date)
    case previewReady(sessionID: UUID, cacheURL: URL, thumbnailState: RecentScreenshotThumbnailState)
    case expired(sessionID: UUID)
    case consumed(sessionID: UUID)

    var sessionID: UUID? {
        switch self {
        case .idle:
            return nil
        case .detected(let sessionID, _):
            return sessionID
        case .previewReady(let sessionID, _, _):
            return sessionID
        case .expired(let sessionID):
            return sessionID
        case .consumed(let sessionID):
            return sessionID
        }
    }

    var showsCaptureSlot: Bool {
        switch self {
        case .detected, .previewReady:
            return true
        case .idle, .expired, .consumed:
            return false
        }
    }

    var previewCacheURL: URL? {
        switch self {
        case .previewReady(_, let cacheURL, _):
            return cacheURL
        case .idle, .detected, .expired, .consumed:
            return nil
        }
    }

    var isPreviewLoading: Bool {
        switch self {
        case .detected:
            return true
        case .previewReady(_, _, let thumbnailState):
            return thumbnailState == .loading
        case .idle, .expired, .consumed:
            return false
        }
    }
}

@MainActor
protocol RecentScreenshotCoordinating: AnyObject {
    var state: RecentScreenshotState { get }
    var onStateChange: ((RecentScreenshotState) -> Void)? { get set }

    func start()
    func stop()
    func prepareForCaptureSession()
    func refreshNow()
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL?
    func consumeCurrent()
    func dismissCurrent()
}

extension RecentScreenshotCoordinating {
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? {
        switch state {
        case .previewReady(_, let cacheURL, _):
            return cacheURL
        case .idle, .detected, .expired, .consumed:
            return nil
        }
    }
}
