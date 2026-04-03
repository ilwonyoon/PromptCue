import AppKit
import Foundation
import PromptCueCore

enum ClipboardFormatter {
    static let debugIncludeAttachmentPathsDefaultsKey = "DebugIncludeAttachmentPathsInClipboardText"
    private static let attachmentPathSingularLabel = "Attached image path:"
    private static let attachmentPathPluralLabel = "Attached image paths:"

    static func string(for cards: [CaptureCard]) -> String {
        string(for: cards, suffix: PromptExportTailPreferences.load().exportSuffix)
    }

    static func rawString(for card: CaptureCard) -> String {
        card.text
    }

    static func string(for cards: [CaptureCard], suffix: ExportSuffix) -> String {
        let screenshotURLs = cards.map { ManagedScreenshotAccess.readableURL(for: $0) }
        return clipboardTextValue(for: cards, screenshotURLs: screenshotURLs, suffix: suffix)
    }

    static func copyToPasteboard(cards: [CaptureCard]) {
        let suffix = PromptExportTailPreferences.load().exportSuffix
        let screenshotURLs = cards.map { ManagedScreenshotAccess.readableURL(for: $0) }
        let textValue = clipboardTextValue(for: cards, screenshotURLs: screenshotURLs, suffix: suffix)
        copyStringToPasteboard(textValue)
    }

    static func copyRawToPasteboard(card: CaptureCard) {
        copyStringToPasteboard(rawString(for: card))
    }

    private static func copyStringToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(value, forType: .string)
    }

    static func clipboardImageData(for screenshotURL: URL) -> (tiff: Data?, png: Data?) {
        let tiffData: Data?
        if let image = NSImage(contentsOf: screenshotURL),
           let tiff = image.tiffRepresentation {
            tiffData = tiff
        } else {
            tiffData = nil
        }

        let pngData: Data?
        if screenshotURL.pathExtension.lowercased() == "png",
           let sourcePNGData = try? Data(contentsOf: screenshotURL) {
            pngData = sourcePNGData
        } else if let tiffData,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let encodedPNG = bitmap.representation(using: .png, properties: [:]) {
            pngData = encodedPNG
        } else {
            pngData = nil
        }

        return (tiffData, pngData)
    }

    private static func clipboardTextValue(
        for cards: [CaptureCard],
        screenshotURLs: [URL?],
        suffix: ExportSuffix
    ) -> String {
        let defaultClipboardText = ExportFormatter.clipboardString(for: cards, suffix: suffix)
        guard includesAttachmentPathsInClipboardText else {
            return defaultClipboardText
        }

        let attachmentPaths = screenshotURLs.compactMap { $0?.path }
        guard attachmentPaths.isEmpty == false else {
            return defaultClipboardText
        }

        let bodyText = ExportFormatter.clipboardString(for: cards, suffix: .off)
        let label = attachmentPaths.count == 1 ? attachmentPathSingularLabel : attachmentPathPluralLabel
        let attachmentSection = ([label] + attachmentPaths).joined(separator: "\n")
        let sections = [attachmentSection, bodyText, normalizedSuffixText(from: suffix)]
            .compactMap { $0 }
            .filter { $0.isEmpty == false }

        return sections.joined(separator: "\n\n")
    }

    private static var includesAttachmentPathsInClipboardText: Bool {
        #if DEBUG
        if let value = UserDefaults.standard.object(forKey: debugIncludeAttachmentPathsDefaultsKey) as? Bool {
            return value
        }
        return true
        #else
        return true
        #endif
    }

    private static func normalizedSuffixText(from suffix: ExportSuffix) -> String? {
        guard let rawValue = suffix.rawValue else {
            return nil
        }

        let normalizedLineEndings = rawValue
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedLineEndings.isEmpty == false else {
            return nil
        }

        return normalizedLineEndings
    }
}
