import Foundation

enum AttachmentStoreError: Error {
    case importSourceMissing(URL)
    case importFailed(source: URL, destination: URL, underlying: Error)
    case removeFailed(URL, underlying: Error)
    case listFailed(URL, underlying: Error)
}

protocol AttachmentStoring {
    var baseDirectoryURL: URL { get }

    func importScreenshot(from sourceURL: URL, ownerID: UUID) throws -> URL
    func removeManagedFile(at fileURL: URL) throws
    func pruneUnreferencedManagedFiles(referencedFileURLs: Set<URL>) throws
    func isManagedFile(_ fileURL: URL) -> Bool
}

struct AttachmentStore: AttachmentStoring {
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
                .appendingPathComponent("PromptCue", isDirectory: true)
                .appendingPathComponent("Attachments", isDirectory: true)
                .standardizedFileURL
        }
    }

    func importScreenshot(from sourceURL: URL, ownerID: UUID) throws -> URL {
        let standardizedSourceURL = sourceURL.standardizedFileURL
        guard fileManager.fileExists(atPath: standardizedSourceURL.path) else {
            throw AttachmentStoreError.importSourceMissing(standardizedSourceURL)
        }

        try ensureBaseDirectoryExists()

        let destinationURL = destinationURL(
            ownerID: ownerID,
            pathExtension: standardizedSourceURL.pathExtension
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try removeManagedFile(at: destinationURL)
        }

        do {
            try fileManager.copyItem(at: standardizedSourceURL, to: destinationURL)
            return destinationURL.standardizedFileURL
        } catch {
            throw AttachmentStoreError.importFailed(
                source: standardizedSourceURL,
                destination: destinationURL,
                underlying: error
            )
        }
    }

    func removeManagedFile(at fileURL: URL) throws {
        let standardizedFileURL = fileURL.standardizedFileURL
        guard isManagedFile(standardizedFileURL) else {
            return
        }

        guard fileManager.fileExists(atPath: standardizedFileURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: standardizedFileURL)
        } catch {
            throw AttachmentStoreError.removeFailed(standardizedFileURL, underlying: error)
        }
    }

    func pruneUnreferencedManagedFiles(referencedFileURLs: Set<URL>) throws {
        let standardizedReferences = Set(referencedFileURLs.map(\.standardizedFileURL))

        guard fileManager.fileExists(atPath: baseDirectoryURL.path) else {
            return
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: baseDirectoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw AttachmentStoreError.listFailed(baseDirectoryURL, underlying: error)
        }

        for candidateURL in contents {
            guard isManagedFile(candidateURL) else {
                continue
            }

            let resourceValues = try? candidateURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else {
                continue
            }

            let standardizedCandidateURL = candidateURL.standardizedFileURL
            guard !standardizedReferences.contains(standardizedCandidateURL) else {
                continue
            }

            try removeManagedFile(at: standardizedCandidateURL)
        }
    }

    func isManagedFile(_ fileURL: URL) -> Bool {
        let resolvedBaseURL = baseDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedFileURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let basePath = resolvedBaseURL.path
        let filePath = resolvedFileURL.path

        return filePath == basePath || filePath.hasPrefix(basePath + "/")
    }

    private func ensureBaseDirectoryExists() throws {
        try fileManager.createDirectory(
            at: baseDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func destinationURL(ownerID: UUID, pathExtension: String) -> URL {
        let filename = ownerID.uuidString.lowercased()
        let destinationURL = baseDirectoryURL.appendingPathComponent(filename, isDirectory: false)

        guard !pathExtension.isEmpty else {
            return destinationURL
        }

        return destinationURL.appendingPathExtension(pathExtension.lowercased())
    }
}
