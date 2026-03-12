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

private struct SupportedSuggestedApp: Equatable {
    let appName: String
    let bundleIdentifier: String
    let sourceKind: CaptureSuggestedTargetSourceKind
}

private enum SupportedSuggestedApps {
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
        refreshAvailableSuggestedTargets()
    }

    private func updateLatestTarget(from application: NSRunningApplication) {
        guard let bundleIdentifier = application.bundleIdentifier,
              let supportedApp = supportedApp(for: bundleIdentifier) else {
            return
        }

        let capturedAt = Date()
        let window = frontWindowSnapshot(forProcessIdentifier: application.processIdentifier)
        latestTarget = CaptureSuggestedTarget(
            appName: supportedApp.appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: window?.title,
            sessionIdentifier: window?.identifier,
            capturedAt: capturedAt,
            confidence: .low
        )
        onChange?()
    }

    private func supportedApp(for bundleIdentifier: String) -> SupportedSuggestedApp? {
        SupportedSuggestedApps.app(for: bundleIdentifier)
    }

    private func frontWindowSnapshot(forProcessIdentifier processIdentifier: pid_t) -> SafeWindowSnapshot? {
        windowSnapshots(forProcessIdentifier: processIdentifier).first
    }
}

private struct SuggestedTargetWindowSnapshot {
    let appName: String
    let bundleIdentifier: String
    let windowTitle: String?
    let sessionIdentifier: String?
}

private struct SafeWindowSnapshot {
    let identifier: String
    let title: String?
}

private func buildSafeSuggestedTarget(
    appName: String,
    bundleIdentifier: String,
    fallbackWindowTitle: String?,
    sessionIdentifier: String?,
    capturedAt: Date
) -> CaptureSuggestedTarget? {
    return CaptureSuggestedTarget(
        appName: appName,
        bundleIdentifier: bundleIdentifier,
        windowTitle: fallbackWindowTitle,
        sessionIdentifier: sessionIdentifier,
        capturedAt: capturedAt,
        confidence: .low
    )
}

private func enumerateAvailableSuggestedTargets(
    latestTarget: CaptureSuggestedTarget?
) -> [CaptureSuggestedTarget] {
    let capturedAt = Date()
    let snapshots = enumerateSafeWindowSnapshots()
    var deduplicatedSnapshots: [String: SuggestedTargetWindowSnapshot] = [:]

    for snapshot in snapshots {
        deduplicatedSnapshots[suggestedTargetSnapshotMatchKey(snapshot)] = snapshot
    }

    let targets = deduplicatedSnapshots.values.compactMap { snapshot in
        buildSafeSuggestedTarget(
            appName: snapshot.appName,
            bundleIdentifier: snapshot.bundleIdentifier,
            fallbackWindowTitle: snapshot.windowTitle,
            sessionIdentifier: snapshot.sessionIdentifier,
            capturedAt: capturedAt
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

private func enumerateSafeWindowSnapshots() -> [SuggestedTargetWindowSnapshot] {
    let runningApplications = NSWorkspace.shared.runningApplications
    let supportedApplications = runningApplications.compactMap { application -> (NSRunningApplication, SupportedSuggestedApp)? in
        guard let bundleIdentifier = application.bundleIdentifier,
              let supportedApp = SupportedSuggestedApps.app(for: bundleIdentifier) else {
            return nil
        }

        return (application, supportedApp)
    }

    return supportedApplications.flatMap { application, supportedApp in
        let windows = windowSnapshots(forProcessIdentifier: application.processIdentifier)
        let uniqueWindowIdentifiers = Array(NSOrderedSet(array: windows.map(\.identifier))) as? [String]
            ?? windows.map(\.identifier)

        if uniqueWindowIdentifiers.isEmpty {
            return [
                SuggestedTargetWindowSnapshot(
                    appName: supportedApp.appName,
                    bundleIdentifier: supportedApp.bundleIdentifier,
                    windowTitle: nil,
                    sessionIdentifier: "\(application.processIdentifier)"
                )
            ]
        }

        let windowsByIdentifier = Dictionary(uniqueKeysWithValues: windows.map { ($0.identifier, $0) })
        return uniqueWindowIdentifiers.compactMap { identifier in
            guard let window = windowsByIdentifier[identifier] else {
                return nil
            }

            return SuggestedTargetWindowSnapshot(
                appName: supportedApp.appName,
                bundleIdentifier: supportedApp.bundleIdentifier,
                windowTitle: window.title,
                sessionIdentifier: window.identifier
            )
        }
    }
}

private func suggestedTargetMatchKey(_ target: CaptureSuggestedTarget) -> String {
    target.canonicalIdentityKey
}

private func suggestedTargetSnapshotMatchKey(_ snapshot: SuggestedTargetWindowSnapshot) -> String {
    return [
        snapshot.bundleIdentifier,
        snapshot.sessionIdentifier ?? "",
        snapshot.windowTitle ?? "",
    ]
    .joined(separator: "|")
}

private func windowSnapshots(forProcessIdentifier processIdentifier: pid_t) -> [SafeWindowSnapshot] {
    guard let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return []
    }

    return windowList.compactMap { window in
        guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
              ownerPID == processIdentifier else {
            return nil
        }

        if let layer = window[kCGWindowLayer as String] as? Int,
           layer != 0 {
            return nil
        }

        guard let windowNumber = window[kCGWindowNumber as String] as? NSNumber else {
            return nil
        }

        let trimmedTitle = (window[kCGWindowName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SafeWindowSnapshot(
            identifier: windowNumber.stringValue,
            title: trimmedTitle?.isEmpty == true ? nil : trimmedTitle
        )
    }
}
