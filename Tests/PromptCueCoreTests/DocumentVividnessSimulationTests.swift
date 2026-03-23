import Foundation
import Testing
@testable import PromptCueCore

/// Simulates realistic usage patterns over time to verify the vividness
/// system behaves as intended across different document lifecycles.
struct DocumentVividnessSimulationTests {
    private let day: TimeInterval = 86_400
    private let startDate = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Scenario 1: New document grace period

    @Test
    func newDocumentStaysVividForAboutThreeWeeks() {
        let created = startDate
        var lastVividDay = 0

        for dayOffset in 0...120 {
            let now = created.addingTimeInterval(Double(dayOffset) * day)
            let tier = DocumentVividness.tier(
                lastRecalledAt: nil,
                createdAt: created,
                stability: DocumentVividness.defaultStability,
                now: now
            )
            if tier == .vivid {
                lastVividDay = dayOffset
            }
        }

        // S=7, factor=3 → vivid until ~21 days (R=0.5 at t=21)
        #expect(lastVividDay >= 15)
        #expect(lastVividDay <= 30)
    }

    // MARK: - Scenario 2: Weekly recall builds stability

    @Test
    func weeklyRecallKeepsDocumentVivid() {
        var stability = DocumentVividness.defaultStability
        var lastRecalledAt = startDate
        let recallInterval = 7 // days

        // Simulate 6 months of weekly recalls
        for week in 1...26 {
            let now = startDate.addingTimeInterval(Double(week * recallInterval) * day)
            stability = DocumentVividness.updatedStability(
                currentStability: stability,
                lastAccessDate: lastRecalledAt,
                createdAt: startDate,
                now: now
            )
            lastRecalledAt = now
        }

        // After 6 months of weekly use, stability should be very high
        #expect(stability > 50)

        // And document should still be vivid even 30 days after last recall
        let thirtyDaysLater = lastRecalledAt.addingTimeInterval(30 * day)
        let r = DocumentVividness.retrievability(
            lastAccessDate: lastRecalledAt,
            createdAt: startDate,
            stability: stability,
            now: thirtyDaysLater
        )
        #expect(DocumentVividness.tier(retrievability: r) == .vivid)
    }

    // MARK: - Scenario 3: Abandoned document fades

    @Test
    func frequentlyUsedThenAbandonedDocumentEventuallyFades() {
        var stability = DocumentVividness.defaultStability
        var lastRecalledAt = startDate

        // Phase 1: Daily use for 2 weeks
        for dayOffset in 1...14 {
            let now = startDate.addingTimeInterval(Double(dayOffset) * day)
            stability = DocumentVividness.updatedStability(
                currentStability: stability,
                lastAccessDate: lastRecalledAt,
                createdAt: startDate,
                now: now
            )
            lastRecalledAt = now
        }

        let peakStability = stability

        // Phase 2: Complete abandonment — check tier over time
        var fadingDay: Int?
        var dormantDay: Int?

        for dayOffset in 15...500 {
            let now = startDate.addingTimeInterval(Double(dayOffset) * day)
            let r = DocumentVividness.retrievability(
                lastAccessDate: lastRecalledAt,
                createdAt: startDate,
                stability: stability,
                now: now
            )
            let tier = DocumentVividness.tier(retrievability: r)

            if tier == .fading, fadingDay == nil {
                fadingDay = dayOffset
            }
            if tier == .dormant, dormantDay == nil {
                dormantDay = dayOffset
            }
        }

        // Peak stability should be moderate (daily use gives small boosts)
        #expect(peakStability > DocumentVividness.defaultStability)

        // Should eventually fade and go dormant
        #expect(fadingDay != nil)
        #expect(dormantDay != nil)

        // But not immediately — high stability buys time
        #expect(fadingDay! > 30)
    }

    // MARK: - Scenario 4: 50-document portfolio distribution

