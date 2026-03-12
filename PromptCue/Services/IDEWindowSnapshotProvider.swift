import AppKit
import Foundation

func enumerateIDEWindowSnapshots() -> [SuggestedTargetWindowSnapshot] {
    let runningApplications = NSWorkspace.shared.runningApplications
    let supportedIDEs = runningApplications.compactMap { application -> (NSRunningApplication, SupportedSuggestedApp)? in
        guard let bundleIdentifier = application.bundleIdentifier,
              let supportedApp = SupportedSuggestedApps.app(for: bundleIdentifier),
              supportedApp.sourceKind == .ide else {
            return nil
        }

        return (application, supportedApp)
    }

    return supportedIDEs.flatMap { application, supportedApp in
        let titles = windowTitles(forProcessIdentifier: application.processIdentifier)
        let uniqueTitles = Array(NSOrderedSet(array: titles)) as? [String] ?? titles

        if uniqueTitles.isEmpty {
            return [
                SuggestedTargetWindowSnapshot(
                    appName: supportedApp.appName,
                    bundleIdentifier: supportedApp.bundleIdentifier,
                    windowTitle: nil,
                    sessionIdentifier: "\(application.processIdentifier)",
                    tty: nil
                )
            ]
        }

        return uniqueTitles.enumerated().map { index, title in
            SuggestedTargetWindowSnapshot(
                appName: supportedApp.appName,
                bundleIdentifier: supportedApp.bundleIdentifier,
                windowTitle: title,
                sessionIdentifier: "\(application.processIdentifier):\(index)",
                tty: nil
            )
        }
    }
}

func windowTitles(forProcessIdentifier processIdentifier: pid_t) -> [String] {
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

        guard let title = window[kCGWindowName as String] as? String else {
            return nil
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}
