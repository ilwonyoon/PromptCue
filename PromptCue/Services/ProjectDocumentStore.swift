import Foundation
import GRDB
import PromptCueCore

enum ProjectDocumentStoreError: LocalizedError {
    case unavailable(underlying: Error?)
    case loadFailed(Error)
    case saveFailed(Error)
    case updateFailed(Error)

    var errorDescription: String? {
        switch self {
        case let .unavailable(underlying):
            return underlying?.localizedDescription ?? "Project document storage is unavailable"
        case let .loadFailed(error), let .saveFailed(error), let .updateFailed(error):
            return error.localizedDescription
        }
    }
}

@MainActor
final class ProjectDocumentStore {
    private let database: PromptCueDatabase

    init(database: PromptCueDatabase) {
        self.database = database
    }

    convenience init(
        fileManager: FileManager = .default,
        databaseURL: URL? = nil
    ) {
        self.init(database: PromptCueDatabase(fileManager: fileManager, databaseURL: databaseURL))
    }

    func list(project: String? = nil) throws -> [ProjectDocumentSummary] {
        guard let dbQueue = database.dbQueue else {
            throw ProjectDocumentStoreError.unavailable(underlying: database.setupError)
        }

        do {
            return try dbQueue.read { db in
                let records: [ProjectDocumentRecord]
                if let project {
                    records = try ProjectDocumentRecord.fetchAll(
                        db,
                        sql: """
                        SELECT *
                        FROM \(ProjectDocumentRecord.databaseTableName)
                        WHERE supersededByID IS NULL AND project = ?
                        ORDER BY updatedAt DESC, project ASC, topic ASC, documentType ASC
                        """,
                        arguments: [project]
                    )
                } else {
                    records = try ProjectDocumentRecord.fetchAll(
                        db,
                        sql: """
                        SELECT *
                        FROM \(ProjectDocumentRecord.databaseTableName)
                        WHERE supersededByID IS NULL
                        ORDER BY updatedAt DESC, project ASC, topic ASC, documentType ASC
                        """
                    )
                }

                return records.map(\.summary)
            }
        } catch {
            NSLog("ProjectDocumentStore list failed: %@", error.localizedDescription)
            throw ProjectDocumentStoreError.loadFailed(error)
        }
    }

    func currentDocument(
        project: String,
        topic: String,
        documentType: ProjectDocumentType
    ) throws -> ProjectDocument? {
        guard let dbQueue = database.dbQueue else {
            throw ProjectDocumentStoreError.unavailable(underlying: database.setupError)
        }

        do {
            return try dbQueue.read { db in
                try ProjectDocumentRecord.fetchOne(
                    db,
                    sql: """
                    SELECT *
                    FROM \(ProjectDocumentRecord.databaseTableName)
                    WHERE supersededByID IS NULL
                      AND project = ?
                      AND topic = ?
                      AND documentType = ?
                    LIMIT 1
                    """,
                    arguments: [project, topic, documentType.rawValue]
                )?.projectDocument
            }
        } catch {
            NSLog("ProjectDocumentStore currentDocument failed: %@", error.localizedDescription)
            throw ProjectDocumentStoreError.loadFailed(error)
        }
    }

    func saveDocument(
        project: String,
        topic: String,
        documentType: ProjectDocumentType,
        content: String,
        now: Date = Date()
    ) throws -> ProjectDocument {
        guard let dbQueue = database.dbQueue else {
            throw ProjectDocumentStoreError.unavailable(underlying: database.setupError)
        }

        do {
            return try dbQueue.write { db in
                let existing = try ProjectDocumentRecord.fetchOne(
                    db,
                    sql: """
                    SELECT *
                    FROM \(ProjectDocumentRecord.databaseTableName)
                    WHERE supersededByID IS NULL
                      AND project = ?
                      AND topic = ?
                      AND documentType = ?
                    LIMIT 1
                    """,
                    arguments: [project, topic, documentType.rawValue]
                )

                if let existing, existing.content == content {
                    return existing.projectDocument
                }

                let nextDocument = ProjectDocument(
                    project: project,
                    topic: topic,
                    documentType: documentType,
                    content: content,
                    createdAt: now,
                    updatedAt: now
                )

                if let existing {
                    try db.execute(
                        sql: """
                        UPDATE \(ProjectDocumentRecord.databaseTableName)
                        SET supersededByID = ?
                        WHERE id = ?
                        """,
                        arguments: [nextDocument.id.uuidString, existing.id]
                    )
                }

                try ProjectDocumentRecord(projectDocument: nextDocument).insert(db)

                return nextDocument
            }
        } catch {
            NSLog("ProjectDocumentStore saveDocument failed: %@", error.localizedDescription)
            throw ProjectDocumentStoreError.saveFailed(error)
        }
    }

