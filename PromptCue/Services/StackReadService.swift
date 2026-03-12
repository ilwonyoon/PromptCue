import Foundation
import PromptCueCore

enum StackReadScope {
    case all
    case active
    case copied

    func matches(_ card: CaptureCard) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return card.isCopied == false
        case .copied:
            return card.isCopied
        }
    }
}

enum StackClassifyGroupBy: String {
    case repository
    case session
    case app
}

struct NoteClassification: Equatable {
    let groupKey: String
    let repositoryName: String?
    let branch: String?
    let appName: String?
    let sessionIdentifier: String?
    let noteIDs: [UUID]
    let previewTexts: [String]
}

struct StackNoteDetail: Equatable {
    let note: CaptureCard
    let copyEvents: [CopyEvent]
}

@MainActor
final class StackReadService {
    private let cardStore: CardStore
    private let copyEventStore: CopyEventStore

    init(
        cardStore: CardStore,
        copyEventStore: CopyEventStore
    ) {
        self.cardStore = cardStore
        self.copyEventStore = copyEventStore
    }

    convenience init(
        fileManager: FileManager = .default,
        databaseURL: URL? = nil
    ) {
        let database = PromptCueDatabase(fileManager: fileManager, databaseURL: databaseURL)
        self.init(
            cardStore: CardStore(database: database),
            copyEventStore: CopyEventStore(database: database)
        )
    }

    func listNotes(scope: StackReadScope = .all) throws -> [CaptureCard] {
        let cards = CardStackOrdering.sort(try cardStore.load())
        return cards.filter(scope.matches(_:))
    }

    func note(id: UUID) throws -> CaptureCard? {
        try listNotes().first(where: { $0.id == id })
    }

    func classifyNotes(
        scope: StackReadScope = .active,
        groupBy: StackClassifyGroupBy = .repository
    ) throws -> [NoteClassification] {
        let notes = try listNotes(scope: scope)
        let grouped = Dictionary(grouping: notes) { note -> String in
            classificationKey(for: note, groupBy: groupBy)
        }

        return grouped
            .map { key, cards in
                let firstTarget = cards.first(where: { $0.suggestedTarget != nil })?.suggestedTarget
                return NoteClassification(
                    groupKey: key,
                    repositoryName: firstTarget?.repositoryName,
                    branch: firstTarget?.branch,
                    appName: firstTarget?.appName,
                    sessionIdentifier: firstTarget?.sessionIdentifier,
                    noteIDs: cards.map(\.id),
                    previewTexts: cards.map { String($0.text.prefix(80)) }
                )
            }
            .sorted { $0.noteIDs.count > $1.noteIDs.count }
    }

    func noteDetail(id: UUID) throws -> StackNoteDetail? {
        guard let note = try note(id: id) else {
            return nil
        }

        return StackNoteDetail(
            note: note,
            copyEvents: try copyEventStore.loadCopyEvents(for: id)
        )
    }

    private func classificationKey(
        for note: CaptureCard,
        groupBy: StackClassifyGroupBy
    ) -> String {
        guard let target = note.suggestedTarget else {
            return "uncategorized"
        }

        switch groupBy {
        case .repository:
            let repo = target.repositoryName ?? "unknown-repo"
            let branch = target.branch ?? "no-branch"
            return "\(repo)|\(branch)"
        case .session:
            return target.sessionIdentifier ?? "no-session"
        case .app:
            return "\(target.bundleIdentifier)|\(target.appName)"
        }
    }
}
