import Foundation
import AppKit
import PromptCueCore

@MainActor
final class MemoryViewerModel: ObservableObject {
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

    @discardableResult
    func saveSelectedDocumentContent(_ content: String) -> Bool {
        guard let selectedDocumentKey else {
            return false
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
}
