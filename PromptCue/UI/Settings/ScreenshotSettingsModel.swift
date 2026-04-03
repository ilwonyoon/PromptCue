import AppKit
import Foundation

@MainActor
final class ScreenshotSettingsModel: ObservableObject {
    enum CaptureReadinessRequirement: Equatable {
        case none
        case chooseFolder
        case reconnect
        case chooseCurrentSystemFolder
    }

    @Published private(set) var accessState: ScreenshotFolderAccessState = .notConfigured

    private let accessStateProvider: () -> ScreenshotFolderAccessState
    private let suggestedSystemPathProvider: () -> String?
    private let systemDirectoryURLProvider: () -> URL?

    init(
        accessStateProvider: @escaping () -> ScreenshotFolderAccessState = { ScreenshotDirectoryResolver.accessState() },
        suggestedSystemPathProvider: @escaping () -> String? = { ScreenshotDirectoryResolver.suggestedDirectoryDisplayPath },
        systemDirectoryURLProvider: @escaping () -> URL? = { ScreenshotDirectoryResolver.resolvedSystemScreenshotDirectory() }
    ) {
        self.accessStateProvider = accessStateProvider
        self.suggestedSystemPathProvider = suggestedSystemPathProvider
        self.systemDirectoryURLProvider = systemDirectoryURLProvider
        refresh()
    }

    var suggestedSystemPath: String? {
        suggestedSystemPathProvider()
    }

    var currentSystemFolderMismatch: Bool {
        guard case let .connected(url, _) = accessState,
              let currentSystemDirectoryURL = systemDirectoryURLProvider() else {
            return false
        }

        return url.standardizedFileURL != currentSystemDirectoryURL.standardizedFileURL
    }

    var captureReadinessRequirement: CaptureReadinessRequirement {
        if currentSystemFolderMismatch {
            return .chooseCurrentSystemFolder
        }

        switch accessState {
        case .connected:
            return .none
        case .notConfigured:
            return .chooseFolder
        case .needsReconnect:
            return .reconnect
        }
    }

    func refresh() {
        accessState = accessStateProvider()
    }

    @discardableResult
    func ensureReadyForCapture() -> Bool {
        refresh()

        let requirement = captureReadinessRequirement
        guard requirement != .none else {
            return true
        }

        switch requirement {
        case .none:
            return true
        case .chooseFolder:
            _ = chooseFolder(
                message: "Choose the folder Backtick should watch for recent screenshots before capture opens."
            )
        case .reconnect:
            reconnectFolder()
        case .chooseCurrentSystemFolder:
            chooseCurrentSystemFolder()
        }

        refresh()
        return captureReadinessRequirement == .none
    }

    @discardableResult
    func chooseFolder(
        message: String = "Choose the folder Backtick should watch for recent screenshots.",
        initialDirectoryURL: URL? = nil,
        attachedTo window: NSWindow? = nil,
        completion: ((Bool) -> Void)? = nil
    ) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = message
        panel.directoryURL = initialDirectoryURL ?? ScreenshotDirectoryResolver.selectionSeedURL()

        NSApp.activate(ignoringOtherApps: true)
        if let window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self else {
                    completion?(false)
                    return
                }

                let didChoose = self.handleFolderChoiceResponse(response, from: panel)
                completion?(didChoose)
            }
            return false
        } else {
            let response = panel.runModal()
            return handleFolderChoiceResponse(response, from: panel)
        }
    }

    func reconnectFolder() {
        _ = chooseFolder()
    }

    func chooseCurrentSystemFolder() {
        let currentSystemDirectoryURL = systemDirectoryURLProvider()
        let currentSystemPath = suggestedSystemPath ?? "the current macOS screenshot folder"
        _ = chooseFolder(
            message: "macOS is currently saving screenshots to \(currentSystemPath). Choose that folder to keep auto-attach working.",
            initialDirectoryURL: currentSystemDirectoryURL
        )
    }

    func clearFolder() {
        ScreenshotDirectoryResolver.clearAuthorizedDirectory()
        refresh()
    }

    func revealFolderInFinder() {
        ScreenshotDirectoryResolver.withAuthorizedDirectory { directoryURL in
            NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
        }
    }

    func presentOnboardingIfNeeded() {
        guard ScreenshotDirectoryResolver.shouldPresentOnboarding else {
            return
        }

        ScreenshotDirectoryResolver.markOnboardingHandled()
        _ = chooseFolder(
            message: "Select your screenshot folder once to enable automatic screenshot attach. You can change this later in Settings."
        )
    }

    private func handleFolderChoiceResponse(_ response: NSApplication.ModalResponse, from panel: NSOpenPanel) -> Bool {
        guard response == .OK, let url = panel.url else {
            return false
        }

        do {
            try ScreenshotDirectoryResolver.saveAuthorizedDirectory(url)
            refresh()
            return true
        } catch {
            NSApp.presentError(error)
            return false
        }
    }
}
