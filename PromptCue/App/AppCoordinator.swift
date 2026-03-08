import AppKit
import KeyboardShortcuts

@MainActor
final class AppCoordinator {
    private let model = AppModel()
    private let hotKeyCenter = HotKeyCenter()
    private lazy var capturePanelController = CapturePanelController(model: model)
    private lazy var stackPanelController = StackPanelController(model: model)
    private lazy var designSystemWindowController = DesignSystemWindowController()
    private lazy var settingsWindowController = SettingsWindowController()
    private var statusItem: NSStatusItem?

    func start() {
        ScreenshotDirectoryResolver.bootstrapPreferredDirectoryIfNeeded()
        model.start()
        hotKeyCenter.registerDefaultShortcuts(
            onCapture: { [weak self] in
                self?.showCapturePanel()
            },
            onToggleStack: { [weak self] in
                self?.toggleStackPanel()
            }
        )
        configureStatusItem()

        if ProcessInfo.processInfo.environment["PROMPTCUE_OPEN_DESIGN_SYSTEM"] == "1" {
            showDesignSystemWindow()
        }
    }

    func stop() {
        hotKeyCenter.unregisterAll()
        model.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Prompt Cue")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        let quickCaptureItem = NSMenuItem(title: "Quick Capture", action: #selector(handleQuickCapture), keyEquivalent: "")
        quickCaptureItem.setShortcut(for: .quickCapture)
        menu.addItem(quickCaptureItem)

        let toggleStackItem = NSMenuItem(title: "Show Stack Panel", action: #selector(handleToggleStack), keyEquivalent: "")
        toggleStackItem.setShortcut(for: .toggleStackPanel)
        menu.addItem(toggleStackItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Design System…", action: #selector(handleOpenDesignSystem), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(handleOpenSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Prompt Cue", action: #selector(handleQuit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func handleQuickCapture() {
        showCapturePanel()
    }

    @objc private func handleToggleStack() {
        toggleStackPanel()
    }

    @objc private func handleOpenSettings() {
        showSettingsWindow()
    }

    @objc private func handleOpenDesignSystem() {
        showDesignSystemWindow()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    private func showCapturePanel() {
        stackPanelController.close()
        capturePanelController.show()
    }

    private func toggleStackPanel() {
        capturePanelController.close()
        if stackPanelController.isVisible {
            stackPanelController.close()
        } else {
            stackPanelController.show()
        }
    }

    private func showDesignSystemWindow() {
        designSystemWindowController.show()
    }

    private func showSettingsWindow() {
        settingsWindowController.show()
    }
}
