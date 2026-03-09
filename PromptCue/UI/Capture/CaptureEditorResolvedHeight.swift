import CoreGraphics

struct CaptureEditorResolvedHeight: Equatable {
    var contentHeight: CGFloat
    var visibleHeight: CGFloat
    var preferredHeight: CGFloat
    var isScrollable: Bool
    var layoutWidth: CGFloat

    static let empty = CaptureEditorResolvedHeight(
        contentHeight: AppUIConstants.captureEditorMinimumVisibleHeight,
        visibleHeight: AppUIConstants.captureEditorMinimumVisibleHeight,
        preferredHeight: AppUIConstants.captureEditorMinimumVisibleHeight,
        isScrollable: false,
        layoutWidth: 0
    )

    var metrics: CaptureEditorMetrics {
        CaptureEditorMetrics(
            contentHeight: contentHeight,
            visibleHeight: visibleHeight,
            isScrollable: isScrollable,
            layoutWidth: layoutWidth
        )
    }
}
