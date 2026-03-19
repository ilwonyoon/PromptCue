import Foundation
import Testing
@testable import PromptCueCore

struct PromptCueCoreTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_000)

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
    func screenshotAttachmentIdentityTracksFreshness() {
        let date = Date(timeIntervalSince1970: 1_000)
        let older = ScreenshotAttachment(path: "/tmp/screenshot.png", modifiedAt: date)
        let newer = ScreenshotAttachment(path: "/tmp/screenshot.png", modifiedAt: date.addingTimeInterval(1))

        #expect(older.identityKey != newer.identityKey)
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
    func captureCardTTLProgressRemainingClampsFromFreshToExpired() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let ttl: TimeInterval = 8_000
        let card = CaptureCard(text: "ttl ring", createdAt: createdAt)

        #expect(card.ttlProgressRemaining(relativeTo: createdAt, ttl: ttl) == 1)
        #expect(card.ttlProgressRemaining(relativeTo: createdAt.addingTimeInterval(4_000), ttl: ttl) == 0.5)
        #expect(card.ttlProgressRemaining(relativeTo: createdAt.addingTimeInterval(9_000), ttl: ttl) == 0)
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
    func cardStackOrderingMovesCopiedCardsToBottomWithMostRecentlyCopiedFirst() {
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

        #expect(ordered.map(\.text) == ["fresh", "just copied", "older copied"])
    }

    @Test
    func cardStackOrderingRespectsManualSortOrderWithinSection() {
        let top = CaptureCard(text: "top", createdAt: .now, sortOrder: 10)
        let bottom = CaptureCard(text: "bottom", createdAt: .now.addingTimeInterval(-10), sortOrder: 1)

        let ordered = CardStackOrdering.sort([bottom, top])

        #expect(ordered.map(\.text) == ["top", "bottom"])
    }

    @Test
    func pinnedCardIsNotExpiredEvenPastTTL() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let card = CaptureCard(text: "pinned note", createdAt: createdAt, isPinned: true)
        let wellPastExpiry = createdAt.addingTimeInterval(CaptureCard.ttl * 10)

        #expect(card.isExpired(relativeTo: wellPastExpiry) == false)
    }

    @Test
    func clearCopiedRevertsCopiedCardToActive() {
        let card = CaptureCard(text: "revert me", createdAt: .now)
        let copied = card.markCopied(at: Date(timeIntervalSince1970: 2_000))

        #expect(copied.isCopied)

        let reverted = copied.clearCopied()

        #expect(reverted.isCopied == false)
        #expect(reverted.lastCopiedAt == nil)
        #expect(reverted.id == card.id)
        #expect(reverted.text == card.text)
        #expect(reverted.sortOrder == card.sortOrder)
        #expect(reverted.isPinned == card.isPinned)
    }

    @Test
    func clearCopiedOnNonCopiedCardIsNoOp() {
        let card = CaptureCard(text: "already active", createdAt: .now)

        #expect(card.isCopied == false)

        let result = card.clearCopied()

        #expect(result.isCopied == false)
        #expect(result.lastCopiedAt == nil)
        #expect(result.id == card.id)
        #expect(result.text == card.text)
    }

    @Test
    func togglePinnedReturnsFlippedState() {
        let card = CaptureCard(text: "toggle me", createdAt: .now)

        #expect(card.isPinned == false)

        let pinned = card.togglePinned()
        #expect(pinned.isPinned == true)
        #expect(pinned.id == card.id)
        #expect(pinned.text == card.text)

        let unpinned = pinned.togglePinned()
        #expect(unpinned.isPinned == false)
    }

    @Test
    func pinnedCardsSortBeforeUnpinned() {
        let now = Date(timeIntervalSince1970: 2_000)
        let unpinnedNewer = CaptureCard(text: "newer unpinned", createdAt: now.addingTimeInterval(10))
        let pinnedOlder = CaptureCard(text: "older pinned", createdAt: now, isPinned: true)

        let ordered = CardStackOrdering.sort([unpinnedNewer, pinnedOlder])

        #expect(ordered.map(\.text) == ["older pinned", "newer unpinned"])
    }

    @Test
    func captureCardJSONCodecRoundTrip() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastCopiedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let suggestedTarget = makeSuggestedTarget()
        let tags = [
            CaptureTag(rawValue: "bug"),
            CaptureTag(rawValue: "#bug_fix"),
        ].compactMap { $0 }
        let original = CaptureCard(
            id: id,
            text: "round-trip test",
            tags: tags,
            suggestedTarget: suggestedTarget,
            createdAt: createdAt,
            screenshotPath: "/tmp/screenshot.png",
            lastCopiedAt: lastCopiedAt,
            sortOrder: 42.0
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CaptureCard.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == id)
        #expect(decoded.text == "round-trip test")
        #expect(decoded.tags == tags)
        #expect(decoded.suggestedTarget == suggestedTarget)
        #expect(decoded.createdAt == createdAt)
        #expect(decoded.screenshotPath == "/tmp/screenshot.png")
        #expect(decoded.lastCopiedAt == lastCopiedAt)
        #expect(decoded.sortOrder == 42.0)
    }

    @Test
    func captureCardJSONCodecRoundTripMinimalFields() throws {
        let original = CaptureCard(
            text: "minimal card",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CaptureCard.self, from: data)

        #expect(decoded == original)
        #expect(decoded.tags.isEmpty)
        #expect(decoded.suggestedTarget == nil)
        #expect(decoded.screenshotPath == nil)
        #expect(decoded.lastCopiedAt == nil)
        #expect(decoded.sortOrder == original.createdAt.timeIntervalSinceReferenceDate)
    }

    @Test
    func captureCardDecodesWithMissingSortOrderFallback() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "text": "legacy card",
            "createdAt": \(createdAt.timeIntervalSinceReferenceDate)
        }
        """

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CaptureCard.self, from: Data(json.utf8))

        #expect(decoded.id == id)
        #expect(decoded.text == "legacy card")
        #expect(decoded.tags.isEmpty)
        #expect(decoded.suggestedTarget == nil)
        #expect(decoded.sortOrder == createdAt.timeIntervalSinceReferenceDate)
    }

    @Test
    func suggestedTargetWorkspaceLabelFallsBackToWindowTitleWhenRepoAndCwdAreMissing() {
        let target = makeSuggestedTarget(
            windowTitle: "PromptCue.swift",
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil
        )

        #expect(target.workspaceLabel == "PromptCue.swift")
    }

    @Test
    func suggestedTargetWorkspaceLabelDerivesProjectNameFromWindowTitleSegments() {
        let target = makeSuggestedTarget(
            appName: "Terminal",
            windowTitle: "Backtick — codex",
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil,
            branch: nil
        )

        #expect(target.workspaceLabel == "Backtick")
        #expect(target.chooserDetailLabel == "codex")
        #expect(target.chooserSecondaryLabel == "Terminal · codex")
    }

    @Test
    func suggestedTargetShortBranchLabelCanDeriveFromWindowTitleWhenExplicitBranchIsMissing() {
        let target = makeSuggestedTarget(
            windowTitle: "Backtick — main",
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil,
            branch: nil
        )

        #expect(target.workspaceLabel == "Backtick")
        #expect(target.shortBranchLabel == "main")
        #expect(target.chooserDetailLabel == "main")
        #expect(target.chooserSecondaryLabel == "Cursor · main")
    }

    @Test
    func suggestedTargetWorkspaceLabelUsesPathLeafWhenOnlyPathLikeWindowTitleIsAvailable() {
        let target = makeSuggestedTarget(
            appName: "Terminal",
            windowTitle: "~/workspace/PromptCue",
            sessionIdentifier: "window-7",
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil,
            branch: nil
        )

        #expect(target.workspaceLabel == "PromptCue")
        #expect(target.chooserDetailLabel == "~/workspace/PromptCue")
        #expect(target.chooserSecondaryLabel == "Terminal · ~/workspace/PromptCue")
    }

    @Test
    func terminalChooserDetailPrefersCurrentWorkingDirectoryForRepositoryRoot() {
        let target = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "PromptCue — main",
            sessionIdentifier: "window-7",
            terminalTTY: "/dev/ttys001",
            currentWorkingDirectory: "/tmp/PromptCue",
            repositoryRoot: "/tmp/PromptCue",
            repositoryName: "PromptCue",
            branch: "main",
            capturedAt: referenceDate
        )

        #expect(target.workspaceLabel == "PromptCue")
        #expect(target.chooserDetailLabel == "main")
        #expect(target.chooserSecondaryLabel == "Terminal · main")
    }

    @Test
    func terminalChooserDetailPrefersCurrentWorkingDirectoryForSubdirectoryTargets() {
        let target = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "PromptCue — feature/refactor",
            sessionIdentifier: "window-8",
            terminalTTY: "/dev/ttys002",
            currentWorkingDirectory: "/tmp/PromptCue/App",
            repositoryRoot: "/tmp/PromptCue",
            repositoryName: "PromptCue",
            branch: "feature/refactor",
            capturedAt: referenceDate
        )

        #expect(target.workspaceLabel == "PromptCue/App")
        #expect(target.chooserDetailLabel == "refactor")
        #expect(target.chooserSecondaryLabel == "Terminal · refactor")
    }

    @Test
    func terminalChooserDetailFallsBackToPathWhenBranchIsUnavailable() {
        let target = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "PromptCue",
            sessionIdentifier: "window-9",
            terminalTTY: "/dev/ttys003",
            currentWorkingDirectory: "/tmp/PromptCue/App",
            repositoryRoot: "/tmp/PromptCue",
            repositoryName: "PromptCue",
            branch: nil,
            capturedAt: referenceDate
        )

        #expect(target.workspaceLabel == "PromptCue/App")
        #expect(target.chooserDetailLabel == "/tmp/PromptCue/App")
        #expect(target.chooserSecondaryLabel == "Terminal · /tmp/PromptCue/App")
    }

    @Test
    func suggestedTargetSourceKindDistinguishesTerminalFromIDEBundleIdentifiers() {
        let terminalTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            capturedAt: referenceDate
        )
        let ideTarget = makeSuggestedTarget()

        #expect(terminalTarget.sourceKind == .terminal)
        #expect(ideTarget.sourceKind == .ide)
    }

    @Test
    func suggestedTargetChooserSecondaryLabelFallsBackToSessionIdentifierWhenWindowTitleMatchesWorkspaceLabel() {
        let target = makeSuggestedTarget(
            windowTitle: "PromptCue",
            sessionIdentifier: "tab-2",
            currentWorkingDirectory: nil,
            repositoryRoot: nil,
            repositoryName: nil,
            branch: nil
        )

        #expect(target.workspaceLabel == "PromptCue")
        #expect(target.chooserDetailLabel == "tab-2")
        #expect(target.chooserSecondaryLabel == "Cursor · tab-2")
    }

    @Test
    func suggestedTargetCanonicalIdentityUsesTTYForTerminalTargets() {
        let firstTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "PromptCue",
            sessionIdentifier: "window-17",
            terminalTTY: "/dev/ttys003",
            currentWorkingDirectory: "/Users/ilwon/dev/PromptCue",
            repositoryRoot: "/Users/ilwon/dev/PromptCue",
            repositoryName: "PromptCue",
            branch: "main",
            capturedAt: referenceDate
        )
        let secondTarget = CaptureSuggestedTarget(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "Other title",
            sessionIdentifier: "window-98",
            terminalTTY: "/dev/ttys003",
            currentWorkingDirectory: "/tmp",
            repositoryRoot: nil,
            repositoryName: nil,
            branch: nil,
            capturedAt: referenceDate
        )

        #expect(firstTarget.choiceKey != secondTarget.choiceKey)
        #expect(firstTarget.canonicalIdentityKey == secondTarget.canonicalIdentityKey)
    }

    @Test
    func suggestedTargetShortBranchLabelUsesLeafAndTruncatesToEighteenCharacters() {
        let target = makeSuggestedTarget(branch: "feature/12345678901234567890")

        #expect(target.shortBranchLabel == "12345678901234567…")
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

    @Test
    func exportFormatterLeavesOutputUnchangedWhenSuffixIsOff() {
        let cards = [
            CaptureCard(text: "mobile layout broken", createdAt: .now),
            CaptureCard(text: "auth redirect incorrect", createdAt: .now),
        ]

        let payload = ExportFormatter.string(for: cards, suffix: .off)

        #expect(
            payload == """
            • mobile layout broken
            • auth redirect incorrect
            """
        )
    }

    @Test
    func exportFormatterAppendsSuffixExactlyOnceAfterBlankLine() {
        let cards = [
            CaptureCard(text: "mobile layout broken", createdAt: .now),
            CaptureCard(text: "auth redirect incorrect", createdAt: .now),
        ]

        let payload = ExportFormatter.string(for: cards, suffix: ExportSuffix("Sent from Prompt Cue"))

        #expect(
            payload == """
            • mobile layout broken
            • auth redirect incorrect

            Sent from Prompt Cue
            """
        )
        #expect(cards.map(\.text) == ["mobile layout broken", "auth redirect incorrect"])
    }

    @Test
    func exportFormatterTreatsBlankSuffixAsOff() {
        let cards = [
            CaptureCard(text: "mobile layout broken", createdAt: .now),
        ]

        let payload = ExportFormatter.string(for: cards, suffix: ExportSuffix(" \n \n "))

        #expect(payload == "• mobile layout broken")
    }

    @Test
    func exportFormatterNormalizesSuffixSurroundingNewlines() {
        let cards = [
            CaptureCard(text: "mobile layout broken", createdAt: .now),
        ]

        let payload = ExportFormatter.string(
            for: cards,
            suffix: ExportSuffix("\n\nFirst line\r\nSecond line\n\n")
        )

        #expect(
            payload == """
            • mobile layout broken

            First line
            Second line
            """
        )
    }

    @Test
    func exportFormatterAppendsSuffixOnceForMultiCardExport() {
        let cards = [
            CaptureCard(text: "mobile layout broken", createdAt: .now),
            CaptureCard(text: "auth redirect incorrect", createdAt: .now),
            CaptureCard(text: "screenshot attached", createdAt: .now),
        ]

        let payload = ExportFormatter.string(for: cards, suffix: ExportSuffix("Sent from Prompt Cue"))

        #expect(payload.components(separatedBy: "\n\n").count == 2)
        #expect(payload.hasSuffix("Sent from Prompt Cue"))
    }

    @Test
    func clipboardExportFormatterReturnsRawStandaloneLinkWithoutSuffix() {
        let cards = [
            CaptureCard(text: "https://example.com/docs", createdAt: .now),
        ]

        let payload = ExportFormatter.clipboardString(
            for: cards,
            suffix: ExportSuffix("Sent from Prompt Cue")
        )

        #expect(payload == "https://example.com/docs")
    }

    @Test
    func clipboardExportFormatterReturnsRawStandalonePathWithoutSuffix() {
        let cards = [
            CaptureCard(text: "~/workspace/PromptCue/README.md", createdAt: .now),
        ]

        let payload = ExportFormatter.clipboardString(
            for: cards,
            suffix: ExportSuffix("Sent from Prompt Cue")
        )

        #expect(payload == "~/workspace/PromptCue/README.md")
    }

    @Test
    func clipboardExportFormatterReturnsRawStandaloneSecretWithoutSuffix() {
        let cards = [
            CaptureCard(text: "sk-ant-abc123def456xyz987", createdAt: .now),
        ]

        let payload = ExportFormatter.clipboardString(
            for: cards,
            suffix: ExportSuffix("Sent from Prompt Cue")
        )

        #expect(payload == "sk-ant-abc123def456xyz987")
    }

    @Test
    func clipboardExportFormatterReturnsRawStandaloneEmailWithoutSuffix() {
        let cards = [
            CaptureCard(text: "dev@example.com", createdAt: .now),
        ]

        let payload = ExportFormatter.clipboardString(
            for: cards,
            suffix: ExportSuffix("Sent from Prompt Cue")
        )

        #expect(payload == "dev@example.com")
    }

    @Test
    func clipboardExportFormatterReturnsRawStandaloneLocalhostWithoutSuffix() {
        let cards = [
            CaptureCard(text: "localhost:3000/api/v1?draft=1", createdAt: .now),
        ]

        let payload = ExportFormatter.clipboardString(
            for: cards,
            suffix: ExportSuffix("Sent from Prompt Cue")
        )

        #expect(payload == "localhost:3000/api/v1?draft=1")
    }

    @Test
    func clipboardExportFormatterKeepsExportShapeForNotesContainingLink() {
        let cards = [
            CaptureCard(text: "Review https://example.com/docs before shipping", createdAt: .now),
        ]

        let payload = ExportFormatter.clipboardString(
            for: cards,
            suffix: ExportSuffix("Sent from Prompt Cue")
        )

        #expect(
            payload == """
            • Review https://example.com/docs before shipping

            Sent from Prompt Cue
            """
        )
    }

    @Test
    func copyEventJSONCodecRoundTripAndSanitizesSessionID() throws {
        let original = CopyEvent(
            id: UUID(),
            noteID: UUID(),
            sessionID: "  run-42  ",
            copiedAt: referenceDate,
            copiedVia: .agentRun,
            copiedBy: .mcp
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CopyEvent.self, from: data)

        #expect(decoded == original)
        #expect(decoded.sessionID == "run-42")
        #expect(decoded.copiedVia == .agentRun)
        #expect(decoded.copiedBy == .mcp)
    }

    @Test
    func projectDocumentExposesStableKeyAndSupersededState() {
        let id = UUID()
        let successorID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = createdAt.addingTimeInterval(60)
        let document = ProjectDocument(
            id: id,
            project: "backtick",
            topic: "pricing",
            documentType: .decision,
            content: "## Decision\n- Freemium + $9/mo premium",
            createdAt: createdAt,
            updatedAt: updatedAt,
            supersededByID: successorID
        )

        #expect(document.key == ProjectDocumentKey(
            project: "backtick",
            topic: "pricing",
            documentType: .decision
        ))
        #expect(document.isSuperseded)
    }

    @Test
    func projectDocumentJSONCodecRoundTrip() throws {
        let original = ProjectDocument(
            project: "backtick",
            topic: "architecture",
            documentType: .reference,
            content: "## Context\n- App-hosted MCP helper",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_120)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProjectDocument.self, from: data)

        #expect(decoded == original)
    }

    private func makeSuggestedTarget(
        appName: String = "Cursor",
        windowTitle: String? = "PromptCue",
        sessionIdentifier: String? = "tab-1",
        currentWorkingDirectory: String? = "/Users/ilwon/dev/PromptCue/App",
        repositoryRoot: String? = "/Users/ilwon/dev/PromptCue",
        repositoryName: String? = "PromptCue",
        branch: String? = "feature/initial-work"
    ) -> CaptureSuggestedTarget {
        CaptureSuggestedTarget(
            appName: appName,
            bundleIdentifier: "com.todesktop.230313mzl4w4u92",
            windowTitle: windowTitle,
            sessionIdentifier: sessionIdentifier,
            currentWorkingDirectory: currentWorkingDirectory,
            repositoryRoot: repositoryRoot,
            repositoryName: repositoryName,
            branch: branch,
            capturedAt: referenceDate
        )
    }
}
