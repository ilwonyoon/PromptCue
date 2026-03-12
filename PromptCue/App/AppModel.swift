import AppKit
import CloudKit
import Combine
import Foundation
import PromptCueCore

enum CardSection {
    case active
    case copied

    func matches(_ card: CaptureCard) -> Bool {
        switch self {
        case .active:
            return !card.isCopied
        case .copied:
            return card.isCopied
        }
    }
}

enum AppStartupMode {
    case immediateMaintenance
    case deferredMaintenance
}

enum CaptureSuggestedTargetChoice: Equatable {
    case automatic(CaptureSuggestedTarget)
    case explicit(CaptureSuggestedTarget)

    var target: CaptureSuggestedTarget {
        switch self {
        case .automatic(let target), .explicit(let target):
            return target
        }
    }

    var isAutomatic: Bool {
        if case .automatic = self {
            return true
        }

        return false
    }
}

enum CloudSyncInitialFetchMode {
    case immediate
    case deferred
}

struct RemoteApplyPlan {
    let sortedCards: [CaptureCard]
    let changedCards: [CaptureCard]
    let deletedIDs: [UUID]
    let survivingIDs: Set<UUID>
    let removedCards: [CaptureCard]
}

enum RemoteMergeWinner {
    case local
    case remote
}

@MainActor
final class AppModel: ObservableObject {
    private static let deferredStartupDelayNanoseconds: UInt64 = 1_500_000_000

    @Published var cards: [CaptureCard] = []
    @Published var storageErrorMessage: String?
    @Published var recentScreenshotState: RecentScreenshotState = .idle
    @Published var draftText = ""
    @Published var draftEditorMetrics: CaptureEditorMetrics = .empty
    @Published var availableSuggestedTargets: [CaptureSuggestedTarget] = []
    @Published var isShowingCaptureSuggestedTargetChooser = false
    @Published var selectedCaptureSuggestedTargetIndex = 0
    @Published var selectedCardIDs: Set<UUID> = []
    @Published private(set) var isMultiSelectMode = false
    @Published var stagedCopiedCardIDs: [UUID] = []
    @Published var isSubmittingCapture = false

    let cardStore: CardStore
    let attachmentStore: AttachmentStoring
    let recentScreenshotCoordinator: RecentScreenshotCoordinating
    let suggestedTargetProvider: any SuggestedTargetProviding
    let cloudSyncEngineFactory: @MainActor () -> any CloudSyncControlling
    private let cleanupInterval: TimeInterval
    var cloudSyncEngine: (any CloudSyncControlling)?
    private var cleanupTimer: Timer?
    var captureSubmissionTask: Task<Bool, Never>?
    var hasStartedSuggestedTargetProvider = false
    private var hasStartedRecentScreenshotCoordinator = false
    var isCaptureSuggestedTargetPresentationActive = false
    var isStackSuggestedTargetPresentationActive = false
    private var retentionSettingsObserver: NSObjectProtocol?
    private var syncToggleObserver: NSObjectProtocol?
    private var deferredStartupMaintenanceTask: Task<Void, Never>?
    var deferredCloudSyncFetchTask: Task<Void, Never>?
    var remoteApplyTask: Task<Void, Never>?
    var pendingRemoteChanges: [SyncChange] = []
    var draftSuggestedTargetOverride: CaptureSuggestedTarget?

