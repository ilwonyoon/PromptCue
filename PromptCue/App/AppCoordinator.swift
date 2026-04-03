import AppKit
import KeyboardShortcuts
import PromptCueCore

@MainActor
final class AppCoordinator: AppLifecycleCoordinating {
    private struct ExperimentalMCPHTTPLaunchConfiguration: Equatable {
        let port: UInt16
        let authMode: ExperimentalMCPHTTPAuthMode
        let apiKey: String?
        let publicBaseURL: URL?
    }

    let model = AppModel()
    private let hotKeyCenter = HotKeyCenter()
    private let screenshotSettingsModel = ScreenshotSettingsModel()
    private let launchAtLoginSettingsModel = LaunchAtLoginSettingsModel()
    private let exportTailSettingsModel = PromptExportTailSettingsModel()
    private let retentionSettingsModel = CardRetentionSettingsModel()
    private let cloudSyncSettingsModel = CloudSyncSettingsModel()
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
    private lazy var memoryWindowController = MemoryWindowController(
        model: MemoryViewerModel(store: model.documentStore)
    )
    private lazy var settingsWindowController = SettingsWindowController(
        screenshotSettingsModel: screenshotSettingsModel,
        launchAtLoginSettingsModel: launchAtLoginSettingsModel,
        exportTailSettingsModel: exportTailSettingsModel,
        retentionSettingsModel: retentionSettingsModel,
        cloudSyncSettingsModel: cloudSyncSettingsModel,
        mcpConnectorSettingsModel: mcpConnectorSettingsModel
    )
    private var statusItem: NSStatusItem?
    private var pendingStackToggleTask: Task<Void, Never>?
    private var systemThemeObserver: NSObjectProtocol?
    private var stackDidChangeObserver: NSObjectProtocol?
    private var experimentalMCPHTTPSettingsObserver: NSObjectProtocol?
    private var experimentalMCPHTTPRetryObserver: NSObjectProtocol?
    private var experimentalMCPHTTPOAuthResetObserver: NSObjectProtocol?
    private var experimentalMCPHTTPDidBecomeActiveObserver: NSObjectProtocol?
    private var lastDidBecomeActiveWork = Date.distantPast
    private var experimentalMCPHTTPWakeObserver: NSObjectProtocol?
    private var experimentalMCPHTTPProcess: Process?
    private var experimentalMCPHTTPLogPipe: Pipe?
    private var experimentalMCPHTTPRestartWorkItem: DispatchWorkItem?
    private var experimentalMCPHTTPHealthRefreshWorkItem: DispatchWorkItem?
    private var shouldKeepExperimentalMCPHTTPRunning = false
    private var currentExperimentalMCPHTTPLaunchConfiguration: ExperimentalMCPHTTPLaunchConfiguration?

    private static let experimentalMCPHTTPRestartDelay: TimeInterval = 1

