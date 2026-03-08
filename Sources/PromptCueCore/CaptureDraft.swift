import Foundation

public struct CaptureDraft: Equatable, Sendable {
    public var text: String
    public var recentScreenshot: ScreenshotAttachment?

    public init(text: String = "", recentScreenshot: ScreenshotAttachment? = nil) {
        self.text = text
        self.recentScreenshot = recentScreenshot
    }

    public var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || recentScreenshot != nil
    }
}