    func updateDocument(
        project: String,
        topic: String,
        documentType: ProjectDocumentType,
        action: ProjectDocumentUpdateAction,
        section: String?,
        content: String?,
        now: Date = Date()
    ) throws -> ProjectDocument {
        guard let dbQueue = database.dbQueue else {
            throw ProjectDocumentStoreError.unavailable(underlying: database.setupError)
        }

        do {
            let updatedContent = try dbQueue.read { db in
                let existing = try ProjectDocumentRecord.fetchOne(
                    db,
                    sql: """
                    SELECT *
                    FROM \(ProjectDocumentRecord.databaseTableName)
                    WHERE supersededByID IS NULL
                      AND project = ?
                      AND topic = ?
                      AND documentType = ?
                    LIMIT 1
                    """,
                    arguments: [project, topic, documentType.rawValue]
                )

                guard let existing else {
                    throw ProjectDocumentMutationError.documentNotFound(
                        key: ProjectDocumentKey(
                            project: project,
                            topic: topic,
                            documentType: documentType
                        )
                    )
                }

                return try ProjectDocumentMutator.apply(
                    action: action,
                    to: existing.content,
                    section: section,
                    content: content
                )
            }
            try validateStoredDocumentContent(updatedContent)

            return try saveDocument(
                project: project,
                topic: topic,
                documentType: documentType,
                content: updatedContent,
                now: now
            )
        } catch {
            NSLog("ProjectDocumentStore updateDocument failed: %@", error.localizedDescription)
            throw ProjectDocumentStoreError.updateFailed(error)
        }
    }
}

enum ProjectDocumentUpdateAction: String, CaseIterable, Sendable {
    case append
    case replaceSection = "replace_section"
    case deleteSection = "delete_section"
}

enum ProjectDocumentMutationError: LocalizedError {
    case documentNotFound(key: ProjectDocumentKey)
    case invalidAppendContent
    case sectionRequired(action: ProjectDocumentUpdateAction)
    case contentRequired(action: ProjectDocumentUpdateAction)
    case sectionNotFound(String)
    case wouldEmptyDocument

    var errorDescription: String? {
        switch self {
        case let .documentNotFound(key):
            return "No current document found for \(key.project)/\(key.topic)/\(key.documentType.rawValue)"
        case .invalidAppendContent:
            return "append content must be a markdown fragment starting with a ## section header"
        case let .sectionRequired(action):
            return "section is required for \(action.rawValue)"
        case let .contentRequired(action):
            return "content is required for \(action.rawValue)"
        case let .sectionNotFound(section):
            return "Section not found: \(section)"
        case .wouldEmptyDocument:
            return "update would remove all document sections"
        }
    }
}

enum ProjectDocumentValidationError: LocalizedError {
    case emptyContent
    case contentTooShort
    case missingSectionHeaders

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "content must not be empty"
        case .contentTooShort:
            return "content must be at least 200 characters of structured markdown"
        case .missingSectionHeaders:
            return "content must include markdown ## section headers"
        }
    }
}

private enum ProjectDocumentMutator {
    static func apply(
        action: ProjectDocumentUpdateAction,
        to content: String,
        section: String?,
        content fragment: String?
    ) throws -> String {
        switch action {
        case .append:
            let fragment = try requiredContent(fragment, action: .append)
            guard fragment.hasPrefix("## ") else {
                throw ProjectDocumentMutationError.invalidAppendContent
            }
            return append(fragment: fragment, to: content)

        case .replaceSection:
            let targetSection = try requiredSection(section, action: .replaceSection)
            let fragment = try requiredContent(fragment, action: .replaceSection)
            return try replaceSection(named: targetSection, with: fragment, in: content)

        case .deleteSection:
            let targetSection = try requiredSection(section, action: .deleteSection)
            return try deleteSection(named: targetSection, in: content)
        }
    }

