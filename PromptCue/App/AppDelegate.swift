import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()
        coordinator?.start()

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        coordinator?.model.handleCloudRemoteNotification()
    }
}
