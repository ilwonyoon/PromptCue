import AppKit
import Combine
import SwiftUI

@MainActor
final class MemoryWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private var window: NSWindow?
    private let model: MemoryViewerModel
    private let uiState = MemoryViewerUIState()
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool {
        window?.isVisible == true
    }

    var isFrontmost: Bool {
        guard let window, window.isVisible else {
            return false
        }

        return window.isKeyWindow
            || window.isMainWindow
            || NSApp.keyWindow === window
            || NSApp.mainWindow === window
    }

    init(model: MemoryViewerModel? = nil) {
        self.model = model ?? MemoryViewerModel()
        super.init()
        bindToolbarValidation()
    }

    func toggle() {
        if isFrontmost {
            hide()
        } else {
            reveal()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    func show() {
        model.refresh()
        uiState.syncSelection(with: model)
        let window = window ?? makeWindow()
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        present(window)
    }

    func reveal() {
        if let window, window.isVisible {
            model.refresh()
            uiState.syncSelection(with: model)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            present(window)
            return
        }

        show()
    }

    func refreshForInheritedAppearanceChange() {
        guard let window else {
            return
        }

        window.appearance = nil
        window.contentView?.appearance = nil
        window.contentViewController?.view.appearance = nil
        window.invalidateShadow()
        window.contentView?.needsDisplay = true
        window.contentViewController?.view.layer?.contents = nil
        window.contentViewController?.view.needsLayout = true
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        window.contentViewController?.view.needsDisplay = true
    }

    private func makeWindow() -> NSWindow {
        let frame = NSRect(
            x: 0,
            y: 0,
            width: PanelMetrics.memoryWindowWidth,
            height: PanelMetrics.memoryWindowHeight
        )

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Backtick Memory"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.toolbar = makeToolbar()
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("BacktickMemoryWindow")
        window.minSize = NSSize(
            width: PanelMetrics.memoryWindowMinimumWidth,
            height: PanelMetrics.memoryWindowMinimumHeight
        )
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: MemoryViewerView(model: model, uiState: uiState)
        )

        self.window = window
        return window
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "BacktickMemoryToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifier = .memoryNewDocument
        return toolbar
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.toolbar?.validateVisibleItems()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .memoryRefresh,
            .memoryNewDocument,
            .memoryEditDocument,
            .memoryCopyDocument,
            .memoryDeleteDocument,
            .flexibleSpace
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .memoryRefresh,
            .flexibleSpace,
            .memoryNewDocument,
            .flexibleSpace,
            .memoryEditDocument,
            .memoryCopyDocument,
            .memoryDeleteDocument
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .memoryRefresh:
            return makeToolbarItem(
                itemIdentifier: itemIdentifier,
                label: "Refresh",
                systemSymbolName: "arrow.clockwise",
                action: #selector(refreshMemory)
            )
        case .memoryNewDocument:
            return makeToolbarItem(
                itemIdentifier: itemIdentifier,
                label: "New Document",
                systemSymbolName: "plus",
                action: #selector(newDocument)
            )
        case .memoryEditDocument:
            return makeToolbarItem(
                itemIdentifier: itemIdentifier,
                label: "Edit",
                systemSymbolName: "square.and.pencil",
                action: #selector(editDocument)
            )
        case .memoryCopyDocument:
            return makeToolbarItem(
                itemIdentifier: itemIdentifier,
                label: "Copy",
                systemSymbolName: "doc.on.doc",
                action: #selector(copyDocument)
            )
        case .memoryDeleteDocument:
            return makeToolbarItem(
                itemIdentifier: itemIdentifier,
                label: "Delete",
                systemSymbolName: "trash",
                action: #selector(deleteDocument)
            )
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .memoryRefresh, .memoryNewDocument:
            return true
        case .memoryEditDocument:
            return model.selectedDocument != nil && !uiState.isEditing
        case .memoryCopyDocument:
            return model.selectedDocument != nil && !uiState.isEditing
        case .memoryDeleteDocument:
            return model.selectedDocument != nil
        default:
            return true
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else {
            return
        }

        window.orderOut(nil)
    }

    private func bindToolbarValidation() {
        model.objectWillChange
            .sink { [weak self] _ in
                self?.window?.toolbar?.validateVisibleItems()
            }
            .store(in: &cancellables)

        uiState.objectWillChange
            .sink { [weak self] _ in
                self?.window?.toolbar?.validateVisibleItems()
            }
            .store(in: &cancellables)
    }

    private func makeToolbarItem(
        itemIdentifier: NSToolbarItem.Identifier,
        label: String,
        systemSymbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: label)
        item.isBordered = true
        return item
    }

    @objc
    private func refreshMemory() {
        model.refresh()
        uiState.syncSelection(with: model)
        window?.toolbar?.validateVisibleItems()
    }

    @objc
    private func newDocument() {
        uiState.prepareNewDocumentDraft(using: model)
        window?.toolbar?.validateVisibleItems()
    }

    @objc
    private func editDocument() {
        guard model.selectedDocument != nil else {
            return
        }
        uiState.startEditing(with: model)
        window?.toolbar?.validateVisibleItems()
    }

    @objc
    private func copyDocument() {
        guard model.selectedDocument != nil else {
            return
        }
        model.copySelectedDocument()
        uiState.showCopiedFeedback()
        window?.toolbar?.validateVisibleItems()
    }

    @objc
    private func deleteDocument() {
        guard let document = model.selectedDocument else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Document?"
        alert.informativeText = "Delete \(document.topic) from \(document.project)? This removes it from the active Memory list."
        alert.alertStyle = .warning
        alert.icon = nil
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        if model.deleteSelectedDocument() {
            uiState.finishDeletion(with: model)
        }
        window?.toolbar?.validateVisibleItems()
    }
}

private extension NSToolbarItem.Identifier {
    static let memoryRefresh = NSToolbarItem.Identifier("backtick.memory.refresh")
    static let memoryNewDocument = NSToolbarItem.Identifier("backtick.memory.newDocument")
    static let memoryEditDocument = NSToolbarItem.Identifier("backtick.memory.editDocument")
    static let memoryCopyDocument = NSToolbarItem.Identifier("backtick.memory.copyDocument")
    static let memoryDeleteDocument = NSToolbarItem.Identifier("backtick.memory.deleteDocument")
}
