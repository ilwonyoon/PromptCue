import AppKit
import CoreGraphics

// Backtick stack-card overflow policy.
// Owns long-card measurement and interaction thresholds so stack-card views can
// stay lightweight and use a Stack-specific scan band instead of inheriting
// Capture editor sizing.
enum StackCardOverflowPolicy {
    struct Metrics: Equatable {
        let totalLineCount: Int
        let fullTextHeight: CGFloat
        let restingVisibleTextHeight: CGFloat
        let expandedVisibleTextHeight: CGFloat
        let hiddenCollapsedCopiedLineCount: Int
        let hiddenRestingLineCount: Int
        let hiddenExpandedLineCount: Int

        var overflowsAtRest: Bool {
            hiddenRestingLineCount > 0
        }

        var overflowsExpanded: Bool {
            hiddenExpandedLineCount > 0
        }

        var isLong: Bool {
            overflowsAtRest
        }
    }

    static let collapsedCopiedSummaryLineLimit = 2
    static let collapsedCopiedLineLimit = collapsedCopiedSummaryLineLimit
    static let restingVisibleLineLimit = 8
    static let expandedMaxVisibleHeight = CGFloat.greatestFiniteMagnitude
    static let restingOverflowToleranceLines = 1
    static let textBottomBreathingRoom: CGFloat = PrimitiveTokens.Space.sm
    static let affordanceTopSpacing: CGFloat = PrimitiveTokens.Space.xs
    static let actionColumnReservedWidth = PrimitiveTokens.Space.xl + PrimitiveTokens.Space.sm
    static let cardTextWidth =
        PanelMetrics.stackCardColumnWidth
        - (PrimitiveTokens.Size.notificationCardPadding * 2)
        - actionColumnReservedWidth
    static let collapsedCopiedSummaryTextWidth =
        PanelMetrics.stackCardColumnWidth
        - (PrimitiveTokens.Size.notificationCardPadding * 2)

