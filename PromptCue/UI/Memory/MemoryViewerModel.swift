import Foundation
import AppKit
import PromptCueCore

@MainActor
final class MemoryViewerModel: ObservableObject {
    struct NewDocumentDraft: Equatable {
        static let starterTemplate = """
        ## Overview

        Summarize the durable context, why it matters, and the current state so a future session can understand this document without rereading raw notes.

        ## Details

        Capture the key supporting details, constraints, decisions, and follow-up context that should stay durable in Memory.
        """

        var project: String
        var topic: String
        var documentType: ProjectDocumentType
        var content: String

        init(
            project: String = "",
            topic: String = "",
            documentType: ProjectDocumentType = .discussion,
            content: String = NewDocumentDraft.starterTemplate
        ) {
            self.project = project
            self.topic = topic
            self.documentType = documentType
            self.content = content
        }

        static func contentForPastedText(_ pastedText: String?) -> String {
            let trimmed = pastedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                return starterTemplate
            }

            if trimmed.hasPrefix("## ") || trimmed.contains("\n## ") {
                return trimmed
            }

            return """
            ## Overview

            \(trimmed)

            Summarize the durable context, why it matters, and the current state so a future session can understand this document without rereading raw notes.

            ## Details

            Capture the key supporting details, constraints, decisions, and follow-up context that should stay durable in Memory.
            """
        }
    }

    enum SaveSelectedDocumentResult: Equatable {
        case saved
        case deleteIntent
        case failed
    }

    @Published private(set) var projects: [String] = []
    @Published private(set) var summariesByProject: [String: [ProjectDocumentSummary]] = [:]
    @Published private(set) var selectedDocument: ProjectDocument?
    @Published private(set) var storageErrorMessage: String?
    @Published var selectedProject: String? {
        didSet {
            guard selectedProject != oldValue else {
                return
            }
            syncSelectionAfterProjectChange()
        }
    }
    @Published var selectedDocumentKey: ProjectDocumentKey? {
        didSet {
            guard selectedDocumentKey != oldValue else {
                return
            }
            loadSelectedDocument()
        }
    }

    private let store: ProjectDocumentStore
    private let pasteboard: NSPasteboard

    init(
        store: ProjectDocumentStore? = nil,
        pasteboard: NSPasteboard = .general
    ) {
        self.store = store ?? ProjectDocumentStore()
        self.pasteboard = pasteboard
        refresh()
    }

    func refresh() {
        do {
            let summaries = try store.list()
            let grouped = Dictionary(grouping: summaries, by: \.project)
            let orderedProjects = grouped.keys.sorted { lhs, rhs in
                let lhsLatest = grouped[lhs]?.first?.updatedAt ?? .distantPast
                let rhsLatest = grouped[rhs]?.first?.updatedAt ?? .distantPast
                if lhsLatest != rhsLatest {
                    return lhsLatest > rhsLatest
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }

            projects = orderedProjects
            summariesByProject = grouped
            storageErrorMessage = nil

            if let selectedProject,
               grouped[selectedProject] != nil {
                syncSelectionAfterProjectChange()
            } else {
                self.selectedProject = orderedProjects.first
            }
        } catch {
            projects = []
            summariesByProject = [:]
            selectedProject = nil
            selectedDocumentKey = nil
            selectedDocument = nil
            storageErrorMessage = error.localizedDescription
        }
    }

    func summaries(for project: String?) -> [ProjectDocumentSummary] {
        guard let project else {
            return []
        }
        return summariesByProject[project] ?? []
    }

    func copySelectedDocument() {
        guard let selectedDocument else {
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(selectedDocument.content, forType: .string)
    }

    func prepareNewDocumentDraft(fromClipboard: Bool = false) -> NewDocumentDraft {
        NewDocumentDraft(
            project: selectedProject ?? "",
            content: fromClipboard
                ? NewDocumentDraft.contentForPastedText(pasteboardString())
                : NewDocumentDraft.starterTemplate
        )
    }

    func pasteboardString() -> String? {
        pasteboard.string(forType: .string)
    }

    @discardableResult
    func createDocument(
        project: String,
        topic: String,
        documentType: ProjectDocumentType,
        content: String
    ) -> Bool {
        let trimmedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            guard !trimmedProject.isEmpty else {
                throw MemoryViewerModelError.projectRequired
            }
            guard !trimmedTopic.isEmpty else {
                throw MemoryViewerModelError.topicRequired
            }

            try ProjectDocumentStore.validateContent(content)
            if try store.currentDocument(
                project: trimmedProject,
                topic: trimmedTopic,
                documentType: documentType
            ) != nil {
                throw MemoryViewerModelError.duplicateDocument
            }

            let savedDocument = try store.saveDocument(
                project: trimmedProject,
                topic: trimmedTopic,
                documentType: documentType,
                content: content
            )
            storageErrorMessage = nil
            refresh()
            selectedProject = savedDocument.project
            selectedDocumentKey = savedDocument.key
            return true
        } catch {
            storageErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveSelectedDocumentContent(_ content: String) -> SaveSelectedDocumentResult {
        guard let selectedDocumentKey else {
            return .failed
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            storageErrorMessage = nil
            return .deleteIntent
        }

        do {
            let savedDocument = try store.saveDocument(
                project: selectedDocumentKey.project,
                topic: selectedDocumentKey.topic,
                documentType: selectedDocumentKey.documentType,
                content: content
            )
            storageErrorMessage = nil
            refresh()
            selectedProject = savedDocument.project
            self.selectedDocumentKey = savedDocument.key
            return .saved
        } catch {
            storageErrorMessage = error.localizedDescription
            return .failed
        }
    }

    @discardableResult
    func deleteSelectedDocument() -> Bool {
        guard let selectedDocumentKey else {
            return false
        }

        let fallbackKey = preferredDocumentSelectionAfterDeletingSelectedDocument()

        do {
            _ = try store.deleteDocument(
                project: selectedDocumentKey.project,
                topic: selectedDocumentKey.topic,
                documentType: selectedDocumentKey.documentType
            )
            storageErrorMessage = nil
            refresh()

            if let fallbackKey,
               summaries(for: fallbackKey.project).contains(where: { $0.key == fallbackKey }) {
                selectedProject = fallbackKey.project
                self.selectedDocumentKey = fallbackKey
            }

            return true
        } catch {
            storageErrorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteProject(_ project: String) -> Bool {
        do {
            _ = try store.deleteProject(project)
            storageErrorMessage = nil
            refresh()
            return true
        } catch {
            storageErrorMessage = error.localizedDescription
            return false
        }
    }

    private func syncSelectionAfterProjectChange() {
        let availableSummaries = summaries(for: selectedProject)
        guard !availableSummaries.isEmpty else {
            selectedDocumentKey = nil
            return
        }

        if let selectedDocumentKey,
           availableSummaries.contains(where: { $0.key == selectedDocumentKey }) {
            loadSelectedDocument()
            return
        }

        selectedDocumentKey = availableSummaries.first?.key
    }

    private func loadSelectedDocument() {
        guard let selectedDocumentKey else {
            selectedDocument = nil
            return
        }

        do {
            selectedDocument = try store.currentDocument(
                project: selectedDocumentKey.project,
                topic: selectedDocumentKey.topic,
                documentType: selectedDocumentKey.documentType
            )
            storageErrorMessage = nil
        } catch {
            selectedDocument = nil
            storageErrorMessage = error.localizedDescription
        }
    }

    private func preferredDocumentSelectionAfterDeletingSelectedDocument() -> ProjectDocumentKey? {
        guard let selectedProject,
              let selectedDocumentKey else {
            return nil
        }

        let projectSummaries = summaries(for: selectedProject)
        guard let selectedIndex = projectSummaries.firstIndex(where: { $0.key == selectedDocumentKey }) else {
            return projectSummaries.first?.key
        }

        if projectSummaries.indices.contains(selectedIndex + 1) {
            return projectSummaries[selectedIndex + 1].key
        }

        return projectSummaries.first(where: { $0.key != selectedDocumentKey })?.key
    }
}

private enum MemoryViewerModelError: LocalizedError {
    case projectRequired
    case topicRequired
    case duplicateDocument

    var errorDescription: String? {
        switch self {
        case .projectRequired:
            return "project is required"
        case .topicRequired:
            return "topic is required"
        case .duplicateDocument:
            return "A document with this project, topic, and type already exists."
        }
    }
}
