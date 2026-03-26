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
    var onImageDetected: (() -> Void)? { get set }
    func start()
    func stop()
    func setMonitoringActive(_ isActive: Bool)
    func refreshNow()
    func recentImage(referenceDate: Date, maxAge: TimeInterval) -> RecentClipboardImage?
    func consumeCurrent()
    func dismissCurrent()
}

extension RecentClipboardImageProviding {
    func setMonitoringActive(_ isActive: Bool) {}
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

    var onImageDetected: (() -> Void)?
    private var currentImage: RecentClipboardImage?
    private var lastObservedChangeCount: Int?
    private var ignoredChangeCounts: [Int: Date] = [:]
    private var pollingTimer: Timer?
    private var isStarted = false
    private var isMonitoringActive = false

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
        updatePollingTimerState()
    }

    func stop() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isStarted = false
        isMonitoringActive = false

        clearCurrentImageCache()
        currentImage = nil
        lastObservedChangeCount = nil
        ignoredChangeCounts.removeAll()
    }

    func setMonitoringActive(_ isActive: Bool) {
        guard isMonitoringActive != isActive else {
            return
        }

        isMonitoringActive = isActive
        if isActive, lastObservedChangeCount == nil {
            lastObservedChangeCount = pasteboard.changeCount
        }
        updatePollingTimerState()
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
        if isMonitoringActive {
            refreshNow()
        }

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
            if currentImage != nil {
                // Keep the cached image alive — another app may have overwritten
                // the pasteboard, but the capture panel still references our file.
            }
            // Do not clear currentImage or its cache; it will be cleaned up
            // when consumeCurrent() or dismissCurrent() is called.
            return
        }

        // New image arrived — replace the previous cache

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
        onImageDetected?()
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

    private func updatePollingTimerState() {
        guard isStarted, isMonitoringActive, pollInterval > 0 else {
            pollingTimer?.invalidate()
            pollingTimer = nil
            return
        }

        guard pollingTimer == nil else {
            return
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, self.isMonitoringActive else {
                    timer.invalidate()
                    return
                }

                self.refreshNow()
            }
        }
    }
}

private struct ClipboardImagePayload {
    let data: Data
    let pathExtension: String
}
