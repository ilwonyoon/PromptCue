import AppKit
import Foundation
import PromptCueCore

enum ClipboardFormatter {
    static func string(for cards: [CaptureCard]) -> String {
        ExportFormatter.string(for: cards)
    }

    static func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
