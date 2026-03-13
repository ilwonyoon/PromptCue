import Foundation

public struct CaptureCard: Codable, Identifiable, Equatable, Sendable {
    public static let ttl: TimeInterval = PromptCueConstants.defaultTTL

    public let id: UUID
    public let text: String
    public let tags: [CaptureTag]
    public let suggestedTarget: CaptureSuggestedTarget?
    public let createdAt: Date
    public let screenshotPath: String?
    public let lastCopiedAt: Date?
    public let sortOrder: Double

    public init(
        id: UUID = UUID(),
        text: String,
        tags: [CaptureTag] = [],
        suggestedTarget: CaptureSuggestedTarget? = nil,
        createdAt: Date,
        screenshotPath: String? = nil,
        lastCopiedAt: Date? = nil,
        sortOrder: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.tags = CaptureTag.deduplicatePreservingOrder(tags)
        self.suggestedTarget = suggestedTarget
        self.createdAt = createdAt
        self.screenshotPath = screenshotPath
        self.lastCopiedAt = lastCopiedAt
        self.sortOrder = sortOrder ?? createdAt.timeIntervalSinceReferenceDate
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case tags
        case suggestedTarget
        case createdAt
        case screenshotPath
        case lastCopiedAt
        case sortOrder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        tags = CaptureTag.deduplicatePreservingOrder(
            try container.decodeIfPresent([CaptureTag].self, forKey: .tags) ?? []
        )
        suggestedTarget = try container.decodeIfPresent(CaptureSuggestedTarget.self, forKey: .suggestedTarget)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        screenshotPath = try container.decodeIfPresent(String.self, forKey: .screenshotPath)
        lastCopiedAt = try container.decodeIfPresent(Date.self, forKey: .lastCopiedAt)
        sortOrder = try container.decodeIfPresent(Double.self, forKey: .sortOrder)
            ?? createdAt.timeIntervalSinceReferenceDate
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(suggestedTarget, forKey: .suggestedTarget)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(screenshotPath, forKey: .screenshotPath)
        try container.encodeIfPresent(lastCopiedAt, forKey: .lastCopiedAt)
        try container.encode(sortOrder, forKey: .sortOrder)
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

    public var visibleBodyText: String {
        guard !tags.isEmpty else {
            return text
        }

        let parseResult = CaptureTagText.parseCommittedPrefix(in: text)
        guard parseResult.tags == tags else {
            return text
        }

        return parseResult.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var visibleInlineText: String {
        guard !tags.isEmpty else {
            return text
        }

        let parseResult = CaptureTagText.parseCommittedPrefix(in: text)
        if parseResult.tags.isEmpty {
            return CaptureTagText.inlineDisplayText(tags: tags, bodyText: text)
        }

        guard parseResult.tags == tags else {
            return text
        }

        return CaptureTagText.inlineDisplayText(tags: tags, bodyText: parseResult.bodyText)
    }

    public var visibleInlineTagRanges: [NSRange] {
        guard !tags.isEmpty else {
            return []
        }

        let parseResult = CaptureTagText.parseCommittedPrefix(in: text)
        if parseResult.tags.isEmpty {
            return CaptureTagText.inlineDisplayTagRanges(tags: tags, bodyText: text)
        }

        guard parseResult.tags == tags else {
            return []
        }

        return CaptureTagText.inlineDisplayTagRanges(tags: tags, bodyText: parseResult.bodyText)
    }

    public func markCopied(at date: Date = Date()) -> CaptureCard {
        CaptureCard(
            id: id,
            text: text,
            tags: tags,
            suggestedTarget: suggestedTarget,
            createdAt: createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: date,
            sortOrder: sortOrder
        )
    }

    public func updatingSortOrder(_ sortOrder: Double) -> CaptureCard {
        CaptureCard(
            id: id,
            text: text,
            tags: tags,
            suggestedTarget: suggestedTarget,
            createdAt: createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: lastCopiedAt,
            sortOrder: sortOrder
        )
    }

    public func updatingSuggestedTarget(_ suggestedTarget: CaptureSuggestedTarget?) -> CaptureCard {
        CaptureCard(
            id: id,
            text: text,
            tags: tags,
            suggestedTarget: suggestedTarget,
            createdAt: createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: lastCopiedAt,
            sortOrder: sortOrder
        )
    }

    public func updatingContent(
        text: String,
        tags: [CaptureTag],
        suggestedTarget: CaptureSuggestedTarget?,
        screenshotPath: String?
    ) -> CaptureCard {
        CaptureCard(
            id: id,
            text: text,
            tags: tags,
            suggestedTarget: suggestedTarget,
            createdAt: createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: lastCopiedAt,
            sortOrder: sortOrder
        )
    }

    public func isExpired(
        relativeTo date: Date = Date(),
        ttl: TimeInterval = CaptureCard.ttl
    ) -> Bool {
        createdAt.addingTimeInterval(ttl) < date
    }
}
