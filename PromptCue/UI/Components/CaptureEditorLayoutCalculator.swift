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
        let verticalInsetHeight = AppUIConstants.captureEditorVerticalInset * 2
        let bottomBreathingRoom = AppUIConstants.captureEditorBottomBreathingRoom

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
        scrollerReservationWidth: CGFloat,
        measureHeight: (CGFloat) -> CGFloat
    ) -> CaptureEditorMetrics {
        let safeViewportWidth = max(viewportWidth, 1)
        let unconstrainedHeight = max(minimumLineHeight, ceil(measureHeight(safeViewportWidth)))
        let initiallyScrollable = unconstrainedHeight > maxContentHeight + 0.5

        if initiallyScrollable {
            let finalWidth = max(safeViewportWidth - max(scrollerReservationWidth, 0), 1)
            let finalContentHeight = max(minimumLineHeight, ceil(measureHeight(finalWidth)))

            return CaptureEditorMetrics(
                contentHeight: finalContentHeight,
                visibleHeight: min(finalContentHeight, maxContentHeight),
                isScrollable: finalContentHeight > maxContentHeight + 0.5,
                layoutWidth: finalWidth
            )
        }

        return CaptureEditorMetrics(
            contentHeight: unconstrainedHeight,
            visibleHeight: min(unconstrainedHeight, maxContentHeight),
            isScrollable: false,
            layoutWidth: safeViewportWidth
        )
    }

    static func estimatedMetrics(
        text: String,
        viewportWidth: CGFloat,
        maxContentHeight: CGFloat,
        minimumLineHeight: CGFloat,
        scrollerReservationWidth: CGFloat,
        font: NSFont,
        lineHeight: CGFloat
    ) -> CaptureEditorMetrics {
        guard !text.isEmpty else {
            return CaptureEditorMetrics(
                contentHeight: minimumLineHeight + (AppUIConstants.captureEditorVerticalInset * 2) + AppUIConstants.captureEditorBottomBreathingRoom,
                visibleHeight: minimumLineHeight + (AppUIConstants.captureEditorVerticalInset * 2) + AppUIConstants.captureEditorBottomBreathingRoom,
                isScrollable: false,
                layoutWidth: viewportWidth
            )
        }

        return metrics(
            viewportWidth: viewportWidth,
            maxContentHeight: maxContentHeight,
            minimumLineHeight: minimumLineHeight,
            scrollerReservationWidth: scrollerReservationWidth
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
