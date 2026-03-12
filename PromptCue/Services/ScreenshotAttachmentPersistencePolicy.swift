import Foundation

struct PreparedManagedScreenshotPath: Equatable {
    let storedPath: String?
    let importedManagedFileURL: URL?
}

enum ScreenshotAttachmentPersistencePolicy {
    static func prepareForPersistence(
        storedPath: String?,
        ownerID: UUID,
        attachmentStore: any AttachmentStoring
    ) throws -> PreparedManagedScreenshotPath {
        guard let normalizedStoredPath = normalizedStoredPath(storedPath) else {
            return PreparedManagedScreenshotPath(
                storedPath: nil,
                importedManagedFileURL: nil
            )
        }

        let screenshotURL = URL(fileURLWithPath: normalizedStoredPath).standardizedFileURL
        if attachmentStore.isManagedFile(screenshotURL) {
            return PreparedManagedScreenshotPath(
                storedPath: screenshotURL.path,
                importedManagedFileURL: nil
            )
        }

        let importedURL = try ScreenshotDirectoryResolver.withAccessIfNeeded(to: screenshotURL) { scopedURL in
            try attachmentStore.importScreenshot(from: scopedURL, ownerID: ownerID)
        }.standardizedFileURL

        return PreparedManagedScreenshotPath(
            storedPath: importedURL.path,
            importedManagedFileURL: importedURL
        )
    }

    static func managedStoredPath(
        from storedPath: String?,
        attachmentStore: any AttachmentStoring
    ) -> String? {
        guard let normalizedStoredPath = normalizedStoredPath(storedPath) else {
            return nil
        }

        let screenshotURL = URL(fileURLWithPath: normalizedStoredPath).standardizedFileURL
        guard attachmentStore.isManagedFile(screenshotURL) else {
            return nil
        }

        return screenshotURL.path
    }

    private static func normalizedStoredPath(_ storedPath: String?) -> String? {
        guard let trimmedStoredPath = storedPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedStoredPath.isEmpty
        else {
            return nil
        }

        return trimmedStoredPath
    }
}
