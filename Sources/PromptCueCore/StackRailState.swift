import Foundation

public enum StackRailFilter: String, CaseIterable, Codable, Equatable, Sendable {
    case all
    case onStage
    case offstage

    public var title: String {
        switch self {
        case .all:
            return "All"
        case .onStage:
            return "On Stage"
        case .offstage:
            return "Offstage"
        }
    }
}

public struct StackRailState: Equatable, Sendable {
    public let activeCount: Int
    public let copiedCount: Int
    public let stagedCount: Int
    public let filter: StackRailFilter

    public init(
        activeCount: Int,
        copiedCount: Int,
        stagedCount: Int,
        filter: StackRailFilter = .all
    ) {
        self.activeCount = max(0, activeCount)
        self.copiedCount = max(0, copiedCount)
        self.stagedCount = max(0, stagedCount)
        self.filter = filter
    }

    public var summaryLabel: String {
        "\(activeCount) on stage · \(copiedCount) offstage"
    }

    public var actionFeedbackLabel: String? {
        guard stagedCount > 0 else {
            return nil
        }

        return "\(stagedCount) Copied"
    }

    public var showsActiveCards: Bool {
        filter != .offstage
    }

    public var showsCopiedCards: Bool {
        filter != .onStage
    }

    public var forcesExpandedCopiedSection: Bool {
        filter == .offstage
    }
}
