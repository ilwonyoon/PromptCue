import Foundation

enum ScreenshotFolderAccessState: Equatable, Sendable {
    case notConfigured
    case connected(url: URL, displayPath: String)
    case needsReconnect(lastKnownDisplayPath: String)
}
