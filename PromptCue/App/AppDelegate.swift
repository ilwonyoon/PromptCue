import AppKit

@MainActor
protocol AppLifecycleCoordinating: AnyObject {
    func start()
    func stop()
    func handleCloudRemoteNotification()
}

protocol RemoteNotificationRegistering {
    func registerForRemoteNotifications()
    func unregisterForRemoteNotifications()
}

struct ApplicationRemoteNotificationRegistrar: RemoteNotificationRegistering {
    func registerForRemoteNotifications() {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func unregisterForRemoteNotifications() {
        NSApplication.shared.unregisterForRemoteNotifications()
    }
}

@MainActor
private func defaultAppDelegateManagesRemoteNotifications() -> Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
}

@MainActor
private func defaultCoordinatorFactory() -> @MainActor () -> any AppLifecycleCoordinating {
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
        return { TestHostLifecycleCoordinator() }
    }

    return { AppCoordinator() }
}

@MainActor
private final class TestHostLifecycleCoordinator: AppLifecycleCoordinating {
    func start() {}
    func stop() {}
    func handleCloudRemoteNotification() {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinatorFactory: @MainActor () -> any AppLifecycleCoordinating
    private let remoteNotificationRegistrar: any RemoteNotificationRegistering
    private let cloudSyncPreferencesDefaults: UserDefaults
    private let managesRemoteNotifications: Bool
    private var coordinator: (any AppLifecycleCoordinating)?
    private var cloudSyncEnabledObserver: NSObjectProtocol?

    override init() {
        self.coordinatorFactory = defaultCoordinatorFactory()
        self.remoteNotificationRegistrar = ApplicationRemoteNotificationRegistrar()
        self.cloudSyncPreferencesDefaults = .standard
        self.managesRemoteNotifications = defaultAppDelegateManagesRemoteNotifications()
        super.init()
    }

    init(
        coordinatorFactory: @escaping @MainActor () -> any AppLifecycleCoordinating,
        remoteNotificationRegistrar: any RemoteNotificationRegistering,
        cloudSyncPreferencesDefaults: UserDefaults,
        managesRemoteNotifications: Bool
    ) {
        self.coordinatorFactory = coordinatorFactory
        self.remoteNotificationRegistrar = remoteNotificationRegistrar
        self.cloudSyncPreferencesDefaults = cloudSyncPreferencesDefaults
        self.managesRemoteNotifications = managesRemoteNotifications
        super.init()
    }

    deinit {
        if let cloudSyncEnabledObserver {
            NotificationCenter.default.removeObserver(cloudSyncEnabledObserver)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = coordinatorFactory()
        coordinator?.start()

        guard managesRemoteNotifications else {
            return
        }

        applyRemoteNotificationRegistration(
            isEnabled: CloudSyncPreferences.load(defaults: cloudSyncPreferencesDefaults)
        )
        cloudSyncEnabledObserver = NotificationCenter.default.addObserver(
            forName: .cloudSyncEnabledChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            self?.applyRemoteNotificationRegistration(isEnabled: enabled)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let cloudSyncEnabledObserver {
            NotificationCenter.default.removeObserver(cloudSyncEnabledObserver)
        }
        cloudSyncEnabledObserver = nil
        coordinator?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        coordinator?.handleCloudRemoteNotification()
    }

    private func applyRemoteNotificationRegistration(isEnabled: Bool) {
        if isEnabled {
            remoteNotificationRegistrar.registerForRemoteNotifications()
        } else {
            remoteNotificationRegistrar.unregisterForRemoteNotifications()
        }
    }
}
