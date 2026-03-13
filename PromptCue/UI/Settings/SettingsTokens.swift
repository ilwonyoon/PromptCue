import CoreGraphics
import SwiftUI

enum SettingsTokens {
    enum Layout {
        static let sidebarWidth: CGFloat = PanelMetrics.settingsSidebarWidth
        static let labelColumnWidth: CGFloat = PanelMetrics.settingsLabelColumnWidth
        static let advancedLabelColumnWidth: CGFloat = 92
        static let trailingRailMinWidth: CGFloat = 140

        static let pageLeadingPadding: CGFloat = 24
        static let pageTrailingPadding: CGFloat = 20
        static let pageTopPadding: CGFloat = 20
        static let pageBottomPadding: CGFloat = 20
        static let titleToFirstSectionSpacing: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
        static let sectionHeaderSpacing: CGFloat = 8
        static let sectionTitleSpacing: CGFloat = 2
        static let contentMaxWidth: CGFloat = 600

        static let sidebarRowHeight: CGFloat = 36
        static let sidebarCornerRadius: CGFloat = 10
        static let sidebarItemSpacing: CGFloat = 6
        static let sidebarItemHorizontalPadding: CGFloat = 12
        static let sidebarItemVerticalPadding: CGFloat = 2
        static let sidebarVerticalPadding: CGFloat = 16
        static let sidebarHorizontalPadding: CGFloat = 10
        static let sidebarIconSize: CGFloat = 30
        static let sidebarIconGlyphSize: CGFloat = 16
        static let sidebarAssetIconInset: CGFloat = 1.75
        static let sidebarIconTextSpacing: CGFloat = 9
        static let sidebarIconCornerRadius: CGFloat = 7

        static let groupCornerRadius: CGFloat = 12
        static let fieldCornerRadius: CGFloat = 10
        static let groupInset: CGFloat = 14
        static let groupVerticalInset: CGFloat = 6
        static let groupDividerInset: CGFloat = groupInset
        static let inlinePanelPadding: CGFloat = 12
        static let inlineEditorHorizontalInset: CGFloat = 10
        static let inlineEditorTopInset: CGFloat = 10
        static let inlineEditorBottomInset: CGFloat = 10
        static let inlineEditorViewportBottomBreathing: CGFloat = 10
        static let connectorCardPadding: CGFloat = 14
        static let formRowMinHeight: CGFloat = 42
        static let rowLabelToValueGap: CGFloat = 16
        static let rowVerticalPadding: CGFloat = 6
        static let rowDetailSpacing: CGFloat = 8
        static let rowActionSpacing: CGFloat = 8
        static let longFormHeaderSpacing: CGFloat = 8
        static let statusBadgeDotSize: CGFloat = 8
    }

    enum Typography {
        static let pageTitle = Font.system(size: 20, weight: .semibold)
        static let sectionTitle = Font.system(size: 13, weight: .semibold)
        static let sectionTitleMedium = Font.system(size: 13, weight: .medium)
        static let sidebarLabel = Font.system(size: 13, weight: .medium)
        static let rowLabel = Font.system(size: 13, weight: .medium)
        static let supporting = Font.system(size: 11, weight: .regular)
        static let supportingStrong = Font.system(size: 11, weight: .semibold)
    }
}
