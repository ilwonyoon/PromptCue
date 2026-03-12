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
    public let terminalTTY: String?
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
        terminalTTY: String? = nil,
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
        self.terminalTTY = Self.sanitizedOptional(terminalTTY)
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

        if let derivedTitleMetadata = Self.derivedTitleMetadata(from: windowTitle) {
            return Self.truncate(derivedTitleMetadata.workspaceLabel, maxLength: 28)
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

    public var canonicalIdentityKey: String {
        switch sourceKind {
        case .terminal:
            return [
                bundleIdentifier,
                terminalTTY
                    ?? sessionIdentifier
                    ?? currentWorkingDirectory
                    ?? windowTitle
                    ?? workspaceLabel,
            ]
            .joined(separator: "|")

        case .ide:
            return [
                bundleIdentifier,
                sessionIdentifier ?? "",
                repositoryRoot ?? "",
                currentWorkingDirectory ?? "",
                windowTitle ?? "",
            ]
            .joined(separator: "|")
        }
    }

    public var shortBranchLabel: String? {
        let branch = branch ?? Self.derivedTitleMetadata(from: windowTitle)?.branch
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

        if let detail = Self.derivedTitleMetadata(from: windowTitle)?.secondaryDetail,
           detail.localizedCaseInsensitiveCompare(workspaceLabel) != .orderedSame {
            return Self.combinedLabel(appName: appName, detail: detail)
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

    private struct DerivedTitleMetadata {
        let workspaceLabel: String
        let secondaryDetail: String?
        let branch: String?
    }

    private static func derivedTitleMetadata(from windowTitle: String?) -> DerivedTitleMetadata? {
        guard let trimmedTitle = sanitizedOptional(windowTitle) else {
            return nil
        }

        if let wrapped = extractWrappedBranchMetadata(from: trimmedTitle) {
            return wrapped
        }

        for separator in titleSeparators {
            guard trimmedTitle.contains(separator) else {
                continue
            }

            let parts = trimmedTitle
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard parts.count >= 2 else {
                continue
            }

            let left = parts[0]
            let right = parts.dropFirst().joined(separator: separator)

            if isLikelyBranchLabel(left), !isLikelyBranchLabel(right) {
                return DerivedTitleMetadata(
                    workspaceLabel: right,
                    secondaryDetail: nil,
                    branch: left
                )
            }

            if isLikelyBranchLabel(right) {
                return DerivedTitleMetadata(
                    workspaceLabel: left,
                    secondaryDetail: nil,
                    branch: right
                )
            }

            if isLikelyGenericTitleComponent(left), !isLikelyGenericTitleComponent(right) {
                return DerivedTitleMetadata(
                    workspaceLabel: right,
                    secondaryDetail: nil,
                    branch: nil
                )
            }

            return DerivedTitleMetadata(
                workspaceLabel: left,
                secondaryDetail: right,
                branch: nil
            )
        }

        return nil
    }

    private static func extractWrappedBranchMetadata(from windowTitle: String) -> DerivedTitleMetadata? {
        for markers in [(" [", "]"), (" (", ")")] {
            guard windowTitle.hasSuffix(markers.1),
                  let range = windowTitle.range(of: markers.0, options: .backwards) else {
                continue
            }

            let workspace = windowTitle[..<range.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let branchCandidate = windowTitle[range.upperBound..<windowTitle.index(before: windowTitle.endIndex)]
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !workspace.isEmpty,
                  !branchCandidate.isEmpty,
                  isLikelyBranchLabel(branchCandidate) else {
                continue
            }

            return DerivedTitleMetadata(
                workspaceLabel: workspace,
                secondaryDetail: nil,
                branch: branchCandidate
            )
        }

        return nil
    }

    private static func isLikelyBranchLabel(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return false
        }

        let lowercaseValue = trimmedValue.lowercased()
        if commonBranchNames.contains(lowercaseValue) {
            return true
        }

        if lowercaseValue.contains("/") {
            return true
        }

        return false
    }

    private static func isLikelyGenericTitleComponent(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return genericTitleComponents.contains(normalized)
    }

    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
    ]

    private static let titleSeparators = [" — ", " – ", " - ", " · ", " | "]
    private static let commonBranchNames: Set<String> = [
        "main", "master", "develop", "development", "dev", "trunk",
        "staging", "stage", "production", "prod", "release", "qa", "test"
    ]
    private static let genericTitleComponents: Set<String> = [
        "terminal", "iterm2", "iterm", "shell", "zsh", "bash", "fish",
        "codex", "cursor", "xcode", "vs code", "vscode", "windsurf",
        "zed", "antigravity", "claude"
    ]
}
