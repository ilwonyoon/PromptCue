import Foundation

enum ScreenshotDirectoryResolver {
    private static let preferredPathKey = "preferredScreenshotDirectoryPath"

    static func bootstrapPreferredDirectoryIfNeeded() {
        let defaults = UserDefaults.standard

        if let existing = defaults.string(forKey: preferredPathKey), !existing.isEmpty {
            return
        }

        guard let resolvedPath = resolvedSystemScreenshotDirectory()?.standardizedFileURL.path else {
            return
        }

        defaults.set(resolvedPath, forKey: preferredPathKey)
    }

    static func preferredDirectoryURL() -> URL? {
        let defaults = UserDefaults.standard

        if let path = defaults.string(forKey: preferredPathKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }

        return resolvedSystemScreenshotDirectory()
    }

    static func resolvedSystemScreenshotDirectory() -> URL? {
        let defaults = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")

        if let rawLocation = defaults?["location"] as? String, !rawLocation.isEmpty {
            let expanded = NSString(string: rawLocation).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        }

        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    }

    static var preferredDirectoryDisplayPath: String {
        let path = preferredDirectoryURL()?.path
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
            ?? "~/Desktop"

        let homeDirectory = NSHomeDirectory()
        if path.hasPrefix(homeDirectory) {
            return path.replacingOccurrences(of: homeDirectory, with: "~")
        }

        return path
    }
}
