import AppKit
import Carbon
import SwiftUI

struct CueTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let maxContentHeight: CGFloat
    let onMetricsChange: (CaptureEditorMetrics) -> Void
    let onResolvedPreferredHeightChange: (CGFloat) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    init(
        text: Binding<String>,
        placeholder: String,
        maxContentHeight: CGFloat,
        onMetricsChange: @escaping (CaptureEditorMetrics) -> Void,
        onResolvedPreferredHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.maxContentHeight = maxContentHeight
        self.onMetricsChange = onMetricsChange
        self.onResolvedPreferredHeightChange = onResolvedPreferredHeightChange
        self.onSubmit = onSubmit
        self.onCancel = onCancel
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
    var onPaste: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch Int(event.keyCode) {
        case Int(kVK_Return), Int(kVK_ANSI_KeypadEnter):
            if modifiers.contains(.shift) {
                super.keyDown(with: event)
            } else {
                onSubmit?()
            }
        case Int(kVK_Escape):
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }

    override func paste(_ sender: Any?) {
        super.paste(sender)
        onPaste?()
    }
}

final class ClickThroughTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
