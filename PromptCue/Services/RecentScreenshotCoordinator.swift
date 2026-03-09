import Foundation

@MainActor
final class RecentScreenshotCoordinator: RecentScreenshotCoordinating {
    var onStateChange: ((RecentScreenshotState) -> Void)?

    private(set) var state: RecentScreenshotState = .idle {
        didSet {
            guard state != oldValue else {
                return
            }

            onStateChange?(state)
        }
    }

    private let observer: RecentScreenshotObserving
    private let locator: RecentScreenshotLocating
    private let cache: TransientScreenshotCaching
    private let clipboardProvider: RecentClipboardImageProviding
    private let maxAge: TimeInterval
    private let settleGrace: TimeInterval
    private let now: () -> Date

    private var currentSession: RecentScreenshotSession?
    private var ignoredSourceKeys: [String: Date] = [:]
    private var settleTimer: Timer?
    private var settleDeadline: Date?
    private var expirationTimer: Timer?
    private var isStarted = false

    init(
        observer: RecentScreenshotObserving? = nil,
        locator: RecentScreenshotLocating = RecentScreenshotLocator(),
        cache: TransientScreenshotCaching = TransientScreenshotCache(),
        clipboardProvider: RecentClipboardImageProviding? = nil,
        maxAge: TimeInterval = AppTiming.recentScreenshotMaxAge,
        settleGrace: TimeInterval = AppTiming.recentScreenshotPlaceholderGrace,
        now: @escaping () -> Date = Date.init
    ) {
        self.observer = observer ?? RecentScreenshotDirectoryObserver()
        self.locator = locator
        self.cache = cache
        self.clipboardProvider = clipboardProvider ?? RecentClipboardImageMonitor(cache: cache)
        self.maxAge = maxAge
        self.settleGrace = settleGrace
        self.now = now
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        observer.onChange = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleObserverChange(event)
            }
        }

        try? cache.clear()
        clipboardProvider.start()
        observer.start()
        refreshState()
    }

    func stop() {
        guard isStarted else {
            return
        }

        observer.onChange = nil
        observer.stop()
        clipboardProvider.stop()
        isStarted = false

        settleTimer?.invalidate()
        settleTimer = nil
        settleDeadline = nil
        expirationTimer?.invalidate()
        expirationTimer = nil

        clearCurrentSessionCache()
        currentSession = nil
        ignoredSourceKeys.removeAll()
        state = .idle
    }

    func prepareForCaptureSession() {
        clipboardProvider.refreshNow()
        refreshNow()
        scheduleSettlePolling()
    }

    func refreshNow() {
        refreshState()
    }

    func resolveCurrentCaptureAttachment(timeout: TimeInterval) async -> URL? {
        if case .previewReady(_, let cacheURL, _) = state {
            return cacheURL
        }

        guard timeout > 0 else {
            refreshState()
            if case .previewReady(_, let cacheURL, _) = state {
                return cacheURL
            }
            return nil
        }

        let deadline = now().addingTimeInterval(timeout)

        while now() < deadline {
            refreshState()

            if case .previewReady(_, let cacheURL, _) = state {
                return cacheURL
            }

            guard state.showsCaptureSlot else {
                return nil
            }

            let remaining = deadline.timeIntervalSince(now())
            guard remaining > 0 else {
                break
            }

            let sleepInterval = min(remaining, 0.05)
            try? await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
        }

        refreshState()
        if case .previewReady(_, let cacheURL, _) = state {
            return cacheURL
        }

        return nil
    }

    func consumeCurrent() {
        guard let currentSession else {
            return
        }

        if currentSession.sourceKey?.hasPrefix("clipboard:") == true {
            clipboardProvider.consumeCurrent()
        }
        rememberIgnoredSourceKey(currentSession.sourceKey)
        clearCurrentSessionCache()
        self.currentSession = nil
        invalidateTimers()
        state = .consumed(sessionID: currentSession.id)
    }

    func dismissCurrent() {
        if let currentSession {
            if currentSession.sourceKey?.hasPrefix("clipboard:") == true {
                clipboardProvider.dismissCurrent()
            }
            rememberIgnoredSourceKey(currentSession.sourceKey)
        }

        clearCurrentSessionCache()
        currentSession = nil
        invalidateTimers()
        refreshState()
    }

    private func handleObserverChange(_ event: RecentScreenshotObservationEvent) {
        if event.impliesImmediateScreenshotSignal {
            ensurePendingDetection(referenceDate: now())
        }

        refreshState()
        scheduleSettlePolling()
    }

    private func refreshState() {
        let referenceDate = now()
        purgeIgnoredSourceKeys(referenceDate: referenceDate)

        if let currentSession, referenceDate >= currentSession.expiresAt {
            expireCurrentSession(currentSession)
            return
        }

        if let clipboardImage = clipboardProvider.recentImage(referenceDate: referenceDate, maxAge: maxAge) {
            let session = ensureClipboardSession(for: clipboardImage, referenceDate: referenceDate)
            state = .previewReady(
                sessionID: session.id,
                cacheURL: clipboardImage.cacheURL,
                thumbnailState: .ready
            )
            scheduleExpirationIfNeeded(for: session, referenceDate: referenceDate)
            return
        }

        let scanResult = locator.locateRecentScreenshot(now: referenceDate, maxAge: maxAge)
        let signalCandidate = filteredCandidate(scanResult.signalCandidate, referenceDate: referenceDate)
        let readableCandidate = filteredCandidate(scanResult.readableCandidate, referenceDate: referenceDate)

        if signalCandidate == nil,
           readableCandidate == nil,
           let recentTemporaryContainerDate = scanResult.recentTemporaryContainerDate {
            ensurePendingDetection(referenceDate: recentTemporaryContainerDate)
        }

        if let signalCandidate {
            let session = ensureSession(for: signalCandidate, referenceDate: referenceDate)

            if let readableCandidate, readableCandidate.sourceKey == session.sourceKey {
                updatePreviewIfNeeded(using: readableCandidate, session: session, referenceDate: referenceDate)
            } else {
                state = .detected(sessionID: session.id, detectedAt: session.detectedAt)
            }

            scheduleExpirationIfNeeded(for: session, referenceDate: referenceDate)
            return
        }

        guard let currentSession else {
            state = .idle
            invalidateExpirationTimer()
            return
        }

        scheduleExpirationIfNeeded(for: currentSession, referenceDate: referenceDate)
        if let cacheURL = currentSession.cacheURL {
            state = .previewReady(
                sessionID: currentSession.id,
                cacheURL: cacheURL,
                thumbnailState: .ready
            )
        } else {
            state = .detected(sessionID: currentSession.id, detectedAt: currentSession.detectedAt)
        }
    }

    private func ensureClipboardSession(
        for clipboardImage: RecentClipboardImage,
        referenceDate: Date
    ) -> RecentScreenshotSession {
        if var currentSession,
           currentSession.sourceKey == clipboardImage.sourceKey || currentSession.sourceKey == nil {
            currentSession.sourceKey = clipboardImage.sourceKey
            currentSession.latestIdentityKey = clipboardImage.identityKey
            currentSession.expiresAt = clipboardImage.detectedAt.addingTimeInterval(maxAge)
            currentSession.cacheURL = clipboardImage.cacheURL
            self.currentSession = currentSession
            return currentSession
        }

        clearCurrentSessionCache()
        invalidateExpirationTimer()

        let session = RecentScreenshotSession(
            id: UUID(),
            sourceKey: clipboardImage.sourceKey,
            latestIdentityKey: clipboardImage.identityKey,
            detectedAt: referenceDate,
            expiresAt: clipboardImage.detectedAt.addingTimeInterval(maxAge),
            cacheURL: clipboardImage.cacheURL
        )

        currentSession = session
        return session
    }

    private func filteredCandidate(
        _ candidate: RecentScreenshotCandidate?,
        referenceDate: Date
    ) -> RecentScreenshotCandidate? {
        guard let candidate else {
            return nil
        }

        guard ignoredSourceKeys[candidate.sourceKey, default: .distantPast] <= referenceDate else {
            return nil
        }

        return candidate
    }

    private func ensureSession(
        for candidate: RecentScreenshotCandidate,
        referenceDate: Date
    ) -> RecentScreenshotSession {
        if var currentSession,
           currentSession.sourceKey == candidate.sourceKey || currentSession.sourceKey == nil {
            currentSession.sourceKey = candidate.sourceKey
            currentSession.latestIdentityKey = candidate.identityKey
            currentSession.expiresAt = candidateExpirationDate(candidate, referenceDate: referenceDate)
            self.currentSession = currentSession
            return currentSession
        }

        clearCurrentSessionCache()
        invalidateExpirationTimer()

        let session = RecentScreenshotSession(
            id: UUID(),
            sourceKey: candidate.sourceKey,
            latestIdentityKey: candidate.identityKey,
            detectedAt: referenceDate,
            expiresAt: candidateExpirationDate(candidate, referenceDate: referenceDate),
            cacheURL: nil
        )

        currentSession = session
        state = .detected(sessionID: session.id, detectedAt: session.detectedAt)
        return session
    }

    private func updatePreviewIfNeeded(
        using candidate: RecentScreenshotCandidate,
        session: RecentScreenshotSession,
        referenceDate: Date
    ) {
        var nextSession = session
        nextSession.latestIdentityKey = candidate.identityKey
        nextSession.expiresAt = candidateExpirationDate(candidate, referenceDate: referenceDate)

        if nextSession.cacheURL == nil || session.latestIdentityKey != candidate.identityKey {
            let sourceURL = candidate.fileURL
            let cacheURL = try? ScreenshotDirectoryResolver.withAccessIfNeeded(to: sourceURL) { readableURL in
                try cache.cacheScreenshot(from: readableURL, sessionID: session.id)
            }
            nextSession.cacheURL = cacheURL
        }

        currentSession = nextSession

        guard let cacheURL = nextSession.cacheURL else {
            state = .detected(sessionID: nextSession.id, detectedAt: nextSession.detectedAt)
            return
        }

        state = .previewReady(
            sessionID: nextSession.id,
            cacheURL: cacheURL,
            thumbnailState: .ready
        )
    }

    private func ensurePendingDetection(referenceDate: Date) {
        if var currentSession {
            guard currentSession.cacheURL == nil else {
                return
            }

            if currentSession.sourceKey == nil {
                currentSession.expiresAt = referenceDate.addingTimeInterval(settleGrace)
                self.currentSession = currentSession
                state = .detected(sessionID: currentSession.id, detectedAt: currentSession.detectedAt)
            }

            return
        }

        let session = RecentScreenshotSession(
            id: UUID(),
            sourceKey: nil,
            latestIdentityKey: nil,
            detectedAt: referenceDate,
            expiresAt: referenceDate.addingTimeInterval(settleGrace),
            cacheURL: nil
        )

        currentSession = session
        state = .detected(sessionID: session.id, detectedAt: session.detectedAt)
    }

    private func candidateExpirationDate(
        _ candidate: RecentScreenshotCandidate,
        referenceDate: Date
    ) -> Date {
        let baseDate = candidate.attachment.modifiedAt ?? referenceDate
        return baseDate.addingTimeInterval(maxAge)
    }

    private func scheduleSettlePolling() {
        guard settleGrace > 0 else {
            return
        }

        settleDeadline = now().addingTimeInterval(settleGrace)

        guard settleTimer == nil else {
            return
        }

        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else {
                    timer.invalidate()
                    return
                }

                self.refreshState()

                let referenceDate = self.now()
                let shouldStop = (self.settleDeadline.map { referenceDate >= $0 } ?? true)
                    || self.currentSession?.cacheURL != nil

                if shouldStop {
                    timer.invalidate()
                    self.settleTimer = nil
                    self.settleDeadline = nil
                }
            }
        }
    }

    private func scheduleExpirationIfNeeded(
        for session: RecentScreenshotSession,
        referenceDate: Date
    ) {
        if referenceDate >= session.expiresAt {
            expireCurrentSession(session)
            return
        }

        let interval = session.expiresAt.timeIntervalSince(referenceDate)
        let currentFireDate = expirationTimer?.fireDate
        if let currentFireDate,
           abs(currentFireDate.timeIntervalSince(session.expiresAt)) < 0.05 {
            return
        }

        invalidateExpirationTimer()
        expirationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else {
                    return
                }
                self.expireCurrentSessionIfNeeded()
            }
        }
    }

    private func expireCurrentSessionIfNeeded() {
        guard let currentSession else {
            state = .idle
            return
        }

        guard now() >= currentSession.expiresAt else {
            scheduleExpirationIfNeeded(for: currentSession, referenceDate: now())
            return
        }

        expireCurrentSession(currentSession)
    }

    private func expireCurrentSession(_ session: RecentScreenshotSession) {
        clearCurrentSessionCache()
        currentSession = nil
        invalidateTimers()
        state = .expired(sessionID: session.id)
    }

    private func rememberIgnoredSourceKey(_ sourceKey: String?) {
        guard let sourceKey else {
            return
        }

        ignoredSourceKeys[sourceKey] = now().addingTimeInterval(maxAge)
    }

    private func purgeIgnoredSourceKeys(referenceDate: Date) {
        ignoredSourceKeys = ignoredSourceKeys.filter { _, expirationDate in
            expirationDate > referenceDate
        }
    }

    private func clearCurrentSessionCache() {
        guard let cacheURL = currentSession?.cacheURL else {
            return
        }

        try? cache.removeCachedFile(at: cacheURL)
    }

    private func invalidateTimers() {
        settleTimer?.invalidate()
        settleTimer = nil
        settleDeadline = nil
        invalidateExpirationTimer()
    }

    private func invalidateExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = nil
    }
}

private struct RecentScreenshotSession {
    let id: UUID
    var sourceKey: String?
    var latestIdentityKey: String?
    let detectedAt: Date
    var expiresAt: Date
    var cacheURL: URL?
}
