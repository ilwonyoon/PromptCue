import Foundation

public enum CaptureSuggestedTargetConfidence: String, Codable, Equatable, Sendable {
    case high
    case low
}

public enum CaptureSuggestedTargetSourceKind: String, Equatable, Sendable {
    case terminal
    case ide
}

public struct CaptureSuggestedTarget: Codable, Equatable, Sendable {
    public let appName: String
    public let bundleIdentifier: String
    public let windowTitle: String?
    public let sessionIdentifier: String?
    public let currentWorkingDirectory: String?
    public let repositoryRoot: String?
    public let repositoryName: String?
    public let branch: String?
    public let capturedAt: Date
    public let confidence: CaptureSuggestedTargetConfidence

    public init(
        appName: String,
        bundleIdentifier: String,
        windowTitle: String? = nil,
        sessionIdentifier: String? = nil,
        currentWorkingDirectory: String? = nil,
        repositoryRoot: String? = nil,
        repositoryName: String? = nil,
        branch: String? = nil,
        capturedAt: Date,
        confidence: CaptureSuggestedTargetConfidence = .high
    ) {
        self.appName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.windowTitle = Self.sanitizedOptional(windowTitle)
        self.sessionIdentifier = Self.sanitizedOptional(sessionIdentifier)
        self.currentWorkingDirectory = Self.sanitizedOptional(currentWorkingDirectory)
        self.repositoryRoot = Self.sanitizedOptional(repositoryRoot)
        self.repositoryName = Self.sanitizedOptional(repositoryName)
        self.branch = Self.sanitizedOptional(branch)
        self.capturedAt = capturedAt
        self.confidence = confidence
    }

    public var workspaceLabel: String {
        if let repositoryName {
            let repositoryLeaf = repositoryRoot.map {
                URL(fileURLWithPath: $0).lastPathComponent
            } ?? repositoryName

            if let currentWorkingDirectory {
                let workingLeaf = URL(fileURLWithPath: currentWorkingDirectory).lastPathComponent
                if !workingLeaf.isEmpty,
                   workingLeaf != repositoryLeaf,
                   workingLeaf != repositoryName {
                    return Self.truncate("\(repositoryName)/\(workingLeaf)", maxLength: 28)
                }
            }

            return Self.truncate(repositoryName, maxLength: 28)
        }

        if let currentWorkingDirectory {
            let leaf = URL(fileURLWithPath: currentWorkingDirectory).lastPathComponent
            if !leaf.isEmpty {
                return Self.truncate(leaf, maxLength: 28)
            }
        }

        if let windowTitle {
            return Self.truncate(windowTitle, maxLength: 28)
        }

        return appName
    }

    public var sourceKind: CaptureSuggestedTargetSourceKind {
        if Self.terminalBundleIdentifiers.contains(bundleIdentifier) {
            return .terminal
        }

        return .ide
    }

    public var fallbackDisplayLabel: String {
        if let windowTitle, !windowTitle.isEmpty {
            return Self.truncate(windowTitle, maxLength: 28)
        }

        return Self.truncate(appName, maxLength: 28)
    }

    public var choiceKey: String {
        [
            bundleIdentifier,
            sessionIdentifier ?? "",
            repositoryRoot ?? "",
            currentWorkingDirectory ?? "",
            windowTitle ?? "",
            workspaceLabel,
        ]
        .joined(separator: "|")
    }

    public var shortBranchLabel: String? {
        guard let branch else {
            return nil
        }

        let trimmedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBranch.isEmpty else {
            return nil
        }

        let branchComponent = trimmedBranch
            .split(separator: "/")
            .last
            .map(String.init) ?? trimmedBranch

        return Self.truncate(branchComponent, maxLength: 18)
    }

    public var chooserSecondaryLabel: String {
        if let shortBranchLabel {
            return Self.combinedLabel(appName: appName, detail: shortBranchLabel)
        }

        if let windowTitle, windowTitle != workspaceLabel {
            return Self.combinedLabel(appName: appName, detail: windowTitle)
        }

        if let sessionIdentifier, sessionIdentifier != workspaceLabel {
            return Self.combinedLabel(appName: appName, detail: sessionIdentifier)
        }

        return appName
    }

    public var chooserSectionTitle: String {
        switch sourceKind {
        case .terminal:
            return "Open Terminals"
        case .ide:
            return "Open IDEs"
        }
    }

    public var debugDetailText: String? {
        if let currentWorkingDirectory {
            return currentWorkingDirectory
        }

        if let windowTitle {
            return windowTitle
        }

        return appName
    }

    public func isFresh(
        relativeTo date: Date = Date(),
        freshness: TimeInterval
    ) -> Bool {
        date.timeIntervalSince(capturedAt) <= freshness
    }

    private static func combinedLabel(appName: String, detail: String) -> String {
        let truncatedDetail = truncate(detail, maxLength: 36)
        guard !truncatedDetail.isEmpty else {
            return appName
        }

        return "\(appName) · \(truncatedDetail)"
    }

    private static func truncate(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else {
            return value
        }

        return String(value.prefix(maxLength - 1)) + "…"
    }

    private static func sanitizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
    ]
}
