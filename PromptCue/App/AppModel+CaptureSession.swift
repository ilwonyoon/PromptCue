import AppKit
import Foundation
import PromptCueCore

extension AppModel {
    var hasSeededCaptureSession: Bool {
        isEditingCaptureCard || isSeedingCaptureFromCopiedCard
    }

    func beginCaptureSession() {
        prepareDraftMetricsForPresentation()
        isShowingCaptureSuggestedTargetChooser = false
        selectedCaptureSuggestedTargetIndex = 0
        focusedCaptureSuggestedTargetChoiceID = nil
        isCaptureSuggestedTargetPresentationActive = true
        refreshSuggestedTargetProviderLifecycle()
        refreshAvailableSuggestedTargets()
        ensureRecentScreenshotCoordinatorStarted()
        if !hasSeededCaptureSession {
            draftSuggestedTargetOverride = nil
            draftRecentScreenshotStateOverride = nil
            recentScreenshotCoordinator.prepareForCaptureSession()
        }
        recentScreenshotCoordinator.suspendExpiration()
        syncRecentScreenshotState()
    }

    func prepareCapturePresentation() {
        prepareDraftMetricsForPresentation()
        syncRecentScreenshotState()
    }

    func endCaptureSession() {
        if !hasSeededCaptureSession {
            draftSuggestedTargetOverride = nil
            draftRecentScreenshotStateOverride = nil
        }
        isShowingCaptureSuggestedTargetChooser = false
        selectedCaptureSuggestedTargetIndex = 0
        focusedCaptureSuggestedTargetChoiceID = nil
        isCaptureSuggestedTargetPresentationActive = false
        refreshSuggestedTargetProviderLifecycle()
        recentScreenshotCoordinator.resumeExpiration()
        recentScreenshotCoordinator.endCaptureSession()
        syncRecentScreenshotState()
    }

    func beginEditingCaptureCard(_ card: CaptureCard) {
        editingCaptureCardID = card.isCopied ? nil : card.id
        isSeedingCaptureFromCopiedCard = card.isCopied
        draftText = CaptureTagText.editorText(tags: card.tags, bodyText: card.text)
        draftEditorMetrics = .empty
        draftSuggestedTargetOverride = card.suggestedTarget
        isShowingCaptureSuggestedTargetChooser = false
        selectedCaptureSuggestedTargetIndex = 0
        focusedCaptureSuggestedTargetChoiceID = nil
        if let screenshotURL = card.screenshotURL {
            draftRecentScreenshotStateOverride = .previewReady(
                sessionID: UUID(),
                cacheURL: screenshotURL,
                thumbnailState: .ready
            )
        } else {
            draftRecentScreenshotStateOverride = .idle
        }
        prepareDraftMetricsForPresentation()
        syncCaptureSuggestedTargetSelection()
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

        let tagParseResult = CaptureTagText.parseCommittedPrefix(in: draftText)
        let trimmed = tagParseResult.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = tagParseResult.tags
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

        if isEditingCaptureCard {
            guard let editingCard = editingCaptureCard else {
                clearDraft()
                return false
            }

            return submitEditedCapture(
                editingCard,
                trimmedText: trimmed,
                tags: tags,
                attachment: attachment
            )
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
            tags: tags,
            suggestedTarget: effectiveCaptureSuggestedTarget,
            createdAt: Date(),
            screenshotPath: importedScreenshotPath,
            sortOrder: nextTopSortOrder(in: .active)
        )
        let updatedCards = sortedCards(cards + [newCard])

        do {
            try cardStore.upsert(newCard)
            storageErrorMessage = nil
        } catch {
            cleanupImportedAttachment(atPath: importedScreenshotPath)
            logStorageFailure("Card save failed", error: error)
            return false
        }

        cards = updatedCards
        draftText = ""
        draftEditorMetrics = .empty
        draftSuggestedTargetOverride = nil
        draftRecentScreenshotStateOverride = nil
        isSeedingCaptureFromCopiedCard = false
        isShowingCaptureSuggestedTargetChooser = false
        selectedCaptureSuggestedTargetIndex = 0
        focusedCaptureSuggestedTargetChoiceID = nil
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
        draftSuggestedTargetOverride = nil
        draftRecentScreenshotStateOverride = nil
        editingCaptureCardID = nil
        isSeedingCaptureFromCopiedCard = false
        isShowingCaptureSuggestedTargetChooser = false
        selectedCaptureSuggestedTargetIndex = 0
        focusedCaptureSuggestedTargetChoiceID = nil
        syncRecentScreenshotState()
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

    private var editingCaptureCard: CaptureCard? {
        guard let editingCaptureCardID else {
            return nil
        }

        return cards.first { $0.id == editingCaptureCardID }
    }

    private var currentRecentScreenshotAttachment: ScreenshotAttachment? {
        switch recentScreenshotState {
        case .previewReady(_, let cacheURL, _):
            return ScreenshotAttachment(path: cacheURL.path)
        case .idle, .detected, .expired, .consumed:
            return nil
        }
    }

    private func submitEditedCapture(
        _ card: CaptureCard,
        trimmedText: String,
        tags: [CaptureTag],
        attachment: ScreenshotAttachment?
    ) -> Bool {
        let updatedText = trimmedText.isEmpty ? "Screenshot attached" : trimmedText
        let existingScreenshotURL = card.screenshotURL?.standardizedFileURL

        let updatedScreenshotPath: String?
        if let attachment {
            let attachmentURL = URL(fileURLWithPath: attachment.path).standardizedFileURL
            if attachmentURL == existingScreenshotURL {
                updatedScreenshotPath = card.screenshotPath
            } else {
                do {
                    updatedScreenshotPath = try ScreenshotDirectoryResolver.withAccessIfNeeded(
                        to: attachmentURL
                    ) { scopedURL in
                        try attachmentStore.importScreenshot(from: scopedURL, ownerID: card.id).path
                    }
                } catch {
                    logStorageFailure("Screenshot edit import failed", error: error)
                    return false
                }
            }
        } else {
            updatedScreenshotPath = nil
        }

        let updatedCard = card.updatingContent(
            text: updatedText,
            tags: tags,
            suggestedTarget: effectiveCaptureSuggestedTarget,
            screenshotPath: updatedScreenshotPath
        )
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
            if updatedScreenshotPath != card.screenshotPath {
                cleanupImportedAttachment(atPath: updatedScreenshotPath)
            }
            logStorageFailure("Card edit save failed", error: error)
            return false
        }

        cards = updatedCards
        cleanupManagedAttachments(removedCards: [card], remainingCards: updatedCards)
        draftText = ""
        draftEditorMetrics = .empty
        draftSuggestedTargetOverride = nil
        draftRecentScreenshotStateOverride = nil
        editingCaptureCardID = nil
        isSeedingCaptureFromCopiedCard = false
        isShowingCaptureSuggestedTargetChooser = false
        selectedCaptureSuggestedTargetIndex = 0
        focusedCaptureSuggestedTargetChoiceID = nil
        syncRecentScreenshotState()
        cloudSyncEngine?.pushLocalChange(card: updatedCard)
        return true
    }
}
