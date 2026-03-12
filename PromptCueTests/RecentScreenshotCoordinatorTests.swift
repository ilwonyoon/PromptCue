import Foundation
import PromptCueCore
import XCTest
@testable import Prompt_Cue

@MainActor
final class RecentScreenshotCoordinatorTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testCoordinatorTransitionsFromDetectedToPreviewReadyUsingTransientCache() throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: screenshotsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let observer = TestRecentScreenshotObserver()
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { screenshotsURL }
        )
        let coordinator = RecentScreenshotCoordinator(
            observer: observer,
            locator: locator,
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.2
        )

        var states: [RecentScreenshotState] = []
        coordinator.onStateChange = { states.append($0) }
        coordinator.start()

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-07 at 10.00.00.png")
        try Data().write(to: screenshotURL)
        observer.signalChange(.authorizedDirectoryContentsChanged)
        waitForCondition("detected state after zero-byte screenshot") {
            if case .detected = coordinator.state {
                return true
            }

            return false
        }

        guard case .detected(let sessionID, _) = coordinator.state else {
            return XCTFail("Expected detected state after zero-byte screenshot signal")
        }

        try Data("png".utf8).write(to: screenshotURL)
        observer.signalChange(.authorizedDirectoryContentsChanged)
        waitForCondition("preview-ready state after screenshot becomes readable") {
            if case .previewReady = coordinator.state {
                return true
            }

            return false
        }

        guard case .previewReady(let previewSessionID, let previewCacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected preview-ready state after screenshot becomes readable")
        }

        XCTAssertEqual(previewSessionID, sessionID)
        XCTAssertTrue(previewCacheURL.path.hasPrefix(cacheURL.path))
        XCTAssertEqual(try Data(contentsOf: previewCacheURL), Data("png".utf8))
        XCTAssertTrue(states.contains { state in
            if case .detected(let recordedSessionID, _) = state {
                return recordedSessionID == sessionID
            }

            return false
        })
    }

    func testPrepareForCaptureSessionDetectsReadableScreenshotWithoutObserverSignal() throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: screenshotsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let observer = TestRecentScreenshotObserver()
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { screenshotsURL }
        )
        let coordinator = RecentScreenshotCoordinator(
            observer: observer,
            locator: locator,
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.2
        )

        coordinator.start()

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-07 at 10.08.00.png")
        try Data("png".utf8).write(to: screenshotURL)

        coordinator.prepareForCaptureSession()
        waitForCondition("preview-ready state after capture session preparation") {
            if case .previewReady = coordinator.state {
                return true
            }

            return false
        }

        guard case .previewReady(_, let previewCacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected preview-ready state after prepareForCaptureSession")
        }

        XCTAssertTrue(previewCacheURL.path.hasPrefix(cacheURL.path))
        XCTAssertEqual(try Data(contentsOf: previewCacheURL), Data("png".utf8))
    }

    func testLocatorIgnoresTemporaryItemsByDefault() throws {
        let temporaryItemsURL = tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
        let childDirectoryURL = temporaryItemsURL
            .appendingPathComponent("NSIRD_screencaptureui_123", isDirectory: true)
        try FileManager.default.createDirectory(
            at: childDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let screenshotURL = childDirectoryURL.appendingPathComponent("Screenshot 2026-03-07 at 10.09.00.png")
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

    func testResolveCurrentCaptureAttachmentWaitsForDetectedScreenshotToBecomeReadable() async throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: screenshotsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let observer = TestRecentScreenshotObserver()
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { screenshotsURL }
        )
        let coordinator = RecentScreenshotCoordinator(
            observer: observer,
            locator: locator,
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.2
        )

        coordinator.start()

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-07 at 10.09.00.png")
        try Data().write(to: screenshotURL)
        coordinator.prepareForCaptureSession()
        await waitForConditionAsync("detected state before resolve") {
            if case .detected = coordinator.state {
                return true
            }

            return false
        }

        guard case .detected = coordinator.state else {
            return XCTFail("Expected detected state before resolve")
        }

        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            try? Data("png".utf8).write(to: screenshotURL)
        }

        let resolvedURL = await coordinator.resolveCurrentCaptureAttachment(timeout: 0.6)

        XCTAssertNotNil(resolvedURL)
        XCTAssertTrue(resolvedURL?.path.hasPrefix(cacheURL.path) == true)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(resolvedURL)), Data("png".utf8))
    }

    func testAuthorizedDirectoryConfigurationChangeRebindsCoordinatorToNewFolder() throws {
        let firstScreenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots-A", isDirectory: true)
        let secondScreenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots-B", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: firstScreenshotsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: secondScreenshotsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let notificationCenter = NotificationCenter()
        var monitoredDirectoryURL = firstScreenshotsURL
        let observer = RecentScreenshotDirectoryObserver(
            authorizedDirectoryProvider: { monitoredDirectoryURL },
            notificationCenter: notificationCenter
        )
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { monitoredDirectoryURL }
        )
        let coordinator = RecentScreenshotCoordinator(
            observer: observer,
            locator: locator,
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.2
        )

        coordinator.start()
        let screenshotURL = secondScreenshotsURL.appendingPathComponent("Screenshot 2026-03-07 at 10.12.35 PM.png")
        try Data("png".utf8).write(to: screenshotURL)

        monitoredDirectoryURL = secondScreenshotsURL
        notificationCenter.post(name: ScreenshotDirectoryResolver.authorizedDirectoryDidChangeNotification, object: nil)

        waitForCondition("preview-ready state after authorized directory rebind") {
            if case .previewReady = coordinator.state {
                return true
            }

            return false
        }

        guard case .previewReady(_, let previewCacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected preview-ready state after authorized directory rebind")
        }

        XCTAssertTrue(previewCacheURL.path.hasPrefix(cacheURL.path))
        XCTAssertEqual(try Data(contentsOf: previewCacheURL), Data("png".utf8))
    }

    func testPrepareForCaptureSessionShowsDetectedImmediatelyBeforeAsyncReadablePromotion() async throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-10 at 01.08.00.png")
        let screenshotData = Data("png".utf8)
        try screenshotData.write(to: screenshotURL)

        let candidate = RecentScreenshotCandidate(
            attachment: ScreenshotAttachment(
                path: screenshotURL.path,
                modifiedAt: Date(),
                fileSize: screenshotData.count
            ),
            sourceKey: screenshotURL.lastPathComponent.lowercased()
        )
        let signalResult = RecentScreenshotScanResult(
            signalCandidate: candidate,
            readableCandidate: nil
        )
        let fullResult = RecentScreenshotScanResult(
            signalCandidate: candidate,
            readableCandidate: candidate
        )
        let coordinator = RecentScreenshotCoordinator(
            observer: TestRecentScreenshotObserver(),
            locator: DelayedSignalProbeLocator(
                fullScanDelay: 0.2,
                signalResult: signalResult,
                fullResult: fullResult
            ),
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.2
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()

        guard case .detected = coordinator.state else {
            return XCTFail("Expected immediate detected state from synchronous capture probe")
        }

        let resolvedURL = await coordinator.resolveCurrentCaptureAttachment(timeout: 0.8)

        XCTAssertNotNil(resolvedURL)
        XCTAssertTrue(resolvedURL?.path.hasPrefix(cacheURL.path) == true)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(resolvedURL)), screenshotData)
    }

    func testDismissSuppressesSameScreenshotUntilItAgesOut() throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: screenshotsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let observer = TestRecentScreenshotObserver()
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { screenshotsURL }
        )
        let coordinator = RecentScreenshotCoordinator(
            observer: observer,
            locator: locator,
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.2
        )

        coordinator.start()

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-07 at 10.05.00.png")
        try Data("png".utf8).write(to: screenshotURL)
        observer.signalChange(.authorizedDirectoryContentsChanged)
        waitForCondition("preview-ready state before dismissal") {
            if case .previewReady = coordinator.state {
                return true
            }

            return false
        }

        guard case .previewReady = coordinator.state else {
            return XCTFail("Expected preview-ready state before dismissal")
        }

        coordinator.dismissCurrent()
        XCTAssertEqual(coordinator.state, .idle)

        observer.signalChange(.authorizedDirectoryContentsChanged)
        drainMainQueue(seconds: 0.1)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testAuthorizedDirectoryConfigurationChangeDropsPendingDetectedStateImmediately() throws {
        let firstScreenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots-A", isDirectory: true)
        let secondScreenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots-B", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: firstScreenshotsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondScreenshotsURL, withIntermediateDirectories: true)

        let notificationCenter = NotificationCenter()
        var monitoredDirectoryURL = firstScreenshotsURL
        let observer = RecentScreenshotDirectoryObserver(
            authorizedDirectoryProvider: { monitoredDirectoryURL },
            notificationCenter: notificationCenter
        )
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { monitoredDirectoryURL }
        )
        let coordinator = RecentScreenshotCoordinator(
            observer: observer,
            locator: locator,
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.4
        )

        coordinator.start()

        let firstScreenshotURL = firstScreenshotsURL.appendingPathComponent("Screenshot 2026-03-07 at 10.00.00.png")
        try Data().write(to: firstScreenshotURL)
        coordinator.prepareForCaptureSession()
        waitForCondition("detected state from zero-byte screenshot in first folder") {
            if case .detected = coordinator.state {
                return true
            }

            return false
        }

        guard case .detected = coordinator.state else {
            return XCTFail("Expected detected state from first folder before rebind")
        }

        monitoredDirectoryURL = secondScreenshotsURL
        notificationCenter.post(name: ScreenshotDirectoryResolver.authorizedDirectoryDidChangeNotification, object: nil)
        waitForCondition("idle state after authorized directory rebind", timeout: 1) {
            if case .idle = coordinator.state {
                return true
            }

            return false
        }

        XCTAssertEqual(coordinator.state, .idle)
    }

    private func drainMainQueue(seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
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

            drainMainQueue(seconds: 0.01)
        }

        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }

    private func waitForConditionAsync(
        _ description: String,
        timeout: TimeInterval = 0.6,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for \(description)", file: file, line: line)
    }
}

@MainActor
private final class TestRecentScreenshotObserver: RecentScreenshotObserving {
    var onChange: ((RecentScreenshotObservationEvent) -> Void)?

    func start() {}
    func stop() {}

    func signalChange(_ event: RecentScreenshotObservationEvent) {
        onChange?(event)
    }
}

@MainActor
private final class NilClipboardImageProvider: RecentClipboardImageProviding {
    func start() {}
    func stop() {}
    func refreshNow() {}
    func recentImage(referenceDate: Date, maxAge: TimeInterval) -> RecentClipboardImage? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
}

private struct DelayedSignalProbeLocator: RecentScreenshotLocating {
    let fullScanDelay: TimeInterval
    let signalResult: RecentScreenshotScanResult
    let fullResult: RecentScreenshotScanResult

    func locateRecentScreenshot(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        Thread.sleep(forTimeInterval: fullScanDelay)
        return fullResult
    }

    func locateRecentScreenshotSignal(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        signalResult
    }
}
