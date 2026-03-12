import Foundation
import XCTest
import PromptCueCore
@testable import Prompt_Cue

@MainActor
final class CloudSyncPushPerformanceTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private let fixtureCardCount = 120
    private let benchmarkRunEnabled: Bool = {
#if PROMPTCUE_RUN_PERF_BENCHMARKS
        true
#else
        ProcessInfo.processInfo.environment["PROMPTCUE_RUN_PERF_BENCHMARKS"] == "1"
#endif
    }()
    private let benchmarkIterations = {
        if let rawValue = ProcessInfo.processInfo.environment["PROMPTCUE_CLOUD_SYNC_PUSH_BENCHMARK_ITERATIONS"],
           let parsedValue = Int(rawValue),
           parsedValue > 0 {
            return parsedValue
        }

        return 120
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

    func testPushCopiedCardsUsesBatchDispatchForMultipleCards() {
        let cloudSync = BenchmarkCloudSyncEngine()
        let model = makeModel(cloudSyncEngine: cloudSync)

        model.pushCopiedCardsToCloudSync(makeCopiedCards(count: 6))

        XCTAssertEqual(cloudSync.localPushCount, 0)
        XCTAssertEqual(cloudSync.batchPushCount, 1)
        XCTAssertEqual(cloudSync.lastBatchCardCount, 6)
    }

    func testPushCopiedCardsKeepsSingleDispatchForSingleCard() {
        let cloudSync = BenchmarkCloudSyncEngine()
        let model = makeModel(cloudSyncEngine: cloudSync)

        model.pushCopiedCardsToCloudSync(makeCopiedCards(count: 1))

        XCTAssertEqual(cloudSync.localPushCount, 1)
        XCTAssertEqual(cloudSync.batchPushCount, 0)
    }

    func testCopiedCardSyncDispatchBenchmark() throws {
        try XCTSkipUnless(
            benchmarkRunEnabled,
            "Compile with -DPROMPTCUE_RUN_PERF_BENCHMARKS or set PROMPTCUE_RUN_PERF_BENCHMARKS=1 to run CloudSync push benchmarks."
        )

        let copiedCards = makeCopiedCards(count: fixtureCardCount)
        let cloudSync = BenchmarkCloudSyncEngine()
        let model = makeModel(cloudSyncEngine: cloudSync)

        let perCard = benchmark(label: "per-card-push") {
            cloudSync.resetMetrics()
            model.pushCopiedCardsToCloudSync(copiedCards, forcePerCardDispatch: true)
            XCTAssertEqual(cloudSync.localPushCount, copiedCards.count)
            XCTAssertEqual(cloudSync.batchPushCount, 0)
        }

        let batched = benchmark(label: "batched-push") {
            cloudSync.resetMetrics()
            model.pushCopiedCardsToCloudSync(copiedCards)
            XCTAssertEqual(cloudSync.localPushCount, 0)
            XCTAssertEqual(cloudSync.batchPushCount, 1)
            XCTAssertEqual(cloudSync.lastBatchCardCount, copiedCards.count)
        }

        let speedup = perCard.totalMilliseconds / max(batched.totalMilliseconds, 0.001)
        print(
            String(
                format: "Cloud sync benchmark [copied-card-dispatch]: perCard=%.2fms batched=%.2fms speedup=%.2fx iterations=%d cards=%d",
                perCard.totalMilliseconds,
                batched.totalMilliseconds,
                speedup,
                benchmarkIterations,
                fixtureCardCount
            )
        )

        XCTAssertGreaterThan(perCard.totalMilliseconds, batched.totalMilliseconds)
    }

    private func benchmark(
        label: String,
        operation: () -> Void
    ) -> BenchmarkResult {
        var totalMilliseconds = 0.0

        for _ in 0..<benchmarkIterations {
            let startedAt = CFAbsoluteTimeGetCurrent()
            autoreleasepool(invoking: operation)
            totalMilliseconds += (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        }

        let averageMilliseconds = totalMilliseconds / Double(benchmarkIterations)
        print(
            String(
                format: "Cloud sync benchmark [%@]: total=%.2fms avg=%.2fms iterations=%d",
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

    private func makeModel(cloudSyncEngine: (any CloudSyncControlling)?) -> AppModel {
        AppModel(
            cardStore: CardStore(databaseURL: tempDirectoryURL.appendingPathComponent("PromptCue.sqlite")),
            attachmentStore: AttachmentStore(
                baseDirectoryURL: tempDirectoryURL.appendingPathComponent("Attachments", isDirectory: true)
            ),
            recentScreenshotCoordinator: TestRecentScreenshotCoordinator(),
            cloudSyncEngine: cloudSyncEngine
        )
    }

    private func makeCopiedCards(count: Int) -> [CaptureCard] {
        (0..<count).map { index in
            CaptureCard(
                id: UUID(),
                text: "Copied card \(index)",
                createdAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                lastCopiedAt: Date(timeIntervalSinceReferenceDate: Double(index + 1_000)),
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

@MainActor
private final class BenchmarkCloudSyncEngine: CloudSyncControlling {
    weak var delegate: CloudSyncDelegate?

    private(set) var localPushCount = 0
    private(set) var batchPushCount = 0
    private(set) var deletionPushCount = 0
    private(set) var lastBatchCardCount = 0
    private var sink = 0

    func setup() async {}
    func stop() {}
    func fetchRemoteChanges() {}
    func handleRemoteNotification() {}

    func pushLocalChange(card: CaptureCard) {
        localPushCount += 1
        simulateOperationSetup(seed: card.id.hashValue)
    }

    func pushDeletion(id: UUID) {
        deletionPushCount += 1
        simulateOperationSetup(seed: id.hashValue)
    }

    func pushBatch(cards: [CaptureCard], deletions: [UUID]) {
        batchPushCount += 1
        lastBatchCardCount = cards.count
        simulateOperationSetup(seed: cards.count &+ deletions.count)
    }

    func resetMetrics() {
        localPushCount = 0
        batchPushCount = 0
        deletionPushCount = 0
        lastBatchCardCount = 0
        sink = 0
    }

    private func simulateOperationSetup(seed: Int) {
        var value = seed
        for _ in 0..<1_200 {
            value = (value &* 1_664_525 &+ 1_013_904_223) & 0x7fff_ffff
        }
        sink ^= value
    }
}

@MainActor
private final class TestRecentScreenshotCoordinator: RecentScreenshotCoordinating {
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
