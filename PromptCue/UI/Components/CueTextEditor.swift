import AppKit
import Carbon
import SwiftUI

struct CueTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onHeightChange: (CGFloat) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CueEditorContainerView {
        let container = CueEditorContainerView()
        let textView = container.textView

        textView.delegate = context.coordinator
        textView.string = text
        container.onHeightChange = onHeightChange
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        configure(textView)

        DispatchQueue.main.async {
            container.window?.makeFirstResponder(textView)
        }

        return container
    }

    func updateNSView(_ container: CueEditorContainerView, context: Context) {
        let textView = container.textView

        if textView.string != text {
            textView.string = text
            container.layoutSubtreeIfNeeded()
        }

        container.onHeightChange = onHeightChange
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        configure(textView)

        if !context.coordinator.didFocus, container.window != nil {
            context.coordinator.didFocus = true
            DispatchQueue.main.async {
                container.window?.makeFirstResponder(textView)
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
        textView.textContainerInset = .zero
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.alignment = .left
        textView.defaultParagraphStyle = paragraphStyle
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]

        if let textStorage = textView.textStorage, textStorage.length > 0 {
            textStorage.beginEditing()
            textStorage.addAttributes([
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ], range: NSRange(location: 0, length: textStorage.length))
            textStorage.endEditing()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CueTextEditor
        var didFocus = false

        init(_ parent: CueTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            if parent.text != textView.string {
                parent.text = textView.string
            }

            (textView.enclosingScrollView?.superview as? CueEditorContainerView)?.updateMeasuredHeight()
        }
    }
}

final class CueEditorContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = WrappingCueTextView()
    var onHeightChange: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        updateMeasuredHeight()
    }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        scrollView.documentView = textView
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
    }

    func updateMeasuredHeight() {
        let width = scrollView.contentSize.width
        guard width > 0 else {
            return
        }

        if let textContainer = textView.textContainer {
            textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
        let contentHeight = max(PrimitiveTokens.LineHeight.capture, ceil(usedHeight))
        let height = contentHeight

        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        onHeightChange?(contentHeight)
    }
}

final class WrappingCueTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
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
}
