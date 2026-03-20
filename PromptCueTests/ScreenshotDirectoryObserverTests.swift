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
            forceRemoveDirectory(tempDirectoryURL)
        }

        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    private func forceRemoveDirectory(_ url: URL) {
        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let itemURL as URL in enumerator {
                try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: itemURL.path)
            }
        }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? fileManager.removeItem(at: url)
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

    func testLocatorScansSystemScreenshotDirectoryWhenAuthorizedFolderDiffers() throws {
        let authorizedDirectoryURL = tempDirectoryURL.appendingPathComponent("Downloads", isDirectory: true)
        let systemDirectoryURL = tempDirectoryURL.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: authorizedDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemDirectoryURL, withIntermediateDirectories: true)

        let screenshotURL = systemDirectoryURL.appendingPathComponent("Screenshot 2026-03-18 at 3.10.00 PM.png")
        let screenshotData = Data("png".utf8)
        try screenshotData.write(to: screenshotURL)

        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { authorizedDirectoryURL },
            systemDirectoryProvider: { systemDirectoryURL }
        )

        let result = locator.locateRecentScreenshot(now: Date(), maxAge: 30)

        XCTAssertEqual(result.signalCandidate?.fileURL, screenshotURL.standardizedFileURL)
        XCTAssertEqual(result.readableCandidate?.fileURL, screenshotURL.standardizedFileURL)
    }

    func testObserverEmitsContentChangeWhenSystemScreenshotFolderChanges() throws {
        let authorizedDirectoryURL = tempDirectoryURL.appendingPathComponent("Downloads", isDirectory: true)
        let systemDirectoryURL = tempDirectoryURL.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: authorizedDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemDirectoryURL, withIntermediateDirectories: true)

        let observer = RecentScreenshotDirectoryObserver(
            authorizedDirectoryProvider: { authorizedDirectoryURL },
            systemDirectoryProvider: { systemDirectoryURL }
        )

        let contentsChanged = expectation(description: "system screenshot directory contents change")
        observer.onChange = { event in
            if event == .authorizedDirectoryContentsChanged {
                contentsChanged.fulfill()
            }
        }

        observer.start()
        let screenshotURL = systemDirectoryURL.appendingPathComponent("Screenshot 2026-03-18 at 3.15.00 PM.png")
        try Data("png".utf8).write(to: screenshotURL)

        wait(for: [contentsChanged], timeout: 1)
        observer.stop()
    }
}
