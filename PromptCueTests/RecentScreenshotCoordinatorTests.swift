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
        coordinator.prepareForCaptureSession()

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
        coordinator.prepareForCaptureSession()

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
        coordinator.prepareForCaptureSession()
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
        coordinator.prepareForCaptureSession()

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

    func testResolveCurrentCaptureAttachmentReturnsImmediatelyWhenNoSignalsExist() async {
        let coordinator = RecentScreenshotCoordinator(
            observer: TestRecentScreenshotObserver(),
            locator: DelayedSignalProbeLocator(
                fullScanDelay: 0.3,
                signalResult: .init(signalCandidate: nil, readableCandidate: nil),
                fullResult: .init(signalCandidate: nil, readableCandidate: nil)
            ),
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("TransientScreenshots")),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.2
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()

        let startedAt = Date()
        let resolvedURL = await coordinator.resolveCurrentCaptureAttachment(timeout: 0.6)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertNil(resolvedURL)
        XCTAssertLessThan(elapsed, 0.18)
    }

    func testResolveCurrentCaptureAttachmentWaitsForPostOpenTemporarySignalAndLateFileArrival() async throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        let temporarySignalDate = Date()
        let locator = MutableRecentScreenshotLocator(
            fullScanDelay: 0.2,
            signalResult: .init(signalCandidate: nil, readableCandidate: nil, recentTemporaryContainerDate: nil),
            fullResult: .init(signalCandidate: nil, readableCandidate: nil, recentTemporaryContainerDate: nil)
        )

        let coordinator = RecentScreenshotCoordinator(
            observer: TestRecentScreenshotObserver(),
            locator: locator,
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.5
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()
        XCTAssertEqual(coordinator.state, .idle)

        locator.update(
            signalResult: .init(
                signalCandidate: nil,
                readableCandidate: nil,
                recentTemporaryContainerDate: temporarySignalDate
            )
        )

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-19 at 10.18.00 PM.png")
        let screenshotData = Data("png".utf8)
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            try? screenshotData.write(to: screenshotURL)
            let candidate = RecentScreenshotCandidate(
                attachment: ScreenshotAttachment(
                    path: screenshotURL.path,
                    modifiedAt: Date(),
                    fileSize: screenshotData.count
                ),
                sourceKey: screenshotURL.lastPathComponent.lowercased()
            )
            locator.update(
                signalResult: .init(
                    signalCandidate: candidate,
                    readableCandidate: nil,
                    recentTemporaryContainerDate: temporarySignalDate
                ),
                fullResult: .init(
                    signalCandidate: candidate,
                    readableCandidate: candidate,
                    recentTemporaryContainerDate: temporarySignalDate
                )
            )
        }

        let resolvedURL = await coordinator.resolveCurrentCaptureAttachment(timeout: 0.8)

        XCTAssertNotNil(resolvedURL)
        XCTAssertTrue(resolvedURL?.path.hasPrefix(cacheURL.path) == true)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(resolvedURL)), screenshotData)
    }

    func testDismissSuppressesLateFileArrivalForPendingTemporaryDetection() throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        let temporarySignalDate = Date()
        let locator = MutableRecentScreenshotLocator(
            signalResult: .init(
                signalCandidate: nil,
                readableCandidate: nil,
                recentTemporaryContainerDate: temporarySignalDate
            ),
            fullResult: .init(
                signalCandidate: nil,
                readableCandidate: nil,
                recentTemporaryContainerDate: temporarySignalDate
            )
        )

        let observer = TestRecentScreenshotObserver()
        let coordinator = RecentScreenshotCoordinator(
            observer: observer,
            locator: locator,
            cache: TransientScreenshotCache(baseDirectoryURL: cacheURL),
            clipboardProvider: NilClipboardImageProvider(),
            maxAge: 30,
            settleGrace: 0.5
        )

        coordinator.start()
        coordinator.prepareForCaptureSession()
        waitForCondition("pending detected state from temporary container") {
            if case .detected = coordinator.state {
                return true
            }

            return false
        }

        coordinator.dismissCurrent()
        XCTAssertEqual(coordinator.state, .idle)

        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-19 at 10.19.00 PM.png")
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
        locator.update(
            signalResult: .init(
                signalCandidate: candidate,
                readableCandidate: nil,
                recentTemporaryContainerDate: temporarySignalDate
            ),
            fullResult: .init(
                signalCandidate: candidate,
                readableCandidate: candidate,
                recentTemporaryContainerDate: temporarySignalDate
            )
        )
        observer.signalChange(.authorizedDirectoryContentsChanged)
        drainMainQueue(seconds: 0.3)

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

    func testMonitoringStartsOnlyDuringCaptureSession() {
        let observer = TestRecentScreenshotObserver()
        let clipboardProvider = CountingClipboardImageProvider()
        let coordinator = RecentScreenshotCoordinator(
            observer: observer,
            locator: DelayedSignalProbeLocator(
                fullScanDelay: 0,
                signalResult: .init(signalCandidate: nil, readableCandidate: nil),
                fullResult: .init(signalCandidate: nil, readableCandidate: nil)
            ),
            cache: TransientScreenshotCache(baseDirectoryURL: tempDirectoryURL.appendingPathComponent("TransientScreenshots")),
            clipboardProvider: clipboardProvider,
            maxAge: 30,
            settleGrace: 0.2
        )

        coordinator.start()

        XCTAssertEqual(observer.startCallCount, 0)
        XCTAssertEqual(observer.stopCallCount, 0)
        XCTAssertEqual(clipboardProvider.monitoringTransitions, [])

        coordinator.prepareForCaptureSession()

        XCTAssertEqual(observer.startCallCount, 1)
        XCTAssertEqual(clipboardProvider.monitoringTransitions, [true])

        coordinator.endCaptureSession()

        XCTAssertEqual(observer.stopCallCount, 1)
        XCTAssertEqual(clipboardProvider.monitoringTransitions, [true, false])
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

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private var isStarted = false

    func start() {
        isStarted = true
        startCallCount += 1
    }

    func stop() {
        isStarted = false
        stopCallCount += 1
    }

    func signalChange(_ event: RecentScreenshotObservationEvent) {
        guard isStarted else {
            return
        }

        onChange?(event)
    }
}

