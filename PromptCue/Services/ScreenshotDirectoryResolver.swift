import Foundation

enum ScreenshotDirectoryResolver {
    private static let bookmarkDataKey = "com.promptcue.preferredScreenshotDirectoryBookmarkData"
    private static let lastKnownPathKey = "com.promptcue.preferredScreenshotDirectoryLastKnownPath"
    private static let legacyPreferredPathKey = "preferredScreenshotDirectoryPath"
    private static let onboardingHandledKey = "com.promptcue.preferredScreenshotDirectoryOnboardingHandled"
    static let authorizedDirectoryDidChangeNotification = Notification.Name(
        "com.promptcue.preferredScreenshotDirectoryDidChange"
    )

    static func bootstrapPreferredDirectoryIfNeeded(defaults: UserDefaults = .standard) {

        guard defaults.string(forKey: lastKnownPathKey) == nil else {
            return
        }

        guard let legacyPath = defaults.string(forKey: legacyPreferredPathKey), !legacyPath.isEmpty else {
            return
        }

        defaults.set(legacyPath, forKey: lastKnownPathKey)
        defaults.set(true, forKey: onboardingHandledKey)
    }

    static func accessState(defaults: UserDefaults = .standard) -> ScreenshotFolderAccessState {
        if let bookmarkData = bookmarkData(defaults: defaults) {
            switch resolvedBookmarkState(from: bookmarkData, defaults: defaults) {
            case .connected(let url):
                return .connected(url: url, displayPath: displayPath(for: url))
            case .needsReconnect(let url):
                if let url {
                    return .needsReconnect(lastKnownDisplayPath: displayPath(for: url))
                }
            }
        }

        if let lastKnownURL = lastKnownDirectoryURL(defaults: defaults)
            ?? legacyPreferredDirectoryURL(defaults: defaults) {
            return .needsReconnect(lastKnownDisplayPath: displayPath(for: lastKnownURL))
        }

        return .notConfigured
    }

    static func saveAuthorizedDirectory(_ url: URL, defaults: UserDefaults = .standard) throws {
        let standardizedURL = url.standardizedFileURL
        guard directoryExists(at: standardizedURL) else {
            throw ScreenshotDirectoryResolverError.invalidDirectory
        }

        let bookmarkData = try standardizedURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        defaults.set(bookmarkData, forKey: bookmarkDataKey)
        defaults.set(standardizedURL.path, forKey: lastKnownPathKey)
        defaults.set(true, forKey: onboardingHandledKey)
        defaults.removeObject(forKey: legacyPreferredPathKey)
        postAuthorizedDirectoryDidChange()
    }

