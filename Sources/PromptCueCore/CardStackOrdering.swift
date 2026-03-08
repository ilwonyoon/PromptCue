import Foundation

public enum CardStackOrdering {
    public static func sort(_ cards: [CaptureCard]) -> [CaptureCard] {
        cards.sorted(by: compare)
    }

    private static func compare(_ lhs: CaptureCard, _ rhs: CaptureCard) -> Bool {
        switch (lhs.lastCopiedAt, rhs.lastCopiedAt) {
        case (nil, nil):
            return compareByFreshPriority(lhs, rhs)
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case let (lhsCopiedAt?, rhsCopiedAt?):
            if lhsCopiedAt != rhsCopiedAt {
                return lhsCopiedAt < rhsCopiedAt
            }

            return compareByFreshPriority(lhs, rhs)
        }
    }

    private static func compareByFreshPriority(_ lhs: CaptureCard, _ rhs: CaptureCard) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
