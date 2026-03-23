import Foundation
import Testing
@testable import PromptCueCore

struct DocumentVividnessTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Retrievability

    @Test
    func retrievabilityIsOneAtZeroDays() {
        let r = DocumentVividness.retrievability(daysSinceAccess: 0, stability: 7.0)

        #expect(r == 1.0)
    }

    @Test
    func retrievabilityDecaysOverTime() {
        let r7 = DocumentVividness.retrievability(daysSinceAccess: 7, stability: 7.0)
        let r30 = DocumentVividness.retrievability(daysSinceAccess: 30, stability: 7.0)
        let r90 = DocumentVividness.retrievability(daysSinceAccess: 90, stability: 7.0)

        #expect(r7 > r30)
        #expect(r30 > r90)
        #expect(r90 > 0)
    }

    @Test
    func retrievabilityHigherStabilityDecaysSlower() {
        let rLow = DocumentVividness.retrievability(daysSinceAccess: 30, stability: 7.0)
        let rHigh = DocumentVividness.retrievability(daysSinceAccess: 30, stability: 30.0)

        #expect(rHigh > rLow)
    }

    @Test
    func retrievabilityReturnsZeroForInvalidInputs() {
        #expect(DocumentVividness.retrievability(daysSinceAccess: 10, stability: 0) == 0)
        #expect(DocumentVividness.retrievability(daysSinceAccess: 10, stability: -1) == 0)
        #expect(DocumentVividness.retrievability(daysSinceAccess: -1, stability: 7) == 0)
    }

    @Test
    func retrievabilityFromDatesUsesLastRecalledAt() {
        let lastRecalled = referenceDate
        let now = referenceDate.addingTimeInterval(7 * 86_400)

        let r = DocumentVividness.retrievability(
            lastAccessDate: lastRecalled,
            createdAt: referenceDate.addingTimeInterval(-30 * 86_400),
            stability: 7.0,
            now: now
        )

        let expected = DocumentVividness.retrievability(daysSinceAccess: 7, stability: 7.0)
        #expect(abs(r - expected) < 0.001)
    }

    @Test
    func retrievabilityFallsBackToCreatedAtWhenNoRecall() {
        let created = referenceDate
        let now = referenceDate.addingTimeInterval(14 * 86_400)

        let r = DocumentVividness.retrievability(
            lastAccessDate: nil,
            createdAt: created,
            stability: 7.0,
            now: now
        )

        let expected = DocumentVividness.retrievability(daysSinceAccess: 14, stability: 7.0)
        #expect(abs(r - expected) < 0.001)
    }

    // MARK: - Tier classification

    @Test
    func tierVividWhenFresh() {
        let tier = DocumentVividness.tier(retrievability: 0.8)

        #expect(tier == .vivid)
    }

    @Test
    func tierVividAtBoundary() {
        #expect(DocumentVividness.tier(retrievability: 0.5) == .vivid)
    }

    @Test
    func tierFadingInRange() {
        #expect(DocumentVividness.tier(retrievability: 0.3) == .fading)
        #expect(DocumentVividness.tier(retrievability: 0.2) == .fading)
    }

    @Test
    func tierDormantBelowThreshold() {
        #expect(DocumentVividness.tier(retrievability: 0.19) == .dormant)
        #expect(DocumentVividness.tier(retrievability: 0.0) == .dormant)
    }

    // MARK: - Stability update

    @Test
    func stabilitySmallBoostWhenStillFresh() {
        let newStability = DocumentVividness.updatedStability(
            currentStability: 7.0,
            daysSinceAccess: 1
        )

        #expect(newStability > 7.0)
        #expect(newStability <= 7.0 * 1.1 + 0.01)
    }

    @Test
    func stabilityMediumBoostWhenModeratelyFaded() {
        let newStability = DocumentVividness.updatedStability(
            currentStability: 7.0,
            daysSinceAccess: 10
        )

        #expect(newStability > 7.0 * 1.1)
    }

    @Test
    func stabilityLargeBoostWhenQuiteFaded() {
        // S=30, t=210 → R=0.30 (fading range 0.2<R<0.5), multiplier=2.0
        let newStability = DocumentVividness.updatedStability(
            currentStability: 30.0,
            daysSinceAccess: 210
        )

        #expect(newStability >= 30.0 * 2.0)
    }

    @Test
    func stabilityNeverDropsBelowDefault() {
        let newStability = DocumentVividness.updatedStability(
            currentStability: 3.0,
            daysSinceAccess: 200
        )

        #expect(newStability >= DocumentVividness.defaultStability)
    }

    @Test
    func stabilityGrowsWithRepeatedRecalls() {
        var stability = DocumentVividness.defaultStability
        for i in 1...5 {
            stability = DocumentVividness.updatedStability(
                currentStability: stability,
                daysSinceAccess: Double(i) * 3
            )
        }

        #expect(stability > DocumentVividness.defaultStability * 2)
    }

    // MARK: - Cold start

    @Test
    func newDocumentIsVividWithinGracePeriod() {
        let created = referenceDate
        let threeDaysLater = referenceDate.addingTimeInterval(3 * 86_400)

        let tier = DocumentVividness.tier(
            lastRecalledAt: nil,
            createdAt: created,
            stability: DocumentVividness.defaultStability,
            now: threeDaysLater
        )

        #expect(tier == .vivid)
    }

    @Test
    func newDocumentFadesAfterNineWeeks() {
        // S=7, t=70 days → R≈0.47 (fading, just under 0.5)
        let created = referenceDate
        let later = referenceDate.addingTimeInterval(70 * 86_400)

        let tier = DocumentVividness.tier(
            lastRecalledAt: nil,
            createdAt: created,
            stability: DocumentVividness.defaultStability,
            now: later
        )

        #expect(tier == .fading)
    }

    @Test
    func newDocumentDormantAfterSixMonths() {
        // S=7, t=180 days → R≈0.26 still fading; t=250 → R≈0.20
        // At t=300, R ≈ 0.17 (dormant)
        let created = referenceDate
        let sixMonthsLater = referenceDate.addingTimeInterval(300 * 86_400)

        let tier = DocumentVividness.tier(
            lastRecalledAt: nil,
            createdAt: created,
            stability: DocumentVividness.defaultStability,
            now: sixMonthsLater
        )

        #expect(tier == .dormant)
    }

    // MARK: - ProjectDocument convenience

    @Test
    func documentRecordingRecallUpdatesAllFields() {
        let doc = ProjectDocument(
            project: "test",
            topic: "design",
            documentType: .decision,
            content: "## Decision\nUse FSRS.",
            createdAt: referenceDate,
            updatedAt: referenceDate
        )
        let now = referenceDate.addingTimeInterval(10 * 86_400)
        let recalled = doc.recordingRecall(now: now)

        #expect(recalled.recallCount == 1)
        #expect(recalled.lastRecalledAt == now)
        #expect(recalled.stability > doc.stability)
        // Immutability: original unchanged
        #expect(doc.recallCount == 0)
        #expect(doc.lastRecalledAt == nil)
    }

    @Test
    func documentRecordingRecallImmutable() {
        let doc = ProjectDocument(
            project: "test",
            topic: "arch",
            documentType: .discussion,
            content: "## Arch\nContent.",
            createdAt: referenceDate,
            updatedAt: referenceDate,
            stability: 14.0,
            recallCount: 3,
            lastRecalledAt: referenceDate
        )
        let now = referenceDate.addingTimeInterval(2 * 86_400)
        let recalled = doc.recordingRecall(now: now)

        #expect(recalled.recallCount == 4)
        #expect(doc.recallCount == 3)
        #expect(doc.stability == 14.0)
    }

    // MARK: - Stale document decay

    @Test
    func previouslyImportantDocumentDecaysGracefully() {
        // Document that was recalled 10 times, building high stability
        var stability = DocumentVividness.defaultStability
        for _ in 1...10 {
            stability = DocumentVividness.updatedStability(
                currentStability: stability,
                daysSinceAccess: 5
            )
        }
        let highStability = stability

        // Even with high stability, after 1 year it should eventually fade
        let r = DocumentVividness.retrievability(
            daysSinceAccess: 365,
            stability: highStability
        )

        #expect(r < 0.5) // No longer vivid after a full year
    }
}