    init() {
        systemThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                // Mark controllers immediately so a show() racing with this
                // notification picks up the pending flag even before the
                // dispatched block runs.
                self.stackPanelController.markAppearanceDirty()
                self.capturePanelController.markAppearanceDirty()

                // Defer the actual refresh to the next runloop iteration.
                // The distributed notification arrives *before* AppKit
                // finishes propagating the new effective appearance to
                // windows, so reading effectiveAppearance synchronously
                // returns the stale value and deduplication skips the
                // refresh — the root cause of the recurring regression.
                DispatchQueue.main.async { [weak self] in
                    self?.refreshForInheritedAppearanceChange()

                    // Second pass: "Auto" mode transitions can take longer
                    // for AppKit to resolve the effective appearance. A
                    // delayed retry ensures the panel catches up.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.refreshForInheritedAppearanceChange()
                    }
                }
            }
        }

        stackDidChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: .backtickStackDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model.refreshCardsForExternalChanges()
            }
        }

        experimentalMCPHTTPSettingsObserver = NotificationCenter.default.addObserver(
            forName: .experimentalMCPHTTPSettingsDidChange,
            object: mcpConnectorSettingsModel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncExperimentalMCPHTTPConfiguration()
            }
        }

        experimentalMCPHTTPOAuthResetObserver = NotificationCenter.default.addObserver(
            forName: .experimentalMCPHTTPOAuthResetRequested,
            object: mcpConnectorSettingsModel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetExperimentalMCPHTTPOAuthState()
            }
        }

        experimentalMCPHTTPRetryObserver = NotificationCenter.default.addObserver(
            forName: .experimentalMCPHTTPRetryRequested,
            object: mcpConnectorSettingsModel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryExperimentalMCPHTTP()
            }
        }

        experimentalMCPHTTPDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                if now.timeIntervalSince(self.lastDidBecomeActiveWork) < 30 { return }
                self.lastDidBecomeActiveWork = now
                AnalyticsService.shared.syncMCPActivitySignals()
                self.model.refreshCardsForExternalChanges()
                self.recheckExperimentalMCPHTTPHealth()
                self.model.fetchRemoteChangesIfSyncEnabled()
            }
        }

        experimentalMCPHTTPWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recheckExperimentalMCPHTTPHealth()
                self?.model.fetchRemoteChangesIfSyncEnabled()
            }
        }
    }

    deinit {
        if let systemThemeObserver {
            DistributedNotificationCenter.default().removeObserver(systemThemeObserver)
        }
        if let stackDidChangeObserver {
            DistributedNotificationCenter.default().removeObserver(stackDidChangeObserver)
        }
        if let experimentalMCPHTTPSettingsObserver {
            NotificationCenter.default.removeObserver(experimentalMCPHTTPSettingsObserver)
        }
        if let experimentalMCPHTTPOAuthResetObserver {
            NotificationCenter.default.removeObserver(experimentalMCPHTTPOAuthResetObserver)
        }
        if let experimentalMCPHTTPRetryObserver {
            NotificationCenter.default.removeObserver(experimentalMCPHTTPRetryObserver)
        }
        if let experimentalMCPHTTPDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(experimentalMCPHTTPDidBecomeActiveObserver)
        }
        if let experimentalMCPHTTPWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(experimentalMCPHTTPWakeObserver)
        }
        experimentalMCPHTTPHealthRefreshWorkItem?.cancel()
    }

    func start() {
        terminateDuplicateDebugInstancesIfNeeded()
        ScreenshotDirectoryResolver.bootstrapPreferredDirectoryIfNeeded()
        model.start()
        applyCaptureQADraftSeedIfNeeded(environment)
        syncExperimentalMCPHTTPConfiguration()
        hotKeyCenter.registerDefaultShortcuts(
            onCapture: { [weak self] in
                self?.showCapturePanel()
            },
            onToggleStack: { [weak self] in
                self?.toggleStackPanel()
            },
            onToggleMemory: { [weak self] in
                self?.toggleMemoryWindow()
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

        if PerformanceTrace.shouldTraceCaptureToggleOnStart {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: PerformanceTrace.captureToggleDelayNanoseconds)
                self?.showCapturePanel()
            }
        }

#if DEBUG
        if PerformanceTrace.shouldTraceCaptureSubmitCloseOnStart {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: PerformanceTrace.captureSubmitCloseDelayNanoseconds)
                await self?.runCaptureSubmitCloseTraceAutomation()
            }
        }
