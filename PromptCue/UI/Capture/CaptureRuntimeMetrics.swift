import CoreGraphics
import Foundation

enum CaptureRuntimeMetrics {
    static let textLineHeight: CGFloat = 22

    static let editorVerticalInset: CGFloat = 12
    static let editorBottomBreathingRoom: CGFloat = 8
    static let editorMaxHeight: CGFloat = 176

    static let editorViewportWidth: CGFloat =
        PanelMetrics.captureSurfaceWidth - (PanelMetrics.captureSurfaceInnerPadding * 2)

    static let editorMinimumVisibleHeight: CGFloat =
        textLineHeight + (editorVerticalInset * 2) + editorBottomBreathingRoom

    static let scrollIndicatorWidth: CGFloat = 2.5
    static let scrollIndicatorMinHeight: CGFloat = 24
    static let scrollIndicatorTrailingInset: CGFloat = 2
    static let scrollIndicatorVerticalInset: CGFloat = 4
    static let scrollIndicatorShowAlpha: CGFloat = 0.56
    static let scrollIndicatorFadeDelay: TimeInterval = 0.10
    static let scrollIndicatorFadeDuration: TimeInterval = 0.10
}
