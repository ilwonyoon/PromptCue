import Foundation

enum AppTiming {
    static let recentScreenshotMaxAge: TimeInterval = 30
    static let recentScreenshotPlaceholderGrace: TimeInterval = 1.5
    static let recentScreenshotSubmitResolveTimeout: TimeInterval = 0.8
    static let captureSubmissionFlushTimeout: TimeInterval = 1.0
}