@MainActor
private final class NilClipboardImageProvider: RecentClipboardImageProviding {
    var onImageDetected: (() -> Void)?
    func start() {}
    func stop() {}
    func refreshNow() {}
    func recentImage(referenceDate: Date, maxAge: TimeInterval) -> RecentClipboardImage? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
}

@MainActor
private final class CountingClipboardImageProvider: RecentClipboardImageProviding {
    var onImageDetected: (() -> Void)?
    private(set) var monitoringTransitions: [Bool] = []

    func start() {}
    func stop() {}
    func setMonitoringActive(_ isActive: Bool) {
        monitoringTransitions.append(isActive)
    }
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

private final class MutableRecentScreenshotLocator: RecentScreenshotLocating {
    private let lock = NSLock()
    private let fullScanDelay: TimeInterval
    private var signalResult: RecentScreenshotScanResult
    private var fullResult: RecentScreenshotScanResult

    init(
        fullScanDelay: TimeInterval = 0,
        signalResult: RecentScreenshotScanResult,
        fullResult: RecentScreenshotScanResult
    ) {
        self.fullScanDelay = fullScanDelay
        self.signalResult = signalResult
        self.fullResult = fullResult
    }

    func update(
        signalResult: RecentScreenshotScanResult? = nil,
        fullResult: RecentScreenshotScanResult? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }

        if let signalResult {
            self.signalResult = signalResult
        }

        if let fullResult {
            self.fullResult = fullResult
        }
    }

    func locateRecentScreenshot(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        if fullScanDelay > 0 {
            Thread.sleep(forTimeInterval: fullScanDelay)
        }

        lock.lock()
        defer { lock.unlock() }
        return fullResult
    }

    func locateRecentScreenshotSignal(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        lock.lock()
        defer { lock.unlock() }
        return signalResult
    }
}
