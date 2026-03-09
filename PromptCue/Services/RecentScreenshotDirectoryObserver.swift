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

    private let fileManager: FileManager
    private let authorizedDirectoryProvider: () -> URL?
    private let temporaryItemsDirectoryProvider: () -> URL

    private var authorizedDirectoryURL: URL?
    private var isAccessingAuthorizedDirectory = false
    private var authorizedDirectoryWatcher: RecentScreenshotFileWatcher?
    private var temporaryItemsWatcher: RecentScreenshotFileWatcher?
    private var temporaryItemsChildWatchers: [URL: RecentScreenshotFileWatcher] = [:]

    init(
        fileManager: FileManager = .default,
        authorizedDirectoryProvider: @escaping () -> URL? = {
            ScreenshotDirectoryResolver.authorizedDirectoryURLForMonitoring()?.standardizedFileURL
        },
        temporaryItemsDirectoryProvider: @escaping () -> URL = {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("TemporaryItems", isDirectory: true)
                .standardizedFileURL
        }
    ) {
        self.fileManager = fileManager
        self.authorizedDirectoryProvider = authorizedDirectoryProvider
        self.temporaryItemsDirectoryProvider = temporaryItemsDirectoryProvider
    }

    func start() {
        refreshAuthorizedDirectoryWatcher(force: true)
        refreshTemporaryItemsWatcher(force: true)
        refreshTemporaryItemsChildWatchers()
    }

    func stop() {
        authorizedDirectoryWatcher = nil
        temporaryItemsWatcher = nil
        temporaryItemsChildWatchers.removeAll()

        if isAccessingAuthorizedDirectory, let authorizedDirectoryURL {
            authorizedDirectoryURL.stopAccessingSecurityScopedResource()
        }

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
                self?.onChange?(.authorizedDirectoryChanged)
            }
        }
    }

    private func refreshTemporaryItemsWatcher(force: Bool = false) {
        let temporaryItemsDirectoryURL = temporaryItemsDirectoryProvider().standardizedFileURL

        guard force || temporaryItemsWatcher?.watchedURL != temporaryItemsDirectoryURL else {
            return
        }

        temporaryItemsWatcher = nil

        guard fileManager.fileExists(atPath: temporaryItemsDirectoryURL.path) else {
            temporaryItemsChildWatchers.removeAll()
            return
        }

        temporaryItemsWatcher = RecentScreenshotFileWatcher(url: temporaryItemsDirectoryURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshTemporaryItemsWatcher()
                let addedChildDirectories = self?.refreshTemporaryItemsChildWatchers() ?? []
                if addedChildDirectories.isEmpty {
                    self?.onChange?(.temporaryItemsChanged)
                } else {
                    self?.onChange?(.temporaryScreenshotContainerDetected)
                }
            }
        }
    }

    @discardableResult
    private func refreshTemporaryItemsChildWatchers() -> Set<URL> {
        let temporaryItemsDirectoryURL = temporaryItemsDirectoryProvider().standardizedFileURL

        guard fileManager.fileExists(atPath: temporaryItemsDirectoryURL.path) else {
            temporaryItemsChildWatchers.removeAll()
            return []
        }

        let contents = (try? fileManager.contentsOfDirectory(
            at: temporaryItemsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        let childDirectories = Set(contents.compactMap { itemURL -> URL? in
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true,
                  itemURL.lastPathComponent.hasPrefix("NSIRD_screencaptureui") else {
                return nil
            }

            return itemURL.standardizedFileURL
        })

        for watchedURL in temporaryItemsChildWatchers.keys where !childDirectories.contains(watchedURL) {
            temporaryItemsChildWatchers.removeValue(forKey: watchedURL)
        }

        let existingChildDirectories = Set(temporaryItemsChildWatchers.keys)
        let addedChildDirectories = childDirectories.subtracting(existingChildDirectories)

        for childDirectoryURL in addedChildDirectories {
            temporaryItemsChildWatchers[childDirectoryURL] = RecentScreenshotFileWatcher(
                url: childDirectoryURL
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    _ = self?.refreshTemporaryItemsChildWatchers()
                    self?.onChange?(.temporaryScreenshotContainerChanged)
                }
            }
        }

        return addedChildDirectories
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
