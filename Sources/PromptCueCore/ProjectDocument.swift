import Foundation

public enum ProjectDocumentType: String, Codable, CaseIterable, Sendable {
    case discussion
    case decision
    case plan
    case reference
}

public struct ProjectDocumentKey: Codable, Hashable, Sendable {
    public var project: String
    public var topic: String
    public var documentType: ProjectDocumentType

    public init(
        project: String,
        topic: String,
        documentType: ProjectDocumentType
    ) {
        self.project = project
        self.topic = topic
        self.documentType = documentType
    }
}

public struct ProjectDocument: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var project: String
    public var topic: String
    public var documentType: ProjectDocumentType
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var supersededByID: UUID?

    public init(
        id: UUID = UUID(),
        project: String,
        topic: String,
        documentType: ProjectDocumentType,
        content: String,
        createdAt: Date,
        updatedAt: Date,
        supersededByID: UUID? = nil
    ) {
        self.id = id
        self.project = project
        self.topic = topic
        self.documentType = documentType
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.supersededByID = supersededByID
    }

    public var key: ProjectDocumentKey {
        ProjectDocumentKey(
            project: project,
            topic: topic,
            documentType: documentType
        )
    }

    public var isSuperseded: Bool {
        supersededByID != nil
    }
}

public struct ProjectDocumentSummary: Codable, Sendable, Equatable {
    public var id: UUID
    public var project: String
    public var topic: String
    public var documentType: ProjectDocumentType
    public var updatedAt: Date

    public init(
        id: UUID,
        project: String,
        topic: String,
        documentType: ProjectDocumentType,
        updatedAt: Date
    ) {
        self.id = id
        self.project = project
        self.topic = topic
        self.documentType = documentType
        self.updatedAt = updatedAt
    }
}
