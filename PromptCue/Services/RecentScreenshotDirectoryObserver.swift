import Darwin
import Foundation

@MainActor
protocol RecentScreenshotObserving: AnyObject {
    var onChange: ((RecentScreenshotObservationEvent) -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
final class RecentScreenshotDirectoryObserver: RecentScreenshotObserving {
    var onChange: ((RecentScreenshotObservationEvent) -> Void)?

    private let authorizedDirectoryProvider: () -> URL?
    private let systemDirectoryProvider: () -> URL?
    private let notificationCenter: NotificationCenter

    private var authorizedDirectoryURL: URL?
    private var isAccessingAuthorizedDirectory = false
    private var authorizedDirectoryWatcher: RecentScreenshotFileWatcher?
    private var systemDirectoryURL: URL?
    private var isAccessingSystemDirectory = false
    private var systemDirectoryWatcher: RecentScreenshotFileWatcher?
    private var directoryDidChangeObserver: NSObjectProtocol?

    init(
        authorizedDirectoryProvider: @escaping () -> URL? = {
            ScreenshotDirectoryResolver.authorizedDirectoryURLForMonitoring()?.standardizedFileURL
        },
        systemDirectoryProvider: @escaping () -> URL? = {
            ScreenshotDirectoryResolver.resolvedSystemScreenshotDirectory()?.standardizedFileURL
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.authorizedDirectoryProvider = authorizedDirectoryProvider
        self.systemDirectoryProvider = systemDirectoryProvider
        self.notificationCenter = notificationCenter
    }

    func start() {
        if directoryDidChangeObserver == nil {
            directoryDidChangeObserver = notificationCenter.addObserver(
                forName: ScreenshotDirectoryResolver.authorizedDirectoryDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAuthorizedDirectoryConfigurationChange()
                }
            }
        }

        refreshDirectoryWatchers(force: true)
    }

    func stop() {
        authorizedDirectoryWatcher = nil
        systemDirectoryWatcher = nil

        if isAccessingAuthorizedDirectory, let authorizedDirectoryURL {
            authorizedDirectoryURL.stopAccessingSecurityScopedResource()
        }

        if isAccessingSystemDirectory, let systemDirectoryURL {
            systemDirectoryURL.stopAccessingSecurityScopedResource()
        }

        if let directoryDidChangeObserver {
            notificationCenter.removeObserver(directoryDidChangeObserver)
        }

        directoryDidChangeObserver = nil
        authorizedDirectoryURL = nil
        isAccessingAuthorizedDirectory = false
        systemDirectoryURL = nil
        isAccessingSystemDirectory = false
    }

    private func refreshDirectoryWatchers(force: Bool = false) {
        let nextDirectoryURL = authorizedDirectoryProvider()?.standardizedFileURL
        let nextSystemDirectoryURL = systemDirectoryProvider()?.standardizedFileURL
        let distinctSystemDirectoryURL = nextSystemDirectoryURL == nextDirectoryURL ? nil : nextSystemDirectoryURL

        refreshWatcher(
            currentDirectoryURL: &authorizedDirectoryURL,
            isAccessingDirectory: &isAccessingAuthorizedDirectory,
            watcher: &authorizedDirectoryWatcher,
            nextDirectoryURL: nextDirectoryURL,
            force: force
        )
        refreshWatcher(
            currentDirectoryURL: &systemDirectoryURL,
            isAccessingDirectory: &isAccessingSystemDirectory,
            watcher: &systemDirectoryWatcher,
            nextDirectoryURL: distinctSystemDirectoryURL,
            force: force
        )
    }

    private func refreshWatcher(
        currentDirectoryURL: inout URL?,
        isAccessingDirectory: inout Bool,
        watcher: inout RecentScreenshotFileWatcher?,
        nextDirectoryURL: URL?,
        force: Bool
    ) {
        guard force || nextDirectoryURL != currentDirectoryURL else {
            return
        }

        watcher = nil

        if isAccessingDirectory, let currentDirectoryURL {
            currentDirectoryURL.stopAccessingSecurityScopedResource()
        }

        currentDirectoryURL = nextDirectoryURL
        isAccessingDirectory = false

        guard let nextDirectoryURL else {
            return
        }

        isAccessingDirectory = nextDirectoryURL.startAccessingSecurityScopedResource()
        watcher = RecentScreenshotFileWatcher(url: nextDirectoryURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshDirectoryWatchers()
                self?.onChange?(.authorizedDirectoryContentsChanged)
            }
        }
    }

    private func handleAuthorizedDirectoryConfigurationChange() {
        refreshDirectoryWatchers(force: true)
        onChange?(.authorizedDirectoryConfigurationChanged)
    }
}

private final class RecentScreenshotFileWatcher {
    let watchedURL: URL

    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?

    init?(url: URL, onEvent: @escaping @Sendable () -> Void) {
        let standardizedURL = url.standardizedFileURL
        let fileDescriptor = open(standardizedURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return nil
        }

        self.watchedURL = standardizedURL
        self.fileDescriptor = fileDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler(handler: onEvent)
        source.setCancelHandler { [fileDescriptor] in
            close(fileDescriptor)
        }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
