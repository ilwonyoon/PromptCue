import AppKit
import Foundation
import PromptCueCore

@MainActor
protocol SuggestedTargetProviding: AnyObject {
    var onChange: (() -> Void)? { get set }
    func start()
    func stop()
    func currentFreshSuggestedTarget(relativeTo date: Date, freshness: TimeInterval) -> CaptureSuggestedTarget?
    func availableSuggestedTargets() -> [CaptureSuggestedTarget]
    func refreshAvailableSuggestedTargets()
}

@MainActor
final class NoopSuggestedTargetProvider: SuggestedTargetProviding {
    var onChange: (() -> Void)?

    func start() {}
    func stop() {}

    func currentFreshSuggestedTarget(relativeTo date: Date, freshness: TimeInterval) -> CaptureSuggestedTarget? {
        nil
    }

    func availableSuggestedTargets() -> [CaptureSuggestedTarget] {
        []
    }

    func refreshAvailableSuggestedTargets() {}
}

struct SupportedSuggestedApp: Equatable {
    let appName: String
    let bundleIdentifier: String
    let sourceKind: CaptureSuggestedTargetSourceKind
}

enum SupportedSuggestedApps {
    static let all: [SupportedSuggestedApp] = [
        SupportedSuggestedApp(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", sourceKind: .terminal),
        SupportedSuggestedApp(appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", sourceKind: .terminal),
        SupportedSuggestedApp(appName: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", sourceKind: .ide),
        SupportedSuggestedApp(appName: "Codex", bundleIdentifier: "com.openai.codex", sourceKind: .ide),
        SupportedSuggestedApp(appName: "Antigravity", bundleIdentifier: "com.google.antigravity", sourceKind: .ide),
        SupportedSuggestedApp(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", sourceKind: .ide),
        SupportedSuggestedApp(appName: "VS Code", bundleIdentifier: "com.microsoft.VSCode", sourceKind: .ide),
        SupportedSuggestedApp(appName: "Windsurf", bundleIdentifier: "com.exafunction.windsurf", sourceKind: .ide),
        SupportedSuggestedApp(appName: "Zed", bundleIdentifier: "dev.zed.Zed", sourceKind: .ide),
    ]

    static let byBundleIdentifier = Dictionary(
        uniqueKeysWithValues: all.map { ($0.bundleIdentifier, $0) }
    )

    static func app(for bundleIdentifier: String) -> SupportedSuggestedApp? {
        byBundleIdentifier[bundleIdentifier]
    }
}

@MainActor
final class RecentSuggestedAppTargetTracker: SuggestedTargetProviding {
    var onChange: (() -> Void)?

    private var activationObserver: NSObjectProtocol?
    private var latestTarget: CaptureSuggestedTarget?
    private var availableTargets: [CaptureSuggestedTarget] = []
    private let resolutionQueue = DispatchQueue(
        label: "com.promptcue.recent-suggested-app-target-resolution",
        qos: .utility
    )
    private var latestResolutionID: UUID?
    private var availableResolutionID: UUID?

    func start() {
        guard activationObserver == nil else {
            return
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleDidActivateApplication(notification)
            }
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            updateLatestTarget(from: frontmostApplication)
        }

        refreshAvailableSuggestedTargets()
    }

    func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }

        activationObserver = nil
    }

    func currentFreshSuggestedTarget(
        relativeTo date: Date = Date(),
        freshness: TimeInterval
    ) -> CaptureSuggestedTarget? {
        guard let latestTarget,
              latestTarget.isFresh(relativeTo: date, freshness: freshness) else {
            return nil
        }

        return latestTarget
    }

    func availableSuggestedTargets() -> [CaptureSuggestedTarget] {
        availableTargets
    }

    func refreshAvailableSuggestedTargets() {
        let resolutionID = UUID()
        availableResolutionID = resolutionID
        let latestTarget = latestTarget

        resolutionQueue.async { [weak self, latestTarget] in
            let enumeratedTargets = enumerateAvailableSuggestedTargets(latestTarget: latestTarget)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.availableResolutionID == resolutionID else {
                    return
                }

                self.availableTargets = enumeratedTargets
                self.onChange?()
            }
        }
    }

    private func handleDidActivateApplication(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        updateLatestTarget(from: application)
    }

