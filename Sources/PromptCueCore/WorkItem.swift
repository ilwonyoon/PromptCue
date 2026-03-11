import Foundation

public enum WorkItemStatus: String, Codable, CaseIterable, Sendable {
    case open
    case inProgress = "in_progress"
    case done
    case dismissed
}

public enum WorkItemCreatedBy: String, Codable, Sendable {
    case user
    case mcpAI = "mcp_ai"
}

public enum WorkItemDifficultyHint: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
}

public struct WorkItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let summary: String?
    public let repoName: String?
    public let branchName: String?
    public let status: WorkItemStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let createdBy: WorkItemCreatedBy
    public let difficultyHint: WorkItemDifficultyHint?
    public let sourceNoteCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        summary: String? = nil,
        repoName: String? = nil,
        branchName: String? = nil,
        status: WorkItemStatus = .open,
        createdAt: Date,
        updatedAt: Date? = nil,
        createdBy: WorkItemCreatedBy,
        difficultyHint: WorkItemDifficultyHint? = nil,
        sourceNoteCount: Int
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = Self.sanitizedOptional(summary)
        self.repoName = Self.sanitizedOptional(repoName)
        self.branchName = Self.sanitizedOptional(branchName)
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.createdBy = createdBy
        self.difficultyHint = difficultyHint
        self.sourceNoteCount = max(0, sourceNoteCount)
    }

    public var isResolved: Bool {
        switch status {
        case .done, .dismissed:
            return true
        case .open, .inProgress:
            return false
        }
    }

    public func updatingStatus(
        _ status: WorkItemStatus,
        updatedAt: Date = Date()
    ) -> WorkItem {
        WorkItem(
            id: id,
            title: title,
            summary: summary,
            repoName: repoName,
            branchName: branchName,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdBy: createdBy,
            difficultyHint: difficultyHint,
            sourceNoteCount: sourceNoteCount
        )
    }

    private static func sanitizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}

public extension WorkItem {
    static func manualDraft(
        from cards: [CaptureCard],
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> WorkItem? {
        let normalizedTexts = cards.map(\.text).map(Self.normalizedText(from:))
        let primaryIndex = normalizedTexts.firstIndex(where: { !$0.isEmpty }) ?? 0

        guard cards.indices.contains(primaryIndex) else {
            return nil
        }

        let primaryText = normalizedTexts[primaryIndex]
        let additionalCount = max(0, cards.count - 1)
        let titleSeed = primaryText.isEmpty ? "Captured note" : primaryText
        let title = Self.buildManualTitle(
            from: titleSeed,
            additionalCount: additionalCount
        )
        let summary = Self.buildManualSummary(
            from: cards,
            normalizedTexts: normalizedTexts,
            title: title
        )

        return WorkItem(
            id: id,
            title: title,
            summary: summary,
            repoName: Self.commonContextValue(for: cards) { $0.suggestedTarget?.repositoryName },
            branchName: Self.commonContextValue(for: cards) { $0.suggestedTarget?.branch },
            status: .open,
            createdAt: createdAt,
            createdBy: .user,
            sourceNoteCount: cards.count
        )
    }

    private static func buildManualTitle(from seed: String, additionalCount: Int) -> String {
        let suffix = additionalCount > 0 ? " + \(additionalCount) more" : ""
        let maxTitleLength = 72
        let availableLength = max(12, maxTitleLength - suffix.count)
        let truncatedSeed = truncate(seed, maxLength: availableLength)
        return "\(truncatedSeed)\(suffix)"
    }

    private static func buildManualSummary(
        from cards: [CaptureCard],
        normalizedTexts: [String],
        title: String
    ) -> String? {
        let fullTexts = cards
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !fullTexts.isEmpty else {
            return nil
        }

        if fullTexts.count > 1 {
            return fullTexts.joined(separator: "\n\n")
        }

        let normalizedTitle = normalizedText(from: title)
        let normalizedSingle = normalizedTexts.first ?? ""
        if normalizedSingle == normalizedTitle {
            return nil
        }

        return fullTexts.first
    }

    private static func commonContextValue(
        for cards: [CaptureCard],
        resolver: (CaptureCard) -> String?
    ) -> String? {
        let uniqueValues = Set(
            cards.compactMap { resolver($0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        guard uniqueValues.count == 1 else {
            return nil
        }

        return uniqueValues.first
    }

    private static func normalizedText(from text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else {
            return value
        }

        return String(value.prefix(maxLength - 1)) + "…"
    }
}
