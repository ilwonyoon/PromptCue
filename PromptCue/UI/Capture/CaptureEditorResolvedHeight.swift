import CoreGraphics

struct CaptureEditorResolvedHeight: Equatable {
    var contentHeight: CGFloat
    var visibleHeight: CGFloat
    var preferredHeight: CGFloat
    var isScrollable: Bool
    var layoutWidth: CGFloat

    static let empty = CaptureEditorResolvedHeight(
        contentHeight: CaptureRuntimeMetrics.editorMinimumVisibleHeight,
        visibleHeight: CaptureRuntimeMetrics.editorMinimumVisibleHeight,
        preferredHeight: CaptureRuntimeMetrics.editorMinimumVisibleHeight,
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
