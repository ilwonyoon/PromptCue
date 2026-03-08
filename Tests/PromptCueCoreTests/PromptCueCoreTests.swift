import Foundation
import Testing
@testable import PromptCueCore

struct PromptCueCoreTests {
    @Test
    func emptyDraftHasNoContent() {
        let draft = CaptureDraft()

        #expect(draft.hasContent == false)
    }

    @Test
    func textDraftHasContentWhenTrimmedTextExists() {
        let draft = CaptureDraft(text: "  mobile layout broken  ")

        #expect(draft.hasContent)
    }

    @Test
    func screenshotOnlyDraftHasContent() {
        let draft = CaptureDraft(recentScreenshot: ScreenshotAttachment(path: "/tmp/screenshot.png"))

        #expect(draft.hasContent)
    }

    @Test
    func captureCardExpiresAfterDefaultTTL() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let card = CaptureCard(text: "auth redirect incorrect", createdAt: createdAt)
        let justBeforeExpiry = createdAt.addingTimeInterval(CaptureCard.ttl - 1)
        let justAfterExpiry = createdAt.addingTimeInterval(CaptureCard.ttl + 1)

        #expect(card.isExpired(relativeTo: justBeforeExpiry) == false)
        #expect(card.isExpired(relativeTo: justAfterExpiry))
    }

    @Test
    func captureCardBuildsScreenshotURL() {
        let card = CaptureCard(
            text: "screenshot attached",
            createdAt: .now,
            screenshotPath: "/tmp/example.png"
        )

        #expect(card.screenshotURL?.path == "/tmp/example.png")
    }

    @Test
    func captureCardTracksCopiedState() {
        let copiedAt = Date(timeIntervalSince1970: 2_000)
        let card = CaptureCard(text: "copied cue", createdAt: .now)
        let copied = card.markCopied(at: copiedAt)

        #expect(card.isCopied == false)
        #expect(copied.isCopied)
        #expect(copied.lastCopiedAt == copiedAt)
    }

    @Test
    func cardStackOrderingMovesCopiedCardsToBottom() {
        let oldest = Date(timeIntervalSince1970: 1_000)
        let newest = Date(timeIntervalSince1970: 2_000)
        let earlierCopy = Date(timeIntervalSince1970: 3_000)
        let laterCopy = Date(timeIntervalSince1970: 4_000)

        let freshCard = CaptureCard(text: "fresh", createdAt: newest)
        let olderCopiedCard = CaptureCard(
            text: "older copied",
            createdAt: oldest,
            lastCopiedAt: earlierCopy
        )
        let justCopiedCard = CaptureCard(
            text: "just copied",
            createdAt: newest.addingTimeInterval(10),
            lastCopiedAt: laterCopy
        )

        let ordered = CardStackOrdering.sort([justCopiedCard, olderCopiedCard, freshCard])

        #expect(ordered.map(\.text) == ["fresh", "older copied", "just copied"])
    }

    @Test
    func exportFormatterBuildsBulletedClipboardPayloadInOrder() {
        let cards = [
            CaptureCard(text: "mobile layout broken", createdAt: .now),
            CaptureCard(text: "auth redirect incorrect", createdAt: .now),
            CaptureCard(text: "screenshot attached", createdAt: .now),
        ]

        let payload = ExportFormatter.string(for: cards)

        #expect(
            payload == """
            • mobile layout broken
            • auth redirect incorrect
            • screenshot attached
            """
        )
    }
}
