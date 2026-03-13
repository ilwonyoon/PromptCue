import AppKit
import Carbon
import SwiftUI

enum CueEditorCommand {
    case moveSelectionUp
    case moveSelectionDown
    case completeSelection(CueEditorCompletionTrigger)
    case cancelSelection
}

enum CueEditorCompletionTrigger {
    case tab
    case returnKey
}

struct CueInlineCompletionPresentation {
    let suffix: String
    let caretUTF16Offset: Int
    let attributes: [NSAttributedString.Key: Any]
}

struct CueTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxContentHeight: CGFloat
    let onMetricsChange: (CaptureEditorMetrics) -> Void
    let onResolvedPreferredHeightChange: (CGFloat) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onCommand: (CueEditorCommand) -> Bool

    init(
        text: Binding<String>,
        placeholder: String,
        maxContentHeight: CGFloat,
        onMetricsChange: @escaping (CaptureEditorMetrics) -> Void,
        onResolvedPreferredHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onCommand: @escaping (CueEditorCommand) -> Bool = { _ in false }
    ) {
        _text = text
        self.placeholder = placeholder
        self.maxContentHeight = maxContentHeight
        self.onMetricsChange = onMetricsChange
        self.onResolvedPreferredHeightChange = onResolvedPreferredHeightChange
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onCommand = onCommand
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CueEditorContainerView {
        let container = CueEditorContainerView()
        let textView = container.textView

        textView.delegate = context.coordinator
        container.maxMeasuredHeight = maxContentHeight
        container.onMetricsChange = onMetricsChange
        container.onResolvedPreferredHeightChange = onResolvedPreferredHeightChange
        container.placeholderText = placeholder
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        textView.onCommand = onCommand
        textView.onPaste = { [weak container] in
            container?.requestScrollToSelectionOnNextMeasurement()
        }
        configure(textView)
        container.applyExternalText(text, forceScrollToSelection: !text.isEmpty, forceMeasure: true)

        DispatchQueue.main.async {
            container.window?.makeFirstResponder(textView)
        }

        return container
    }

    func updateNSView(_ container: CueEditorContainerView, context: Context) {
        let textView = container.textView

        container.maxMeasuredHeight = maxContentHeight
        container.onMetricsChange = onMetricsChange
        container.onResolvedPreferredHeightChange = onResolvedPreferredHeightChange
        container.placeholderText = placeholder
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        textView.onCommand = onCommand
        textView.onPaste = { [weak container] in
            container?.requestScrollToSelectionOnNextMeasurement()
        }

        if textView.string != text {
            container.applyExternalText(text, forceScrollToSelection: !text.isEmpty, forceMeasure: true)
        }

        requestFocusIfNeeded(in: container)
    }

    private func requestFocusIfNeeded(in container: CueEditorContainerView) {
        DispatchQueue.main.async {
            guard let window = container.window else {
                return
            }

            guard NSApp.isActive, window.isKeyWindow else {
                return
            }

            if window.firstResponder !== container.textView {
                window.makeFirstResponder(container.textView)
            }
        }
    }

    private func configure(_ textView: WrappingCueTextView) {
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        let font = NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.capture)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = PrimitiveTokens.LineHeight.capture
        paragraphStyle.maximumLineHeight = PrimitiveTokens.LineHeight.capture
        textView.font = font
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: CaptureRuntimeMetrics.editorVerticalInset)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.alignment = .left
        textView.defaultParagraphStyle = paragraphStyle
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CueTextEditor

        init(_ parent: CueTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let container = textView.enclosingScrollView?.superview as? CueEditorContainerView else {
                return
            }

            container.updateMeasuredMetrics(forceMeasure: true, emitMetrics: false)

            if parent.text != textView.string {
                parent.text = textView.string
            }

            container.flushPendingMetricsIfNeeded()
        }
    }
}

typealias CueEditorContainerView = CaptureEditorRuntimeHostView
typealias CaptureEditorHostView = CaptureEditorRuntimeHostView