    private static func requiredSection(
        _ section: String?,
        action: ProjectDocumentUpdateAction
    ) throws -> String {
        let trimmed = section?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw ProjectDocumentMutationError.sectionRequired(action: action)
        }
        return trimmed
    }

    private static func requiredContent(
        _ content: String?,
        action: ProjectDocumentUpdateAction
    ) throws -> String {
        let trimmed = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw ProjectDocumentMutationError.contentRequired(action: action)
        }
        return trimmed
    }

    private static func append(fragment: String, to content: String) -> String {
        let trimmedBase = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty {
            return fragment
        }
        return "\(trimmedBase)\n\n\(fragment)"
    }

    private static func replaceSection(
        named section: String,
        with replacementBody: String,
        in content: String
    ) throws -> String {
        let ranges = try sectionRanges(in: content)
        guard let target = ranges.first(where: { normalizedSectionName($0.title) == normalizedSectionName(section) }) else {
            throw ProjectDocumentMutationError.sectionNotFound(section)
        }
        guard let targetRange = Range(target.range, in: content) else {
            throw ProjectDocumentMutationError.sectionNotFound(section)
        }

        var replacement = replacementSection(title: target.title, body: replacementBody)
        let hasFollowingSection = target.range.location + target.range.length < (content as NSString).length
        if hasFollowingSection {
            replacement += "\n\n"
        }
        let updated = content.replacingCharacters(in: targetRange, with: replacement)
        return normalizeDocument(updated)
    }

    private static func deleteSection(
        named section: String,
        in content: String
    ) throws -> String {
        let ranges = try sectionRanges(in: content)
        guard let target = ranges.first(where: { normalizedSectionName($0.title) == normalizedSectionName(section) }) else {
            throw ProjectDocumentMutationError.sectionNotFound(section)
        }
        guard ranges.count > 1 else {
            throw ProjectDocumentMutationError.wouldEmptyDocument
        }
        guard let targetRange = Range(target.range, in: content) else {
            throw ProjectDocumentMutationError.sectionNotFound(section)
        }

        let updated = content.replacingCharacters(in: targetRange, with: "")
        return normalizeDocument(updated)
    }

    private static func replacementSection(title: String, body: String) -> String {
        let normalizedBody: String
        if body.hasPrefix("## ") {
            normalizedBody = stripFirstSectionHeader(from: body)
        } else {
            normalizedBody = body
        }

        let trimmedBody = normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        return "## \(title)\n\(trimmedBody)"
    }

    private static func stripFirstSectionHeader(from fragment: String) -> String {
        let lines = fragment.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, first.hasPrefix("## ") else {
            return fragment
        }
        return lines.dropFirst().joined(separator: "\n")
    }

    private static func normalizeDocument(_ content: String) -> String {
        let lines = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)

        var normalized: [String] = []
        var previousWasBlank = false
        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !previousWasBlank {
                    normalized.append("")
                }
            } else if line.hasPrefix("## "), !normalized.isEmpty, !previousWasBlank {
                normalized.append("")
                normalized.append(line)
            } else {
                normalized.append(line)
            }
            previousWasBlank = isBlank
        }
        return normalized.joined(separator: "\n")
    }

    private static func normalizedSectionName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func sectionRanges(in content: String) throws -> [DocumentSectionRange] {
        let nsContent = content as NSString
        let pattern = #"(?m)^##\s+(.+?)\s*$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(
            in: content,
            options: [],
            range: NSRange(location: 0, length: nsContent.length)
        )

        return matches.enumerated().compactMap { index, match in
            guard match.numberOfRanges >= 2 else { return nil }
            let titleRange = match.range(at: 1)
            guard let titleSwiftRange = Range(titleRange, in: content) else { return nil }

            let sectionStart = match.range.location
            let sectionEnd: Int
            if index + 1 < matches.count {
                sectionEnd = matches[index + 1].range.location
            } else {
                sectionEnd = nsContent.length
            }

            return DocumentSectionRange(
                title: String(content[titleSwiftRange]),
                range: NSRange(location: sectionStart, length: sectionEnd - sectionStart)
            )
        }
    }
}

private struct DocumentSectionRange {
    let title: String
    let range: NSRange
}

private func validateStoredDocumentContent(_ content: String) throws {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw ProjectDocumentValidationError.emptyContent
    }
    guard trimmed.count >= 200 else {
        throw ProjectDocumentValidationError.contentTooShort
    }
    guard trimmed.contains("\n## ") || trimmed.hasPrefix("## ") else {
        throw ProjectDocumentValidationError.missingSectionHeaders
    }
}

private struct ProjectDocumentRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = PromptCueDatabaseSchema.projectDocumentsTableName

    let id: String
    let project: String
    let topic: String
    let documentType: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let supersededByID: String?

    init(projectDocument: ProjectDocument) {
        id = projectDocument.id.uuidString
        project = projectDocument.project
        topic = projectDocument.topic
        documentType = projectDocument.documentType.rawValue
        content = projectDocument.content
        createdAt = projectDocument.createdAt
        updatedAt = projectDocument.updatedAt
        supersededByID = projectDocument.supersededByID?.uuidString
    }

    var projectDocument: ProjectDocument {
        ProjectDocument(
            id: UUID(uuidString: id) ?? UUID(),
            project: project,
            topic: topic,
            documentType: ProjectDocumentType(rawValue: documentType) ?? .discussion,
            content: content,
            createdAt: createdAt,
            updatedAt: updatedAt,
            supersededByID: supersededByID.flatMap(UUID.init(uuidString:))
        )
    }

    var summary: ProjectDocumentSummary {
        ProjectDocumentSummary(
            id: UUID(uuidString: id) ?? UUID(),
            project: project,
            topic: topic,
            documentType: ProjectDocumentType(rawValue: documentType) ?? .discussion,
            updatedAt: updatedAt
        )
    }
}
