import Foundation
import Testing
@testable import PromptCueCore

struct AppAccessEvaluatorTests {
    private let evaluator = AppAccessEvaluator()

    @Test
    func firstLaunchStartsTrialAndPersistsTrialState() {
        let now = Date(timeIntervalSince1970: 1_000)

        let resolution = evaluator.resolve(trialState: nil, isLicensed: false, now: now)

        guard case .trial(let status) = resolution.snapshot.status else {
            Issue.record("Expected trial access on first launch")
            return
        }

        #expect(status.startedAt == now)
        #expect(status.lastSeenAt == now)
        #expect(status.daysRemaining == 14)
        #expect(status.expiresAt == now.addingTimeInterval(14 * 24 * 60 * 60))
        #expect(resolution.trialStateToPersist == TrialState(startedAt: now, lastSeenAt: now))
        #expect(resolution.snapshot.allowsCaptureSave)
    }

    @Test
    func activeTrialRefreshesLastSeenTimestamp() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let previousSeenAt = startedAt.addingTimeInterval(60)
        let now = startedAt.addingTimeInterval(2 * 24 * 60 * 60)
        let existingTrial = TrialState(startedAt: startedAt, lastSeenAt: previousSeenAt)

        let resolution = evaluator.resolve(
            trialState: existingTrial,
            isLicensed: false,
            now: now
        )

        guard case .trial(let status) = resolution.snapshot.status else {
            Issue.record("Expected active trial state")
            return
        }

        #expect(status.startedAt == startedAt)
        #expect(status.lastSeenAt == now)
        #expect(status.daysRemaining == 12)
        #expect(resolution.trialStateToPersist == TrialState(startedAt: startedAt, lastSeenAt: now))
    }

    @Test
    func expiredTrialBlocksCaptureButKeepsReadOnlyAccess() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let expiredNow = startedAt.addingTimeInterval((14 * 24 * 60 * 60) + 1)

        let resolution = evaluator.resolve(
            trialState: TrialState(startedAt: startedAt, lastSeenAt: startedAt),
            isLicensed: false,
            now: expiredNow
        )

        guard case .expired(.trialExpired(let expiredAt)) = resolution.snapshot.status else {
            Issue.record("Expected trial expiry")
            return
        }

        #expect(expiredAt == startedAt.addingTimeInterval(14 * 24 * 60 * 60))
        #expect(resolution.snapshot.allowsCaptureSave == false)
        #expect(resolution.snapshot.allowsReadAccess)
        #expect(resolution.snapshot.allowsExport)
        #expect(resolution.snapshot.allowsLicenseManagement)
    }

    @Test
    func activeLicenseOverridesExpiredTrial() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let expiredNow = startedAt.addingTimeInterval((20 * 24 * 60 * 60))

        let resolution = evaluator.resolve(
            trialState: TrialState(startedAt: startedAt, lastSeenAt: startedAt),
            isLicensed: true,
            now: expiredNow
        )

        #expect(resolution.snapshot.status == .licensed)
        #expect(resolution.snapshot.allowsCaptureSave)
    }

    @Test
    func clockRollbackBeyondToleranceExpiresTrial() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let lastSeenAt = startedAt.addingTimeInterval(10 * 60)
        let now = startedAt.addingTimeInterval(4 * 60)

        let resolution = evaluator.resolve(
            trialState: TrialState(startedAt: startedAt, lastSeenAt: lastSeenAt),
            isLicensed: false,
            now: now
        )

        guard case .expired(.clockMovedBackward(let persistedLastSeenAt, let currentDate)) = resolution.snapshot.status else {
            Issue.record("Expected clock rollback expiry")
            return
        }

        #expect(persistedLastSeenAt == lastSeenAt)
        #expect(currentDate == now)
        #expect(resolution.snapshot.allowsCaptureSave == false)
    }

    @Test
    func smallClockSkewWithinToleranceKeepsTrialActive() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let lastSeenAt = startedAt.addingTimeInterval(10 * 60)
        let now = lastSeenAt.addingTimeInterval(-(4 * 60))

        let resolution = evaluator.resolve(
            trialState: TrialState(startedAt: startedAt, lastSeenAt: lastSeenAt),
            isLicensed: false,
            now: now
        )

        guard case .trial(let status) = resolution.snapshot.status else {
            Issue.record("Expected trial to remain active within skew tolerance")
            return
        }

        #expect(status.lastSeenAt == lastSeenAt)
        #expect(resolution.snapshot.allowsCaptureSave)
    }
}
