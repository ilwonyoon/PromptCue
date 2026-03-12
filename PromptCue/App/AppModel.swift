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

private struct RemoteApplyPlan {
    let sortedCards: [CaptureCard]
    let changedCards: [CaptureCard]
    let deletedIDs: [UUID]
    let survivingIDs: Set<UUID>
    let removedCards: [CaptureCard]
}

private enum RemoteMergeWinner {
    case local
    case remote
}

@MainActor
final class AppModel: ObservableObject {
    private static let deferredStartupDelayNanoseconds: UInt64 = 1_500_000_000

    @Published var cards: [CaptureCard] = []
    @Published var storageErrorMessage: String?
    @Published private(set) var recentScreenshotState: RecentScreenshotState = .idle
    @Published var draftText = ""
    @Published var draftEditorMetrics: CaptureEditorMetrics = .empty
    @Published var availableSuggestedTargets: [CaptureSuggestedTarget] = []
    @Published var isShowingCaptureSuggestedTargetChooser = false
    @Published var selectedCaptureSuggestedTargetIndex = 0
    @Published var selectedCardIDs: Set<UUID> = []
    @Published private(set) var isMultiSelectMode = false
    @Published private(set) var stagedCopiedCardIDs: [UUID] = []
    @Published var isSubmittingCapture = false
    @Published var editingCaptureCardID: UUID?

    let cardStore: CardStore
    let attachmentStore: AttachmentStoring
    let recentScreenshotCoordinator: RecentScreenshotCoordinating
    let suggestedTargetProvider: any SuggestedTargetProviding
    private let cloudSyncEngineFactory: @MainActor () -> any CloudSyncControlling
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
    private var deferredCloudSyncFetchTask: Task<Void, Never>?
    private var remoteApplyTask: Task<Void, Never>?
    private var pendingRemoteChanges: [SyncChange] = []
    var draftSuggestedTargetOverride: CaptureSuggestedTarget?
    var draftRecentScreenshotStateOverride: RecentScreenshotState?
    var isSeedingCaptureFromCopiedCard = false

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

    var isEditingCaptureCard: Bool {
        editingCaptureCardID != nil
    }

    var showsRecentScreenshotSlot: Bool {
        switch recentScreenshotState {
        case .detected, .previewReady:
            return true
        case .idle, .expired, .consumed:
            return false
        }
    }

    var showsRecentScreenshotPlaceholder: Bool {
        switch recentScreenshotState {
        case .detected, .previewReady(_, _, .loading):
            return true
        case .idle, .previewReady(_, _, .ready), .expired, .consumed:
            return false
        }
    }

