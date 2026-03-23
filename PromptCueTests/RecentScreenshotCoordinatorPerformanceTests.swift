import Foundation
import XCTest
import PromptCueCore
@testable import Prompt_Cue

@MainActor
final class RecentScreenshotCoordinatorPerformanceTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private let benchmarkRunEnabled: Bool = {
#if PROMPTCUE_RUN_PERF_BENCHMARKS
        true
#else
        ProcessInfo.processInfo.environment["PROMPTCUE_RUN_PERF_BENCHMARKS"] == "1"
#endif
    }()
    private let benchmarkIterations = {
        if let rawValue = ProcessInfo.processInfo.environment["PROMPTCUE_RECENT_SCREENSHOT_BENCHMARK_ITERATIONS"],
           let parsedValue = Int(rawValue),
           parsedValue > 0 {
            return parsedValue
        }

        return 24
    }()
    private let benchmarkDelayMilliseconds = {
        if let rawValue = ProcessInfo.processInfo.environment["PROMPTCUE_RECENT_SCREENSHOT_BENCHMARK_DELAY_MS"],
           let parsedValue = Double(rawValue),
           parsedValue > 0 {
            return parsedValue
        }

        return 25.0
    }()

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

    func testPrepareForCaptureSessionReturnLatencyBenchmark() throws {
        try XCTSkipUnless(
            benchmarkRunEnabled,
            "Compile with -DPROMPTCUE_RUN_PERF_BENCHMARKS or set PROMPTCUE_RUN_PERF_BENCHMARKS=1 to run recent screenshot benchmarks."
        )

        let fixture = try makeFixture()
        let locatorDelay = benchmarkDelayMilliseconds / 1_000

        let baseline = benchmark(label: "slow-locator-baseline") {
            let locator = DelayedRecentScreenshotLocator(delay: locatorDelay, result: fixture.scanResult)
            _ = locator.locateRecentScreenshot(now: fixture.referenceDate, maxAge: 30)
        }

        let asyncReturn = try benchmark(label: "prepare-return") { iteration in
            let cacheDirectoryURL = tempDirectoryURL.appendingPathComponent(
                "TransientScreenshots-\(iteration)",
                isDirectory: true
            )
            let coordinator = RecentScreenshotCoordinator(
                observer: BenchmarkRecentScreenshotObserver(),
                locator: DelayedRecentScreenshotLocator(delay: locatorDelay, result: fixture.scanResult),
                cache: TransientScreenshotCache(baseDirectoryURL: cacheDirectoryURL),
                clipboardProvider: BenchmarkNilClipboardProvider(),
                maxAge: 30,
                settleGrace: 0.2,
                now: { fixture.referenceDate }
            )

            coordinator.start()
            let startedAt = CFAbsoluteTimeGetCurrent()
            coordinator.prepareForCaptureSession()
            let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000

            waitForCondition("benchmark preview-ready state", timeout: 2.0) {
                if case .previewReady = coordinator.state {
                    return true
                }

                return false
            }

            coordinator.stop()
            return elapsedMilliseconds
        }

        let speedup = baseline.totalMilliseconds / max(asyncReturn.totalMilliseconds, 0.001)
        print(
            String(
                format: "Recent screenshot benchmark [capture-open-prep]: baseline=%.2fms asyncReturn=%.2fms speedup=%.2fx iterations=%d delay=%.0fms",
                baseline.totalMilliseconds,
                asyncReturn.totalMilliseconds,
                speedup,
                benchmarkIterations,
                benchmarkDelayMilliseconds
            )
        )

        XCTAssertGreaterThan(baseline.totalMilliseconds, asyncReturn.totalMilliseconds)
        XCTAssertGreaterThan(
            speedup,
            8,
            "Expected prepareForCaptureSession() return latency to decouple materially from slow screenshot scans."
        )
    }

    func testIdleSettlePollingSignalProbeBenchmark() throws {
        try XCTSkipUnless(
            benchmarkRunEnabled,
            "Compile with -DPROMPTCUE_RUN_PERF_BENCHMARKS or set PROMPTCUE_RUN_PERF_BENCHMARKS=1 to run recent screenshot benchmarks."
        )

        let signalDelayMilliseconds = benchmarkDelayMilliseconds
        let settleWindow = 0.35
        var totalSignalProbeCount = 0
        var totalSignalBlockedMilliseconds = 0.0

        for iteration in 0..<benchmarkIterations {
            let cacheDirectoryURL = tempDirectoryURL.appendingPathComponent(
                "IdleTransientScreenshots-\(iteration)",
                isDirectory: true
            )
            let locator = CountingDelayedSignalLocator(
                signalDelay: signalDelayMilliseconds / 1_000,
                signalResult: RecentScreenshotScanResult(
                    signalCandidate: nil,
                    readableCandidate: nil,
                    recentTemporaryContainerDate: nil
                ),
                fullResult: RecentScreenshotScanResult(
                    signalCandidate: nil,
                    readableCandidate: nil,
                    recentTemporaryContainerDate: nil
                )
            )
            let coordinator = RecentScreenshotCoordinator(
                observer: BenchmarkRecentScreenshotObserver(),
                locator: locator,
                cache: TransientScreenshotCache(baseDirectoryURL: cacheDirectoryURL),
                clipboardProvider: BenchmarkNilClipboardProvider(),
                maxAge: 30,
                settleGrace: 0.2,
                now: Date.init
            )

            coordinator.start()
            coordinator.prepareForCaptureSession()

            let deadline = Date().addingTimeInterval(settleWindow)
            while Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }

            totalSignalProbeCount += locator.signalProbeCallCount
            totalSignalBlockedMilliseconds += locator.totalSignalBlockedMilliseconds
            coordinator.stop()
        }

        let averageSignalProbeCount = Double(totalSignalProbeCount) / Double(benchmarkIterations)
        let averageSignalBlockedMilliseconds = totalSignalBlockedMilliseconds / Double(benchmarkIterations)

        print(
            String(
                format: "Recent screenshot benchmark [idle-settle-signal-probe]: avg_calls=%.2f avg_blocked_ms=%.2f iterations=%d delay=%.0fms",
                averageSignalProbeCount,
                averageSignalBlockedMilliseconds,
                benchmarkIterations,
                signalDelayMilliseconds
            )
        )

        XCTAssertGreaterThan(averageSignalProbeCount, 0)
    }

    private func benchmark(
        label: String,
        operation: () -> Void
    ) -> BenchmarkResult {
        benchmark(label: label) { _ in
            operation()
            return nil
        }
    }

    private func benchmark(
        label: String,
        operation: (Int) -> Double?
    ) -> BenchmarkResult {
        var totalMilliseconds = 0.0

        for iteration in 0..<benchmarkIterations {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let customElapsedMilliseconds = operation(iteration)

            if let customElapsedMilliseconds {
                totalMilliseconds += customElapsedMilliseconds
            } else {
                totalMilliseconds += (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            }
        }

        let averageMilliseconds = totalMilliseconds / Double(benchmarkIterations)
        print(
            String(
                format: "Recent screenshot benchmark [%@]: total=%.2fms avg=%.2fms iterations=%d",
                label,
                totalMilliseconds,
                averageMilliseconds,
                benchmarkIterations
            )
        )

        return BenchmarkResult(
            totalMilliseconds: totalMilliseconds,
            averageMilliseconds: averageMilliseconds,
            iterationCount: benchmarkIterations
        )
    }

    private func makeFixture() throws -> BenchmarkFixture {
        let screenshotsURL = tempDirectoryURL.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotsURL, withIntermediateDirectories: true)

        let referenceDate = Date(timeIntervalSinceReferenceDate: 123_456)
        let screenshotURL = screenshotsURL.appendingPathComponent("Screenshot 2026-03-09 at 10.12.00 PM.png")
        try Data("png".utf8).write(to: screenshotURL)

        let candidate = RecentScreenshotCandidate(
            attachment: ScreenshotAttachment(
                path: screenshotURL.path,
                modifiedAt: referenceDate,
                fileSize: 3
            ),
            sourceKey: screenshotURL.lastPathComponent.lowercased()
        )

        return BenchmarkFixture(
            referenceDate: referenceDate,
            scanResult: RecentScreenshotScanResult(
                signalCandidate: candidate,
                readableCandidate: candidate,
                recentTemporaryContainerDate: nil
            )
        )
    }

    private func waitForCondition(
        _ description: String,
        timeout: TimeInterval,
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

private struct BenchmarkFixture {
    let referenceDate: Date
    let scanResult: RecentScreenshotScanResult
}

private struct BenchmarkResult {
    let totalMilliseconds: Double
    let averageMilliseconds: Double
    let iterationCount: Int
}

private struct DelayedRecentScreenshotLocator: RecentScreenshotLocating {
    let delay: TimeInterval
    let result: RecentScreenshotScanResult

    func locateRecentScreenshot(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        Thread.sleep(forTimeInterval: delay)
        return result
    }
}

private final class CountingDelayedSignalLocator: RecentScreenshotLocating {
    private let lock = NSLock()
    private let signalDelay: TimeInterval
    private let signalResult: RecentScreenshotScanResult
    private let fullResult: RecentScreenshotScanResult
    private(set) var signalProbeCallCount = 0
    private(set) var totalSignalBlockedMilliseconds = 0.0

    init(
        signalDelay: TimeInterval,
        signalResult: RecentScreenshotScanResult,
        fullResult: RecentScreenshotScanResult
    ) {
        self.signalDelay = signalDelay
        self.signalResult = signalResult
        self.fullResult = fullResult
    }

    func locateRecentScreenshot(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        fullResult
    }

    func locateRecentScreenshotSignal(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        Thread.sleep(forTimeInterval: signalDelay)
        let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000

        lock.lock()
        signalProbeCallCount += 1
        totalSignalBlockedMilliseconds += elapsedMilliseconds
        lock.unlock()
        return signalResult
    }
}

@MainActor
private final class BenchmarkRecentScreenshotObserver: RecentScreenshotObserving {
    var onChange: ((RecentScreenshotObservationEvent) -> Void)?

    func start() {}
    func stop() {}
}

@MainActor
private final class BenchmarkNilClipboardProvider: RecentClipboardImageProviding {
    var onImageDetected: (() -> Void)?
    func start() {}
    func stop() {}
    func refreshNow() {}
    func recentImage(referenceDate: Date, maxAge: TimeInterval) -> RecentClipboardImage? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
}
