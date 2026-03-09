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

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var cards: [CaptureCard] = []
    @Published private(set) var storageErrorMessage: String?
    @Published private(set) var recentScreenshotState: RecentScreenshotState = .idle
    @Published var draftText = ""
    @Published var draftEditorMetrics: CaptureEditorMetrics = .empty
    @Published var selectedCardIDs: Set<UUID> = []
    @Published private(set) var isSubmittingCapture = false

    private let cardStore: CardStore
    private let attachmentStore: AttachmentStoring
    private let recentScreenshotCoordinator: RecentScreenshotCoordinating
    private var cloudSyncEngine: CloudSyncEngine?
    private var cleanupTimer: Timer?
    private var captureSubmissionTask: Task<Bool, Never>?
    private var syncToggleObserver: NSObjectProtocol?

    init(
        cardStore: CardStore,
        attachmentStore: AttachmentStoring,
        recentScreenshotCoordinator: RecentScreenshotCoordinating,
        cloudSyncEngine: CloudSyncEngine? = nil
    ) {
        self.cardStore = cardStore
        self.attachmentStore = attachmentStore
        self.recentScreenshotCoordinator = recentScreenshotCoordinator
        self.cloudSyncEngine = cloudSyncEngine
    }

    convenience init() {
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let syncEnabled = !isTestEnvironment && CloudSyncPreferences.load()
        self.init(
            cardStore: CardStore(),
            attachmentStore: AttachmentStore(),
            recentScreenshotCoordinator: RecentScreenshotCoordinator(),
            cloudSyncEngine: syncEnabled ? CloudSyncEngine() : nil
        )
    }

    var selectionCount: Int {
        selectedCardIDs.count
    }

    var selectedCardsInDisplayOrder: [CaptureCard] {
        cards.filter { selectedCardIDs.contains($0.id) }
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

    func start() {
        recentScreenshotCoordinator.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.applyRecentScreenshotState(state)
            }
        }
        recentScreenshotCoordinator.start()
        applyRecentScreenshotState(recentScreenshotCoordinator.state)
        reloadCards()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.purgeExpiredCards()
            }
        }
        startCloudSync()
    }

    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        recentScreenshotCoordinator.onStateChange = nil
        recentScreenshotCoordinator.stop()
        applyRecentScreenshotState(.idle)
        if let syncToggleObserver {
            NotificationCenter.default.removeObserver(syncToggleObserver)
        }
        syncToggleObserver = nil
        cloudSyncEngine?.delegate = nil
    }

    func reloadCards() {
        do {
            cards = sortedCards(try cardStore.load())
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Card load failed", error: error)
            return
        }

        migrateLegacyExternalAttachmentsIfNeeded()
        purgeExpiredCards()
        pruneOrphanedManagedAttachments()
    }

    func beginCaptureSession() {
        prepareDraftMetricsForPresentation()
        recentScreenshotCoordinator.prepareForCaptureSession()
        syncRecentScreenshotState()
    }

    func endCaptureSession() {
        syncRecentScreenshotState()
    }

    func refreshPendingScreenshot() {
        recentScreenshotCoordinator.prepareForCaptureSession()
        syncRecentScreenshotState()
    }

    func beginCaptureSubmission(onSuccess: @escaping @MainActor () -> Void = {}) {
        guard captureSubmissionTask == nil else {
            return
        }

        isSubmittingCapture = true

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return false
            }

            defer {
                self.captureSubmissionTask = nil
                self.isSubmittingCapture = false
            }

            let didSubmit = await self.submitCapture()
            if didSubmit {
                onSuccess()
            }
            return didSubmit
        }

        captureSubmissionTask = task
    }

    @discardableResult
    func submitCapture() async -> Bool {
        let managesSubmittingState = !isSubmittingCapture
        if managesSubmittingState {
            isSubmittingCapture = true
        }
        defer {
            if managesSubmittingState {
                isSubmittingCapture = false
            }
        }

        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        var attachment = currentRecentScreenshotAttachment

        if attachment == nil, recentScreenshotState.showsCaptureSlot {
            if let resolvedURL = await recentScreenshotCoordinator.resolveCurrentCaptureAttachment(
                timeout: AppTiming.recentScreenshotSubmitResolveTimeout
            ) {
                attachment = ScreenshotAttachment(path: resolvedURL.path)
            }

            syncRecentScreenshotState()
        }

        guard !trimmed.isEmpty || attachment != nil else {
            return false
        }

        let newCardID = UUID()
        let importedScreenshotPath: String?

        if let attachment {
            let sourceURL = URL(fileURLWithPath: attachment.path)
            do {
                importedScreenshotPath = try ScreenshotDirectoryResolver.withAccessIfNeeded(
                    to: sourceURL
                ) { scopedURL in
                    try attachmentStore.importScreenshot(
                        from: scopedURL,
                        ownerID: newCardID
                    ).path
                }
            } catch {
                logStorageFailure("Screenshot import failed", error: error)
                return false
            }
        } else {
            importedScreenshotPath = nil
        }

        let newCard = CaptureCard(
            id: newCardID,
            text: trimmed.isEmpty ? "Screenshot attached" : trimmed,
            createdAt: Date(),
            screenshotPath: importedScreenshotPath,
            sortOrder: nextTopSortOrder(in: .active)
        )
        let updatedCards = sortedCards(cards + [newCard])

        do {
            try cardStore.save(updatedCards)
            storageErrorMessage = nil
        } catch {
            cleanupImportedAttachment(atPath: importedScreenshotPath)
            logStorageFailure("Card save failed", error: error)
            return false
        }

        cards = updatedCards
        draftText = ""
        draftEditorMetrics = .empty
        if attachment != nil {
            recentScreenshotCoordinator.consumeCurrent()
        }
        syncRecentScreenshotState()
        cloudSyncEngine?.pushLocalChange(card: newCard)
        return true
    }

    func clearDraft() {
        draftText = ""
        draftEditorMetrics = .empty
    }

    func updateDraftEditorMetrics(_ metrics: CaptureEditorMetrics) {
        if draftEditorMetrics != metrics {
            draftEditorMetrics = metrics
        }
    }

    func prepareDraftMetricsForPresentation() {
        let trimmed = draftText.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else {
            if draftEditorMetrics.layoutWidth == 0 {
                draftEditorMetrics = .empty
            }
            return
        }

        let estimatedMetrics = CaptureEditorLayoutCalculator.estimatedMetrics(
            text: draftText,
            viewportWidth: CaptureRuntimeMetrics.editorViewportWidth,
            maxContentHeight: CaptureRuntimeMetrics.editorMaxHeight,
            minimumLineHeight: CaptureRuntimeMetrics.textLineHeight,
            font: NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.capture),
            lineHeight: PrimitiveTokens.LineHeight.capture
        )

        if draftEditorMetrics.layoutWidth == 0 || estimatedMetrics.visibleHeight > draftEditorMetrics.visibleHeight {
            draftEditorMetrics = estimatedMetrics
        }
    }

    func waitForCaptureSubmissionToSettle(timeout: TimeInterval) async {
        if let captureSubmissionTask {
            _ = await captureSubmissionTask.value
            return
        }

        guard timeout > 0 else {
            return
        }

        let deadline = Date().addingTimeInterval(timeout)
        while isSubmittingCapture && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func dismissPendingScreenshot() {
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

    func clearSelection() {
        selectedCardIDs.removeAll()
    }

    @discardableResult
    func copy(card: CaptureCard) -> String {
        let payload = ClipboardFormatter.string(for: [card])
        ClipboardFormatter.copyToPasteboard(cards: [card])
        markCopied(ids: [card.id])
        return payload
    }

    @discardableResult
    func copySelection() -> String? {
        let selectedCards = selectedCardsInDisplayOrder
        guard !selectedCards.isEmpty else {
            return nil
        }

        let payload = ClipboardFormatter.string(for: selectedCards)
        ClipboardFormatter.copyToPasteboard(cards: selectedCards)
        markCopied(ids: selectedCards.map(\.id))
        return payload
    }

    func delete(card: CaptureCard) {
        let updatedCards = cards.filter { $0.id != card.id }

        do {
            try cardStore.save(updatedCards)
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Card delete failed", error: error)
            return
        }

        cards = updatedCards
        selectedCardIDs.remove(card.id)
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

        do {
            try cardStore.save(filtered)
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Card purge failed", error: error)
            return
        }

        cards = filtered
        selectedCardIDs = selectedCardIDs.filter { id in
            filtered.contains(where: { $0.id == id })
        }
        cleanupManagedAttachments(removedCards: expiredCards, remainingCards: filtered)
        cloudSyncEngine?.pushBatch(cards: [], deletions: expiredCards.map(\.id))
    }

    private func markCopied(ids: [UUID]) {
        let copiedIDs = Set(ids)
        let copiedAt = Date()
        let updatedCards = sortedCards(
            cards.map { card in
                guard copiedIDs.contains(card.id) else {
                    return card
                }

                return card.markCopied(at: copiedAt)
            }
        )

        do {
            try cardStore.save(updatedCards)
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Card copy state save failed", error: error)
            return
        }

        cards = updatedCards
        clearSelection()

        let copiedCards = updatedCards.filter { copiedIDs.contains($0.id) }
        for card in copiedCards {
            cloudSyncEngine?.pushLocalChange(card: card)
        }
    }

    private func sortedCards(_ cards: [CaptureCard]) -> [CaptureCard] {
        CardStackOrdering.sort(cards)
    }

    private func cleanupManagedAttachments(removedCards: [CaptureCard], remainingCards: [CaptureCard]) {
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

    private func cleanupImportedAttachment(atPath path: String?) {
        guard let path else {
            return
        }

        do {
            try attachmentStore.removeManagedFile(at: URL(fileURLWithPath: path))
        } catch {
            logStorageFailure("Imported attachment rollback failed", error: error)
        }
    }

    private var currentRecentScreenshotAttachment: ScreenshotAttachment? {
        switch recentScreenshotState {
        case .previewReady(_, let cacheURL, _):
            return ScreenshotAttachment(path: cacheURL.path)
        case .idle, .detected, .expired, .consumed:
            return nil
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
            if FileManager.default.fileExists(atPath: screenshotURL.path) {
                do {
                    migratedPath = try ScreenshotDirectoryResolver.withAccessIfNeeded(to: screenshotURL) { scopedURL in
                        try attachmentStore.importScreenshot(from: scopedURL, ownerID: card.id).path
                    }
                } catch {
                    logStorageFailure("Legacy screenshot migration failed", error: error)
                    migratedPath = nil
                }
            } else {
                migratedPath = nil
            }

            if migratedPath != card.screenshotPath {
                migratedCards[index] = CaptureCard(
                    id: card.id,
                    text: card.text,
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

        do {
            try cardStore.save(sortedMigratedCards)
            storageErrorMessage = nil
            cards = sortedMigratedCards
        } catch {
            logStorageFailure("Legacy screenshot save failed", error: error)
        }
    }

    private func logStorageFailure(_ message: String, error: Error) {
        storageErrorMessage = "\(message): \(error.localizedDescription)"
        NSLog("%@: %@", message, String(describing: error))
    }

    private func nextTopSortOrder(in section: CardSection) -> Double {
        let maximum = cards
            .filter { section.matches($0) }
            .map(\.sortOrder)
            .max() ?? 0

        return maximum + 1
    }

    private func syncRecentScreenshotState() {
        applyRecentScreenshotState(recentScreenshotCoordinator.state)
    }

    private func applyRecentScreenshotState(_ state: RecentScreenshotState) {
        recentScreenshotState = state
    }

    // MARK: - Cloud Sync

    private func startCloudSync() {
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

        guard let cloudSyncEngine else { return }
        cloudSyncEngine.delegate = self

        Task {
            await cloudSyncEngine.setup()
            cloudSyncEngine.fetchRemoteChanges()
        }
    }

    func handleCloudRemoteNotification() {
        cloudSyncEngine?.handleRemoteNotification()
    }

    func setSyncEnabled(_ enabled: Bool) {
        if enabled, cloudSyncEngine == nil {
            let engine = CloudSyncEngine()
            cloudSyncEngine = engine
            startCloudSync()
        } else if !enabled {
            cloudSyncEngine?.delegate = nil
            cloudSyncEngine = nil
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
        applyRemoteChanges(changes)
    }

    func applyRemoteChanges(_ changes: [SyncChange]) {
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
                    let merged = mergeCard(local: local, remote: cardWithScreenshot)
                    updatedCards[index] = merged
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

        let sorted = sortedCards(updatedCards)

        do {
            try cardStore.save(sorted)
            storageErrorMessage = nil
        } catch {
            logStorageFailure("Cloud sync apply failed", error: error)
            return
        }

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
            logStorageFailure("Remote screenshot import failed", error: error)
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
}
