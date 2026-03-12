import Foundation
import XCTest
import PromptCueCore
@testable import Prompt_Cue

@MainActor
final class CloudSyncApplyPerformanceTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private let fixtureCardCount = 600
    private let upsertCount = 400
    private let deleteCount = 200
    private let benchmarkRunEnabled: Bool = {
#if PROMPTCUE_RUN_PERF_BENCHMARKS
        true
#else
        ProcessInfo.processInfo.environment["PROMPTCUE_RUN_PERF_BENCHMARKS"] == "1"
#endif
    }()
    private let benchmarkIterations = {
        if let rawValue = ProcessInfo.processInfo.environment["PROMPTCUE_CLOUD_SYNC_APPLY_BENCHMARK_ITERATIONS"],
           let parsedValue = Int(rawValue),
           parsedValue > 0 {
            return parsedValue
        }

        return 24
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

    func testRemoteApplyBenchmark() throws {
        try XCTSkipUnless(
            benchmarkRunEnabled,
            "Compile with -DPROMPTCUE_RUN_PERF_BENCHMARKS or set PROMPTCUE_RUN_PERF_BENCHMARKS=1 to run cloud sync apply benchmarks."
        )

        let legacy = try benchmark(label: "legacy-array-eager-import") { iteration in
            let fixture = try makeFixture(label: "legacy-\(iteration)")
            let harness = LegacyRemoteApplyHarness(
                cards: fixture.localCards,
                selectedCardIDs: fixture.selectedIDs,
                cardStore: fixture.cardStore,
                attachmentStore: fixture.attachmentStore
            )

            try harness.applyRemoteChanges(fixture.changes)
            XCTAssertEqual(harness.cards.count, fixtureCardCount - deleteCount)
            return fixture.attachmentStore.importCallCount
        }

        let optimized = try benchmark(label: "indexed-lazy-import") { iteration in
            let fixture = try makeFixture(label: "optimized-\(iteration)")
            let model = AppModel(
                cardStore: fixture.cardStore,
                attachmentStore: fixture.attachmentStore,
                recentScreenshotCoordinator: BenchmarkRecentScreenshotCoordinator()
            )
            model.reloadCards(runNonCriticalMaintenance: false)
            applySelection(fixture.selectedIDs, to: model)

            fixture.attachmentStore.resetMetrics()
            model.applyRemoteChanges(fixture.changes)

            XCTAssertEqual(model.cards.count, fixtureCardCount - deleteCount)
            return fixture.attachmentStore.importCallCount
        }

        let speedup = legacy.totalMilliseconds / max(optimized.totalMilliseconds, 0.001)
        let importReduction = legacy.averageImportCount / max(optimized.averageImportCount, 0.001)
        print(
            String(
                format: "Cloud sync apply benchmark [remote-apply]: legacy=%.2fms optimized=%.2fms speedup=%.2fx avgLegacyImports=%.2f avgOptimizedImports=%.2f importReduction=%.2fx iterations=%d cards=%d upserts=%d deletes=%d",
                legacy.totalMilliseconds,
                optimized.totalMilliseconds,
                speedup,
                legacy.averageImportCount,
                optimized.averageImportCount,
                importReduction,
                benchmarkIterations,
                fixtureCardCount,
                upsertCount,
                deleteCount
            )
        )

        XCTAssertGreaterThan(legacy.totalMilliseconds, optimized.totalMilliseconds)
        XCTAssertGreaterThan(legacy.averageImportCount, optimized.averageImportCount)
    }

    func testRemoteApplyDispatchBenchmark() async throws {
        try XCTSkipUnless(
            benchmarkRunEnabled,
            "Compile with -DPROMPTCUE_RUN_PERF_BENCHMARKS or set PROMPTCUE_RUN_PERF_BENCHMARKS=1 to run cloud sync apply benchmarks."
        )

        let synchronous = try await benchmarkAsync(label: "direct-apply-return") { iteration in
            let fixture = try makeDispatchFixture(label: "direct-\(iteration)")

            let startedAt = CFAbsoluteTimeGetCurrent()
            fixture.model.applyRemoteChanges(fixture.changes)
            return (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        }

        let queued = try await benchmarkAsync(label: "queued-dispatch-return") { iteration in
            let fixture = try makeDispatchFixture(label: "queued-\(iteration)")

            let startedAt = CFAbsoluteTimeGetCurrent()
            fixture.model.scheduleRemoteChangesForApply(fixture.changes)
            let elapsedMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            await fixture.model.waitForRemoteApplyToDrain()
            return elapsedMilliseconds
        }

        let speedup = synchronous.totalMilliseconds / max(queued.totalMilliseconds, 0.001)
        print(
            String(
                format: "Cloud sync apply benchmark [dispatch-return]: synchronous=%.2fms queued=%.2fms speedup=%.2fx iterations=%d cards=%d upserts=%d deletes=%d",
                synchronous.totalMilliseconds,
                queued.totalMilliseconds,
                speedup,
                benchmarkIterations,
                fixtureCardCount,
                upsertCount,
                deleteCount
            )
        )

        XCTAssertGreaterThan(synchronous.totalMilliseconds, queued.totalMilliseconds)
    }

    func testQueuedRemoteApplyCompletionBenchmark() async throws {
        try XCTSkipUnless(
            benchmarkRunEnabled,
            "Compile with -DPROMPTCUE_RUN_PERF_BENCHMARKS or set PROMPTCUE_RUN_PERF_BENCHMARKS=1 to run cloud sync apply benchmarks."
        )

        let legacy = try await benchmarkAsync(label: "queued-eager-preprocess-completion") { iteration in
            let fixture = try makeQueuedCompletionFixture(label: "legacy-queued-\(iteration)")

            let startedAt = CFAbsoluteTimeGetCurrent()
            let preprocessedChanges = try legacyQueuedPreprocess(
                fixture.changes,
                attachmentStore: fixture.attachmentStore
            )
            fixture.model.applyRemoteChanges(preprocessedChanges)
            return (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        }

        let optimized = try await benchmarkAsync(label: "queued-selective-import-completion") { iteration in
            let fixture = try makeQueuedCompletionFixture(label: "optimized-queued-\(iteration)")

            let startedAt = CFAbsoluteTimeGetCurrent()
            fixture.model.scheduleRemoteChangesForApply(fixture.changes)
            await fixture.model.waitForRemoteApplyToDrain()
            return (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        }

        let speedup = legacy.totalMilliseconds / max(optimized.totalMilliseconds, 0.001)
        print(
            String(
                format: "Cloud sync apply benchmark [queued-completion]: eager=%.2fms optimized=%.2fms speedup=%.2fx iterations=%d cards=%d upserts=%d deletes=%d",
                legacy.totalMilliseconds,
                optimized.totalMilliseconds,
                speedup,
                benchmarkIterations,
                fixtureCardCount,
                upsertCount,
                deleteCount
            )
        )

        XCTAssertGreaterThan(legacy.totalMilliseconds, optimized.totalMilliseconds)
    }

    private func benchmark(
        label: String,
        operation: (Int) throws -> Int
    ) throws -> RemoteApplyBenchmarkResult {
        var totalMilliseconds = 0.0
        var totalImportCount = 0

        for iteration in 0..<benchmarkIterations {
            let startedAt = CFAbsoluteTimeGetCurrent()
            totalImportCount += try autoreleasepool {
                try operation(iteration)
            }
            totalMilliseconds += (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
        }

        let averageMilliseconds = totalMilliseconds / Double(benchmarkIterations)
        let averageImportCount = Double(totalImportCount) / Double(benchmarkIterations)
        print(
            String(
                format: "Cloud sync apply benchmark [%@]: total=%.2fms avg=%.2fms avgImports=%.2f iterations=%d",
                label,
                totalMilliseconds,
                averageMilliseconds,
                averageImportCount,
                benchmarkIterations
            )
        )

        return RemoteApplyBenchmarkResult(
            totalMilliseconds: totalMilliseconds,
            averageMilliseconds: averageMilliseconds,
            averageImportCount: averageImportCount
        )
    }

    private func benchmarkAsync(
        label: String,
        operation: (Int) async throws -> Double
    ) async throws -> DispatchBenchmarkResult {
        var totalMilliseconds = 0.0

        for iteration in 0..<benchmarkIterations {
            totalMilliseconds += try await operation(iteration)
        }

        let averageMilliseconds = totalMilliseconds / Double(benchmarkIterations)
        print(
            String(
                format: "Cloud sync apply benchmark [%@]: total=%.2fms avg=%.2fms iterations=%d",
                label,
                totalMilliseconds,
                averageMilliseconds,
                benchmarkIterations
            )
        )

        return DispatchBenchmarkResult(
            totalMilliseconds: totalMilliseconds,
            averageMilliseconds: averageMilliseconds
        )
    }

    private func makeFixture(label: String) throws -> RemoteApplyBenchmarkFixture {
        let attachmentsURL = tempDirectoryURL.appendingPathComponent("\(label)-Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)

        let localCards = makeLocalCards(attachmentsURL: attachmentsURL)
        let selectedIDs = makeSelectedIDs(from: localCards)
        let assetFileURL = tempDirectoryURL.appendingPathComponent("\(label)-remote-asset.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetFileURL)

        let changes = makeRemoteChanges(localCards: localCards, assetFileURL: assetFileURL)
        let cardStore = CardStore(
            databaseURL: tempDirectoryURL.appendingPathComponent("\(label)-PromptCue.sqlite")
        )
        try cardStore.replaceAll(localCards)

        let attachmentStore = BenchmarkAttachmentStore(baseDirectoryURL: attachmentsURL)
        return RemoteApplyBenchmarkFixture(
            localCards: localCards,
            selectedIDs: selectedIDs,
            changes: changes,
            cardStore: cardStore,
            attachmentStore: attachmentStore
        )
    }

    private func makeLocalCards(attachmentsURL: URL) -> [CaptureCard] {
        (0..<fixtureCardCount).map { index in
            let localWins = index < upsertCount && index.isMultiple(of: 2)
            let screenshotPath = localWins
                ? attachmentsURL.appendingPathComponent("local-\(index).png").path
                : nil
            let lastCopiedAt: Date?
            if localWins {
                lastCopiedAt = Date(timeIntervalSinceReferenceDate: 2_000 + Double(index))
            } else {
                lastCopiedAt = nil
            }

            return CaptureCard(
                id: UUID(),
                text: "Local \(index)",
                createdAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                screenshotPath: screenshotPath,
                lastCopiedAt: lastCopiedAt,
                sortOrder: Double(fixtureCardCount - index)
            )
        }
    }

    private func makeSelectedIDs(from cards: [CaptureCard]) -> Set<UUID> {
        Set(cards.enumerated().compactMap { index, card in
            index.isMultiple(of: 4) ? card.id : nil
        })
    }

    private func makeRemoteChanges(localCards: [CaptureCard], assetFileURL: URL) -> [SyncChange] {
        var changes: [SyncChange] = []

        for index in 0..<upsertCount {
            let localCard = localCards[index]
            let remoteWins = !index.isMultiple(of: 2)
            let remoteCard = CaptureCard(
                id: localCard.id,
                text: remoteWins ? "Remote wins \(index)" : "Remote loses \(index)",
                createdAt: localCard.createdAt,
                screenshotPath: nil,
                lastCopiedAt: remoteWins
                    ? Date(timeIntervalSinceReferenceDate: 4_000 + Double(index))
                    : Date(timeIntervalSinceReferenceDate: 1_000 + Double(index)),
                sortOrder: localCard.sortOrder
            )
            changes.append(.upsert(remoteCard, screenshotAssetURL: assetFileURL))
        }

        for index in (fixtureCardCount - deleteCount)..<fixtureCardCount {
            changes.append(.delete(localCards[index].id))
        }

        return changes
    }

    private func applySelection(_ selectedIDs: Set<UUID>, to model: AppModel) {
        for card in model.cards where selectedIDs.contains(card.id) {
            model.toggleSelection(for: card)
        }
    }

    private func makeDispatchFixture(label: String) throws -> DispatchBenchmarkFixture {
        let attachmentsURL = tempDirectoryURL.appendingPathComponent("\(label)-DispatchAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)

        let localCards = makeLocalCards(attachmentsURL: attachmentsURL)
        let selectedIDs = makeSelectedIDs(from: localCards)
        let assetFileURL = tempDirectoryURL.appendingPathComponent("\(label)-dispatch-asset.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: assetFileURL)
        let changes = makeRemoteChanges(localCards: localCards, assetFileURL: assetFileURL)
        let cardStore = CardStore(
            databaseURL: tempDirectoryURL.appendingPathComponent("\(label)-Dispatch.sqlite")
        )
        try cardStore.replaceAll(localCards)
        let attachmentStore = BenchmarkAttachmentStore(baseDirectoryURL: attachmentsURL)

        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: BenchmarkRecentScreenshotCoordinator()
        )
        model.reloadCards(runNonCriticalMaintenance: false)
        applySelection(selectedIDs, to: model)
        return DispatchBenchmarkFixture(
            model: model,
            changes: changes
        )
    }

    private func makeQueuedCompletionFixture(label: String) throws -> QueuedCompletionBenchmarkFixture {
        let attachmentsURL = tempDirectoryURL.appendingPathComponent("\(label)-QueuedAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)

        let localCards = makeLocalCards(attachmentsURL: attachmentsURL)
        let selectedIDs = makeSelectedIDs(from: localCards)
        let assetFileURL = tempDirectoryURL.appendingPathComponent("\(label)-queued-asset.png")
        try Data(repeating: 0x41, count: 262_144).write(to: assetFileURL)
        let changes = makeRemoteChanges(localCards: localCards, assetFileURL: assetFileURL)
        let cardStore = CardStore(
            databaseURL: tempDirectoryURL.appendingPathComponent("\(label)-Queued.sqlite")
        )
        try cardStore.replaceAll(localCards)
        let attachmentStore = BenchmarkAttachmentStore(baseDirectoryURL: attachmentsURL)

        let model = AppModel(
            cardStore: cardStore,
            attachmentStore: attachmentStore,
            recentScreenshotCoordinator: BenchmarkRecentScreenshotCoordinator()
        )
        model.reloadCards(runNonCriticalMaintenance: false)
        applySelection(selectedIDs, to: model)
        return QueuedCompletionBenchmarkFixture(
            model: model,
            changes: changes,
            attachmentStore: attachmentStore
        )
    }

    private func legacyQueuedPreprocess(
        _ changes: [SyncChange],
        attachmentStore: BenchmarkAttachmentStore
    ) throws -> [SyncChange] {
        try changes.map { change in
            switch change {
            case .upsert(let remoteCard, let screenshotAssetURL):
                guard let screenshotAssetURL,
                      FileManager.default.fileExists(atPath: screenshotAssetURL.path)
                else {
                    return change
                }

                let importedURL = try attachmentStore.importScreenshot(
                    from: screenshotAssetURL,
                    ownerID: remoteCard.id
                )
                return .upsert(
                    CaptureCard(
                        id: remoteCard.id,
                        text: remoteCard.text,
                        createdAt: remoteCard.createdAt,
                        screenshotPath: importedURL.path,
                        lastCopiedAt: remoteCard.lastCopiedAt,
                        sortOrder: remoteCard.sortOrder
                    ),
                    screenshotAssetURL: nil
                )

            case .delete:
                return change
            }
        }
    }
}

private struct RemoteApplyBenchmarkFixture {
    let localCards: [CaptureCard]
    let selectedIDs: Set<UUID>
    let changes: [SyncChange]
    let cardStore: CardStore
    let attachmentStore: BenchmarkAttachmentStore
}

private struct RemoteApplyBenchmarkResult {
    let totalMilliseconds: Double
    let averageMilliseconds: Double
    let averageImportCount: Double
}

private struct DispatchBenchmarkResult {
    let totalMilliseconds: Double
    let averageMilliseconds: Double
}

private struct DispatchBenchmarkFixture {
    let model: AppModel
    let changes: [SyncChange]
}

private struct QueuedCompletionBenchmarkFixture {
    let model: AppModel
    let changes: [SyncChange]
    let attachmentStore: BenchmarkAttachmentStore
}

private final class BenchmarkAttachmentStore: AttachmentStoring {
    let baseDirectoryURL: URL

    private(set) var importCallCount = 0
    private var sink = 0

    init(baseDirectoryURL: URL) {
        self.baseDirectoryURL = baseDirectoryURL
    }

    func importScreenshot(from sourceURL: URL, ownerID: UUID) throws -> URL {
        importCallCount += 1
        simulateImportWork(seed: ownerID.hashValue)
        return baseDirectoryURL
            .appendingPathComponent(ownerID.uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension(sourceURL.pathExtension)
    }

    func removeManagedFile(at fileURL: URL) throws {}
    func pruneUnreferencedManagedFiles(referencedFileURLs: Set<URL>) throws {}

    func isManagedFile(_ fileURL: URL) -> Bool {
        let standardizedURL = fileURL.standardizedFileURL
        let basePath = baseDirectoryURL.standardizedFileURL.path
        let filePath = standardizedURL.path
        return filePath == basePath || filePath.hasPrefix(basePath + "/")
    }

    func resetMetrics() {
        importCallCount = 0
        sink = 0
    }

    private func simulateImportWork(seed: Int) {
        var value = seed
        for _ in 0..<2_400 {
            value = (value &* 1_664_525 &+ 1_013_904_223) & 0x7fff_ffff
        }
        sink ^= value
    }
}

@MainActor
private final class LegacyRemoteApplyHarness {
    private let cardStore: CardStore
    private let attachmentStore: AttachmentStoring

    private(set) var cards: [CaptureCard]
    private(set) var selectedCardIDs: Set<UUID>

    init(
        cards: [CaptureCard],
        selectedCardIDs: Set<UUID>,
        cardStore: CardStore,
        attachmentStore: AttachmentStoring
    ) {
        self.cards = cards
        self.selectedCardIDs = selectedCardIDs
        self.cardStore = cardStore
        self.attachmentStore = attachmentStore
    }

    func applyRemoteChanges(_ changes: [SyncChange]) throws {
        let originalCardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        var updatedCards = cards
        var removedCards: [CaptureCard] = []

        for change in changes {
            switch change {
            case .upsert(let remoteCard, let screenshotAssetURL):
                let cardWithScreenshot = importRemoteScreenshotIfNeeded(
                    card: remoteCard,
                    assetURL: screenshotAssetURL
                )

                if let index = updatedCards.firstIndex(where: { $0.id == cardWithScreenshot.id }) {
                    let local = updatedCards[index]
                    updatedCards[index] = mergeCard(local: local, remote: cardWithScreenshot)
                } else {
                    updatedCards.append(cardWithScreenshot)
                }

            case .delete(let id):
                if let index = updatedCards.firstIndex(where: { $0.id == id }) {
                    removedCards.append(updatedCards[index])
                    updatedCards.remove(at: index)
                }
            }
        }

        let sorted = CardStackOrdering.sort(updatedCards)
        let sortedIDs = Set(sorted.map(\.id))
        let deletedIDs = originalCardsByID.keys.filter { !sortedIDs.contains($0) }
        let changedCards = sorted.filter { card in
            originalCardsByID[card.id] != card
        }

        try cardStore.delete(ids: deletedIDs)
        try cardStore.upsert(changedCards)

        cards = sorted
        selectedCardIDs = selectedCardIDs.filter { id in
            sorted.contains(where: { $0.id == id })
        }

        if !removedCards.isEmpty {
            cleanupManagedAttachments(removedCards: removedCards, remainingCards: sorted)
        }
    }

    private func importRemoteScreenshotIfNeeded(card: CaptureCard, assetURL: URL?) -> CaptureCard {
        guard let assetURL, FileManager.default.fileExists(atPath: assetURL.path) else {
            return card
        }

        do {
            let importedURL = try attachmentStore.importScreenshot(
                from: assetURL,
                ownerID: card.id
            )
            return CaptureCard(
                id: card.id,
                text: card.text,
                createdAt: card.createdAt,
                screenshotPath: importedURL.path,
                lastCopiedAt: card.lastCopiedAt,
                sortOrder: card.sortOrder
            )
        } catch {
            return card
        }
    }

    private func mergeCard(local: CaptureCard, remote: CaptureCard) -> CaptureCard {
        let winner: CaptureCard
        switch (local.lastCopiedAt, remote.lastCopiedAt) {
        case (.some(let localDate), .some(let remoteDate)):
            winner = localDate >= remoteDate ? local : remote
        case (.some, .none):
            winner = local
        case (.none, .some):
            winner = remote
        case (.none, .none):
            winner = local
        }

        let resolvedScreenshotPath = winner.screenshotPath ?? local.screenshotPath ?? remote.screenshotPath
        guard resolvedScreenshotPath != winner.screenshotPath else {
            return winner
        }

        return CaptureCard(
            id: winner.id,
            text: winner.text,
            createdAt: winner.createdAt,
            screenshotPath: resolvedScreenshotPath,
            lastCopiedAt: winner.lastCopiedAt,
            sortOrder: winner.sortOrder
        )
    }

    private func cleanupManagedAttachments(removedCards: [CaptureCard], remainingCards: [CaptureCard]) {
        let referencedURLs = Set(remainingCards.compactMap { $0.screenshotURL?.standardizedFileURL })

        for card in removedCards {
            guard let screenshotURL = card.screenshotURL?.standardizedFileURL else {
                continue
            }

            guard attachmentStore.isManagedFile(screenshotURL) else {
                continue
            }

            guard !referencedURLs.contains(screenshotURL) else {
                continue
            }

            try? attachmentStore.removeManagedFile(at: screenshotURL)
        }
    }
}

@MainActor
private final class BenchmarkRecentScreenshotCoordinator: RecentScreenshotCoordinating {
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
