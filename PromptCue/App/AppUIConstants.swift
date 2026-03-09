import Foundation
import CoreGraphics

// Transitional compatibility facade.
// New code should prefer PanelMetrics, CaptureRuntimeMetrics, and AppTiming to keep ownership explicit.
enum AppUIConstants {
    static let stackPanelWidth: CGFloat = PanelMetrics.stackPanelWidth
    static let stackCardColumnWidth: CGFloat = PanelMetrics.stackCardColumnWidth
    static let capturePanelWidth: CGFloat = PanelMetrics.capturePanelWidth
    static let captureSurfaceWidth: CGFloat = PanelMetrics.captureSurfaceWidth
    static let captureSurfaceInnerPadding: CGFloat = PanelMetrics.captureSurfaceInnerPadding
    static let captureSurfaceTopPadding: CGFloat = PanelMetrics.captureSurfaceTopPadding
    static let captureSurfaceBottomPadding: CGFloat = PanelMetrics.captureSurfaceBottomPadding
    static let capturePanelOuterPadding: CGFloat = PanelMetrics.capturePanelOuterPadding
    static let capturePanelVerticalSpacing: CGFloat = PanelMetrics.capturePanelVerticalSpacing
    static let settingsPanelWidth: CGFloat = PanelMetrics.settingsPanelWidth
    static let settingsPanelHeight: CGFloat = PanelMetrics.settingsPanelHeight
    static let settingsExportTailEditorMinHeight: CGFloat = PanelMetrics.settingsExportTailEditorMinHeight
    static let settingsExportTailEditorMaxHeight: CGFloat = PanelMetrics.settingsExportTailEditorMaxHeight
    static let horizontalMargin: CGFloat = PanelMetrics.horizontalMargin
    static let verticalMargin: CGFloat = PanelMetrics.verticalMargin

    static let captureEditorViewportWidth: CGFloat = CaptureRuntimeMetrics.editorViewportWidth
    static let captureEditorVerticalInset: CGFloat = CaptureRuntimeMetrics.editorVerticalInset
    static let captureEditorBottomBreathingRoom: CGFloat = CaptureRuntimeMetrics.editorBottomBreathingRoom
    static let captureEditorMinimumVisibleHeight: CGFloat = CaptureRuntimeMetrics.editorMinimumVisibleHeight
    static let captureTextLineHeight: CGFloat = CaptureRuntimeMetrics.textLineHeight
    static let captureEditorMaxHeight: CGFloat = CaptureRuntimeMetrics.editorMaxHeight
    static let captureScrollIndicatorWidth: CGFloat = CaptureRuntimeMetrics.scrollIndicatorWidth
    static let captureScrollIndicatorMinHeight: CGFloat = CaptureRuntimeMetrics.scrollIndicatorMinHeight
    static let captureScrollIndicatorTrailingInset: CGFloat = CaptureRuntimeMetrics.scrollIndicatorTrailingInset
    static let captureScrollIndicatorVerticalInset: CGFloat = CaptureRuntimeMetrics.scrollIndicatorVerticalInset
    static let captureScrollIndicatorShowAlpha: CGFloat = CaptureRuntimeMetrics.scrollIndicatorShowAlpha
    static let captureScrollIndicatorFadeDelay: TimeInterval = CaptureRuntimeMetrics.scrollIndicatorFadeDelay
    static let captureScrollIndicatorFadeDuration: TimeInterval = CaptureRuntimeMetrics.scrollIndicatorFadeDuration

    static let recentScreenshotMaxAge: TimeInterval = AppTiming.recentScreenshotMaxAge
    static let recentScreenshotPlaceholderGrace: TimeInterval = AppTiming.recentScreenshotPlaceholderGrace
    static let recentScreenshotSubmitResolveTimeout: TimeInterval = AppTiming.recentScreenshotSubmitResolveTimeout
    static let captureSubmissionFlushTimeout: TimeInterval = AppTiming.captureSubmissionFlushTimeout
}
