import AppKit
import Foundation
import PromptCueCore

enum ClipboardFormatter {
    static func string(for cards: [CaptureCard]) -> String {
        string(for: cards, suffix: PromptExportTailPreferences.load().exportSuffix)
    }

    static func rawString(for card: CaptureCard) -> String {
        card.text
    }

    static func string(for cards: [CaptureCard], suffix: ExportSuffix) -> String {
        ExportFormatter.clipboardString(for: cards, suffix: suffix)
    }

    static func copyToPasteboard(cards: [CaptureCard]) {
        let suffix = PromptExportTailPreferences.load().exportSuffix
        let pasteboard = NSPasteboard.general

        var types: [NSPasteboard.PasteboardType] = [.string]
        var firstImageData: (tiff: Data?, png: Data?) = (nil, nil)

        let cardsWithURLs = cards.map { card in
            (card: card, screenshotURL: ManagedScreenshotAccess.readableURL(for: card))
        }
        let attachmentFlags = cardsWithURLs.map { $0.screenshotURL != nil }

        // Attach the first available image to the pasteboard
        if let firstImageEntry = cardsWithURLs.first(where: { $0.screenshotURL != nil }),
           let screenshotURL = firstImageEntry.screenshotURL {
            if let image = NSImage(contentsOf: screenshotURL),
               let tiff = image.tiffRepresentation {
                firstImageData.tiff = tiff
                types.append(.tiff)
            }
            if screenshotURL.pathExtension.lowercased() == "png",
               let png = try? Data(contentsOf: screenshotURL) {
                firstImageData.png = png
                types.append(.png)
            }
        }

        let textValue = ExportFormatter.clipboardString(
            for: cards,
            suffix: suffix,
            attachmentFlags: attachmentFlags
        )

        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(textValue, forType: .string)
        if let tiff = firstImageData.tiff {
            pasteboard.setData(tiff, forType: .tiff)
        }
        if let png = firstImageData.png {
            pasteboard.setData(png, forType: .png)
        }
    }

    static func copyRawToPasteboard(card: CaptureCard) {
        copyStringToPasteboard(rawString(for: card))
    }

    private static func copyStringToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(value, forType: .string)
    }
}
