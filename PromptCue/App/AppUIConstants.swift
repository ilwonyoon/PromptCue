import Foundation
import CoreGraphics

enum AppUIConstants {
    static let stackPanelWidth: CGFloat = 392
    static let capturePanelWidth: CGFloat = 448
    static let captureSurfaceWidth: CGFloat = 400
    static let captureSurfaceInnerPadding: CGFloat = 24
    static let captureSurfaceTopPadding: CGFloat = 12
    static let captureSurfaceBottomPadding: CGFloat = 4
    static let captureEditorViewportWidth: CGFloat = captureSurfaceWidth - (captureSurfaceInnerPadding * 2)
    static let captureEditorVerticalInset: CGFloat = 12
    static let captureEditorBottomBreathingRoom: CGFloat = 8
    static let captureEditorMinimumVisibleHeight: CGFloat = captureTextLineHeight + (captureEditorVerticalInset * 2) + captureEditorBottomBreathingRoom
    static let capturePanelOuterPadding: CGFloat = 24
    static let capturePanelVerticalSpacing: CGFloat = 12
    static let captureTextLineHeight: CGFloat = 22
    static let captureEditorMaxHeight: CGFloat = 176
    static let settingsPanelWidth: CGFloat = 420
    static let settingsPanelHeight: CGFloat = 360
    static let horizontalMargin: CGFloat = 24
    static let verticalMargin: CGFloat = 24
    static let recentScreenshotMaxAge: TimeInterval = 30
    static let recentScreenshotPlaceholderGrace: TimeInterval = 1.5
    static let recentScreenshotSubmitResolveTimeout: TimeInterval = 0.8
    static let captureSubmissionFlushTimeout: TimeInterval = 1.0
}
