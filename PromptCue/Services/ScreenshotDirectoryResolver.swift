import Foundation

enum ScreenshotDirectoryResolver {
    private static let bookmarkDataKey = "com.promptcue.preferredScreenshotDirectoryBookmarkData"
    private static let lastKnownPathKey = "com.promptcue.preferredScreenshotDirectoryLastKnownPath"
    private static let legacyPreferredPathKey = "preferredScreenshotDirectoryPath"
    private static let onboardingHandledKey = "com.promptcue.preferredScreenshotDirectoryOnboardingHandled"
    static let authorizedDirectoryDidChangeNotification = Notification.Name(
        "com.promptcue.preferredScreenshotDirectoryDidChange"
    )

    static func bootstrapPreferredDirectoryIfNeeded() {
        let defaults = UserDefaults.standard

        guard defaults.string(forKey: lastKnownPathKey) == nil else {
            return
        }

        guard let legacyPath = defaults.string(forKey: legacyPreferredPathKey), !legacyPath.isEmpty else {
            return
        }

        defaults.set(legacyPath, forKey: lastKnownPathKey)
    }

    static func accessState() -> ScreenshotFolderAccessState {
        if let bookmarkData = bookmarkData() {
            switch resolvedBookmarkState(from: bookmarkData) {
            case .connected(let url):
                return .connected(url: url, displayPath: displayPath(for: url))
            case .needsReconnect(let url):
                if let url {
                    return .needsReconnect(lastKnownDisplayPath: displayPath(for: url))
                }
            }
        }

        if let lastKnownURL = lastKnownDirectoryURL() ?? legacyPreferredDirectoryURL() {
            return .needsReconnect(lastKnownDisplayPath: displayPath(for: lastKnownURL))
        }

        return .notConfigured
    }

    static func saveAuthorizedDirectory(_ url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        guard directoryExists(at: standardizedURL) else {
            throw ScreenshotDirectoryResolverError.invalidDirectory
        }

        let bookmarkData = try standardizedURL.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let defaults = UserDefaults.standard
        defaults.set(bookmarkData, forKey: bookmarkDataKey)
        defaults.set(standardizedURL.path, forKey: lastKnownPathKey)
        defaults.removeObject(forKey: legacyPreferredPathKey)
        postAuthorizedDirectoryDidChange()
    }

    static func clearAuthorizedDirectory() {
        let defaults = UserDefaults.standard
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
        guard case .notConfigured = accessState() else {
            return false
        }

        return !UserDefaults.standard.bool(forKey: onboardingHandledKey)
    }

    static func markOnboardingHandled() {
        UserDefaults.standard.set(true, forKey: onboardingHandledKey)
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

    private static func authorizedDirectoryURL() -> URL? {
        guard let bookmarkData = bookmarkData() else {
            return nil
        }

        switch resolvedBookmarkState(from: bookmarkData) {
        case .connected(let url):
            return url
        case .needsReconnect:
            return nil
        }
    }

    private static func bookmarkData() -> Data? {
        let data = UserDefaults.standard.data(forKey: bookmarkDataKey)
        return data?.isEmpty == false ? data : nil
    }

    private static func lastKnownDirectoryURL() -> URL? {
        directoryURL(fromStoredPath: UserDefaults.standard.string(forKey: lastKnownPathKey))
    }

    private static func legacyPreferredDirectoryURL() -> URL? {
        directoryURL(fromStoredPath: UserDefaults.standard.string(forKey: legacyPreferredPathKey))
    }

    private static func directoryURL(fromStoredPath path: String?) -> URL? {
        guard let path, !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func resolvedBookmarkState(from bookmarkData: Data) -> ResolvedBookmarkState {
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
                if refreshBookmarkIfPossible(for: resolvedURL) {
                    return .connected(resolvedURL)
                }

                return .needsReconnect(resolvedURL)
            }

            return .connected(resolvedURL)
        } catch {
            return .needsReconnect(lastKnownDirectoryURL() ?? legacyPreferredDirectoryURL())
        }
    }

    private static func refreshBookmarkIfPossible(for url: URL) -> Bool {
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

        let defaults = UserDefaults.standard
        defaults.set(freshData, forKey: bookmarkDataKey)
        defaults.set(url.standardizedFileURL.path, forKey: lastKnownPathKey)
        postAuthorizedDirectoryDidChange()
        return true
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
