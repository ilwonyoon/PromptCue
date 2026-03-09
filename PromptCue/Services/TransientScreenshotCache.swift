import Foundation

enum TransientScreenshotCacheError: Error {
    case sourceMissing(URL)
    case cacheFailed(source: URL, destination: URL, underlying: Error)
    case removalFailed(URL, underlying: Error)
}

protocol TransientScreenshotCaching {
    var baseDirectoryURL: URL { get }

    func cacheScreenshot(from sourceURL: URL, sessionID: UUID) throws -> URL
    func cacheImageData(_ data: Data, sessionID: UUID, pathExtension: String) throws -> URL
    func removeCachedFile(at fileURL: URL) throws
    func clear() throws
}

struct TransientScreenshotCache: TransientScreenshotCaching {
    let baseDirectoryURL: URL
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager

        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL.standardizedFileURL
        } else {
            let applicationSupportURL = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

            self.baseDirectoryURL = applicationSupportURL
                .appendingPathComponent("Prompt Cue", isDirectory: true)
                .appendingPathComponent("TransientScreenshots", isDirectory: true)
                .standardizedFileURL
        }
    }

    func cacheScreenshot(from sourceURL: URL, sessionID: UUID) throws -> URL {
        let standardizedSourceURL = sourceURL.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedSourceURL.path) else {
            throw TransientScreenshotCacheError.sourceMissing(standardizedSourceURL)
        }

        try ensureBaseDirectoryExists()

        let destinationURL = destinationURL(
            sessionID: sessionID,
            pathExtension: standardizedSourceURL.pathExtension
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try removeCachedFile(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: standardizedSourceURL, to: destinationURL)
            return destinationURL.standardizedFileURL
        } catch {
            throw TransientScreenshotCacheError.cacheFailed(
                source: standardizedSourceURL,
                destination: destinationURL,
                underlying: error
            )
        }
    }

    func cacheImageData(_ data: Data, sessionID: UUID, pathExtension: String) throws -> URL {
        try ensureBaseDirectoryExists()

        let destinationURL = destinationURL(
            sessionID: sessionID,
            pathExtension: pathExtension
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try removeCachedFile(at: destinationURL)
        }

        do {
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL.standardizedFileURL
        } catch {
            throw TransientScreenshotCacheError.cacheFailed(
                source: baseDirectoryURL,
                destination: destinationURL,
                underlying: error
            )
        }
    }

    func removeCachedFile(at fileURL: URL) throws {
        let standardizedFileURL = fileURL.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedFileURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: standardizedFileURL)
        } catch {
            throw TransientScreenshotCacheError.removalFailed(standardizedFileURL, underlying: error)
        }
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: baseDirectoryURL.path) else {
            return
        }

        let contents = try fileManager.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for itemURL in contents {
            try removeCachedFile(at: itemURL)
        }
    }

    private func ensureBaseDirectoryExists() throws {
        try fileManager.createDirectory(
            at: baseDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func destinationURL(sessionID: UUID, pathExtension: String) -> URL {
        let filename = sessionID.uuidString.lowercased()
        let destinationURL = baseDirectoryURL.appendingPathComponent(filename, isDirectory: false)

        guard !pathExtension.isEmpty else {
            return destinationURL
        }

        return destinationURL.appendingPathExtension(pathExtension.lowercased())
    }
}
