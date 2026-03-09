import Foundation
import CoreGraphics

enum AppUIConstants {
    static let stackPanelWidth: CGFloat = 392
    static let capturePanelWidth: CGFloat = 448
    static let captureSurfaceWidth: CGFloat = 400
    static let captureSurfaceInnerPadding: CGFloat = 24
    static let capturePanelOuterPadding: CGFloat = 24
    static let capturePanelVerticalSpacing: CGFloat = 12
    static let captureChooserPanelVerticalSpacing: CGFloat = 12
    static let captureChooserPanelOuterPadding: CGFloat = 12
    static let captureChooserSurfaceHorizontalPadding: CGFloat = 0
    static let captureChooserSurfaceVerticalPadding: CGFloat = captureSurfaceInnerPadding
    static let captureSelectorControlWidth: CGFloat = captureSurfaceWidth - (captureSurfaceInnerPadding * 2)
    static let captureChooserPromptLineHeight: CGFloat = 16
    static let captureChooserPromptVerticalPadding: CGFloat = 6
    static let captureChooserPromptBottomSpacing: CGFloat = 12
    static let captureChooserSectionSpacing: CGFloat = 6
    static let captureChooserRowHeight: CGFloat = 34
    static let captureChooserRowSpacing: CGFloat = 4
    static let captureChooserMaxVisibleRows: Int = 4
    static let captureChooserPeekRowFraction: CGFloat = 0.25
    static let captureTextLineHeight: CGFloat = 22
    static let captureDebugLineHeight: CGFloat = 18
    static let captureEditorMaxHeight: CGFloat = 176
    static let settingsPanelWidth: CGFloat = 420
    static let settingsPanelHeight: CGFloat = 360
    static let horizontalMargin: CGFloat = 24
    static let verticalMargin: CGFloat = 24
    static let recentScreenshotMaxAge: TimeInterval = 30
    static let recentScreenshotPlaceholderGrace: TimeInterval = 1.5
    static let suggestedTargetFreshness: TimeInterval = 60

    static func captureChooserVisibleRowUnits(for totalRows: Int) -> CGFloat {
        let clampedRows = max(totalRows, 1)

        if clampedRows <= 4 {
            return CGFloat(clampedRows)
        }

        return CGFloat(captureChooserMaxVisibleRows) + captureChooserPeekRowFraction
    }
}
