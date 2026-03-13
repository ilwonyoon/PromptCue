import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class LicensingSettingsModelTests: XCTestCase {
    func testExpiredQAAccessOverrideForcesExpiredStatusWithoutTouchingStoredState() throws {
        let store = InMemoryLicensingStateStore()
        let now = Date(timeIntervalSince1970: 2_000_000)
        try store.saveTrialState(
            TrialState(
                startedAt: now.addingTimeInterval(-(3 * 24 * 60 * 60)),
                lastSeenAt: now
            )
        )
        try store.saveLicenseRecord(makeLicenseRecord(activatedAt: now))

        let model = makeModel(
            stateStore: store,
            now: now,
            qaAccessStateOverride: .expired
        )

        guard case .expired(.trialExpired(let expiredAt)) = model.accessSnapshot.status else {
            XCTFail("Expected QA override to force expired trial status")
            return
        }

        XCTAssertEqual(expiredAt, now.addingTimeInterval(-(24 * 60 * 60)))
        XCTAssertFalse(model.accessSnapshot.allowsCaptureSave)
        XCTAssertNil(model.storedLicenseRecord)
        XCTAssertEqual(model.accessStatusTitle, "Trial expired")
        XCTAssertTrue(model.accessDetailText.contains("new saves now require a license"))
        XCTAssertEqual(
            try store.loadTrialState(),
            TrialState(
                startedAt: now.addingTimeInterval(-(3 * 24 * 60 * 60)),
                lastSeenAt: now
            )
        )
        XCTAssertEqual(try store.loadLicenseRecord(), makeLicenseRecord(activatedAt: now))
    }

    func testRollbackQAAccessOverrideSurfacesInvalidatedTrialState() {
        let now = Date(timeIntervalSince1970: 2_100_000)
        let model = makeModel(
            stateStore: InMemoryLicensingStateStore(),
            now: now,
            qaAccessStateOverride: .rollback
        )

        guard case .expired(.clockMovedBackward(let lastSeenAt, let currentDate)) = model.accessSnapshot.status else {
            XCTFail("Expected QA override to force rollback expiry")
            return
        }

        XCTAssertEqual(currentDate, now)
        XCTAssertGreaterThan(lastSeenAt, now)
        XCTAssertEqual(model.accessStatusTitle, "Trial invalidated")
        XCTAssertTrue(model.accessDetailText.contains("system clock moving backward"))
    }

    func testLicensedQAAccessOverrideKeepsCaptureUnlocked() {
        let now = Date(timeIntervalSince1970: 2_200_000)
        let model = makeModel(
            stateStore: InMemoryLicensingStateStore(),
            now: now,
            qaAccessStateOverride: .licensed
        )

        XCTAssertEqual(model.accessSnapshot.status, .licensed)
        XCTAssertTrue(model.accessSnapshot.allowsCaptureSave)
        XCTAssertEqual(model.accessStatusTitle, "Licensed")
        XCTAssertTrue(model.accessDetailText.contains("activated"))
    }

    func testRuntimeQAAccessOverrideCanReturnToLiveTrialState() throws {
        let now = Date(timeIntervalSince1970: 2_300_000)
        let store = InMemoryLicensingStateStore()
        try store.saveTrialState(
            TrialState(
                startedAt: now.addingTimeInterval(-(24 * 60 * 60)),
                lastSeenAt: now
            )
        )

        let model = makeModel(
            stateStore: store,
            now: now,
            qaAccessStateOverride: .expired
        )

        XCTAssertEqual(model.accessStatusTitle, "Trial expired")

        model.setQAAccessStateOverrideSelectionValue("live")

        guard case .trial(let status) = model.accessSnapshot.status else {
            XCTFail("Expected live trial state after clearing QA override")
            return
        }

        XCTAssertEqual(status.daysRemaining, 13)
        XCTAssertTrue(model.accessSnapshot.allowsCaptureSave)
    }

    private func makeModel(
        stateStore: any LicensingStateStoring,
        now: Date,
        qaAccessStateOverride: QAAccessStateOverride
    ) -> LicensingSettingsModel {
        LicensingSettingsModel(
            stateStore: stateStore,
            configuration: LicensingConfiguration(
                storefrontURL: nil,
                lemonSqueezyStoreID: nil,
                lemonSqueezyProductID: nil,
                lemonSqueezyVariantID: nil
            ),
            notificationCenter: NotificationCenter(),
            nowProvider: { now },
            qaAccessStateOverride: qaAccessStateOverride
        )
    }

    private func makeLicenseRecord(activatedAt: Date) -> LicenseActivationRecord {
        LicenseActivationRecord(
            licenseKey: "TEST-LICENSE-KEY",
            licenseKeyID: 42,
            activationInstanceID: "instance-1",
            activationInstanceName: "QA Mac",
            storeID: 1,
            orderID: 2,
            productID: 3,
            productName: "Backtick",
            variantID: 4,
            variantName: "Founding",
            customerName: "QA Override",
            customerEmail: "qa@example.com",
            activatedAt: activatedAt,
            lastValidatedAt: activatedAt
        )
    }
}
