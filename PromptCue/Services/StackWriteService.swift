import Foundation
import PromptCueCore

enum StackWriteServiceError: Error, Equatable {
    case emptyNote
}

enum StackOptionalUpdate<Value: Equatable & Sendable>: Equatable, Sendable {
    case keep
    case set(Value)
    case clear
}

struct StackNoteCreateRequest: Equatable, Sendable {
    let id: UUID
    let text: String
    let suggestedTarget: CaptureSuggestedTarget?
    let screenshotPath: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        suggestedTarget: CaptureSuggestedTarget? = nil,
        screenshotPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.suggestedTarget = suggestedTarget
        self.screenshotPath = screenshotPath
        self.createdAt = createdAt
    }
}

struct StackNoteUpdate: Equatable, Sendable {
    let text: String?
    let suggestedTarget: StackOptionalUpdate<CaptureSuggestedTarget>
    let screenshotPath: StackOptionalUpdate<String>

    init(
        text: String? = nil,
        suggestedTarget: StackOptionalUpdate<CaptureSuggestedTarget> = .keep,
        screenshotPath: StackOptionalUpdate<String> = .keep
    ) {
        self.text = text
        self.suggestedTarget = suggestedTarget
        self.screenshotPath = screenshotPath
    }
}

@MainActor
final class StackWriteService {
    private let cardStore: CardStore
    private let attachmentStore: any AttachmentStoring

    private struct PreparedScreenshotPath {
        let path: String?
        let importedManagedURL: URL?
    }

    init(
        cardStore: CardStore,
        attachmentStore: any AttachmentStoring
    ) {
        self.cardStore = cardStore
        self.attachmentStore = attachmentStore
    }

    convenience init(
        fileManager: FileManager = .default,
        databaseURL: URL? = nil,
        attachmentBaseDirectoryURL: URL? = nil
    ) {
        let database = PromptCueDatabase(fileManager: fileManager, databaseURL: databaseURL)
        self.init(
            cardStore: CardStore(database: database),
            attachmentStore: AttachmentStore(
                fileManager: fileManager,
                baseDirectoryURL: attachmentBaseDirectoryURL
            )
        )
    }

    func createNote(_ request: StackNoteCreateRequest) throws -> CaptureCard {
        let existingCards = try cardStore.load()
        let preparedScreenshotPath = try prepareScreenshotPath(
            request.screenshotPath,
            ownerID: request.id
        )
        let note = CaptureCard(
            id: request.id,
            text: try normalizedText(
                rawText: request.text,
                screenshotPath: preparedScreenshotPath.path
            ),
            suggestedTarget: request.suggestedTarget,
            createdAt: request.createdAt,
            screenshotPath: preparedScreenshotPath.path,
            sortOrder: nextTopSortOrder(in: existingCards)
        )

        do {
            try cardStore.upsert(note)
        } catch {
            cleanupImportedAttachment(at: preparedScreenshotPath.importedManagedURL)
            throw error
        }
        return note
    }

    func updateNote(id: UUID, changes: StackNoteUpdate) throws -> CaptureCard? {
        let existingCards = try cardStore.load()
        guard let existingNote = existingCards.first(where: { $0.id == id }) else {
            return nil
        }

        let preparedScreenshotPath = try resolvedScreenshotPath(
            for: existingNote,
            update: changes.screenshotPath
        )
        let updatedNote = CaptureCard(
            id: existingNote.id,
            text: try normalizedText(
                rawText: changes.text ?? existingNote.text,
                screenshotPath: preparedScreenshotPath.path
            ),
            suggestedTarget: resolvedValue(
                current: existingNote.suggestedTarget,
                update: changes.suggestedTarget
            ),
            createdAt: existingNote.createdAt,
            screenshotPath: preparedScreenshotPath.path,
            lastCopiedAt: existingNote.lastCopiedAt,
            sortOrder: existingNote.sortOrder
        )

        do {
            try cardStore.upsert(updatedNote)
        } catch {
            cleanupImportedAttachment(at: preparedScreenshotPath.importedManagedURL)
            throw error
        }

        if existingNote.screenshotPath != updatedNote.screenshotPath {
            let remainingCards = existingCards.filter { $0.id != id } + [updatedNote]
            cleanupManagedAttachments(
                removedCards: [existingNote],
                remainingCards: remainingCards
            )
        }

        return updatedNote
    }

