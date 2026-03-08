import AppKit
import Combine
import Foundation
import PromptCueCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var cards: [CaptureCard] = []
    @Published var draftText = ""
    @Published var draftEditorContentHeight: CGFloat = 0
    @Published var pendingScreenshotAttachment: ScreenshotAttachment?
    @Published var selectedCardIDs: Set<UUID> = []

    private let cardStore = CardStore()
    private let screenshotMonitor = ScreenshotMonitor()
    private var cleanupTimer: Timer?
    private var captureSessionTimer: Timer?
    private var ignoredRecentScreenshotPath: String?

    var selectionCount: Int {
        selectedCardIDs.count
    }

    var selectedCardsInDisplayOrder: [CaptureCard] {
        cards.filter { selectedCardIDs.contains($0.id) }
    }

    func start() {
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
        captureSessionTimer?.invalidate()
        captureSessionTimer = nil
    }

    func reloadCards() {
        cards = sortedCards(cardStore.load())
        purgeExpiredCards()
    }

    func beginCaptureSession() {
        refreshPendingScreenshot()

        guard captureSessionTimer == nil else {
            return
        }

        captureSessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPendingScreenshot()
            }
        }
    }

    func endCaptureSession() {
        captureSessionTimer?.invalidate()
        captureSessionTimer = nil
    }

    func refreshPendingScreenshot() {
        let candidate = screenshotMonitor.mostRecentScreenshot(maxAge: AppUIConstants.recentScreenshotMaxAge)

        guard let candidate else {
            return
        }

        guard candidate.path != pendingScreenshotAttachment?.path else {
            return
        }

        guard candidate.path != ignoredRecentScreenshotPath else {
            return
        }

        pendingScreenshotAttachment = candidate
    }

    @discardableResult
    func submitCapture() -> Bool {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || pendingScreenshotAttachment != nil else {
            return false
        }

        let attachment = pendingScreenshotAttachment
        let newCard = CaptureCard(
            text: trimmed.isEmpty ? "Screenshot attached" : trimmed,
            createdAt: Date(),
            screenshotPath: attachment?.path
        )
        cards = sortedCards(cards + [newCard])
        persistCards()
        draftText = ""
        draftEditorContentHeight = 0
        if let attachment {
            ignoredRecentScreenshotPath = attachment.path
        }
        pendingScreenshotAttachment = nil
        return true
    }

    func clearDraft() {
        draftText = ""
        draftEditorContentHeight = 0
        pendingScreenshotAttachment = nil
    }

    func dismissPendingScreenshot() {
        guard let pendingScreenshotAttachment else {
            return
        }

        ignoredRecentScreenshotPath = pendingScreenshotAttachment.path
        self.pendingScreenshotAttachment = nil
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
        ClipboardFormatter.copyToPasteboard(payload)
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
        ClipboardFormatter.copyToPasteboard(payload)
        markCopied(ids: selectedCards.map(\.id))
        return payload
    }

    func delete(card: CaptureCard) {
        cards.removeAll { $0.id == card.id }
        selectedCardIDs.remove(card.id)
        persistCards()
    }

    func purgeExpiredCards() {
        let now = Date()
        let filtered = cards.filter { !$0.isExpired(relativeTo: now) }
        guard filtered.count != cards.count else {
            return
        }

        cards = sortedCards(filtered)
        selectedCardIDs = selectedCardIDs.filter { id in
            filtered.contains(where: { $0.id == id })
        }
        persistCards()
    }

    private func markCopied(ids: [UUID]) {
        let copiedIDs = Set(ids)
        let copiedAt = Date()
        cards = sortedCards(
            cards.map { card in
                guard copiedIDs.contains(card.id) else {
                    return card
                }

                return card.markCopied(at: copiedAt)
            }
        )
        clearSelection()
        persistCards()
    }

    private func sortedCards(_ cards: [CaptureCard]) -> [CaptureCard] {
        CardStackOrdering.sort(cards)
    }

    private func persistCards() {
        cardStore.save(cards)
    }
}
