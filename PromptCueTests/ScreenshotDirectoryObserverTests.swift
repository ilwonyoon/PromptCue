import Foundation
import XCTest
@testable import Prompt_Cue

@MainActor
final class ScreenshotDirectoryObserverTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testObserverEmitsConfigurationChangeWhenAuthorizedFolderChanges() throws {
        let firstDirectoryURL = tempDirectoryURL.appendingPathComponent("Screenshots-A", isDirectory: true)
        let secondDirectoryURL = tempDirectoryURL.appendingPathComponent("Screenshots-B", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectoryURL, withIntermediateDirectories: true)

        let notificationCenter = NotificationCenter()
        var authorizedDirectoryURL: URL? = firstDirectoryURL
        let observer = RecentScreenshotDirectoryObserver(
            authorizedDirectoryProvider: { authorizedDirectoryURL },
            notificationCenter: notificationCenter
        )

        let configurationEvent = expectation(description: "configuration change event")
        observer.onChange = { event in
            if event == .authorizedDirectoryConfigurationChanged {
                configurationEvent.fulfill()
            }
        }

        observer.start()
        authorizedDirectoryURL = secondDirectoryURL
        notificationCenter.post(
            name: ScreenshotDirectoryResolver.authorizedDirectoryDidChangeNotification,
            object: nil
        )

        wait(for: [configurationEvent], timeout: 1)
        observer.stop()
    }

    func testLocatorIgnoresTemporaryItemsWhenAuthorizedFolderIsUnavailable() throws {
        let temporaryItemsURL = tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
        let childDirectoryURL = temporaryItemsURL
            .appendingPathComponent("NSIRD_screencaptureui_123", isDirectory: true)
        try FileManager.default.createDirectory(at: childDirectoryURL, withIntermediateDirectories: true)

        let screenshotURL = childDirectoryURL.appendingPathComponent("Screenshot 2026-03-12 at 10.00.00.png")
        try Data("png".utf8).write(to: screenshotURL)

        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { nil },
            temporaryItemsDirectoryProvider: { temporaryItemsURL }
        )

        let result = locator.locateRecentScreenshot(now: Date(), maxAge: 30)

        XCTAssertNil(result.signalCandidate)
        XCTAssertNil(result.readableCandidate)
        XCTAssertNil(result.recentTemporaryContainerDate)
    }
}
