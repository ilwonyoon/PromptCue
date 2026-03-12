import Foundation
import XCTest
import PromptCueCore
@testable import Prompt_Cue

@MainActor
final class AppStartupPerformanceTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var originalRetentionState: CardRetentionState!
    private let fixtureCardCount = 600
    private let benchmarkRunEnabled: Bool = {
#if PROMPTCUE_RUN_PERF_BENCHMARKS
        true
#else
        ProcessInfo.processInfo.environment["PROMPTCUE_RUN_PERF_BENCHMARKS"] == "1"
#endif
    }()
    private let benchmarkIterations = {
        if let rawValue = ProcessInfo.processInfo.environment["PROMPTCUE_STARTUP_BENCHMARK_ITERATIONS"],
           let parsedValue = Int(rawValue),
           parsedValue > 0 {
            return parsedValue
        }

        return 24
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalRetentionState = CardRetentionPreferences.load()
        CardRetentionPreferences.save(CardRetentionState(isAutoExpireEnabled: false))
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let originalRetentionState {
            CardRetentionPreferences.save(originalRetentionState)
        }
        originalRetentionState = nil
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }
        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testDeferredStartupSkipsImmediateMaintenance() throws {
        let (model, attachmentStore) = try makeModel(pruneDelayNanoseconds: 0)

        model.start(startupMode: .deferredMaintenance)

        XCTAssertEqual(attachmentStore.pruneCallCount, 0)
        model.stop()
    }

    func testImmediateStartupRunsMaintenanceSynchronously() throws {
        let (model, attachmentStore) = try makeModel(pruneDelayNanoseconds: 0)

        model.start(startupMode: .immediateMaintenance)

        XCTAssertEqual(attachmentStore.pruneCallCount, 1)
        model.stop()
    }

    func testCleanupTimerRemainsIdleWhenTTLIsDisabled() throws {
        let (model, _) = try makeModel(
            pruneDelayNanoseconds: 0,
            cleanupInterval: 0.02,
            databaseLabel: "cleanup-disabled"
        )
        defer { model.stop() }

        model.start(startupMode: .deferredMaintenance)
        drainMainQueue(seconds: 0.08)

        XCTAssertEqual(model.cards.count, fixtureCardCount)
    }

    func testCleanupTimerPurgesExpiredCardsWhenTTLEnabled() throws {
        CardRetentionPreferences.save(CardRetentionState(isAutoExpireEnabled: true))

        let (model, _) = try makeModel(
            pruneDelayNanoseconds: 0,
            cleanupInterval: 0.02,
            databaseLabel: "cleanup-enabled"
        )
        defer { model.stop() }

        model.start(startupMode: .deferredMaintenance)
        drainMainQueue(seconds: 0.08)

        XCTAssertTrue(model.cards.isEmpty)
    }

    func testCleanupTimerRespondsToRetentionPreferenceChanges() throws {
        let (model, _) = try makeModel(
            pruneDelayNanoseconds: 0,
            cleanupInterval: 0.02,
            databaseLabel: "cleanup-live-toggle"
        )
        defer { model.stop() }

        model.start(startupMode: .deferredMaintenance)
        drainMainQueue(seconds: 0.04)
        XCTAssertEqual(model.cards.count, fixtureCardCount)

        CardRetentionPreferences.save(CardRetentionState(isAutoExpireEnabled: true))
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        drainMainQueue(seconds: 0.08)

        XCTAssertTrue(model.cards.isEmpty)
    }

    func testStartupDeferredMaintenanceBenchmark() throws {
        try XCTSkipUnless(
            benchmarkRunEnabled,
            "Compile with -DPROMPTCUE_RUN_PERF_BENCHMARKS or set PROMPTCUE_RUN_PERF_BENCHMARKS=1 to run startup benchmarks."
        )

        let synchronous = try benchmark(
            label: "startup-synchronous-maintenance",
            startupMode: .immediateMaintenance
        )
        let deferred = try benchmark(
            label: "startup-deferred-maintenance",
            startupMode: .deferredMaintenance
        )

        let speedup = synchronous.totalMilliseconds / max(deferred.totalMilliseconds, 0.001)
        print(
            String(
                format: "Startup benchmark [start-return-latency]: synchronous=%.2fms deferred=%.2fms speedup=%.2fx iterations=%d cards=%d",
                synchronous.totalMilliseconds,
                deferred.totalMilliseconds,
                speedup,
                benchmarkIterations,
                fixtureCardCount
            )
        )

        XCTAssertGreaterThan(synchronous.totalMilliseconds, deferred.totalMilliseconds)
    }

    private func benchmark(
        label: String,
        startupMode: AppStartupMode
    ) throws -> BenchmarkResult {
        var totalMilliseconds = 0.0

        for iteration in 0..<benchmarkIterations {
            let (model, attachmentStore) = try makeModel(
                pruneDelayNanoseconds: 80_000_000,
                databaseLabel: "\(label)-\(iteration)"
            )

            let startedAt = CFAbsoluteTimeGetCurrent()
            model.start(startupMode: startupMode)
            totalMilliseconds += (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000

            if startupMode == .immediateMaintenance {
                XCTAssertEqual(attachmentStore.pruneCallCount, 1)
            } else {
                XCTAssertEqual(attachmentStore.pruneCallCount, 0)
            }

            model.stop()
        }

        let averageMilliseconds = totalMilliseconds / Double(benchmarkIterations)
        print(
            String(
                format: "Startup benchmark [%@]: total=%.2fms avg=%.2fms iterations=%d",
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

    private func makeModel(
        pruneDelayNanoseconds: UInt64,
        cleanupInterval: TimeInterval = 60,
        databaseLabel: String = "PromptCue"
    ) throws -> (AppModel, RecordingAttachmentStore) {
        let databaseURL = tempDirectoryURL.appendingPathComponent("\(databaseLabel).sqlite")
        let cardStore = CardStore(databaseURL: databaseURL)
        try cardStore.replaceAll(makeFixtureCards(count: fixtureCardCount))

        let attachmentStore = RecordingAttachmentStore(
            baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true),
            pruneDelayNanoseconds: pruneDelayNanoseconds
        )
        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: StartupRecentScreenshotCoordinator(),
            cleanupInterval: cleanupInterval
        )

        return (model, attachmentStore)
    }

    private func drainMainQueue(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func makeFixtureCards(count: Int) -> [CaptureCard] {
        (0..<count).map { index in
            CaptureCard(
                id: UUID(),
                text: "Startup fixture card \(index)",
                createdAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                sortOrder: Double(count - index)
            )
        }
    }
}

private struct BenchmarkResult {
    let totalMilliseconds: Double
    let averageMilliseconds: Double
    let iterationCount: Int
}

private final class RecordingAttachmentStore: AttachmentStoring {
    let baseDirectoryURL: URL
    private let pruneDelayNanoseconds: UInt64

    private(set) var pruneCallCount = 0

    init(baseDirectoryURL: URL, pruneDelayNanoseconds: UInt64) {
        self.baseDirectoryURL = baseDirectoryURL
        self.pruneDelayNanoseconds = pruneDelayNanoseconds
    }

    func importScreenshot(from sourceURL: URL, ownerID: UUID) throws -> URL {
        sourceURL
    }

    func removeManagedFile(at fileURL: URL) throws {}

    func pruneUnreferencedManagedFiles(referencedFileURLs: Set<URL>) throws {
        pruneCallCount += 1
        if pruneDelayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(pruneDelayNanoseconds) / 1_000_000_000)
        }
    }

    func isManagedFile(_ fileURL: URL) -> Bool {
        true
    }
}

@MainActor
private final class StartupRecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var state: RecentScreenshotState = .idle
    var onStateChange: ((RecentScreenshotState) -> Void)?

    func start() {}
    func stop() {}
    func prepareForCaptureSession() {}
    func refreshNow() {}
    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? { nil }
    func consumeCurrent() {}
    func dismissCurrent() {}
    func suspendExpiration() {}
    func resumeExpiration() {}
}
