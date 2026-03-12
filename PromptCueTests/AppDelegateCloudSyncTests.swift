import AppKit
import XCTest
@testable import Prompt_Cue

@MainActor
final class AppDelegateCloudSyncTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var originalSyncEnabled: Bool!

    override func setUp() {
        super.setUp()
        suiteName = "AppDelegateCloudSyncTests.\(UUID().uuidString)"
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

    func testLaunchSkipsRemoteNotificationRegistrationWhenSyncDisabled() {
        CloudSyncPreferences.save(enabled: false, defaults: defaults)
        let coordinator = RecordingCoordinator()
        let registrar = RecordingRemoteNotificationRegistrar()
        let delegate = AppDelegate(
            coordinatorFactory: { coordinator },
            remoteNotificationRegistrar: registrar,
            cloudSyncPreferencesDefaults: defaults,
            managesRemoteNotifications: true
        )
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertTrue(coordinator.didStart)
        XCTAssertEqual(registrar.registerCount, 0)
        XCTAssertEqual(registrar.unregisterCount, 1)
    }

    func testLaunchRegistersForRemoteNotificationsWhenSyncEnabled() {
        CloudSyncPreferences.save(enabled: true, defaults: defaults)
        let registrar = RecordingRemoteNotificationRegistrar()
        let delegate = AppDelegate(
            coordinatorFactory: { RecordingCoordinator() },
            remoteNotificationRegistrar: registrar,
            cloudSyncPreferencesDefaults: defaults,
            managesRemoteNotifications: true
        )
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(registrar.registerCount, 1)
        XCTAssertEqual(registrar.unregisterCount, 0)
    }

    func testCloudSyncToggleUpdatesRemoteNotificationRegistration() {
        CloudSyncPreferences.save(enabled: false, defaults: defaults)
        let registrar = RecordingRemoteNotificationRegistrar()
        let delegate = AppDelegate(
            coordinatorFactory: { RecordingCoordinator() },
            remoteNotificationRegistrar: registrar,
            cloudSyncPreferencesDefaults: defaults,
            managesRemoteNotifications: true
        )
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        NotificationCenter.default.post(
            name: .cloudSyncEnabledChanged,
            object: nil,
            userInfo: ["enabled": true]
        )
        XCTAssertEqual(registrar.registerCount, 1)

        NotificationCenter.default.post(
            name: .cloudSyncEnabledChanged,
            object: nil,
            userInfo: ["enabled": false]
        )
        XCTAssertEqual(registrar.unregisterCount, 2)
    }
}

@MainActor
private final class RecordingCoordinator: AppLifecycleCoordinating {
    private(set) var didStart = false
    private(set) var didStop = false
    private(set) var remoteNotificationCount = 0

    func start() {
        didStart = true
    }

    func stop() {
        didStop = true
    }

    func handleCloudRemoteNotification() {
        remoteNotificationCount += 1
    }
}

private final class RecordingRemoteNotificationRegistrar: RemoteNotificationRegistering {
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    func registerForRemoteNotifications() {
        registerCount += 1
    }

    func unregisterForRemoteNotifications() {
        unregisterCount += 1
    }
}
