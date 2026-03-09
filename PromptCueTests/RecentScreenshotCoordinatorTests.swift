import Foundation
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
            authorizedDirectoryProvider: { screenshotsURL },
            temporaryItemsDirectoryProvider: {
                self.tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
            }
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
        observer.signalChange(.authorizedDirectoryChanged)
        drainMainQueue()

        guard case .detected(let sessionID, _) = coordinator.state else {
            return XCTFail("Expected detected state after zero-byte screenshot signal")
        }

        try Data("png".utf8).write(to: screenshotURL)
        observer.signalChange(.authorizedDirectoryChanged)
        drainMainQueue()

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
            authorizedDirectoryProvider: { screenshotsURL },
            temporaryItemsDirectoryProvider: {
                self.tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
            }
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
        drainMainQueue()

        guard case .previewReady(_, let previewCacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected preview-ready state after prepareForCaptureSession")
        }

        XCTAssertTrue(previewCacheURL.path.hasPrefix(cacheURL.path))
        XCTAssertEqual(try Data(contentsOf: previewCacheURL), Data("png".utf8))
    }

    func testResolveCurrentCaptureAttachmentWaitsForDetectedScreenshotToBecomeReadable() async throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let temporaryItemsURL = tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
        let childDirectoryURL = temporaryItemsURL
            .appendingPathComponent("NSIRD_screencaptureui_resolve", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: screenshotsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: childDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let observer = TestRecentScreenshotObserver()
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { screenshotsURL },
            temporaryItemsDirectoryProvider: { temporaryItemsURL }
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

        let filename = "Screenshot 2026-03-07 at 10.09.00.png"
        let temporaryScreenshotURL = childDirectoryURL.appendingPathComponent(filename)
        let finalScreenshotURL = screenshotsURL.appendingPathComponent(filename)
        try Data().write(to: temporaryScreenshotURL)
        observer.signalChange(.temporaryScreenshotContainerChanged)
        drainMainQueue()

        guard case .detected = coordinator.state else {
            return XCTFail("Expected detected state before resolve")
        }

        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            try? Data("png".utf8).write(to: finalScreenshotURL)
        }

        let resolvedURL = await coordinator.resolveCurrentCaptureAttachment(timeout: 0.6)

        XCTAssertNotNil(resolvedURL)
        XCTAssertTrue(resolvedURL?.path.hasPrefix(cacheURL.path) == true)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(resolvedURL)), Data("png".utf8))
    }

    func testPrepareForCaptureSessionPromotesTempSignalToFinalPreviewAcrossPathChange() throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let temporaryItemsURL = tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
        let childDirectoryURL = temporaryItemsURL
            .appendingPathComponent("NSIRD_screencaptureui_123", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)

        try FileManager.default.createDirectory(
            at: screenshotsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: childDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let observer = TestRecentScreenshotObserver()
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { screenshotsURL },
            temporaryItemsDirectoryProvider: { temporaryItemsURL }
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

        let filename = "Screenshot 2026-03-07 at 10.12.35 PM.png"
        let temporaryScreenshotURL = childDirectoryURL.appendingPathComponent(filename)
        try Data().write(to: temporaryScreenshotURL)

        coordinator.prepareForCaptureSession()
        drainMainQueue()

        guard case .detected(let sessionID, _) = coordinator.state else {
            return XCTFail("Expected detected state for zero-byte temporary screenshot")
        }

        let finalScreenshotURL = screenshotsURL.appendingPathComponent(filename)
        try Data("png".utf8).write(to: finalScreenshotURL)

        coordinator.prepareForCaptureSession()
        drainMainQueue()

        guard case .previewReady(let previewSessionID, let previewCacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected preview-ready state after final screenshot becomes readable")
        }

        XCTAssertEqual(previewSessionID, sessionID)
        XCTAssertTrue(previewCacheURL.path.hasPrefix(cacheURL.path))
        XCTAssertEqual(try Data(contentsOf: previewCacheURL), Data("png".utf8))
    }

    func testPrepareForCaptureSessionDetectsRecentTemporaryContainerWithoutImageFile() throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let temporaryItemsURL = tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
        let childDirectoryURL = temporaryItemsURL
            .appendingPathComponent("NSIRD_screencaptureui_early", isDirectory: true)
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)

        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childDirectoryURL, withIntermediateDirectories: true)

        let observer = TestRecentScreenshotObserver()
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { screenshotsURL },
            temporaryItemsDirectoryProvider: { temporaryItemsURL }
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
        coordinator.prepareForCaptureSession()
        drainMainQueue()

        guard case .detected = coordinator.state else {
            return XCTFail("Expected detected state from recent temporary screenshot container")
        }
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
            authorizedDirectoryProvider: { screenshotsURL },
            temporaryItemsDirectoryProvider: {
                self.tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
            }
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
        observer.signalChange(.authorizedDirectoryChanged)
        drainMainQueue()

        guard case .previewReady = coordinator.state else {
            return XCTFail("Expected preview-ready state before dismissal")
        }

        coordinator.dismissCurrent()
        XCTAssertEqual(coordinator.state, .idle)

        observer.signalChange(.authorizedDirectoryChanged)
        drainMainQueue()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testTemporaryContainerDetectionCreatesImmediateDetectedPlaceholderBeforeReadableFileExists() throws {
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
            authorizedDirectoryProvider: { screenshotsURL },
            temporaryItemsDirectoryProvider: {
                self.tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
            }
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
        observer.signalChange(.temporaryScreenshotContainerDetected)
        drainMainQueue()

        guard case .detected = coordinator.state else {
            return XCTFail("Expected immediate detected state after screenshot container signal")
        }
    }

    func testTemporaryAndFinalScreenshotPathsReuseSameSessionID() throws {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        let temporaryItemsURL = tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
        let childDirectoryURL = temporaryItemsURL.appendingPathComponent(
            "NSIRD_screencaptureui_123",
            isDirectory: true
        )
        let cacheURL = tempDirectoryURL.appendingPathComponent("TransientScreenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: childDirectoryURL, withIntermediateDirectories: true)

        let observer = TestRecentScreenshotObserver()
        let locator = RecentScreenshotLocator(
            fileManager: .default,
            authorizedDirectoryProvider: { screenshotsURL },
            temporaryItemsDirectoryProvider: { temporaryItemsURL }
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

        let filename = "Screenshot 2026-03-07 at 10.00.00.png"
        let tempScreenshotURL = childDirectoryURL.appendingPathComponent(filename)
        let finalScreenshotURL = screenshotsURL.appendingPathComponent(filename)

        try Data().write(to: tempScreenshotURL)
        observer.signalChange(.temporaryScreenshotContainerChanged)
        drainMainQueue()

        guard case .detected(let detectedSessionID, _) = coordinator.state else {
            return XCTFail("Expected detected state from temporary screenshot")
        }

        try Data("png".utf8).write(to: finalScreenshotURL)
        observer.signalChange(.authorizedDirectoryChanged)
        drainMainQueue(seconds: 0.1)

        guard case .previewReady(let previewSessionID, let previewCacheURL, .ready) = coordinator.state else {
            return XCTFail("Expected preview-ready state after final screenshot write")
        }

        XCTAssertEqual(previewSessionID, detectedSessionID)
        XCTAssertTrue(previewCacheURL.path.hasPrefix(cacheURL.path))
    }

    func testTemporaryItemsObserverEmitsAfterChildFolderRegistration() throws {
        let temporaryItemsURL = tempDirectoryURL.appendingPathComponent("TemporaryItems", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryItemsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let observer = RecentScreenshotDirectoryObserver(
            fileManager: .default,
            authorizedDirectoryProvider: { nil },
            temporaryItemsDirectoryProvider: { temporaryItemsURL }
        )

        let fileEvent = expectation(description: "File event inside child NSIRD folder")
        var observedRootEvent = false
        observer.onChange = { [fileEvent] _ in
            if observedRootEvent {
                fileEvent.fulfill()
            } else {
                observedRootEvent = true
            }
        }

        observer.start()

        let childDirectoryURL = temporaryItemsURL
            .appendingPathComponent("NSIRD_screencaptureui_123", isDirectory: true)
        try FileManager.default.createDirectory(
            at: childDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        drainMainQueue(seconds: 0.3)

        let screenshotURL = childDirectoryURL.appendingPathComponent("Screenshot.png")
        try Data("png".utf8).write(to: screenshotURL)

        wait(for: [fileEvent], timeout: 2)
        observer.stop()
    }

    private func drainMainQueue(seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
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
