import AppKit
import KeyboardShortcuts
import PromptCueCore

@MainActor
final class AppCoordinator: AppLifecycleCoordinating {
    let model = AppModel()
    private let hotKeyCenter = HotKeyCenter()
    private let screenshotSettingsModel = ScreenshotSettingsModel()
    private let exportTailSettingsModel = PromptExportTailSettingsModel()
    private let retentionSettingsModel = CardRetentionSettingsModel()
    private let cloudSyncSettingsModel = CloudSyncSettingsModel()
    private let appearanceSettingsModel = AppearanceSettingsModel()
    private let mcpConnectorSettingsModel = MCPConnectorSettingsModel()
    private let environment = AppEnvironment.current
    private lazy var capturePanelController = CapturePanelController(model: model)
    private lazy var stackPanelController = StackPanelController(
        model: model,
        onEditCard: { [weak self] card in
            self?.editCardFromStack(card)
        }
    )
    private lazy var designSystemWindowController = DesignSystemWindowController()
    private lazy var settingsWindowController = SettingsWindowController(
        screenshotSettingsModel: screenshotSettingsModel,
        exportTailSettingsModel: exportTailSettingsModel,
        retentionSettingsModel: retentionSettingsModel,
        cloudSyncSettingsModel: cloudSyncSettingsModel,
        appearanceSettingsModel: appearanceSettingsModel,
        mcpConnectorSettingsModel: mcpConnectorSettingsModel
    )
    private var statusItem: NSStatusItem?
    private var pendingStackToggleTask: Task<Void, Never>?

    init() {
        appearanceSettingsModel.onAppearanceApplied = { [weak self] appearance in
            self?.applyAppearance(appearance)
        }
    }

    func start() {
        terminateDuplicateDebugInstancesIfNeeded()
        ScreenshotDirectoryResolver.bootstrapPreferredDirectoryIfNeeded()
        appearanceSettingsModel.applyAppearance()
        model.start()
        applyCaptureQADraftSeedIfNeeded(environment)
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
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.stackPanelController.prepareForFirstPresentation()
        }

        if environment.shouldOpenDesignSystemOnStart {
            showDesignSystemWindow()
        }

        if environment.shouldOpenStackOnStart {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.stackPanelController.show()
            }
        }

        if PerformanceTrace.shouldTraceStackToggleOnStart {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: PerformanceTrace.stackToggleDelayNanoseconds)
                self?.toggleStackPanel()
            }
        }

        if environment.shouldOpenSettingsOnStart {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.showSettingsWindow()
            }
        }

        if environment.shouldOpenCaptureOnStart {
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

    func handleCloudRemoteNotification() {
        model.handleCloudRemoteNotification()
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

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    private func showCapturePanel() {
        pendingStackToggleTask?.cancel()
        pendingStackToggleTask = nil
        stackPanelController.close()
        capturePanelController.show()
    }

    private func editCardFromStack(_ card: CaptureCard) {
        pendingStackToggleTask?.cancel()
        pendingStackToggleTask = nil
        model.beginEditingCaptureCard(card)
        stackPanelController.close(commitDeferredCopies: false)
        capturePanelController.show()
    }

    private func toggleStackPanel() {
        if let pendingStackToggleTask {
            pendingStackToggleTask.cancel()
            self.pendingStackToggleTask = nil
            return
        }
        let shouldMeasureStackOpen = !stackPanelController.isPresentedOrTransitioning

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
                if shouldMeasureStackOpen {
                    PerformanceTrace.beginStackOpenTrace()
                }
                self.stackPanelController.show()
            }
        }
    }

    private func showDesignSystemWindow() {
        designSystemWindowController.show()
    }

    private func showSettingsWindow() {
        settingsWindowController.show(selectedTab: startupSettingsTab())
    }

    private func applyAppearance(_ appearance: NSAppearance?) {
        NSApp.windows.forEach { window in
            window.appearance = appearance
            window.invalidateShadow()
            window.contentView?.needsDisplay = true
            window.contentView?.subviews.forEach { $0.needsDisplay = true }
        }

        capturePanelController.applyAppearance(appearance)
        stackPanelController.applyAppearance(appearance)
        settingsWindowController.applyAppearance(appearance)
        designSystemWindowController.applyAppearance(appearance)
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

    private func applyCaptureQADraftSeedIfNeeded(_ environment: AppEnvironment) {
        if let directText = environment.qaDraftText {
            model.draftText = directText
            return
        }

        guard let filePath = environment.qaDraftTextFilePath else {
            return
        }

        if let seededText = try? String(contentsOfFile: filePath, encoding: .utf8) {
            model.draftText = seededText
        }
    }

    private func startupSettingsTab() -> SettingsTab? {
        switch environment.startupSettingsTab {
        case .general:
            return .general
        case .capture:
            return .capture
        case .stack:
            return .stack
        case .connectors:
            return .connectors
        case nil:
            return nil
        }
    }
}
