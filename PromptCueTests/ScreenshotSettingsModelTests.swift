import Foundation
import XCTest
@testable import Prompt_Cue

@MainActor
final class ScreenshotSettingsModelTests: XCTestCase {
    func testConnectedFolderMismatchIsDetectedAgainstCurrentSystemFolder() {
        let downloadsURL = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        let desktopURL = URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true)
        let model = ScreenshotSettingsModel(
            accessStateProvider: {
                .connected(url: downloadsURL, displayPath: "~/Downloads")
            },
            suggestedSystemPathProvider: { "~/Desktop" },
            systemDirectoryURLProvider: { desktopURL }
        )

        XCTAssertTrue(model.currentSystemFolderMismatch)
        XCTAssertEqual(model.suggestedSystemPath, "~/Desktop")
    }

    func testConnectedFolderMatchDoesNotTriggerMismatch() {
        let desktopURL = URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true)
        let model = ScreenshotSettingsModel(
            accessStateProvider: {
                .connected(url: desktopURL, displayPath: "~/Desktop")
            },
            suggestedSystemPathProvider: { "~/Desktop" },
            systemDirectoryURLProvider: { desktopURL }
        )

        XCTAssertFalse(model.currentSystemFolderMismatch)
    }
}
