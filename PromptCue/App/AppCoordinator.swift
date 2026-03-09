import AppKit
import KeyboardShortcuts

@MainActor
final class AppCoordinator {
    private let model = AppModel()
    private let hotKeyCenter = HotKeyCenter()
    private let screenshotSettingsModel = ScreenshotSettingsModel()
    private let exportTailSettingsModel = PromptExportTailSettingsModel()
    private let retentionSettingsModel = CardRetentionSettingsModel()
    private lazy var capturePanelController = CapturePanelController(model: model)
    private lazy var stackPanelController = StackPanelController(model: model)
    private lazy var designSystemWindowController = DesignSystemWindowController()
    private lazy var settingsWindowController = SettingsWindowController(
        screenshotSettingsModel: screenshotSettingsModel,
        exportTailSettingsModel: exportTailSettingsModel,
        retentionSettingsModel: retentionSettingsModel
    )
    private var statusItem: NSStatusItem?
    private var pendingStackToggleTask: Task<Void, Never>?

    func start() {
        terminateDuplicateDebugInstancesIfNeeded()
        ScreenshotDirectoryResolver.bootstrapPreferredDirectoryIfNeeded()
        model.start()
        applyCaptureQADraftSeedIfNeeded()
        hotKeyCenter.registerDefaultShortcuts(
            onCapture: { [weak self] in
                self?.showCapturePanel()
            },
            onToggleStack: { [weak self] in
                self?.toggleStackPanel()
            }
        )
        configureStatusItem()
        screenshotSettingsModel.presentOnboardingIfNeeded()

        if ProcessInfo.processInfo.environment["PROMPTCUE_OPEN_DESIGN_SYSTEM"] == "1" {
            showDesignSystemWindow()
        }

        if ProcessInfo.processInfo.environment["PROMPTCUE_OPEN_STACK_ON_START"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.stackPanelController.show()
            }
        }

        if ProcessInfo.processInfo.environment["PROMPTCUE_OPEN_CAPTURE_ON_START"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.showCapturePanel()
            }
        }
    }

    func stop() {
        pendingStackToggleTask?.cancel()
        pendingStackToggleTask = nil
        hotKeyCenter.unregisterAll()
        model.stop()
        statusItem = nil
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "quote.opening", accessibilityDescription: "Prompt Cue")
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
        pendingStackToggleTask?.cancel()
        pendingStackToggleTask = nil
        stackPanelController.close()
        capturePanelController.show()
    }

    private func toggleStackPanel() {
        if let pendingStackToggleTask {
            pendingStackToggleTask.cancel()
            self.pendingStackToggleTask = nil
            return
        }

        pendingStackToggleTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer { self.pendingStackToggleTask = nil }

            await self.model.waitForCaptureSubmissionToSettle(
                timeout: AppTiming.captureSubmissionFlushTimeout
            )

            guard !Task.isCancelled else {
                return
            }

            self.capturePanelController.close()
            if self.stackPanelController.isPresentedOrTransitioning {
                self.stackPanelController.close()
            } else {
                self.stackPanelController.show()
            }
        }
    }

    private func showDesignSystemWindow() {
        designSystemWindowController.show()
    }

    private func showSettingsWindow() {
        settingsWindowController.show()
    }

    private func terminateDuplicateDebugInstancesIfNeeded() {
        #if DEBUG
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let duplicateApps = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessIdentifier }

        for duplicateApp in duplicateApps {
            duplicateApp.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !duplicateApp.isTerminated {
                    duplicateApp.forceTerminate()
                }
            }
        }
        #endif
    }

    private func applyCaptureQADraftSeedIfNeeded() {
        let environment = ProcessInfo.processInfo.environment

        if let directText = environment["PROMPTCUE_QA_DRAFT_TEXT"], !directText.isEmpty {
            model.draftText = directText
            return
        }

        guard let filePath = environment["PROMPTCUE_QA_DRAFT_TEXT_FILE"], !filePath.isEmpty else {
            return
        }

        if let seededText = try? String(contentsOfFile: filePath, encoding: .utf8) {
            model.draftText = seededText
        }
    }
}
