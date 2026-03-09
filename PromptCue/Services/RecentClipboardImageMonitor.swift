import AppKit
import Foundation

struct RecentClipboardImage: Equatable {
    let changeCount: Int
    let detectedAt: Date
    let cacheURL: URL

    var sourceKey: String {
        "clipboard:\(changeCount)"
    }

    var identityKey: String {
        sourceKey
    }
}

@MainActor
protocol RecentClipboardImageProviding: AnyObject {
    func start()
    func stop()
    func refreshNow()
    func recentImage(referenceDate: Date, maxAge: TimeInterval) -> RecentClipboardImage?
    func consumeCurrent()
    func dismissCurrent()
}

protocol ClipboardPasteboardReading {
    var changeCount: Int { get }
    func data(for type: NSPasteboard.PasteboardType) -> Data?
}

struct SystemClipboardPasteboard: ClipboardPasteboardReading {
    var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        NSPasteboard.general.data(forType: type)
    }
}

@MainActor
final class RecentClipboardImageMonitor: RecentClipboardImageProviding {
    private let pasteboard: ClipboardPasteboardReading
    private let cache: TransientScreenshotCaching
    private let now: () -> Date
    private let pollInterval: TimeInterval

    private var currentImage: RecentClipboardImage?
    private var lastObservedChangeCount: Int?
    private var ignoredChangeCounts: [Int: Date] = [:]
    private var pollingTimer: Timer?
    private var isStarted = false

    init(
        pasteboard: ClipboardPasteboardReading = SystemClipboardPasteboard(),
        cache: TransientScreenshotCaching = TransientScreenshotCache(),
        now: @escaping () -> Date = Date.init,
        pollInterval: TimeInterval = 0.25
    ) {
        self.pasteboard = pasteboard
        self.cache = cache
        self.now = now
        self.pollInterval = pollInterval
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        lastObservedChangeCount = pasteboard.changeCount

        guard pollInterval > 0 else {
            return
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }

                self.refreshNow()
            }
        }
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isStarted = false

        clearCurrentImageCache()
        currentImage = nil
        lastObservedChangeCount = nil
        ignoredChangeCounts.removeAll()
    }

    func refreshNow() {
        let currentChangeCount = pasteboard.changeCount
        guard let lastObservedChangeCount else {
            self.lastObservedChangeCount = currentChangeCount
            return
        }

        guard currentChangeCount != lastObservedChangeCount else {
            return
        }

        self.lastObservedChangeCount = currentChangeCount
        processCurrentPasteboard(changeCount: currentChangeCount)
    }

    func recentImage(referenceDate: Date, maxAge: TimeInterval) -> RecentClipboardImage? {
        purgeIgnoredChangeCounts(referenceDate: referenceDate)
        refreshNow()

        guard let currentImage else {
            return nil
        }

        guard ignoredChangeCounts[currentImage.changeCount, default: .distantPast] <= referenceDate else {
            return nil
        }

        guard referenceDate.timeIntervalSince(currentImage.detectedAt) <= maxAge else {
            return nil
        }

        return currentImage
    }

    func consumeCurrent() {
        suppressCurrentImage()
    }

    func dismissCurrent() {
        suppressCurrentImage()
    }

    private func suppressCurrentImage() {
        guard let currentImage else {
            return
        }

        ignoredChangeCounts[currentImage.changeCount] = now().addingTimeInterval(60 * 60)
        clearCurrentImageCache()
        self.currentImage = nil
    }

    private func processCurrentPasteboard(changeCount: Int) {
        guard let payload = imagePayload() else {
            clearCurrentImageCache()
            currentImage = nil
            return
        }

        let sessionID = UUID()
        guard let cacheURL = try? cache.cacheImageData(
            payload.data,
            sessionID: sessionID,
            pathExtension: payload.pathExtension
        ) else {
            clearCurrentImageCache()
            currentImage = nil
            return
        }

        clearCurrentImageCache()
        currentImage = RecentClipboardImage(
            changeCount: changeCount,
            detectedAt: now(),
            cacheURL: cacheURL
        )
    }

    private func imagePayload() -> ClipboardImagePayload? {
        if let pngData = pasteboard.data(for: .png), !pngData.isEmpty {
            return ClipboardImagePayload(data: pngData, pathExtension: "png")
        }

        if let tiffData = pasteboard.data(for: .tiff), !tiffData.isEmpty {
            return ClipboardImagePayload(data: tiffData, pathExtension: "tiff")
        }

        return nil
    }

    private func purgeIgnoredChangeCounts(referenceDate: Date) {
        ignoredChangeCounts = ignoredChangeCounts.filter { _, expirationDate in
            expirationDate > referenceDate
        }
    }

    private func clearCurrentImageCache() {
        guard let cacheURL = currentImage?.cacheURL else {
            return
        }

        try? cache.removeCachedFile(at: cacheURL)
    }
}

private struct ClipboardImagePayload {
    let data: Data
    let pathExtension: String
}
