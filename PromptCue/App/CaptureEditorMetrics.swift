import CoreGraphics

struct CaptureEditorMetrics: Equatable {
    var contentHeight: CGFloat
    var visibleHeight: CGFloat
    var isScrollable: Bool
    var layoutWidth: CGFloat

    static let empty = CaptureEditorMetrics(
        contentHeight: CaptureRuntimeMetrics.editorMinimumVisibleHeight,
        visibleHeight: CaptureRuntimeMetrics.editorMinimumVisibleHeight,
        isScrollable: false,
        layoutWidth: 0
    )
}
