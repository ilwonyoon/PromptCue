import PromptCueCore

extension AppModel {
    var knownCaptureTagNames: [String] {
        let counts = cards.reduce(into: [String: Int]()) { partialResult, card in
            for tag in card.tags {
                partialResult[tag.name, default: 0] += 1
            }
        }

        return counts.keys.sorted { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]

            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }

            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}
