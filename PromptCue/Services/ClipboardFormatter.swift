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
        let value = string(for: cards)
        let pasteboard = NSPasteboard.general

        var types: [NSPasteboard.PasteboardType] = [.string]
        var imageData: (tiff: Data?, png: Data?) = (nil, nil)

        if let card = cards.first,
           let screenshotURL = ManagedScreenshotAccess.readableURL(for: card) {
            if let image = NSImage(contentsOf: screenshotURL),
               let tiff = image.tiffRepresentation {
                imageData.tiff = tiff
                types.append(.tiff)
            }
            if screenshotURL.pathExtension.lowercased() == "png",
               let png = try? Data(contentsOf: screenshotURL) {
                imageData.png = png
                types.append(.png)
            }
        }

        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(value, forType: .string)
        if let tiff = imageData.tiff {
            pasteboard.setData(tiff, forType: .tiff)
        }
        if let png = imageData.png {
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
