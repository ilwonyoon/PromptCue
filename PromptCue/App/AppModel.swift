import AppKit
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
    private var cleanupTimer: Timer?
    private var captureSubmissionTask: Task<Bool, Never>?

    init(
        cardStore: CardStore,
        attachmentStore: AttachmentStoring,
        recentScreenshotCoordinator: RecentScreenshotCoordinating
    ) {
        self.cardStore = cardStore
        self.attachmentStore = attachmentStore
        self.recentScreenshotCoordinator = recentScreenshotCoordinator
    }

    convenience init() {
        self.init(
            cardStore: CardStore(),
            attachmentStore: AttachmentStore(),
            recentScreenshotCoordinator: RecentScreenshotCoordinator()
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
    }

    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        recentScreenshotCoordinator.onStateChange = nil
        recentScreenshotCoordinator.stop()
        applyRecentScreenshotState(.idle)
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
}
