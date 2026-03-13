import Foundation
import PromptCueCore

struct StackGroupRequest: Equatable, Sendable {
    let sourceNoteIDs: [UUID]
    let title: String
    let separator: String
    let archiveSources: Bool
    let sessionID: String?

    init(
        sourceNoteIDs: [UUID],
        title: String,
        separator: String = "---",
        archiveSources: Bool = false,
        sessionID: String? = nil
    ) {
        self.sourceNoteIDs = sourceNoteIDs
        self.title = title
        self.separator = separator
        self.archiveSources = archiveSources
        self.sessionID = sessionID
    }
}

struct StackGroupResult: Equatable, Sendable {
    let groupedNote: CaptureCard
    let archivedNotes: [CaptureCard]
    let copyEvents: [CopyEvent]
}

enum StackGroupServiceError: Error, Equatable {
    case emptyNoteIDs
    case emptyTitle
    case noteNotFound(UUID)
}

@MainActor
final class StackGroupService {
    private let readService: StackReadService
    private let writeService: StackWriteService
    private let executionService: StackExecutionService

    init(
        readService: StackReadService,
        writeService: StackWriteService,
        executionService: StackExecutionService
    ) {
        self.readService = readService
        self.writeService = writeService
        self.executionService = executionService
    }

    func groupNotes(_ request: StackGroupRequest) throws -> StackGroupResult {
        guard !request.sourceNoteIDs.isEmpty else {
            throw StackGroupServiceError.emptyNoteIDs
        }

        let trimmedTitle = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw StackGroupServiceError.emptyTitle
        }

        let uniqueIDs = deduplicatePreservingOrder(request.sourceNoteIDs)
        let sourceNotes = try loadSourceNotes(ids: uniqueIDs)
        let mergedText = buildMergedText(
            title: trimmedTitle,
            notes: sourceNotes,
            separator: request.separator
        )
        let inheritedTags = CaptureTag.deduplicatePreservingOrder(sourceNotes.flatMap(\.tags))
        let inheritedTarget = sourceNotes.first(where: { $0.suggestedTarget != nil })?.suggestedTarget

        let groupedNote = try writeService.createNote(
            StackNoteCreateRequest(
                text: mergedText,
                tags: inheritedTags,
                suggestedTarget: inheritedTarget
            )
        )

        var archivedNotes: [CaptureCard] = []
        var copyEvents: [CopyEvent] = []

        if request.archiveSources {
            let executionResult = try executionService.markExecuted(
                noteIDs: uniqueIDs,
                sessionID: request.sessionID
            )
            archivedNotes = executionResult.notes
            copyEvents = executionResult.copyEvents
        }

        return StackGroupResult(
            groupedNote: groupedNote,
            archivedNotes: archivedNotes,
            copyEvents: copyEvents
        )
    }

    private func loadSourceNotes(ids: [UUID]) throws -> [CaptureCard] {
        try ids.map { id in
            guard let note = try readService.note(id: id) else {
                throw StackGroupServiceError.noteNotFound(id)
            }
            return note
        }
    }

    private static let mergedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    private func buildMergedText(
        title: String,
        notes: [CaptureCard],
        separator: String
    ) -> String {
        var parts: [String] = ["# \(title)"]

        for note in notes {
            let shortID = note.id.uuidString.lowercased().prefix(8)
            let dateString = Self.mergedDateFormatter.string(from: note.createdAt)
            parts.append("\(separator) [note:\(shortID) | \(dateString)]")
            parts.append(note.text)
        }

        return parts.joined(separator: "\n\n")
    }

    private func deduplicatePreservingOrder(_ ids: [UUID]) -> [UUID] {
        ids.reduce(into: [UUID]()) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
    }
}
