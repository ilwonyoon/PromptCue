import Foundation

public struct CaptureCard: Codable, Identifiable, Equatable, Sendable {
    public static let ttl: TimeInterval = PromptCueConstants.defaultTTL

    public let id: UUID
    public let text: String
    public let createdAt: Date
    public let screenshotPath: String?
    public let lastCopiedAt: Date?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date,
        screenshotPath: String? = nil,
        lastCopiedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.screenshotPath = screenshotPath
        self.lastCopiedAt = lastCopiedAt
    }

    public var isCopied: Bool {
        lastCopiedAt != nil
    }

    public var screenshotURL: URL? {
        guard let screenshotPath else {
            return nil
        }
        return URL(fileURLWithPath: screenshotPath)
    }

    public func markCopied(at date: Date = Date()) -> CaptureCard {
        CaptureCard(
            id: id,
            text: text,
            createdAt: createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: date
        )
    }

    public func isExpired(
        relativeTo date: Date = Date(),
        ttl: TimeInterval = CaptureCard.ttl
    ) -> Bool {
        createdAt.addingTimeInterval(ttl) < date
    }
}
