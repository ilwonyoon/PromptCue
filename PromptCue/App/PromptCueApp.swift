import SwiftUI

@main
struct PromptCueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PromptCueSettingsView(
                selectedTab: .general,
                screenshotSettingsModel: ScreenshotSettingsModel(),
                exportTailSettingsModel: PromptExportTailSettingsModel(),
                retentionSettingsModel: CardRetentionSettingsModel(),
                cloudSyncSettingsModel: CloudSyncSettingsModel(),
                appearanceSettingsModel: AppearanceSettingsModel()
            )
        }
    }
}
