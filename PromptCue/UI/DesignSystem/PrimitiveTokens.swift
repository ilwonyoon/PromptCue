import CoreGraphics
import SwiftUI

enum PrimitiveTokens {
    enum FontSize {
        static let capture: CGFloat = 17
        static let body: CGFloat = 15
        static let meta: CGFloat = 13
        static let micro: CGFloat = 11
        static let chip: CGFloat = 12
    }

    enum LineHeight {
        static let capture: CGFloat = 22
        static let body: CGFloat = 20
        static let meta: CGFloat = 18
        static let micro: CGFloat = 14
    }

    enum Space {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let compactCard: CGFloat = 12
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 26
        static let xl: CGFloat = 30
    }

    enum Size {
        static let chipHeight: CGFloat = 30
        static let searchFieldHeight: CGFloat = 70
        static let captureAttachmentPreviewHeight: CGFloat = 64
        static let captureAttachmentPreviewWidth: CGFloat = 92
        static let captureAttachmentPreviewSize: CGFloat = 72
        static let thumbnailHeight: CGFloat = 112
        static let notificationThumbnailHeight: CGFloat = 96
        static let notificationStackPlateHeight: CGFloat = 96
        static let emptyStateHeight: CGFloat = 240
        static let emptyStateTextWidth: CGFloat = 220
        static let panelPadding: CGFloat = 18
        static let cardPadding: CGFloat = 14
        static let notificationCardPadding: CGFloat = 20
        static let emptyStatePadding: CGFloat = 24
        static let cardStackSpacing: CGFloat = 12
        static let panelSectionSpacing: CGFloat = 14
        static let compactCardPadding: CGFloat = 10
        static let compactCardPaddingHorizontal: CGFloat = 12
        static let pinnedCardWidth: CGFloat = 170
        static let copiedControlClusterSpacing: CGFloat = 16
        static let sectionHeaderTrailingHeight: CGFloat = 22

        static let connectorBadge: CGFloat = 44
        static let connectorBadgeCornerRadius: CGFloat = 10
        static let connectorStatusDot: CGFloat = 9
        static let connectorStatusDotRing: CGFloat = 12
        static let connectorStatusDotOffset: CGFloat = 1
        static let connectorFallbackIconSize: CGFloat = 18
    }

    enum Stroke {
        static let subtle: CGFloat = 1
        static let emphasis: CGFloat = 1.5
    }

    enum Icon {
        static let search: CGFloat = 28
        static let panelEmpty: CGFloat = 24
        static let cardAccessory: CGFloat = 16
        static let chipAccessory: CGFloat = 12
    }

    enum Opacity {
        static let faint: Double = 0.12
        static let subtle: Double = 0.32
        static let soft: Double = 0.65
        static let copiedCard: Double = 0.55
        static let medium: Double = 0.75
        static let strong: Double = 0.85
        static let shell: Double = 0.84
        static let surface: Double = 0.9
        static let raisedSurface: Double = 0.92
    }

    enum Motion {
        static let quick: Double = 0.14
        static let standard: Double = 0.2
        static let hoverQuick: Double = 0.1
        static let stackOpen: Double = 0.18
        static let stackClose: Double = 0.12
    }

    enum Shadow {
        static let zeroX: CGFloat = 0

        static let cardAmbientBlur: CGFloat = 20
        static let cardAmbientY: CGFloat = 12
        static let cardKeyBlur: CGFloat = 8
        static let cardKeyY: CGFloat = 3
        static let captureAmbientOpacity: Double = 0.62
        static let captureAmbientBlur: CGFloat = 28
        static let captureAmbientY: CGFloat = 6
        static let captureKeyOpacity: Double = 0.52
        static let captureKeyBlur: CGFloat = 18
        static let captureKeyY: CGFloat = 12
        static let glassBlur: CGFloat = 10
        static let glassY: CGFloat = 2
        static let panelBlur: CGFloat = 10
        static let panelY: CGFloat = 2
        static let panelAmbientBlur: CGFloat = 28
        static let panelAmbientY: CGFloat = 16
        static let panelKeyBlur: CGFloat = 12
        static let panelKeyY: CGFloat = 4
        static let raisedCardBlur: CGFloat = 14
        static let raisedCardY: CGFloat = 8
        static let floatingControlBlur: CGFloat = 8
        static let floatingControlY: CGFloat = 2
    }

    // MARK: - macOS System Alert Specs (Figma macOS 26 Community reference)
    //
    // NSAlert / SwiftUI .alert() standard typography:
    //   Title (messageText):       13pt Bold,  line-height 16pt
    //   Body  (informativeText):   11pt Regular, line-height 14pt
    //   Title ↔ Body spacing:      10pt
    //   Alert width:               260pt (content area)
    //   Icon size:                 64×64pt
    //   Corner radius:             26pt (Liquid Glass)
    //   Button height:             ~21pt
    //
    // These map to existing primitive values:
    //   FontSize.meta (13) → alert title
    //   FontSize.micro (11) → alert body
    //   LineHeight.micro (14) → alert body line-height
    //
    // Use NSAlert or SwiftUI .alert() directly for standard system alerts.
    // Only build custom alert views when system alerts are insufficient.

    enum Alert {
        static let titleSize: CGFloat = FontSize.meta       // 13pt — macOS systemFontSize
        static let bodySize: CGFloat = FontSize.micro        // 11pt — macOS smallSystemFontSize
        static let titleLineHeight: CGFloat = 16
        static let bodyLineHeight: CGFloat = LineHeight.micro // 14pt
        static let titleBodySpacing: CGFloat = 10
        static let contentWidth: CGFloat = 260
        static let iconSize: CGFloat = 64
        static let cornerRadius: CGFloat = Radius.lg         // 26pt
        static let buttonMinWidth: CGFloat = 68
    }

    enum Typography {
        static let alertTitle = Font.system(size: FontSize.meta, weight: .bold)
        static let alertBody = Font.system(size: FontSize.micro, weight: .regular)

        static let panelTitle = Font.system(size: FontSize.body, weight: .semibold)
        static let body = Font.system(size: FontSize.body, weight: .regular)
        static let bodyStrong = Font.system(size: FontSize.body, weight: .medium)
        static let meta = Font.system(size: FontSize.meta, weight: .regular)
        static let metaStrong = Font.system(size: FontSize.meta, weight: .semibold)
        static let code = Font.system(size: FontSize.micro, weight: .regular, design: .monospaced)
        static let codeStrong = Font.system(size: FontSize.micro, weight: .medium, design: .monospaced)
        static let selection = Font.system(size: FontSize.micro, weight: .semibold)
        static let chip = Font.system(size: FontSize.meta, weight: .medium)
        static let captureInput = Font.system(size: FontSize.capture, weight: .regular)
        static let iconLabel = Font.system(size: FontSize.body, weight: .medium)
        static let accessoryIcon = Font.system(size: 14, weight: .semibold)
        static let chipIcon = Font.system(size: FontSize.chip, weight: .medium)
        static let emptyStateIcon = Font.system(size: 24, weight: .medium)
    }
}
