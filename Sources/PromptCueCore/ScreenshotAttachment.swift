import Foundation

public struct ScreenshotAttachment: Equatable, Codable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}
