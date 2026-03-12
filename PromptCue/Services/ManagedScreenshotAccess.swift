import Foundation
import PromptCueCore

enum ManagedScreenshotAccess {
    private static let fileManager = FileManager.default
    private static let attachmentStore = AttachmentStore()

    static func readableURL(for screenshotPath: String?) -> URL? {
        guard let screenshotPath, !screenshotPath.isEmpty else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: screenshotPath).standardizedFileURL
        guard attachmentStore.isManagedFile(fileURL) else {
            return nil
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return fileURL
    }

    static func readableURL(for card: CaptureCard) -> URL? {
        readableURL(for: card.screenshotPath)
    }
}
