import AppKit
import SwiftUI

struct SettingsMultilineTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SettingsMultilineTextEditorContainerView {
        let container = SettingsMultilineTextEditorContainerView()
        container.textView.delegate = context.coordinator
        container.applyExternalText(text)
        return container
    }

    func updateNSView(_ container: SettingsMultilineTextEditorContainerView, context: Context) {
        if container.textView.string != text {
            container.applyExternalText(text)
        } else {
            container.recalculateDocumentHeight()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: SettingsMultilineTextEditor

        init(_ parent: SettingsMultilineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let container = textView.enclosingScrollView?.superview as? SettingsMultilineTextEditorContainerView else {
                return
            }

            if parent.text != textView.string {
                parent.text = textView.string
            }

            container.recalculateDocumentHeight()
        }
    }
}

final class SettingsMultilineTextEditorContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    private let bottomBreathingRoomView = NSView()

    private lazy var scrollViewHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var bottomBreathingHeightConstraint = bottomBreathingRoomView.heightAnchor.constraint(
        equalToConstant: viewportBottomBreathing
    )

    override var isFlipped: Bool { true }

    private var horizontalInset: CGFloat { SettingsTokens.Layout.inlineEditorHorizontalInset }
    private var verticalInset: CGFloat { SettingsTokens.Layout.inlineEditorTopInset }
    private var viewportBottomBreathing: CGFloat { SettingsTokens.Layout.inlineEditorViewportBottomBreathing }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        recalculateDocumentHeight()
    }

    func applyExternalText(_ text: String) {
        if textView.string != text {
            textView.string = text
            applyTextStorageAttributes()
        }

        recalculateDocumentHeight()
    }

    func recalculateDocumentHeight() {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return
        }

        let visibleBodyHeight = max(bounds.height - viewportBottomBreathing, 1)
        let viewportWidth = max(scrollView.contentSize.width, 1)
        let contentWidth = max(viewportWidth - (horizontalInset * 2), 1)

        scrollViewHeightConstraint.constant = visibleBodyHeight
        bottomBreathingHeightConstraint.constant = viewportBottomBreathing

        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(
            width: contentWidth,
            height: CGFloat.greatestFiniteMagnitude
        )

        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let extraLineHeight = max(
            layoutManager.extraLineFragmentRect.height,
            abs(textView.font?.descender ?? 0)
        )
        let targetHeight = max(
            visibleBodyHeight,
            ceil(usedHeight + (verticalInset * 2) + extraLineHeight)
        )

        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: viewportWidth,
            height: targetHeight
        )
    }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false

        addSubview(scrollView)
        bottomBreathingRoomView.translatesAutoresizingMaskIntoConstraints = false
        bottomBreathingRoomView.wantsLayer = true
        bottomBreathingRoomView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(bottomBreathingRoomView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollViewHeightConstraint,
            bottomBreathingRoomView.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomBreathingRoomView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBreathingRoomView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBreathingRoomView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBreathingHeightConstraint,
        ])

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body)
        textView.textContainerInset = NSSize(width: horizontalInset, height: verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        applyTextStorageAttributes()
    }

    private func applyTextStorageAttributes() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = PrimitiveTokens.LineHeight.body
        paragraphStyle.maximumLineHeight = PrimitiveTokens.LineHeight.body

        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]

        let attributed = NSMutableAttributedString(string: textView.string)
        attributed.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: PrimitiveTokens.FontSize.body),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ],
            range: NSRange(location: 0, length: attributed.length)
        )
        textView.textStorage?.setAttributedString(attributed)
    }
}
