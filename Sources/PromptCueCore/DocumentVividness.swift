import Foundation

/// FSRS-inspired vividness scoring for memory documents.
///
/// Each document carries a `stability` value (in days) that represents how
/// long the memory stays "vivid" before fading. Retrievability decays over
/// time following a power-law forgetting curve. Recalling a document
/// increases its stability — and recalling a faded document increases it
/// more than recalling one that is still fresh.
public enum DocumentVividness: Sendable {

    // MARK: - Constants

    public static let defaultStability: Double = 7.0

    /// Decay factor controlling how quickly retrievability drops.
    /// Lower values = faster decay. FSRS uses 9; we use 3 for a
    /// more aggressive curve suited to a document memory system
    /// where 6-month-old untouched documents should be dormant.
    static let decayFactor: Double = 3.0

    // MARK: - Tier

    public enum Tier: String, Codable, Sendable, CaseIterable {
        case vivid
        case fading
        case dormant
    }

    // MARK: - Retrievability

    /// Returns the current retrievability of a document (0…1).
    ///
    /// Uses the FSRS forgetting curve: `R(t) = (1 + t / (9 × S))^(−1)`
    /// where `t` is the number of days since last access and `S` is stability.
    public static func retrievability(
        daysSinceAccess: Double,
        stability: Double
    ) -> Double {
        guard stability > 0, daysSinceAccess >= 0 else {
            return 0
        }
        return pow(1.0 + daysSinceAccess / (decayFactor * stability), -1.0)
    }

    /// Convenience that derives `daysSinceAccess` from dates.
    public static func retrievability(
        lastAccessDate: Date?,
        createdAt: Date,
        stability: Double,
        now: Date = Date()
    ) -> Double {
        let referenceDate = lastAccessDate ?? createdAt
        let days = max(0, now.timeIntervalSince(referenceDate) / 86_400)
        return retrievability(daysSinceAccess: days, stability: stability)
    }

    // MARK: - Tier classification

    public static func tier(retrievability r: Double) -> Tier {
        if r >= 0.5 {
            return .vivid
        } else if r >= 0.2 {
            return .fading
        } else {
            return .dormant
        }
    }

    /// Convenience that computes tier directly from a document's fields.
    public static func tier(
        lastRecalledAt: Date?,
        createdAt: Date,
        stability: Double,
        now: Date = Date()
    ) -> Tier {
        let r = retrievability(
            lastAccessDate: lastRecalledAt,
            createdAt: createdAt,
            stability: stability,
            now: now
        )
        return tier(retrievability: r)
    }

    // MARK: - Stability update on recall

    /// Returns the new stability after a recall event.
    ///
    /// The key insight from FSRS: recalling a faded memory strengthens it
    /// more than recalling one that is still fresh. This mirrors how human
    /// memory works — successfully retrieving a difficult memory creates a
    /// stronger trace.
    public static func updatedStability(
        currentStability: Double,
        daysSinceAccess: Double
    ) -> Double {
        let r = retrievability(
            daysSinceAccess: daysSinceAccess,
            stability: currentStability
        )

        let multiplier: Double
        if r > 0.9 {
            // Still very fresh — small boost
            multiplier = 1.1
        } else if r > 0.5 {
            // Moderately faded — meaningful boost
            multiplier = 1.5
        } else if r > 0.2 {
            // Quite faded — large boost (hard recall = stronger memory)
            multiplier = 2.0
        } else {
            // Nearly forgotten — resurrect to baseline
            multiplier = 1.0
        }

        let newStability = currentStability * multiplier
        return max(newStability, defaultStability)
    }

    /// Convenience that derives `daysSinceAccess` from dates.
    public static func updatedStability(
        currentStability: Double,
        lastAccessDate: Date?,
        createdAt: Date,
        now: Date = Date()
    ) -> Double {
        let referenceDate = lastAccessDate ?? createdAt
        let days = max(0, now.timeIntervalSince(referenceDate) / 86_400)
        return updatedStability(
            currentStability: currentStability,
            daysSinceAccess: days
        )
    }
}

// MARK: - ProjectDocument convenience

extension ProjectDocument {
    public func retrievability(now: Date = Date()) -> Double {
        DocumentVividness.retrievability(
            lastAccessDate: lastRecalledAt ?? updatedAt,
            createdAt: createdAt,
            stability: stability,
            now: now
        )
    }

    public func vividnessTier(now: Date = Date()) -> DocumentVividness.Tier {
        DocumentVividness.tier(retrievability: retrievability(now: now))
    }

    /// Returns a new document with stability and recall metadata updated
    /// after a recall event. Does not mutate the original.
    public func recordingRecall(now: Date = Date()) -> ProjectDocument {
        let newStability = DocumentVividness.updatedStability(
            currentStability: stability,
            lastAccessDate: lastRecalledAt ?? updatedAt,
            createdAt: createdAt,
            now: now
        )
        var updated = self
        updated.stability = newStability
        updated.recallCount = recallCount + 1
        updated.lastRecalledAt = now
        return updated
    }
}

// MARK: - ProjectDocumentSummary convenience

extension ProjectDocumentSummary {
    public func retrievability(
        createdAt: Date? = nil,
        now: Date = Date()
    ) -> Double {
        let referenceDate = lastRecalledAt ?? (createdAt ?? updatedAt)
        let days = max(0, now.timeIntervalSince(referenceDate) / 86_400)
        return DocumentVividness.retrievability(
            daysSinceAccess: days,
            stability: stability
        )
    }

    public func vividnessTier(
        createdAt: Date? = nil,
        now: Date = Date()
    ) -> DocumentVividness.Tier {
        DocumentVividness.tier(retrievability: retrievability(
            createdAt: createdAt,
            now: now
        ))
    }
}