    @discardableResult
    func deleteNote(id: UUID) throws -> Bool {
        let existingCards = try cardStore.load()
        guard let removedNote = existingCards.first(where: { $0.id == id }) else {
            return false
        }

        let remainingCards = existingCards.filter { $0.id != id }
        try cardStore.delete(id: id)
        cleanupManagedAttachments(
            removedCards: [removedNote],
            remainingCards: remainingCards
        )
        return true
    }

    private func nextTopSortOrder(in cards: [CaptureCard]) -> Double {
        let maximum = cards
            .filter { !$0.isCopied }
            .map(\.sortOrder)
            .max() ?? 0

        return maximum + 1
    }

    private func normalizedText(
        rawText: String,
        screenshotPath: String?
    ) throws -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            guard screenshotPath != nil else {
                throw StackWriteServiceError.emptyNote
            }
            return "Screenshot attached"
        }

        return trimmed
    }

    private func resolvedScreenshotPath(
        for existingNote: CaptureCard,
        update: StackOptionalUpdate<String>
    ) throws -> PreparedScreenshotPath {
        switch update {
        case .keep:
            return try prepareScreenshotPath(
                existingNote.screenshotPath,
                ownerID: existingNote.id,
                currentPath: existingNote.screenshotPath
            )
        case .clear:
            return PreparedScreenshotPath(path: nil, importedManagedURL: nil)
        case .set(let value):
            return try prepareScreenshotPath(
                value,
                ownerID: replacementOwnerID(
                    preferredOwnerID: existingNote.id,
                    currentPath: existingNote.screenshotPath
                ),
                currentPath: existingNote.screenshotPath
            )
        }
    }

    private func prepareScreenshotPath(
        _ requestedPath: String?,
        ownerID: UUID,
        currentPath: String? = nil
    ) throws -> PreparedScreenshotPath {
        guard let requestedPath else {
            return PreparedScreenshotPath(path: nil, importedManagedURL: nil)
        }

        let trimmedPath = requestedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return PreparedScreenshotPath(path: nil, importedManagedURL: nil)
        }

        let requestedURL = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        let currentURL = currentPath.map { URL(fileURLWithPath: $0).standardizedFileURL }

        if let currentURL,
           currentURL == requestedURL,
           attachmentStore.isManagedFile(currentURL) {
            return PreparedScreenshotPath(path: currentURL.path, importedManagedURL: nil)
        }

        if attachmentStore.isManagedFile(requestedURL) {
            return PreparedScreenshotPath(path: requestedURL.path, importedManagedURL: nil)
        }

        let importedURL = try attachmentStore.importScreenshot(
            from: requestedURL,
            ownerID: ownerID
        ).standardizedFileURL
        return PreparedScreenshotPath(path: importedURL.path, importedManagedURL: importedURL)
    }

    private func replacementOwnerID(
        preferredOwnerID: UUID,
        currentPath: String?
    ) -> UUID {
        guard let currentPath else {
            return preferredOwnerID
        }

        let currentURL = URL(fileURLWithPath: currentPath).standardizedFileURL
        guard attachmentStore.isManagedFile(currentURL) else {
            return preferredOwnerID
        }

        return UUID()
    }

    private func cleanupImportedAttachment(at importedManagedURL: URL?) {
        guard let importedManagedURL else {
            return
        }

        do {
            try attachmentStore.removeManagedFile(at: importedManagedURL)
        } catch {
            NSLog(
                "StackWriteService imported attachment rollback failed: %@",
                error.localizedDescription
            )
        }
    }

    private func cleanupManagedAttachments(
        removedCards: [CaptureCard],
        remainingCards: [CaptureCard]
    ) {
        let referencedURLs = Set(remainingCards.compactMap { $0.screenshotURL?.standardizedFileURL })
        let removableURLs = Set(removedCards.compactMap { $0.screenshotURL?.standardizedFileURL })

        for fileURL in removableURLs where !referencedURLs.contains(fileURL) {
            do {
                try attachmentStore.removeManagedFile(at: fileURL)
            } catch {
                NSLog(
                    "StackWriteService attachment cleanup failed: %@",
                    error.localizedDescription
                )
            }
        }
    }

}

private func resolvedValue<Value>(
    current: Value,
    update: StackOptionalUpdate<Value>
) -> Value {
    switch update {
    case .keep:
        return current
    case .set(let value):
        return value
    case .clear:
        return current
    }
}

private func resolvedValue<Value>(
    current: Value?,
    update: StackOptionalUpdate<Value>
) -> Value? {
    switch update {
    case .keep:
        return current
    case .set(let value):
        return value
    case .clear:
        return nil
    }
}
