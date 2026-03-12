import Foundation
import XCTest
@testable import Prompt_Cue

@MainActor
final class CloudSyncSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var originalSyncEnabled: Bool!

    override func setUp() {
        super.setUp()
        suiteName = "CloudSyncSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        originalSyncEnabled = CloudSyncPreferences.load()
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        CloudSyncPreferences.save(enabled: originalSyncEnabled)
        defaults = nil
        suiteName = nil
        originalSyncEnabled = nil
        super.tearDown()
    }

    func testSyncDefaultsToDisabled() {
        let enabled = CloudSyncPreferences.load(defaults: defaults)

        XCTAssertFalse(enabled)
    }

    func testSyncPreferencePersistsDisabledState() {
        CloudSyncPreferences.save(enabled: false, defaults: defaults)

        let enabled = CloudSyncPreferences.load(defaults: defaults)

        XCTAssertFalse(enabled)
    }

    func testSyncPreferencePersistsEnabledState() {
        CloudSyncPreferences.save(enabled: false, defaults: defaults)
        CloudSyncPreferences.save(enabled: true, defaults: defaults)

        let enabled = CloudSyncPreferences.load(defaults: defaults)

        XCTAssertTrue(enabled)
    }

    func testSettingsModelRefreshLoadsCurrentPreference() {
        CloudSyncPreferences.save(enabled: false)

        let model = CloudSyncSettingsModel()

        XCTAssertFalse(model.isSyncEnabled)
    }

    func testSettingsModelUpdateSyncEnabledPersists() {
        let model = CloudSyncSettingsModel()

        model.updateSyncEnabled(false)

        XCTAssertFalse(model.isSyncEnabled)
        XCTAssertFalse(CloudSyncPreferences.load())
    }

    func testSyncStatusTextShowsDisabledWhenOff() {
        let model = CloudSyncSettingsModel()
        model.updateSyncEnabled(false)

        XCTAssertEqual(model.syncStatusText, "Disabled")
    }

    func testSyncStatusTextShowsWaitingBeforeFirstSync() {
        CloudSyncPreferences.save(enabled: true)
        let model = CloudSyncSettingsModel()

        XCTAssertEqual(model.syncStatusText, "Waiting for first sync…")
    }

    func testSyncStatusTextShowsLastSyncedAfterCompletion() {
        CloudSyncPreferences.save(enabled: true)
        let model = CloudSyncSettingsModel()

        model.updateLastSynced(Date())

        XCTAssertTrue(model.syncStatusText.hasPrefix("Last synced"))
    }

    func testSyncStatusTextShowsErrorWhenPresent() {
        CloudSyncPreferences.save(enabled: true)
        let model = CloudSyncSettingsModel()

        model.updateSyncError("Network timeout")

        XCTAssertEqual(model.syncStatusText, "Error: Network timeout")
    }

    func testUpdateLastSyncedClearsError() {
        let model = CloudSyncSettingsModel()
        model.updateSyncError("Something failed")

        model.updateLastSynced(Date())

        XCTAssertNil(model.syncError)
    }

    func testSyncStatusTextShowsNoAccountStatus() {
        CloudSyncPreferences.save(enabled: true)
        let model = CloudSyncSettingsModel()
        model.accountStatus = .noAccount

        XCTAssertEqual(model.syncStatusText, "No iCloud account")
    }

    func testSyncStatusTextShowsRestrictedStatus() {
        CloudSyncPreferences.save(enabled: true)
        let model = CloudSyncSettingsModel()
        model.accountStatus = .restricted

        XCTAssertEqual(model.syncStatusText, "iCloud restricted")
    }

    func testUpdateSyncEnabledPostsNotification() {
        let model = CloudSyncSettingsModel()
        let expectation = expectation(forNotification: .cloudSyncEnabledChanged, object: nil) { notification in
            let enabled = notification.userInfo?["enabled"] as? Bool
            return enabled == false
        }

        model.updateSyncEnabled(false)

        wait(for: [expectation], timeout: 1.0)
    }
}
