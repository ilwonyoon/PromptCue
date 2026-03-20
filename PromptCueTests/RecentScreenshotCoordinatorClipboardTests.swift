import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class RecentScreenshotCoordinatorClipboardTests: XCTestCase {
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

    func testPrepareForCaptureSessionPrioritizesRecentClipboardImage() throws {
        let now = Date()
        let clipboardCacheURL = tempDirectoryURL.appendingPathComponent("clipboard.png")
        try Data("png".utf8).write(to: clipboardCacheURL)

        let clipboardProvider = TestRecentClipboardProvider()
        clipboardProvider.currentImage = RecentClipboardImage(
            changeCount: 41,
            detectedAt: now,
            cacheURL: clipboardCacheURL
        )

        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-08 at 10.00.00 PM.png")
        let screenshotData = Data("png".utf8)
        try screenshotData.write(to: screenshotURL)

        let fileCandidate = RecentScreenshotCandidate(
            attachment: ScreenshotAttachment(
                path: screenshotURL.path,
                modifiedAt: now.addingTimeInterval(-10),
                fileSize: screenshotData.count
            ),
            sourceKey: screenshotURL.lastPathComponent.lowercased()
        )

        let coordinator = RecentScreenshotCoordinator(
            observer: ClipboardTestRecentScreenshotObserver(),
            locator: TestRecentScreenshotLocator(
                result: RecentScreenshotScanResult(
                    signalCandidate: fileCandidate,
                    readableCandidate: fileCandidate,
                    recentTemporaryContainerDate: nil
                )
            ),
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("TransientScreenshots")),
            clipboardProvider: clipboardProvider,
            maxAge: 30,
            settleGrace: 0.2,
            now: { now }
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()

        guard case .previewReady(_, let cacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected clipboard preview-ready state")
        }

        XCTAssertEqual(cacheURL.standardizedFileURL, clipboardCacheURL.standardizedFileURL)
    }

    func testDismissSuppressesCurrentClipboardImageUntilPasteboardChanges() throws {
        let now = Date()
        let clipboardCacheURL = tempDirectoryURL.appendingPathComponent("clipboard.png")
        try Data("png".utf8).write(to: clipboardCacheURL)

        let clipboardProvider = TestRecentClipboardProvider()
        clipboardProvider.currentImage = RecentClipboardImage(
            changeCount: 7,
            detectedAt: now,
            cacheURL: clipboardCacheURL
        )

        let coordinator = RecentScreenshotCoordinator(
            observer: ClipboardTestRecentScreenshotObserver(),
            locator: TestRecentScreenshotLocator(result: .init(signalCandidate: nil, readableCandidate: nil, recentTemporaryContainerDate: nil)),
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("TransientScreenshots")),
            clipboardProvider: clipboardProvider,
            maxAge: 30,
            settleGrace: 0.2,
            now: { now }
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()
        guard case .previewReady = coordinator.state else {
            return XCTFail("Expected initial clipboard preview-ready state")
        }

        coordinator.dismissCurrent()
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(clipboardProvider.dismissCalls, 1)

        coordinator.prepareForCaptureSession()
        XCTAssertEqual(coordinator.state, .idle)

        let nextCacheURL = tempDirectoryURL.appendingPathComponent("clipboard-2.png")
        try Data("png2".utf8).write(to: nextCacheURL)
        clipboardProvider.currentImage = RecentClipboardImage(
            changeCount: 8,
            detectedAt: now.addingTimeInterval(1),
            cacheURL: nextCacheURL
        )

        coordinator.prepareForCaptureSession()
        guard case .previewReady(_, let cacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected updated clipboard preview-ready state")
        }

        XCTAssertEqual(cacheURL.standardizedFileURL, nextCacheURL.standardizedFileURL)
    }

    func testConsumeSuppressesCurrentClipboardImageUntilPasteboardChanges() throws {
        let now = Date()
        let clipboardCacheURL = tempDirectoryURL.appendingPathComponent("clipboard-consume.png")
        try Data("png".utf8).write(to: clipboardCacheURL)

        let clipboardProvider = TestRecentClipboardProvider()
        clipboardProvider.currentImage = RecentClipboardImage(
            changeCount: 11,
            detectedAt: now,
            cacheURL: clipboardCacheURL
        )

        let coordinator = RecentScreenshotCoordinator(
            observer: ClipboardTestRecentScreenshotObserver(),
            locator: TestRecentScreenshotLocator(result: .init(signalCandidate: nil, readableCandidate: nil, recentTemporaryContainerDate: nil)),
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("TransientScreenshots")),
            clipboardProvider: clipboardProvider,
            maxAge: 30,
            settleGrace: 0.2,
            now: { now }
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()
        guard case .previewReady = coordinator.state else {
            return XCTFail("Expected initial clipboard preview-ready state")
        }

        coordinator.consumeCurrent()
        if case .consumed = coordinator.state {
        } else {
            XCTFail("Expected consumed state after consuming current clipboard image")
        }
        XCTAssertEqual(clipboardProvider.consumeCalls, 1)

        coordinator.prepareForCaptureSession()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testPrepareForCaptureSessionFallsBackToFileScreenshotWhenClipboardIsUnavailable() throws {
        let now = Date()
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-08 at 10.10.00 PM.png")
        try Data("png".utf8).write(to: screenshotURL)

        let candidate = makeCandidate(
            filename: screenshotURL.lastPathComponent,
            directory: screenshotsURL
        )
        let clipboardProvider = TestRecentClipboardProvider()
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)

        let coordinator = RecentScreenshotCoordinator(
            observer: ClipboardTestRecentScreenshotObserver(),
            locator: TestRecentScreenshotLocator(
                result: RecentScreenshotScanResult(
                    signalCandidate: candidate,
                    readableCandidate: candidate,
                    recentTemporaryContainerDate: nil
                )
            ),
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: clipboardProvider,
            maxAge: 30,
            settleGrace: 0.2,
            now: { now }
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()

        waitForCondition("file screenshot preview-ready state") {
            if case .previewReady = coordinator.state {
                return true
            }

            return false
        }

        guard case .previewReady(_, let previewCacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected file screenshot preview-ready state")
        }

        XCTAssertTrue(previewCacheURL.path.hasPrefix(cacheURL.path))
        XCTAssertEqual(try Data(contentsOf: previewCacheURL), Data("png".utf8))
    }

    func testPrepareForCaptureSessionPrefersNewerFileScreenshotOverOlderClipboardImage() throws {
        let now = Date()
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)

        let clipboardCacheURL = tempDirectoryURL.appendingPathComponent("clipboard.png")
        try Data("clipboard".utf8).write(to: clipboardCacheURL)

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-08 at 10.11.00 PM.png")
        let screenshotData = Data("png".utf8)
        try screenshotData.write(to: screenshotURL)

        let clipboardProvider = TestRecentClipboardProvider()
        clipboardProvider.currentImage = RecentClipboardImage(
            changeCount: 99,
            detectedAt: now.addingTimeInterval(-10),
            cacheURL: clipboardCacheURL
        )

        let fileCandidate = RecentScreenshotCandidate(
            attachment: ScreenshotAttachment(
                path: screenshotURL.path,
                modifiedAt: now,
                fileSize: screenshotData.count
            ),
            sourceKey: screenshotURL.lastPathComponent.lowercased()
        )
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        let coordinator = RecentScreenshotCoordinator(
            observer: ClipboardTestRecentScreenshotObserver(),
            locator: TestRecentScreenshotLocator(
                result: RecentScreenshotScanResult(
                    signalCandidate: fileCandidate,
                    readableCandidate: fileCandidate,
                    recentTemporaryContainerDate: nil
                )
            ),
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: clipboardProvider,
            maxAge: 30,
            settleGrace: 0.2,
            now: { now }
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()

        waitForCondition("file screenshot preferred over clipboard") {
            if case .previewReady(_, let previewCacheURL, .ready) = coordinator.state {
                return previewCacheURL.standardizedFileURL != clipboardCacheURL.standardizedFileURL
            }

            return false
        }

        guard case .previewReady(_, let previewCacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected file screenshot preview-ready state")
        }

        XCTAssertTrue(previewCacheURL.path.hasPrefix(cacheURL.path))
        XCTAssertEqual(try Data(contentsOf: previewCacheURL), screenshotData)
    }

    private func makeCandidate(filename: String, directory: URL) -> RecentScreenshotCandidate {
        let fileURL = directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Data("png".utf8).write(to: fileURL)
        }

        return RecentScreenshotCandidate(
            attachment: ScreenshotAttachment(
                path: fileURL.path,
                modifiedAt: Date(),
                fileSize: 3
            ),
            sourceKey: filename.lowercased()
        )
    }

    private func waitForCondition(
        _ description: String,
        timeout: TimeInterval = 0.6,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }
}

private struct TestRecentScreenshotLocator: RecentScreenshotLocating {
    let result: RecentScreenshotScanResult

    func locateRecentScreenshot(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        result
    }
}

private final class ClipboardTestRecentScreenshotObserver: RecentScreenshotObserving {
    var onChange: ((RecentScreenshotObservationEvent) -> Void)?

    func start() {}
    func stop() {}
}

@MainActor
private final class TestRecentClipboardProvider: RecentClipboardImageProviding {
    var onImageDetected: (() -> Void)?
    var currentImage: RecentClipboardImage?
    var dismissCalls = 0
    var consumeCalls = 0

    func start() {}
    func stop() {}
    func refreshNow() {}

    func recentImage(referenceDate: Date, maxAge: TimeInterval) -> RecentClipboardImage? {
        guard let currentImage else {
            return nil
        }

        guard referenceDate.timeIntervalSince(currentImage.detectedAt) <= maxAge else {
            return nil
        }

        return currentImage
    }

    func consumeCurrent() {
        consumeCalls += 1
        currentImage = nil
    }

    func dismissCurrent() {
        dismissCalls += 1
        currentImage = nil
    }
}