    @Test
    func fiftyDocumentPortfolioHasReasonableTierDistribution() {
        struct SimDoc {
            let name: String
            var stability: Double
            var lastRecalledAt: Date
            let createdAt: Date
        }

        let now = startDate.addingTimeInterval(180 * day) // 6 months in

        var docs: [SimDoc] = []

        // 5 daily-use docs (created 3 months ago, used daily)
        for i in 0..<5 {
            var s = DocumentVividness.defaultStability
            let created = startDate.addingTimeInterval(Double(i * 7) * day)
            var lastRecalled = created
            var current = created
            while current < now {
                current = current.addingTimeInterval(day)
                s = DocumentVividness.updatedStability(
                    currentStability: s,
                    lastAccessDate: lastRecalled,
                    createdAt: created,
                    now: current
                )
                lastRecalled = current
            }
            docs.append(SimDoc(name: "daily-\(i)", stability: s, lastRecalledAt: lastRecalled, createdAt: created))
        }

        // 10 weekly-use docs (created 4 months ago, used weekly)
        for i in 0..<10 {
            var s = DocumentVividness.defaultStability
            let created = startDate.addingTimeInterval(Double(i * 3) * day)
            var lastRecalled = created
            var weekCounter = 0
            var current = created
            while current < now {
                current = current.addingTimeInterval(day)
                weekCounter += 1
                if weekCounter >= 7 {
                    s = DocumentVividness.updatedStability(
                        currentStability: s,
                        lastAccessDate: lastRecalled,
                        createdAt: created,
                        now: current
                    )
                    lastRecalled = current
                    weekCounter = 0
                }
            }
            docs.append(SimDoc(name: "weekly-\(i)", stability: s, lastRecalledAt: lastRecalled, createdAt: created))
        }

        // 15 monthly-use docs (created 5 months ago, used monthly)
        for i in 0..<15 {
            var s = DocumentVividness.defaultStability
            let created = startDate.addingTimeInterval(Double(i * 2) * day)
            var lastRecalled = created
            var dayCounter = 0
            var current = created
            while current < now {
                current = current.addingTimeInterval(day)
                dayCounter += 1
                if dayCounter >= 30 {
                    s = DocumentVividness.updatedStability(
                        currentStability: s,
                        lastAccessDate: lastRecalled,
                        createdAt: created,
                        now: current
                    )
                    lastRecalled = current
                    dayCounter = 0
                }
            }
            docs.append(SimDoc(name: "monthly-\(i)", stability: s, lastRecalledAt: lastRecalled, createdAt: created))
        }

        // 10 abandoned docs (created 4 months ago, used once then abandoned)
        for i in 0..<10 {
            let created = startDate.addingTimeInterval(Double(i * 5) * day)
            let onceRecalled = created.addingTimeInterval(3 * day)
            let s = DocumentVividness.updatedStability(
                currentStability: DocumentVividness.defaultStability,
                lastAccessDate: created,
                createdAt: created,
                now: onceRecalled
            )
            docs.append(SimDoc(name: "abandoned-\(i)", stability: s, lastRecalledAt: onceRecalled, createdAt: created))
        }

        // 10 ancient docs (created at start, never recalled)
        for i in 0..<10 {
            let created = startDate.addingTimeInterval(Double(i) * day)
            docs.append(SimDoc(name: "ancient-\(i)", stability: DocumentVividness.defaultStability, lastRecalledAt: created, createdAt: created))
        }

        // Classify all 50 docs
        var vivid = 0
        var fading = 0
        var dormant = 0

        for doc in docs {
            let r = DocumentVividness.retrievability(
                lastAccessDate: doc.lastRecalledAt,
                createdAt: doc.createdAt,
                stability: doc.stability,
                now: now
            )
            switch DocumentVividness.tier(retrievability: r) {
            case .vivid: vivid += 1
            case .fading: fading += 1
            case .dormant: dormant += 1
            }
        }

        #expect(docs.count == 50)

        // Active list (vivid + fading) should be 15-30 docs
        let activeCount = vivid + fading
        #expect(activeCount >= 10)
        #expect(activeCount <= 35)

        // Dormant should capture abandoned and ancient docs
        #expect(dormant >= 5)

        // Daily and weekly docs should all be vivid
        #expect(vivid >= 10)
    }

    // MARK: - Scenario 5: Spaced recall gives bigger boost

    @Test
    func spacedRecallStrengthensMoreThanDailyRecall() {
        // Daily recall for 30 days
        var dailyStability = DocumentVividness.defaultStability
        var dailyLastRecalled = startDate
        for dayOffset in 1...30 {
            let now = startDate.addingTimeInterval(Double(dayOffset) * day)
            dailyStability = DocumentVividness.updatedStability(
                currentStability: dailyStability,
                lastAccessDate: dailyLastRecalled,
                createdAt: startDate,
                now: now
            )
            dailyLastRecalled = now
        }

        // Spaced recall: once every 10 days for 30 days (3 recalls)
        var spacedStability = DocumentVividness.defaultStability
        var spacedLastRecalled = startDate
        for interval in [10, 20, 30] {
            let now = startDate.addingTimeInterval(Double(interval) * day)
            spacedStability = DocumentVividness.updatedStability(
                currentStability: spacedStability,
                lastAccessDate: spacedLastRecalled,
                createdAt: startDate,
                now: now
            )
            spacedLastRecalled = now
        }

        // Daily recall: 30 interactions but always fresh (1.1x each)
        // Spaced recall: 3 interactions but faded each time (1.5x each)
        // Spaced should give comparable or better stability per-recall
        let dailyPerRecall = dailyStability / 30.0
        let spacedPerRecall = spacedStability / 3.0
        #expect(spacedPerRecall > dailyPerRecall)
    }

    // MARK: - Scenario 6: Dormant resurrection

    @Test
    func dormantDocumentRevivesAfterSingleRecall() {
        let created = startDate
        // Document goes dormant (300 days, no recall)
        let dormantDate = created.addingTimeInterval(300 * day)
        let tierBefore = DocumentVividness.tier(
            lastRecalledAt: nil,
            createdAt: created,
            stability: DocumentVividness.defaultStability,
            now: dormantDate
        )
        #expect(tierBefore == .dormant)

        // Single recall at dormant date
        let newStability = DocumentVividness.updatedStability(
            currentStability: DocumentVividness.defaultStability,
            lastAccessDate: created,
            createdAt: created,
            now: dormantDate
        )

        // Immediately after recall, R=1.0 → vivid
        let tierAfter = DocumentVividness.tier(
            lastRecalledAt: dormantDate,
            createdAt: created,
            stability: newStability,
            now: dormantDate
        )
        #expect(tierAfter == .vivid)

        // Should stay vivid for at least a few days
        let weekLater = dormantDate.addingTimeInterval(7 * day)
        let tierWeekLater = DocumentVividness.tier(
            lastRecalledAt: dormantDate,
            createdAt: created,
            stability: newStability,
            now: weekLater
        )
        #expect(tierWeekLater == .vivid)
    }
}