    private static let bodyFont = NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body)
    private static let bodyLineSpacing = PrimitiveTokens.Space.xxxs
    private static let bodyBaseLineHeight = ceil(NSLayoutManager().defaultLineHeight(for: bodyFont))
    private static let bodyLineAdvance = bodyBaseLineHeight + bodyLineSpacing
    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        style.lineSpacing = bodyLineSpacing
        return style
    }()
    private static let metricsCache: NSCache<NSString, MetricsBox> = {
        let cache = NSCache<NSString, MetricsBox>()
        cache.countLimit = 512
        return cache
    }()

    static func metrics(
        for text: String,
        availableWidth: CGFloat = cardTextWidth
    ) -> Metrics {
        let normalizedWidth = max(availableWidth, 1)
        let cacheKey = metricsCacheKey(text: text, width: normalizedWidth)
        if let cached = metricsCache.object(forKey: cacheKey) {
            return cached.metrics
        }

        let metrics = uncachedMetrics(for: text, availableWidth: normalizedWidth)
        metricsCache.setObject(MetricsBox(metrics), forKey: cacheKey, cost: text.utf16.count)
        return metrics
    }

    static func metrics(
        for text: String,
        cacheIdentity: UUID,
        layoutVariant: Int = 0,
        availableWidth: CGFloat = cardTextWidth
    ) -> Metrics {
        let normalizedWidth = max(availableWidth, 1)
        let cacheKey = identityCacheKey(
            cacheIdentity: cacheIdentity,
            layoutVariant: layoutVariant,
            styleSignature: 0,
            width: normalizedWidth
        )
        if let cached = metricsCache.object(forKey: cacheKey) {
            return cached.metrics
        }

        let metrics = uncachedMetrics(for: text, availableWidth: normalizedWidth)
        metricsCache.setObject(MetricsBox(metrics), forKey: cacheKey, cost: text.utf16.count)
        return metrics
    }

    static func metrics(
        for measurementText: NSAttributedString,
        cacheIdentity: UUID,
        layoutVariant: Int = 0,
        styleSignature: UInt64 = 0,
        availableWidth: CGFloat = cardTextWidth
    ) -> Metrics {
        let normalizedWidth = max(availableWidth, 1)
        let cacheKey = identityCacheKey(
            cacheIdentity: cacheIdentity,
            layoutVariant: layoutVariant,
            styleSignature: styleSignature,
            width: normalizedWidth
        )
        if let cached = metricsCache.object(forKey: cacheKey) {
            return cached.metrics
        }

        let metrics = uncachedMetrics(for: measurementText, availableWidth: normalizedWidth)
        metricsCache.setObject(MetricsBox(metrics), forKey: cacheKey, cost: measurementText.length)
        return metrics
    }

    static func uncachedMetrics(
        for text: String,
        availableWidth: CGFloat = cardTextWidth
    ) -> Metrics {
        let normalizedWidth = max(availableWidth, 1)
        let measuredHeight = measureTextHeight(
            measurementText: NSAttributedString(
                string: text,
                attributes: [
                    .font: bodyFont,
                    .paragraphStyle: paragraphStyle,
                ]
            ),
            width: normalizedWidth
        )
        return metrics(
            measuredHeight: measuredHeight,
            availableWidth: normalizedWidth
        )
    }

    static func uncachedMetrics(
        for measurementText: NSAttributedString,
        availableWidth: CGFloat = cardTextWidth
    ) -> Metrics {
        let normalizedWidth = max(availableWidth, 1)
        let measuredHeight = measureTextHeight(measurementText: measurementText, width: normalizedWidth)
        return metrics(
            measuredHeight: measuredHeight,
            availableWidth: normalizedWidth
        )
    }

    private static func metrics(
        measuredHeight: CGFloat,
        availableWidth: CGFloat
    ) -> Metrics {
        let totalLineCount = max(1, Int(ceil((measuredHeight + bodyLineSpacing) / bodyLineAdvance)))

        let restingVisibleLineCount = min(totalLineCount, restingVisibleLineLimit)
        let restingVisibleTextHeight = min(
            measuredHeight,
            visibleTextHeight(forLineCount: restingVisibleLineCount)
        )
        let rawHiddenRestingLineCount = max(0, totalLineCount - restingVisibleLineCount)
        let hiddenRestingLineCount: Int
        let resolvedRestingVisibleTextHeight: CGFloat
        if rawHiddenRestingLineCount <= restingOverflowToleranceLines {
            hiddenRestingLineCount = 0
            resolvedRestingVisibleTextHeight = measuredHeight
        } else {
            hiddenRestingLineCount = rawHiddenRestingLineCount
            resolvedRestingVisibleTextHeight = restingVisibleTextHeight
        }

        let collapsedCopiedVisibleLineCount = min(totalLineCount, collapsedCopiedSummaryLineLimit)

        let expandedVisibleTextHeight = min(measuredHeight, expandedMaxVisibleHeight)
        let expandedVisibleLineCount: Int
        if expandedMaxVisibleHeight == .greatestFiniteMagnitude {
            expandedVisibleLineCount = totalLineCount
        } else {
            expandedVisibleLineCount = min(totalLineCount, maxVisibleLineCount(in: expandedVisibleTextHeight))
        }

        return Metrics(
            totalLineCount: totalLineCount,
            fullTextHeight: measuredHeight,
            restingVisibleTextHeight: resolvedRestingVisibleTextHeight + textBottomBreathingRoom,
            expandedVisibleTextHeight: expandedVisibleTextHeight + textBottomBreathingRoom,
            hiddenCollapsedCopiedLineCount: max(0, totalLineCount - collapsedCopiedVisibleLineCount),
            hiddenRestingLineCount: hiddenRestingLineCount,
            hiddenExpandedLineCount: max(0, totalLineCount - expandedVisibleLineCount)
        )
    }

    static func resetCacheForTesting() {
        metricsCache.removeAllObjects()
    }

    static func overflowLabel(hiddenLineCount: Int) -> String {
        "+\(hiddenLineCount) lines"
    }

    static func collapseLabel() -> String {
        "Show less"
    }

    private static func maxVisibleLineCount(in height: CGFloat) -> Int {
        max(1, Int(floor((height + bodyLineSpacing) / bodyLineAdvance)))
    }

    private static func visibleTextHeight(forLineCount lineCount: Int) -> CGFloat {
        guard lineCount > 1 else {
            return bodyBaseLineHeight
        }

        return bodyBaseLineHeight + CGFloat(lineCount - 1) * bodyLineAdvance
    }

    private static func measureTextHeight(measurementText: NSAttributedString, width: CGFloat) -> CGFloat {
        let textStorage = NSTextStorage(attributedString: measurementText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let measuredHeight = layoutManager.usedRect(for: textContainer).height
        return max(bodyBaseLineHeight, ceil(measuredHeight))
    }

    private static func metricsCacheKey(text: String, width: CGFloat) -> NSString {
        let normalizedWidth = Int((width * 10).rounded())
        return NSString(string: "\(normalizedWidth):\(text.utf16.count):\(stableTextHash(text))")
    }

    private static func identityCacheKey(
        cacheIdentity: UUID,
        layoutVariant: Int,
        styleSignature: UInt64,
        width: CGFloat
    ) -> NSString {
        let normalizedWidth = Int((width * 10).rounded())
        return NSString(
            string: "\(normalizedWidth):\(cacheIdentity.uuidString):\(layoutVariant):\(styleSignature)"
        )
    }

    private static func stableTextHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

private final class MetricsBox: NSObject {
    let metrics: StackCardOverflowPolicy.Metrics

    init(_ metrics: StackCardOverflowPolicy.Metrics) {
        self.metrics = metrics
    }
}
