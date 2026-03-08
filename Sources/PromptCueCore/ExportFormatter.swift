import Foundation

public enum ExportFormatter {
    public static func string(for cards: [CaptureCard]) -> String {
        cards
            .map { "\u{2022} \($0.text)" }
            .joined(separator: "\n")
    }
}