final class WrappingCueTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCommand: ((CueEditorCommand) -> Bool)?
    var onPaste: (() -> Void)?
    var inlineCompletionPresentation: CueInlineCompletionPresentation? {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawInlineCompletionIfNeeded(in: dirtyRect)
    }

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch Int(event.keyCode) {
        case Int(kVK_UpArrow):
            if onCommand?(.moveSelectionUp) == true {
                return
            }
            super.keyDown(with: event)
        case Int(kVK_DownArrow):
            if onCommand?(.moveSelectionDown) == true {
                return
            }
            super.keyDown(with: event)
        case Int(kVK_Tab):
            if onCommand?(.completeSelection(.tab)) == true {
                return
            }
            super.keyDown(with: event)
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            if onCommand?(.completeSelection(.returnKey)) == true {
                return
            }
            if modifiers.contains(.shift) {
                super.keyDown(with: event)
            } else {
                onSubmit?()
            }
        case Int(kVK_Escape):
            if onCommand?(.cancelSelection) == true {
                return
            }
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }

    override func paste(_ sender: Any?) {
        super.paste(sender)
        onPaste?()
    }

    #if DEBUG
    var debugIsInlineCompletionVisible: Bool {
        guard let inlineCompletionPresentation else {
            return false
        }

        return inlineCompletionDrawingRect(for: inlineCompletionPresentation) != nil
    }
    #endif

    private func drawInlineCompletionIfNeeded(in dirtyRect: NSRect) {
        guard let inlineCompletionPresentation,
              let drawingRect = inlineCompletionDrawingRect(for: inlineCompletionPresentation),
              drawingRect.intersects(dirtyRect) else {
            return
        }

        NSAttributedString(
            string: inlineCompletionPresentation.suffix,
            attributes: inlineCompletionPresentation.attributes
        ).draw(
            with: drawingRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }

    private func inlineCompletionDrawingRect(
        for presentation: CueInlineCompletionPresentation
    ) -> NSRect? {
        guard let textContainer,
              let layoutManager else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)

        let textLength = string.utf16.count
        let caretLocation = max(0, min(presentation.caretUTF16Offset, textLength))
        let containerOrigin = textContainerOrigin

        if textLength == 0 || layoutManager.numberOfGlyphs == 0 {
            let extraLineRect = layoutManager.extraLineFragmentRect
            let resolvedHeight = max(extraLineRect.height, inlineCompletionFont.ascender - inlineCompletionFont.descender)
            let resolvedRect = extraLineRect.isEmpty
                ? NSRect(x: 0, y: 0, width: 0, height: resolvedHeight)
                : extraLineRect
            return drawingRect(
                anchorX: containerOrigin.x + resolvedRect.minX,
                lineOriginY: containerOrigin.y + resolvedRect.minY,
                lineHeight: resolvedRect.height
            )
        }

        let nsText = string as NSString
        if caretLocation >= textLength {
            return inlineCompletionRectAtDocumentEnd(
                text: nsText,
                containerOrigin: containerOrigin,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: caretLocation)
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        let lineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )

        return drawingRect(
            anchorX: containerOrigin.x + glyphRect.minX,
            lineOriginY: containerOrigin.y + lineRect.minY,
            lineHeight: lineRect.height
        )
    }

    private func inlineCompletionRectAtDocumentEnd(
        text: NSString,
        containerOrigin: NSPoint,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else {
            return nil
        }

        let lastGlyphIndex = glyphCount - 1
        let lastGlyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: lastGlyphIndex, length: 1),
            in: textContainer
        )
        let lineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: lastGlyphIndex,
            effectiveRange: nil
        )

        let endsWithNewline: Bool
        if text.length > 0,
           let lastScalar = UnicodeScalar(text.character(at: text.length - 1)) {
            endsWithNewline = CharacterSet.newlines.contains(lastScalar)
        } else {
            endsWithNewline = false
        }

        if endsWithNewline {
            let extraLineRect = layoutManager.extraLineFragmentRect
            let resolvedRect = extraLineRect.isEmpty
                ? NSRect(
                    x: lineRect.minX,
                    y: lineRect.maxY,
                    width: 0,
                    height: max(lineRect.height, inlineCompletionFont.ascender - inlineCompletionFont.descender)
                )
                : extraLineRect

            return drawingRect(
                anchorX: containerOrigin.x + resolvedRect.minX,
                lineOriginY: containerOrigin.y + resolvedRect.minY,
                lineHeight: resolvedRect.height
            )
        }

        return drawingRect(
            anchorX: containerOrigin.x + lastGlyphRect.maxX,
            lineOriginY: containerOrigin.y + lineRect.minY,
            lineHeight: lineRect.height
        )
    }

    private func drawingRect(
        anchorX: CGFloat,
        lineOriginY: CGFloat,
        lineHeight: CGFloat
    ) -> NSRect? {
        let availableWidth = max(bounds.width - anchorX, 0)
        guard availableWidth > 0.5 else {
            return nil
        }

        return NSRect(
            x: anchorX,
            y: lineOriginY,
            width: availableWidth,
            height: max(lineHeight, 1)
        )
    }

    private var inlineCompletionFont: NSFont {
        inlineCompletionPresentation?.attributes[.font] as? NSFont
            ?? font
            ?? NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.capture)
    }
}

final class ClickThroughTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