    static func clearAuthorizedDirectory(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bookmarkDataKey)
        defaults.removeObject(forKey: lastKnownPathKey)
        defaults.removeObject(forKey: legacyPreferredPathKey)
        postAuthorizedDirectoryDidChange()
    }

    static func withAuthorizedDirectory<Result>(_ body: (URL) throws -> Result) rethrows -> Result? {
        guard let authorizedDirectoryURL = authorizedDirectoryURL() else {
            return nil
        }

        let startedAccess = authorizedDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                authorizedDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        return try body(authorizedDirectoryURL)
    }

    static func withAccessIfNeeded<Result>(
        to fileURL: URL,
        _ body: (URL) throws -> Result
    ) rethrows -> Result {
        let standardizedFileURL = fileURL.standardizedFileURL

        guard let authorizedDirectoryURL = authorizedDirectoryURL(),
              contains(fileURL: standardizedFileURL, inDirectory: authorizedDirectoryURL)
        else {
            return try body(standardizedFileURL)
        }

        let startedAccess = authorizedDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                authorizedDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        return try body(standardizedFileURL)
    }

    static var shouldPresentOnboarding: Bool {
        shouldPresentOnboarding(using: .standard)
    }

    static func shouldPresentOnboarding(using defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: onboardingHandledKey) else {
            return false
        }

        guard !hasPersistedDirectoryHistory(defaults: defaults) else {
            return false
        }

        guard case .notConfigured = accessState(defaults: defaults) else {
            return false
        }

        return true
    }

    static func markOnboardingHandled(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: onboardingHandledKey)
    }

    static func selectionSeedURL() -> URL? {
        authorizedDirectoryURL()
            ?? lastKnownDirectoryURL()
            ?? legacyPreferredDirectoryURL()
            ?? resolvedSystemScreenshotDirectory()
    }

    static var preferredDirectoryDisplayPath: String {
        switch accessState() {
        case .connected(_, let displayPath):
            return displayPath
        case .needsReconnect(let lastKnownDisplayPath):
            return lastKnownDisplayPath
        case .notConfigured:
            return suggestedDirectoryDisplayPath ?? "Not selected"
        }
    }

    static var suggestedDirectoryDisplayPath: String? {
        resolvedSystemScreenshotDirectory().map(displayPath(for:))
    }

    static func resolvedSystemScreenshotDirectory() -> URL? {
        let defaults = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")

        if let rawLocation = defaults?["location"] as? String, !rawLocation.isEmpty {
            let expanded = NSString(string: rawLocation).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }

        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    }

    static func authorizedDirectoryURLForMonitoring() -> URL? {
        authorizedDirectoryURL()
    }

    private static func authorizedDirectoryURL(defaults: UserDefaults = .standard) -> URL? {
        guard let bookmarkData = bookmarkData(defaults: defaults) else {
            return nil
        }

        switch resolvedBookmarkState(from: bookmarkData, defaults: defaults) {
        case .connected(let url):
            return url
        case .needsReconnect:
            return nil
        }
    }

    private static func bookmarkData(defaults: UserDefaults = .standard) -> Data? {
        let data = defaults.data(forKey: bookmarkDataKey)
        return data?.isEmpty == false ? data : nil
    }

    private static func lastKnownDirectoryURL(defaults: UserDefaults = .standard) -> URL? {
        directoryURL(fromStoredPath: defaults.string(forKey: lastKnownPathKey))
    }

    private static func legacyPreferredDirectoryURL(defaults: UserDefaults = .standard) -> URL? {
        directoryURL(fromStoredPath: defaults.string(forKey: legacyPreferredPathKey))
    }

    private static func directoryURL(fromStoredPath path: String?) -> URL? {
        guard let path, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func resolvedBookmarkState(
        from bookmarkData: Data,
        defaults: UserDefaults = .standard
    ) -> ResolvedBookmarkState {
        var isStale = false

        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL

            guard directoryExists(at: resolvedURL) else {
                return .needsReconnect(resolvedURL)
            }

            if isStale {
                if refreshBookmarkIfPossible(for: resolvedURL, defaults: defaults) {
                    return .connected(resolvedURL)
                }

                return .needsReconnect(resolvedURL)
            }

            return .connected(resolvedURL)
        } catch {
            return .needsReconnect(
                lastKnownDirectoryURL(defaults: defaults) ?? legacyPreferredDirectoryURL(defaults: defaults)
            )
        }
    }

    private static func refreshBookmarkIfPossible(for url: URL, defaults: UserDefaults = .standard) -> Bool {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }

        guard let freshData = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return false
        }

        defaults.set(freshData, forKey: bookmarkDataKey)
        defaults.set(url.standardizedFileURL.path, forKey: lastKnownPathKey)
        postAuthorizedDirectoryDidChange()
        return true
    }

    private static func hasPersistedDirectoryHistory(defaults: UserDefaults) -> Bool {
        bookmarkData(defaults: defaults) != nil
            || lastKnownDirectoryURL(defaults: defaults) != nil
            || legacyPreferredDirectoryURL(defaults: defaults) != nil
    }

    private static func postAuthorizedDirectoryDidChange() {
        NotificationCenter.default.post(name: authorizedDirectoryDidChangeNotification, object: nil)
    }

    private static func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private static func displayPath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let homeDirectory = NSHomeDirectory()
        if path.hasPrefix(homeDirectory) {
            return path.replacingOccurrences(of: homeDirectory, with: "~")
        }

        return path
    }

    private static func contains(fileURL: URL, inDirectory directoryURL: URL) -> Bool {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL
        let directoryPath = standardizedDirectoryURL.path
        let filePath = fileURL.standardizedFileURL.path

        return filePath == directoryPath || filePath.hasPrefix(directoryPath + "/")
    }
}

private enum ResolvedBookmarkState {
    case connected(URL)
    case needsReconnect(URL?)
}

enum ScreenshotDirectoryResolverError: LocalizedError {
    case invalidDirectory

    var errorDescription: String? {
        switch self {
        case .invalidDirectory:
            return "Select a folder that still exists."
        }
    }
}
