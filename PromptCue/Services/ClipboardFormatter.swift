import AppKit
import Foundation
import PromptCueCore

enum ClipboardFormatter {
    static func string(for cards: [CaptureCard]) -> String {
        string(for: cards, suffix: PromptExportTailPreferences.load().exportSuffix)
    }

    static func string(for cards: [CaptureCard], suffix: ExportSuffix) -> String {
        ExportFormatter.clipboardString(for: cards, suffix: suffix)
    }

    static func copyToPasteboard(cards: [CaptureCard]) {
        let value = string(for: cards)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let items = pasteboardItems(for: cards, textPayload: value)
        if !items.isEmpty, pasteboard.writeObjects(items) {
            return
        }

        pasteboard.setString(value, forType: .string)
    }

    private static func pasteboardItems(for cards: [CaptureCard], textPayload: String) -> [NSPasteboardItem] {
        var items: [NSPasteboardItem] = []

        let textItem = NSPasteboardItem()
        textItem.setString(textPayload, forType: .string)
        items.append(textItem)

        for card in cards {
            guard let screenshotURL = ManagedScreenshotAccess.readableURL(for: card) else {
                continue
            }

            let imageItem = NSPasteboardItem()
            imageItem.setString(screenshotURL.absoluteString, forType: .fileURL)

            if let image = NSImage(contentsOf: screenshotURL),
               let tiffData = image.tiffRepresentation {
                imageItem.setData(tiffData, forType: .tiff)
            }

            if screenshotURL.pathExtension.lowercased() == "png",
               let pngData = try? Data(contentsOf: screenshotURL) {
                imageItem.setData(pngData, forType: .png)
            }

            items.append(imageItem)
        }

        return items
    }
}