    init(
        cardStore: CardStore,
        attachmentStore: AttachmentStoring,
        recentScreenshotCoordinator: RecentScreenshotCoordinating,
        suggestedTargetProvider: (any SuggestedTargetProviding)? = nil,
        cloudSyncEngine: (any CloudSyncControlling)? = nil,
        cloudSyncEngineFactory: @escaping @MainActor () -> any CloudSyncControlling = { CloudSyncEngine() },
        cleanupInterval: TimeInterval = 60
    ) {
        self.cardStore = cardStore
        self.attachmentStore = attachmentStore
        self.recentScreenshotCoordinator = recentScreenshotCoordinator
        self.suggestedTargetProvider = suggestedTargetProvider ?? NoopSuggestedTargetProvider()
        self.cloudSyncEngine = cloudSyncEngine
        self.cloudSyncEngineFactory = cloudSyncEngineFactory
        self.cleanupInterval = cleanupInterval
        self.suggestedTargetProvider.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncAvailableSuggestedTargets()
            }
        }
    }

    convenience init() {
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let syncEnabled = !isTestEnvironment && CloudSyncPreferences.load()
        self.init(
            cardStore: CardStore(),
            attachmentStore: AttachmentStore(),
            recentScreenshotCoordinator: RecentScreenshotCoordinator(),
            suggestedTargetProvider: RecentSuggestedAppTargetTracker(),
            cloudSyncEngine: syncEnabled ? CloudSyncEngine() : nil
        )
    }

    var stagedCopiedCount: Int {
        stagedCopiedCardIDs.count
    }

    var hasStagedCopiedCards: Bool {
        !stagedCopiedCardIDs.isEmpty
    }

    var stagedCopiedCardsInClickOrder: [CaptureCard] {
        let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return stagedCopiedCardIDs.compactMap { cardsByID[$0] }
    }

    func start(startupMode: AppStartupMode = .immediateMaintenance) {
        ensureCloudSyncToggleObserver()
        retentionSettingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCleanupTimer()
            }
        }
        recentScreenshotCoordinator.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.applyRecentScreenshotState(state)
            }
        }
        applyRecentScreenshotState(recentScreenshotCoordinator.state)
        reloadCards(runNonCriticalMaintenance: startupMode == .immediateMaintenance)
        refreshCleanupTimer()
        if startupMode == .deferredMaintenance {
            scheduleDeferredStartupMaintenance()
        }
        startCloudSync(
            initialFetchMode: startupMode == .immediateMaintenance ? .immediate : .deferred
        )
    }

    func stop() {
        deferredStartupMaintenanceTask?.cancel()
        deferredStartupMaintenanceTask = nil
        deferredCloudSyncFetchTask?.cancel()
        deferredCloudSyncFetchTask = nil
        remoteApplyTask?.cancel()
        remoteApplyTask = nil
        pendingRemoteChanges.removeAll()
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        if let retentionSettingsObserver {
            NotificationCenter.default.removeObserver(retentionSettingsObserver)
        }
        retentionSettingsObserver = nil
        isCaptureSuggestedTargetPresentationActive = false
        isStackSuggestedTargetPresentationActive = false
        stopSuggestedTargetProvider()
        recentScreenshotCoordinator.onStateChange = nil
        if hasStartedRecentScreenshotCoordinator {
            recentScreenshotCoordinator.stop()
            hasStartedRecentScreenshotCoordinator = false
        }
        applyRecentScreenshotState(.idle)
        availableSuggestedTargets = []
        draftSuggestedTargetOverride = nil
        isShowingCaptureSuggestedTargetChooser = false
        selectedCaptureSuggestedTargetIndex = 0
        isMultiSelectMode = false
        selectedCardIDs.removeAll()
        stagedCopiedCardIDs.removeAll()
        if let syncToggleObserver {
            NotificationCenter.default.removeObserver(syncToggleObserver)
        }
        syncToggleObserver = nil
        stopCloudSyncEngine()
    }

    func reloadCards(runNonCriticalMaintenance: Bool = true) {
        do {
            cards = sortedCards(try cardStore.load())
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Card load failed", error: error)
            return
        }

        guard runNonCriticalMaintenance else {
            return
        }

        performNonCriticalStartupMaintenance()
    }

    func toggleSelection(for card: CaptureCard) {
        if selectedCardIDs.contains(card.id) {
            selectedCardIDs.remove(card.id)
        } else {
            selectedCardIDs.insert(card.id)
        }
    }

    func enterMultiSelectMode() {
        isMultiSelectMode = true
        selectedCardIDs.removeAll()
        stagedCopiedCardIDs.removeAll()
    }

    func exitMultiSelectMode() {
        isMultiSelectMode = false
        selectedCardIDs.removeAll()
        stagedCopiedCardIDs.removeAll()
    }

    func clearSelection() {
        selectedCardIDs.removeAll()
    }

    func assignSuggestedTarget(_ target: CaptureSuggestedTarget, to card: CaptureCard) {
        let updatedCard = card.updatingSuggestedTarget(target)
        let updatedCards = sortedCards(
            cards.map { existingCard in
                guard existingCard.id == card.id else {
                    return existingCard
                }

                return updatedCard
            }
        )

        do {
            try cardStore.upsert(updatedCard)
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Suggested target update failed", error: error)
            return
        }

        cards = updatedCards
        cloudSyncEngine?.pushLocalChange(card: updatedCard)
    }

    @discardableResult
    func toggleMultiCopiedCard(_ card: CaptureCard) -> String? {
        if let existingIndex = stagedCopiedCardIDs.firstIndex(of: card.id) {
            stagedCopiedCardIDs.remove(at: existingIndex)
        } else {
            stagedCopiedCardIDs.append(card.id)
        }

        syncStagedCopyMode()
        return syncStagedMultiCopyClipboard()
    }

    func commitDeferredCopies() {
        let deferredCopiedIDs = stagedCopiedCardIDs
        guard !deferredCopiedIDs.isEmpty else {
            exitMultiSelectMode()
            return
        }

        markCopied(orderedIDs: deferredCopiedIDs)
        exitMultiSelectMode()
    }

    func delete(card: CaptureCard) {
        let updatedCards = cards.filter { $0.id != card.id }

        do {
            try cardStore.delete(id: card.id)
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Card delete failed", error: error)
            return
        }

        cards = updatedCards
        selectedCardIDs.remove(card.id)
        stagedCopiedCardIDs.removeAll { $0 == card.id }
        syncStagedCopyMode()
        if hasStagedCopiedCards {
            _ = syncStagedMultiCopyClipboard()
        }
        cleanupManagedAttachments(removedCards: [card], remainingCards: updatedCards)
        cloudSyncEngine?.pushDeletion(id: card.id)
    }

    func purgeExpiredCards() {
        guard let ttl = CardRetentionPreferences.load().effectiveTTL else {
            return
        }

        let now = Date()
        let expiredCards = cards.filter { $0.isExpired(relativeTo: now, ttl: ttl) }
        guard !expiredCards.isEmpty else {
            return
        }

        let filtered = sortedCards(cards.filter { !$0.isExpired(relativeTo: now, ttl: ttl) })
        let expiredIDs = expiredCards.map(\.id)

        do {
            try cardStore.delete(ids: expiredIDs)
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Card purge failed", error: error)
            return
        }

        cards = filtered
        selectedCardIDs = selectedCardIDs.filter { id in
            filtered.contains(where: { $0.id == id })
        }
        stagedCopiedCardIDs.removeAll { id in
            filtered.contains(where: { $0.id == id })
                == false
        }
        syncStagedCopyMode()
        if hasStagedCopiedCards {
            _ = syncStagedMultiCopyClipboard()
        }
        cleanupManagedAttachments(removedCards: expiredCards, remainingCards: filtered)
        cloudSyncEngine?.pushBatch(cards: [], deletions: expiredCards.map(\.id))
    }

    private func markCopied(orderedIDs: [UUID]) {
        let uniqueOrderedIDs = orderedIDs.reduce(into: [UUID]()) { partialResult, id in
            if partialResult.contains(id) == false {
                partialResult.append(id)
            }
        }
        let copiedIDs = Set(uniqueOrderedIDs)
        let copiedAt = Date()
        let copiedTimestamps = Dictionary(
            uniqueKeysWithValues: uniqueOrderedIDs.enumerated().map { offset, id in
                (
                    id,
                    copiedAt.addingTimeInterval(
                        TimeInterval(uniqueOrderedIDs.count - offset) * 0.001
                    )
                )
            }
        )
        let updatedCards = sortedCards(
            cards.map { card in
                guard copiedIDs.contains(card.id) else {
                    return card
                }

                return card.markCopied(at: copiedTimestamps[card.id] ?? copiedAt)
            }
        )
        let copiedCards = updatedCards.filter { copiedIDs.contains($0.id) }

        do {
            try cardStore.upsert(copiedCards)
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Card copy state save failed", error: error)
            return
        }

        cards = updatedCards
        clearSelection()
        stagedCopiedCardIDs.removeAll()
        pushCopiedCardsToCloudSync(copiedCards, forcePerCardDispatch: true)
    }

    func syncStagedMultiCopyClipboard() -> String? {
        let stagedCards = stagedCopiedCardsInClickOrder
        guard !stagedCards.isEmpty else {
            return nil
        }

        let payload = ClipboardFormatter.string(for: stagedCards)
        ClipboardFormatter.copyToPasteboard(cards: stagedCards)
        return payload
    }

    func syncStagedCopyMode() {
        isMultiSelectMode = hasStagedCopiedCards
    }

    func sortedCards(_ cards: [CaptureCard]) -> [CaptureCard] {
        CardStackOrdering.sort(cards)
    }

    func cleanupManagedAttachments(removedCards: [CaptureCard], remainingCards: [CaptureCard]) {
        let referencedURLs = Set(remainingCards.compactMap { $0.screenshotURL?.standardizedFileURL })
        let removableURLs = Set(removedCards.compactMap { $0.screenshotURL?.standardizedFileURL })

        for fileURL in removableURLs where !referencedURLs.contains(fileURL) {
            do {
                try attachmentStore.removeManagedFile(at: fileURL)
            } catch {
                logStorageFailure("Managed attachment cleanup failed", error: error)
            }
        }
    }

    private func pruneOrphanedManagedAttachments() {
        let referencedURLs = Set(cards.compactMap { $0.screenshotURL?.standardizedFileURL })

        do {
            try attachmentStore.pruneUnreferencedManagedFiles(referencedFileURLs: referencedURLs)
        } catch {
            logStorageFailure("Managed attachment prune failed", error: error)
        }
    }

    func cleanupImportedAttachment(atPath path: String?) {
        guard let path else {
            return
        }

        do {
            try attachmentStore.removeManagedFile(at: URL(fileURLWithPath: path))
        } catch {
            logStorageFailure("Imported attachment rollback failed", error: error)
        }
    }

    private func migrateLegacyExternalAttachmentsIfNeeded() {
        var migratedCards = cards
        var didChange = false

        for index in migratedCards.indices {
            let card = migratedCards[index]
            guard let screenshotURL = card.screenshotURL?.standardizedFileURL else {
                continue
            }

            guard !attachmentStore.isManagedFile(screenshotURL) else {
                continue
            }

            let migratedPath: String?
            do {
                migratedPath = try ScreenshotAttachmentPersistencePolicy.prepareForPersistence(
                    storedPath: screenshotURL.path,
                    ownerID: card.id,
                    attachmentStore: attachmentStore
                ).storedPath
            } catch {
                logStorageFailure("Legacy screenshot migration failed", error: error)
                migratedPath = nil
            }

            if migratedPath != card.screenshotPath {
                migratedCards[index] = CaptureCard(
                    id: card.id,
                    text: card.text,
                    suggestedTarget: card.suggestedTarget,
                    createdAt: card.createdAt,
                    screenshotPath: migratedPath,
                    lastCopiedAt: card.lastCopiedAt,
                    sortOrder: card.sortOrder
                )
                didChange = true
            }
        }

        guard didChange else {
            return
        }

        let sortedMigratedCards = sortedCards(migratedCards)
        let originalCardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let migratedChanges = sortedMigratedCards.filter { migratedCard in
            originalCardsByID[migratedCard.id] != migratedCard
        }

        do {
            try cardStore.upsert(migratedChanges)
            storageErrorMessage = nil
            cards = sortedMigratedCards
        } catch {
            logStorageFailure("Legacy screenshot save failed", error: error)
        }
    }

    func logStorageFailure(_ message: String, error: Error) {
        storageErrorMessage = "\(message): \(error.localizedDescription)"
        NSLog("%@: %@", message, String(describing: error))
    }

    private func performNonCriticalStartupMaintenance() {
        migrateLegacyExternalAttachmentsIfNeeded()
        purgeExpiredCards()
        pruneOrphanedManagedAttachments()
    }

    private func refreshCleanupTimer() {
        guard cleanupInterval > 0, CardRetentionPreferences.load().effectiveTTL != nil else {
            cleanupTimer?.invalidate()
            cleanupTimer = nil
            return
        }

        guard cleanupTimer == nil else {
            return
        }

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeExpiredCards()
            }
        }
        cleanupTimer?.tolerance = min(cleanupInterval * 0.25, 15)
    }

    func ensureRecentScreenshotCoordinatorStarted() {
        guard !hasStartedRecentScreenshotCoordinator else {
            return
        }

        recentScreenshotCoordinator.start()
        hasStartedRecentScreenshotCoordinator = true
        applyRecentScreenshotState(recentScreenshotCoordinator.state)
    }

    func ensureSuggestedTargetProviderStarted() {
        guard !hasStartedSuggestedTargetProvider else {
            return
        }

        suggestedTargetProvider.start()
        hasStartedSuggestedTargetProvider = true
        syncAvailableSuggestedTargets()
    }

    func refreshSuggestedTargetProviderLifecycle() {
        guard isCaptureSuggestedTargetPresentationActive || isStackSuggestedTargetPresentationActive else {
            stopSuggestedTargetProvider()
            return
        }

        ensureSuggestedTargetProviderStarted()
    }

    func stopSuggestedTargetProvider() {
        guard hasStartedSuggestedTargetProvider else {
            availableSuggestedTargets = []
            syncCaptureSuggestedTargetSelection()
            return
        }

        suggestedTargetProvider.stop()
        hasStartedSuggestedTargetProvider = false
        availableSuggestedTargets = []
        syncCaptureSuggestedTargetSelection()
    }

    private func scheduleDeferredStartupMaintenance() {
        deferredStartupMaintenanceTask?.cancel()
        deferredStartupMaintenanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.deferredStartupDelayNanoseconds)

            guard let self, !Task.isCancelled else {
                return
            }

            self.deferredStartupMaintenanceTask = nil
            self.performNonCriticalStartupMaintenance()
        }
    }

    func scheduleDeferredCloudSyncFetch() {
        deferredCloudSyncFetchTask?.cancel()
        deferredCloudSyncFetchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.deferredStartupDelayNanoseconds)

            guard let self, !Task.isCancelled else {
                return
            }

            self.deferredCloudSyncFetchTask = nil
            self.cloudSyncEngine?.fetchRemoteChanges()
        }
    }

    func nextTopSortOrder(in section: CardSection) -> Double {
        let maximum = cards
            .filter { section.matches($0) }
            .map(\.sortOrder)
            .max() ?? 0

        return maximum + 1
    }

    // MARK: - Cloud Sync

    private func ensureCloudSyncToggleObserver() {
        guard syncToggleObserver == nil else {
            return
        }

        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        syncToggleObserver = NotificationCenter.default.addObserver(
            forName: .cloudSyncEnabledChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            Task { @MainActor [weak self] in
                self?.setSyncEnabled(enabled)
            }
        }
    }

    func stopCloudSyncEngine() {
        cloudSyncEngine?.delegate = nil
        cloudSyncEngine?.stop()
        cloudSyncEngine = nil
    }
}