    private func updateLatestTarget(from application: NSRunningApplication) {
        guard let bundleIdentifier = application.bundleIdentifier,
              let supportedApp = supportedApp(for: bundleIdentifier) else {
            return
        }

        let capturedAt = Date()
        let windowTitle = frontWindowTitle(forProcessIdentifier: application.processIdentifier)
        let provisionalTarget = CaptureSuggestedTarget(
            appName: supportedApp.appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            capturedAt: capturedAt,
            confidence: .low
        )

        latestTarget = supportedApp.sourceKind == .terminal ? nil : provisionalTarget
        onChange?()
        refreshAvailableSuggestedTargets()

        let resolutionID = UUID()
        latestResolutionID = resolutionID

        resolutionQueue.async { [weak self] in
            let resolvedTarget = buildDetailedSuggestedTarget(
                appName: supportedApp.appName,
                bundleIdentifier: bundleIdentifier,
                fallbackWindowTitle: windowTitle,
                capturedAt: capturedAt
            )

            guard let resolvedTarget else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.latestResolutionID == resolutionID else {
                    return
                }

                self.latestTarget = resolvedTarget
                self.onChange?()
            }
        }
    }

    private func supportedApp(for bundleIdentifier: String) -> SupportedSuggestedApp? {
        SupportedSuggestedApps.app(for: bundleIdentifier)
    }

    private func frontWindowTitle(forProcessIdentifier processIdentifier: pid_t) -> String? {
        windowTitles(forProcessIdentifier: processIdentifier).first
    }
}

struct SuggestedTargetWindowSnapshot {
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String?
    let sessionIdentifier: String?
    let tty: String?
}

private func enumerateAvailableSuggestedTargets(
    latestTarget: CaptureSuggestedTarget?
) -> [CaptureSuggestedTarget] {
    let capturedAt = Date()
    let snapshots = enumerateTerminalWindowSnapshots()
        + enumerateITermWindowSnapshots()
        + enumerateIDEWindowSnapshots()
    var deduplicatedSnapshots: [String: SuggestedTargetWindowSnapshot] = [:]

    for snapshot in snapshots {
        deduplicatedSnapshots[suggestedTargetSnapshotMatchKey(snapshot)] = snapshot
    }

    let targets = deduplicatedSnapshots.values.compactMap { snapshot in
        buildDetailedSuggestedTarget(
            appName: snapshot.appName,
            bundleIdentifier: snapshot.bundleIdentifier,
            fallbackWindowTitle: snapshot.windowTitle,
            capturedAt: capturedAt,
            sessionContext: snapshot.tty.map {
                TerminalSessionContext(
                    tty: $0,
                    sessionIdentifier: snapshot.sessionIdentifier ?? $0
                )
            }
        )
    }

    guard !targets.isEmpty else {
        if let latestTarget {
            return [latestTarget]
        }

        return []
    }

    let latestKey = latestTarget.map(suggestedTargetMatchKey)
    return targets.sorted { lhs, rhs in
        let lhsIsLatest = latestKey == suggestedTargetMatchKey(lhs)
        let rhsIsLatest = latestKey == suggestedTargetMatchKey(rhs)

        if lhsIsLatest != rhsIsLatest {
            return lhsIsLatest
        }

        if lhs.sourceKind != rhs.sourceKind {
            return lhs.sourceKind == .terminal
        }

        if lhs.confidence != rhs.confidence {
            return lhs.confidence == .high
        }

        let appComparison = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
        if appComparison != .orderedSame {
            return appComparison == .orderedAscending
        }

        return lhs.workspaceLabel.localizedCaseInsensitiveCompare(rhs.workspaceLabel) == .orderedAscending
    }
}

private func suggestedTargetMatchKey(_ target: CaptureSuggestedTarget) -> String {
    target.canonicalIdentityKey
}

private func suggestedTargetSnapshotMatchKey(_ snapshot: SuggestedTargetWindowSnapshot) -> String {
    if SupportedSuggestedApps.app(for: snapshot.bundleIdentifier)?.sourceKind == .terminal {
        return [
            snapshot.bundleIdentifier,
            snapshot.tty
                ?? snapshot.sessionIdentifier
                ?? snapshot.windowTitle
                ?? snapshot.appName,
        ]
        .joined(separator: "|")
    }

    return [
        snapshot.bundleIdentifier,
        snapshot.sessionIdentifier ?? "",
        snapshot.windowTitle ?? "",
    ]
    .joined(separator: "|")
}

func runCommand(
    executableURL: URL,
    arguments: [String]
) -> String? {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        return nil
    }

    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        return nil
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
          !output.isEmpty else {
        return nil
    }

    return output
}
