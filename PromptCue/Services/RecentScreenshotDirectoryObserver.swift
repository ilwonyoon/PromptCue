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
    private let notificationCenter: NotificationCenter

    private var authorizedDirectoryURL: URL?
    private var isAccessingAuthorizedDirectory = false
    private var authorizedDirectoryWatcher: RecentScreenshotFileWatcher?
    private var directoryDidChangeObserver: NSObjectProtocol?

    init(
        authorizedDirectoryProvider: @escaping () -> URL? = {
            ScreenshotDirectoryResolver.authorizedDirectoryURLForMonitoring()?.standardizedFileURL
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.authorizedDirectoryProvider = authorizedDirectoryProvider
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

        refreshAuthorizedDirectoryWatcher(force: true)
    }

    func stop() {
        authorizedDirectoryWatcher = nil

        if isAccessingAuthorizedDirectory, let authorizedDirectoryURL {
            authorizedDirectoryURL.stopAccessingSecurityScopedResource()
        }

        if let directoryDidChangeObserver {
            notificationCenter.removeObserver(directoryDidChangeObserver)
        }

        directoryDidChangeObserver = nil
        authorizedDirectoryURL = nil
        isAccessingAuthorizedDirectory = false
    }

    private func refreshAuthorizedDirectoryWatcher(force: Bool = false) {
        let nextDirectoryURL = authorizedDirectoryProvider()?.standardizedFileURL

        guard force || nextDirectoryURL != authorizedDirectoryURL else {
            return
        }

        authorizedDirectoryWatcher = nil

        if isAccessingAuthorizedDirectory, let authorizedDirectoryURL {
            authorizedDirectoryURL.stopAccessingSecurityScopedResource()
        }

        authorizedDirectoryURL = nextDirectoryURL
        isAccessingAuthorizedDirectory = false

        guard let nextDirectoryURL else {
            return
        }

        isAccessingAuthorizedDirectory = nextDirectoryURL.startAccessingSecurityScopedResource()
        authorizedDirectoryWatcher = RecentScreenshotFileWatcher(url: nextDirectoryURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAuthorizedDirectoryWatcher()
                self?.onChange?(.authorizedDirectoryContentsChanged)
            }
        }
    }

    private func handleAuthorizedDirectoryConfigurationChange() {
        refreshAuthorizedDirectoryWatcher(force: true)
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