#endif
    }

    func stop() {
        pendingStackToggleTask?.cancel()
        pendingStackToggleTask = nil
        stopExperimentalMCPHTTP()
        hotKeyCenter.unregisterAll()
        model.stop()
        statusItem = nil
    }

    func handleCloudRemoteNotification() {
        model.handleCloudRemoteNotification()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = makeStatusItemImage()
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleNone
        item.button?.appearance = nil

        let menu = NSMenu()
        let quickCaptureItem = NSMenuItem(title: "Quick Capture", action: #selector(handleQuickCapture), keyEquivalent: "")
        quickCaptureItem.setShortcut(for: .quickCapture)
        menu.addItem(quickCaptureItem)

        let toggleStackItem = NSMenuItem(title: "Show Stack Panel", action: #selector(handleToggleStack), keyEquivalent: "")
        toggleStackItem.setShortcut(for: .toggleStackPanel)
        menu.addItem(toggleStackItem)

        let toggleMemoryItem = NSMenuItem(title: "Show Memory", action: #selector(handleToggleMemory), keyEquivalent: "")
        toggleMemoryItem.setShortcut(for: .toggleMemoryViewer)
        menu.addItem(toggleMemoryItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(handleOpenSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit Backtick", action: #selector(handleQuit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func makeStatusItemImage() -> NSImage? {
        if let image = NSImage(named: NSImage.Name("BacktickStatusMark")) {
            image.isTemplate = true
            image.size = NSSize(width: 20, height: 20)
            return image
        }

        return NSImage(
            systemSymbolName: "quote.opening",
            accessibilityDescription: "Backtick"
        )
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

    @objc private func handleToggleMemory() {
        toggleMemoryWindow()
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    private func showCapturePanel() {
        screenshotSettingsModel.refresh()
        guard screenshotSettingsModel.captureReadinessRequirement == .none else {
            settingsWindowController.promptForScreenshotFolderReadiness { [weak self] didResolve in
                guard didResolve else {
                    return
                }
                self?.showCapturePanel()
            }
            return
        }
        pendingStackToggleTask?.cancel()
        pendingStackToggleTask = nil
        if !capturePanelController.isPresented, PerformanceTrace.shouldMeasureCaptureOpen {
            PerformanceTrace.beginCaptureOpenTrace()
        }
        stackPanelController.close()
        memoryWindowController.hide()
        capturePanelController.toggle()
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
            self.memoryWindowController.hide()
            if self.stackPanelController.isPresentedOrTransitioning {
                self.stackPanelController.close()
            } else {
                if shouldMeasureStackOpen {
                    PerformanceTrace.beginStackOpenTrace()
                }
                self.stackPanelController.show()
                AnalyticsService.shared.trackStackOpened(promptCount: self.model.cards.count)
            }
        }
    }

    private func showDesignSystemWindow() {
        designSystemWindowController.show()
    }

    private func toggleMemoryWindow() {
        pendingStackToggleTask?.cancel()
        pendingStackToggleTask = nil
        capturePanelController.close()
        stackPanelController.close()
        // Memory is a regular window inside a status-item app, so hiding the
        // frontmost window makes the app appear to quit. Treat cmd+3 as a
        // reveal/focus shortcut instead of a hide toggle.
        memoryWindowController.reveal()
    }

    private func showSettingsWindow() {
        settingsWindowController.show(selectedTab: startupSettingsTab())
    }

    private func refreshForInheritedAppearanceChange() {
        statusItem?.button?.appearance = nil
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.needsDisplay = true

        capturePanelController.refreshForInheritedAppearanceChange()
        stackPanelController.refreshForInheritedAppearanceChange()
        memoryWindowController.refreshForInheritedAppearanceChange()
        settingsWindowController.refreshForInheritedAppearanceChange()
        designSystemWindowController.refreshForInheritedAppearanceChange()
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

#if DEBUG
    private func runCaptureSubmitCloseTraceAutomation() async {
        showCapturePanel()

        let timeoutNanoseconds: UInt64 = 2_000_000_000
        let pollIntervalNanoseconds: UInt64 = 25_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            guard let runtimeController = capturePanelController.debugRuntimeViewController else {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                continue
            }

            guard runtimeController.debugIsEditorFirstResponder else {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                continue
            }

            let currentDraft = runtimeController.debugEditorText.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentDraft.isEmpty {
                let fallbackText = model.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Capture trace seed"
                    : model.draftText
                runtimeController.debugApplyEditorText(
                    fallbackText,
                    selectedLocation: fallbackText.utf16.count
                )
            }

            runtimeController.debugTriggerSubmit()
            return
        }
    }
#endif

    private func syncExperimentalMCPHTTPConfiguration() {
        guard let desiredConfiguration = desiredExperimentalMCPHTTPLaunchConfiguration() else {
            currentExperimentalMCPHTTPLaunchConfiguration = nil
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.stopped)
            stopExperimentalMCPHTTP()
            return
        }

        let configurationChanged = currentExperimentalMCPHTTPLaunchConfiguration != desiredConfiguration
        currentExperimentalMCPHTTPLaunchConfiguration = desiredConfiguration

        if let process = experimentalMCPHTTPProcess, process.isRunning {
            guard configurationChanged else {
                return
            }

            shouldKeepExperimentalMCPHTTPRunning = true
            experimentalMCPHTTPRestartWorkItem?.cancel()
            experimentalMCPHTTPRestartWorkItem = nil
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.restarting)
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    process.interrupt()
                }
            }
            return
        }

        shouldKeepExperimentalMCPHTTPRunning = true
        launchExperimentalMCPHTTPHelper()
    }

    private func launchExperimentalMCPHTTPHelper() {
        guard experimentalMCPHTTPProcess == nil else {
            return
        }

        guard let launchConfiguration = currentExperimentalMCPHTTPLaunchConfiguration
                ?? desiredExperimentalMCPHTTPLaunchConfiguration() else {
            shouldKeepExperimentalMCPHTTPRunning = false
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.stopped)
            return
        }

        if launchConfiguration.authMode == .oauth, launchConfiguration.publicBaseURL == nil {
            shouldKeepExperimentalMCPHTTPRunning = false
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(
                .failed("OAuth mode needs a valid public HTTPS URL before Backtick can start the remote server.")
            )
            return
        }

        guard let launchSpec = mcpConnectorSettingsModel.inspection.launchSpec else {
            shouldKeepExperimentalMCPHTTPRunning = false
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(
                .failed("Backtick MCP helper launch spec is unavailable.")
            )
            NSLog("Experimental MCP HTTP launch skipped: BacktickMCP helper launch spec unavailable")
            return
        }

        experimentalMCPHTTPRestartWorkItem?.cancel()
        experimentalMCPHTTPRestartWorkItem = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchSpec.command)
        var arguments = launchSpec.arguments + [
            "--transport",
            "http",
            "--host",
            "127.0.0.1",
            "--port",
            "\(launchConfiguration.port)",
            "--auth-mode",
            launchConfiguration.authMode.rawValue,
            "--parent-pid",
            "\(ProcessInfo.processInfo.processIdentifier)",
        ]
        if let apiKey = launchConfiguration.apiKey, launchConfiguration.authMode == .apiKey {
            arguments += ["--api-key", apiKey]
        }
        if let publicBaseURL = launchConfiguration.publicBaseURL {
            arguments += ["--public-base-url", publicBaseURL.absoluteString]
        }
        process.arguments = arguments

        let logPipe = Pipe()
        process.standardOutput = logPipe
        process.standardError = logPipe
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleExperimentalMCPHTTPTermination(process)
            }
        }

        beginExperimentalMCPHTTPLogStreaming(from: logPipe)
        mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.starting)

        do {
            try process.run()
            experimentalMCPHTTPProcess = process
            experimentalMCPHTTPLogPipe = logPipe
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.running)
            scheduleExperimentalMCPHTTPHealthRefresh()
            NSLog(
                "Experimental MCP HTTP helper started on http://127.0.0.1:%d/mcp",
                Int(launchConfiguration.port)
            )
        } catch {
            logPipe.fileHandleForReading.readabilityHandler = nil
            shouldKeepExperimentalMCPHTTPRunning = false
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(
                .failed(error.localizedDescription)
            )
            NSLog("Experimental MCP HTTP helper failed to start: %@", String(describing: error))
        }
    }

    private func stopExperimentalMCPHTTP() {
        shouldKeepExperimentalMCPHTTPRunning = false
        experimentalMCPHTTPRestartWorkItem?.cancel()
        experimentalMCPHTTPRestartWorkItem = nil
        experimentalMCPHTTPHealthRefreshWorkItem?.cancel()
        experimentalMCPHTTPHealthRefreshWorkItem = nil

        guard let process = experimentalMCPHTTPProcess else {
            return
        }

        experimentalMCPHTTPProcess = nil
        process.terminationHandler = nil
        experimentalMCPHTTPLogPipe?.fileHandleForReading.readabilityHandler = nil
        experimentalMCPHTTPLogPipe = nil
        mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.stopped)
        guard process.isRunning else {
            return
        }

        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning {
                process.interrupt()
            }
        }
    }

    private func handleExperimentalMCPHTTPTermination(_ process: Process) {
        NSLog(
            "Experimental MCP HTTP helper exited with status %d",
            process.terminationStatus
        )

        guard experimentalMCPHTTPProcess === process else {
            return
        }

        experimentalMCPHTTPProcess = nil
        experimentalMCPHTTPLogPipe?.fileHandleForReading.readabilityHandler = nil
        experimentalMCPHTTPLogPipe = nil

        guard shouldKeepExperimentalMCPHTTPRunning else {
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.stopped)
            return
        }

        scheduleExperimentalMCPHTTPRestart()
    }

    private func scheduleExperimentalMCPHTTPRestart() {
        experimentalMCPHTTPRestartWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.experimentalMCPHTTPRestartWorkItem = nil
            self.launchExperimentalMCPHTTPHelper()
        }

        experimentalMCPHTTPRestartWorkItem = workItem
        mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.restarting)
        NSLog(
            "Experimental MCP HTTP helper restart scheduled in %.1f seconds",
            Self.experimentalMCPHTTPRestartDelay
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.experimentalMCPHTTPRestartDelay,
            execute: workItem
        )
    }

    private func beginExperimentalMCPHTTPLogStreaming(from pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let chunk = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !chunk.isEmpty else {
                return
            }

            NSLog("Experimental MCP HTTP helper: %@", chunk)
            DispatchQueue.main.async {
                self?.mcpConnectorSettingsModel.recordExperimentalRemoteHelperLog(chunk)
            }
        }
    }

    private func resetExperimentalMCPHTTPOAuthState() {
        if experimentalMCPHTTPProcess != nil {
            mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.restarting)
        }

        stopExperimentalMCPHTTP()
        syncExperimentalMCPHTTPConfiguration()
    }

    private func retryExperimentalMCPHTTP() {
        if experimentalMCPHTTPProcess == nil || !(experimentalMCPHTTPProcess?.isRunning ?? false) {
            syncExperimentalMCPHTTPConfiguration()
            return
        }

        recheckExperimentalMCPHTTPHealth()
    }

    private func recheckExperimentalMCPHTTPHealth() {
        guard let desiredConfiguration = desiredExperimentalMCPHTTPLaunchConfiguration() else {
            return
        }

        guard let process = experimentalMCPHTTPProcess, process.isRunning else {
            syncExperimentalMCPHTTPConfiguration()
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            let isHealthy = await self.isExperimentalMCPHTTPLocalEndpointHealthy(port: desiredConfiguration.port)
            await MainActor.run {
                guard self.shouldKeepExperimentalMCPHTTPRunning,
                      self.currentExperimentalMCPHTTPLaunchConfiguration == desiredConfiguration,
                      self.experimentalMCPHTTPProcess === process,
                      process.isRunning else {
                    return
                }

                if isHealthy {
                    self.scheduleExperimentalMCPHTTPHealthRefresh(after: 0)
                    return
                }

                self.mcpConnectorSettingsModel.setExperimentalRemoteRuntimeState(.restarting)
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning {
                        process.interrupt()
                    }
                }
            }
        }
    }

    private func scheduleExperimentalMCPHTTPHealthRefresh(after delay: TimeInterval = 0.6) {
        experimentalMCPHTTPHealthRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.experimentalMCPHTTPHealthRefreshWorkItem = nil
            self.mcpConnectorSettingsModel.refresh()
            self.mcpConnectorSettingsModel.refreshExperimentalRemoteProbe()
            self.mcpConnectorSettingsModel.startPeriodicRemoteProbe()
        }

        experimentalMCPHTTPHealthRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func isExperimentalMCPHTTPLocalEndpointHealthy(port: UInt16) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private func desiredExperimentalMCPHTTPLaunchConfiguration() -> ExperimentalMCPHTTPLaunchConfiguration? {
        if environment.shouldLaunchExperimentalMCPHTTPOnStart {
            return ExperimentalMCPHTTPLaunchConfiguration(
                port: environment.experimentalMCPHTTPPort,
                authMode: .apiKey,
                apiKey: environment.experimentalMCPHTTPAPIKey,
                publicBaseURL: nil
            )
        }

        guard mcpConnectorSettingsModel.experimentalRemoteSettings.isEnabled else {
            return nil
        }

        return ExperimentalMCPHTTPLaunchConfiguration(
            port: mcpConnectorSettingsModel.experimentalRemoteSettings.port,
            authMode: mcpConnectorSettingsModel.experimentalRemoteSettings.authMode,
            apiKey: mcpConnectorSettingsModel.experimentalRemoteSettings.apiKey,
            publicBaseURL: mcpConnectorSettingsModel.experimentalRemotePublicBaseURL
        )
    }
}