    var recentScreenshotPreviewURL: URL? {
        switch recentScreenshotState {
        case .previewReady(_, let cacheURL, .ready):
            return cacheURL
        case .idle, .detected, .previewReady(_, _, .loading), .expired, .consumed:
            return nil
        }
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
        recentScreenshotCoordinator.onStateChange = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncRecentScreenshotState()
            }
        }
        syncRecentScreenshotState()
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
        draftRecentScreenshotStateOverride = nil
        editingCaptureCardID = nil
        isSeedingCaptureFromCopiedCard = false
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

    func refreshPendingScreenshot() {
        if hasSeededCaptureSession {
            draftRecentScreenshotStateOverride = nil
        }
        ensureRecentScreenshotCoordinatorStarted()
        recentScreenshotCoordinator.prepareForCaptureSession()
        recentScreenshotCoordinator.suspendExpiration()
        syncRecentScreenshotState()
    }

    func dismissPendingScreenshot() {
        if draftRecentScreenshotStateOverride != nil {
            draftRecentScreenshotStateOverride = .idle
            syncRecentScreenshotState()
            return
        }

        recentScreenshotCoordinator.dismissCurrent()
        syncRecentScreenshotState()
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

    @discardableResult
    func copyRaw(card: CaptureCard) -> String {
        let payload = ClipboardFormatter.rawString(for: card)
        ClipboardFormatter.copyRawToPasteboard(card: card)
        markCopied(orderedIDs: [card.id])
        exitMultiSelectMode()
        return payload
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

    private func syncStagedMultiCopyClipboard() -> String? {
        let stagedCards = stagedCopiedCardsInClickOrder
        guard !stagedCards.isEmpty else {
            return nil
        }

        let payload = ClipboardFormatter.string(for: stagedCards)
        ClipboardFormatter.copyToPasteboard(cards: stagedCards)
        return payload
    }

    private func syncStagedCopyMode() {
        isMultiSelectMode = hasStagedCopiedCards
    }

    func pushCopiedCardsToCloudSync(
        _ copiedCards: [CaptureCard],
        forcePerCardDispatch: Bool = false
    ) {
        guard let cloudSyncEngine, !copiedCards.isEmpty else {
            return
        }

        if forcePerCardDispatch || copiedCards.count == 1 {
            for card in copiedCards {
                cloudSyncEngine.pushLocalChange(card: card)
            }
            return
        }

        cloudSyncEngine.pushBatch(cards: copiedCards, deletions: [])
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

    private func scheduleDeferredCloudSyncFetch() {
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

    func syncRecentScreenshotState() {
        applyRecentScreenshotState(draftRecentScreenshotStateOverride ?? recentScreenshotCoordinator.state)
    }

    private func applyRecentScreenshotState(_ state: RecentScreenshotState) {
        recentScreenshotState = state
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

    private func stopCloudSyncEngine() {
        cloudSyncEngine?.delegate = nil
        cloudSyncEngine?.stop()
        cloudSyncEngine = nil
    }

    private func startCloudSync(initialFetchMode: CloudSyncInitialFetchMode = .immediate) {

        guard let cloudSyncEngine else { return }
        cloudSyncEngine.delegate = self

        Task {
            await cloudSyncEngine.setup()
            switch initialFetchMode {
            case .immediate:
                cloudSyncEngine.fetchRemoteChanges()
            case .deferred:
                scheduleDeferredCloudSyncFetch()
            }
        }
    }

    func handleCloudRemoteNotification() {
        deferredCloudSyncFetchTask?.cancel()
        deferredCloudSyncFetchTask = nil
        cloudSyncEngine?.handleRemoteNotification()
    }

    func setSyncEnabled(_ enabled: Bool) {
        if enabled, cloudSyncEngine == nil {
            let engine = cloudSyncEngineFactory()
            cloudSyncEngine = engine
            startCloudSync(initialFetchMode: .immediate)
        } else if !enabled {
            stopCloudSyncEngine()
            deferredCloudSyncFetchTask?.cancel()
            deferredCloudSyncFetchTask = nil
        }
    }
}

// MARK: - CloudSyncDelegate

extension AppModel: CloudSyncDelegate {
    func cloudSyncDidComplete(_ engine: CloudSyncEngine) {
        // Observable by CloudSyncSettingsModel via NotificationCenter
        NotificationCenter.default.post(name: .cloudSyncDidComplete, object: nil)
    }

    func cloudSync(_ engine: CloudSyncEngine, didFailWithError message: String) {
        NotificationCenter.default.post(
            name: .cloudSyncDidFail,
            object: nil,
            userInfo: ["message": message]
        )
    }

    func cloudSync(_ engine: CloudSyncEngine, accountStatusChanged status: CloudSyncAccountStatus) {
        NotificationCenter.default.post(
            name: .cloudSyncAccountStatusChanged,
            object: nil,
            userInfo: ["status": status]
        )
    }

    func cloudSync(_ engine: CloudSyncEngine, didReceiveChanges changes: [SyncChange]) {
        scheduleRemoteChangesForApply(changes)
    }

    func applyRemoteChanges(_ changes: [SyncChange]) {
        let plan = buildRemoteApplyPlan(changes)
        applyRemoteApplyPlan(plan)
    }

    func scheduleRemoteChangesForApply(_ changes: [SyncChange]) {
        guard !changes.isEmpty else {
            return
        }

        pendingRemoteChanges.append(contentsOf: changes)
        guard remoteApplyTask == nil else {
            return
        }

        remoteApplyTask = Task { @MainActor [weak self] in
            await self?.processPendingRemoteChanges()
        }
    }

    func waitForRemoteApplyToDrain() async {
        while let remoteApplyTask {
            await remoteApplyTask.value
        }
    }

    private func mergeRemoteChange(
        local: CaptureCard?,
        remote: CaptureCard,
        assetURL: URL?
    ) -> CaptureCard {
        let remoteManagedScreenshotPath = ScreenshotAttachmentPersistencePolicy.managedStoredPath(
            from: remote.screenshotPath,
            attachmentStore: attachmentStore
        )

        guard let local else {
            return card(
                remote,
                replacingScreenshotPath: importRemoteScreenshotPathIfNeeded(
                    for: remote,
                    assetURL: assetURL,
                    shouldImport: remoteManagedScreenshotPath == nil
                ) ?? remoteManagedScreenshotPath
            )
        }

        let winner = mergeWinner(local: local, remote: remote)
        let importedRemoteScreenshotPath = importRemoteScreenshotPathIfNeeded(
            for: remote,
            assetURL: assetURL,
            shouldImport: shouldImportRemoteScreenshot(
                local: local,
                remote: remote,
                winner: winner,
                assetURL: assetURL
            )
        )
        return mergeCard(
            local: local,
            remote: remote,
            winner: winner,
            importedRemoteScreenshotPath: importedRemoteScreenshotPath,
            remoteManagedScreenshotPath: remoteManagedScreenshotPath
        )
    }

    private func importRemoteScreenshotPathIfNeeded(
        for card: CaptureCard,
        assetURL: URL?,
        shouldImport: Bool
    ) -> String? {
        guard shouldImport, let assetURL else {
            return nil
        }

        return importRemoteScreenshotPath(for: card, assetURL: assetURL)
    }

    private func shouldImportRemoteScreenshot(
        local: CaptureCard,
        remote: CaptureCard,
        winner: RemoteMergeWinner,
        assetURL: URL?
    ) -> Bool {
        guard ScreenshotAttachmentPersistencePolicy.managedStoredPath(
            from: remote.screenshotPath,
            attachmentStore: attachmentStore
        ) == nil,
              let assetURL,
              FileManager.default.fileExists(atPath: assetURL.path)
        else {
            return false
        }

        switch winner {
        case .local:
            return local.screenshotPath == nil
        case .remote:
            return true
        }
    }

    private func mergeWinner(local: CaptureCard, remote: CaptureCard) -> RemoteMergeWinner {
        switch (local.lastCopiedAt, remote.lastCopiedAt) {
        case (.some(let localDate), .some(let remoteDate)):
            return localDate >= remoteDate ? .local : .remote
        case (.some, .none):
            return .local
        case (.none, .some):
            return .remote
        case (.none, .none):
            return .local
        }
    }

    private func mergeCard(
        local: CaptureCard,
        remote: CaptureCard,
        winner: RemoteMergeWinner,
        importedRemoteScreenshotPath: String?,
        remoteManagedScreenshotPath: String?
    ) -> CaptureCard {
        switch winner {
        case .local:
            return card(
                local,
                replacingScreenshotPath: local.screenshotPath
                    ?? remoteManagedScreenshotPath
                    ?? importedRemoteScreenshotPath
            )
        case .remote:
            return card(
                remote,
                replacingScreenshotPath: importedRemoteScreenshotPath
                    ?? remoteManagedScreenshotPath
                    ?? local.screenshotPath
            )
        }
    }

    private func card(_ card: CaptureCard, replacingScreenshotPath screenshotPath: String?) -> CaptureCard {
        guard screenshotPath != card.screenshotPath else {
            return card
        }

        return CaptureCard(
            id: card.id,
            text: card.text,
            suggestedTarget: card.suggestedTarget,
            createdAt: card.createdAt,
            screenshotPath: screenshotPath,
            lastCopiedAt: card.lastCopiedAt,
            sortOrder: card.sortOrder
        )
    }

    private func processPendingRemoteChanges() async {
        while !Task.isCancelled {
            guard !pendingRemoteChanges.isEmpty else {
                remoteApplyTask = nil
                return
            }

            let changes = pendingRemoteChanges
            pendingRemoteChanges.removeAll()

            guard !Task.isCancelled else {
                remoteApplyTask = nil
                return
            }

            applyRemoteChanges(changes)
        }

        remoteApplyTask = nil
    }

    private func buildRemoteApplyPlan(_ changes: [SyncChange]) -> RemoteApplyPlan {
        let originalCardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        var updatedCardsByID = originalCardsByID
        var changedCardsByID: [UUID: CaptureCard] = [:]
        var removedCardsByID: [UUID: CaptureCard] = [:]
        var deletedIDs: [UUID] = []

        for change in changes {
            switch change {
            case .upsert(let remoteCard, let screenshotAssetURL):
                let mergedCard = mergeRemoteChange(
                    local: updatedCardsByID[remoteCard.id],
                    remote: remoteCard,
                    assetURL: screenshotAssetURL
                )
                updatedCardsByID[mergedCard.id] = mergedCard
                removedCardsByID.removeValue(forKey: mergedCard.id)

                if originalCardsByID[mergedCard.id] != mergedCard {
                    changedCardsByID[mergedCard.id] = mergedCard
                } else {
                    changedCardsByID.removeValue(forKey: mergedCard.id)
                }

            case .delete(let id):
                if let removedCard = updatedCardsByID.removeValue(forKey: id) {
                    removedCardsByID[id] = removedCard
                    if originalCardsByID[id] != nil {
                        deletedIDs.append(id)
                    }
                }
                changedCardsByID.removeValue(forKey: id)
            }
        }

        let sorted = sortedCards(Array(updatedCardsByID.values))
        let survivingIDs = Set(updatedCardsByID.keys)
        return RemoteApplyPlan(
            sortedCards: sorted,
            changedCards: Array(changedCardsByID.values),
            deletedIDs: deletedIDs,
            survivingIDs: survivingIDs,
            removedCards: Array(removedCardsByID.values)
        )
    }

    private func applyRemoteApplyPlan(_ plan: RemoteApplyPlan) {
        if !plan.changedCards.isEmpty || !plan.deletedIDs.isEmpty {
            do {
                try cardStore.apply(upserts: plan.changedCards, deletions: plan.deletedIDs)
                storageErrorMessage = nil
            } catch {
                logStorageFailure("Cloud sync apply failed", error: error)
                return
            }
        }

        cards = plan.sortedCards
        selectedCardIDs.formIntersection(plan.survivingIDs)
        let hadStagedCopiedCards = hasStagedCopiedCards
        stagedCopiedCardIDs.removeAll { plan.survivingIDs.contains($0) == false }
        syncStagedCopyMode()
        if hadStagedCopiedCards, hasStagedCopiedCards {
            _ = syncStagedMultiCopyClipboard()
        }

        if !plan.removedCards.isEmpty {
            cleanupManagedAttachments(
                removedCards: plan.removedCards,
                remainingCards: plan.sortedCards
            )
        }
    }

    private func importRemoteScreenshotPath(for card: CaptureCard, assetURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: assetURL.path) else {
            return nil
        }

        do {
            let importedURL = try attachmentStore.importScreenshot(
                from: assetURL,
                ownerID: card.id
            )
            return importedURL.path
        } catch {
            logStorageFailure("Remote screenshot import failed", error: error)
            return nil
        }
    }
}
