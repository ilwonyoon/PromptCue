import AppKit
import CoreGraphics

enum CaptureEditorLayoutCalculator {
    static func measuredTextHeight(
        text: String,
        width: CGFloat,
        minimumLineHeight: CGFloat,
        font: NSFont,
        lineHeight: CGFloat
    ) -> CGFloat {
        let verticalInsetHeight = CaptureRuntimeMetrics.editorVerticalInset * 2
        let bottomBreathingRoom = CaptureRuntimeMetrics.editorBottomBreathingRoom

        guard !text.isEmpty else {
            return minimumLineHeight + verticalInsetHeight + bottomBreathingRoom
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
            ]
        )

        let boundingRect = attributedString.boundingRect(
            with: NSSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return max(minimumLineHeight, ceil(boundingRect.height)) + verticalInsetHeight + bottomBreathingRoom
    }

    static func metrics(
        viewportWidth: CGFloat,
        maxContentHeight: CGFloat,
        minimumLineHeight: CGFloat,
        measureHeight: (CGFloat) -> CGFloat
    ) -> CaptureEditorMetrics {
        let safeViewportWidth = max(viewportWidth, 1)
        let unconstrainedHeight = max(minimumLineHeight, ceil(measureHeight(safeViewportWidth)))
        let isScrollable = unconstrainedHeight > maxContentHeight + 0.5

        return CaptureEditorMetrics(
            contentHeight: unconstrainedHeight,
            visibleHeight: min(unconstrainedHeight, maxContentHeight),
            isScrollable: isScrollable,
            layoutWidth: safeViewportWidth
        )
    }

    static func estimatedMetrics(
        text: String,
        viewportWidth: CGFloat,
        maxContentHeight: CGFloat,
        minimumLineHeight: CGFloat,
        font: NSFont,
        lineHeight: CGFloat
    ) -> CaptureEditorMetrics {
        guard !text.isEmpty else {
            return CaptureEditorMetrics(
                contentHeight: minimumLineHeight + (CaptureRuntimeMetrics.editorVerticalInset * 2) + CaptureRuntimeMetrics.editorBottomBreathingRoom,
                visibleHeight: minimumLineHeight + (CaptureRuntimeMetrics.editorVerticalInset * 2) + CaptureRuntimeMetrics.editorBottomBreathingRoom,
                isScrollable: false,
                layoutWidth: viewportWidth
            )
        }

        return metrics(
            viewportWidth: viewportWidth,
            maxContentHeight: maxContentHeight,
            minimumLineHeight: minimumLineHeight
        ) { width in
            measuredTextHeight(
                text: text,
                width: width,
                minimumLineHeight: minimumLineHeight,
                font: font,
                lineHeight: lineHeight
            )
        }
    }
}
