import Foundation
import PromptCueCore
import UniformTypeIdentifiers

struct RecentScreenshotScanResult: Equatable, Sendable {
    let signalCandidate: RecentScreenshotCandidate?
    let readableCandidate: RecentScreenshotCandidate?
    let recentTemporaryContainerDate: Date?

    init(
        signalCandidate: RecentScreenshotCandidate?,
        readableCandidate: RecentScreenshotCandidate?,
        recentTemporaryContainerDate: Date? = nil
    ) {
        self.signalCandidate = signalCandidate
        self.readableCandidate = readableCandidate
        self.recentTemporaryContainerDate = recentTemporaryContainerDate
    }
}

struct RecentScreenshotCandidate: Equatable, Sendable {
    let attachment: ScreenshotAttachment
    let sourceKey: String

    var identityKey: String {
        attachment.identityKey
    }

    var fileURL: URL {
        URL(fileURLWithPath: attachment.path).standardizedFileURL
    }

    var modifiedAt: Date {
        attachment.modifiedAt ?? .distantPast
    }
}

protocol RecentScreenshotLocating {
    func locateRecentScreenshot(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult
    func locateRecentScreenshotSignal(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult
}

extension RecentScreenshotLocating {
    func locateRecentScreenshotSignal(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        let scanResult = locateRecentScreenshot(now: now, maxAge: maxAge)
        return RecentScreenshotScanResult(
            signalCandidate: scanResult.signalCandidate,
            readableCandidate: nil,
            recentTemporaryContainerDate: scanResult.recentTemporaryContainerDate
        )
    }
}

struct RecentScreenshotLocator: RecentScreenshotLocating {
    private let fileManager: FileManager
    private let authorizedDirectoryProvider: () -> URL?
    private let temporaryItemsDirectoryProvider: () -> URL
    private let includeTemporaryItemsScanning: Bool

    init(
        fileManager: FileManager = .default,
        authorizedDirectoryProvider: @escaping () -> URL? = {
            ScreenshotDirectoryResolver.authorizedDirectoryURLForMonitoring()?.standardizedFileURL
        },
        temporaryItemsDirectoryProvider: @escaping () -> URL = {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("TemporaryItems", isDirectory: true)
                .standardizedFileURL
        },
        includeTemporaryItemsScanning: Bool = false
    ) {
        self.fileManager = fileManager
        self.authorizedDirectoryProvider = authorizedDirectoryProvider
        self.temporaryItemsDirectoryProvider = temporaryItemsDirectoryProvider
        self.includeTemporaryItemsScanning = includeTemporaryItemsScanning
    }

    func locateRecentScreenshot(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        locateRecentScreenshot(now: now, maxAge: maxAge, includeReadableCandidates: true)
    }

    func locateRecentScreenshotSignal(now: Date, maxAge: TimeInterval) -> RecentScreenshotScanResult {
        locateRecentScreenshot(now: now, maxAge: maxAge, includeReadableCandidates: false)
    }

    private func locateRecentScreenshot(
        now: Date,
        maxAge: TimeInterval,
        includeReadableCandidates: Bool
    ) -> RecentScreenshotScanResult {
        let minimumDate = now.addingTimeInterval(-maxAge)
        var signalCandidates: [ScreenshotMatch] = []
        var readableCandidates: [ScreenshotMatch] = []
        var recentTemporaryContainerDate: Date?

        if let authorizedDirectoryURL = authorizedDirectoryProvider()?.standardizedFileURL {
            if let signalMatch = newestScreenshot(
                in: authorizedDirectoryURL,
                minimumDate: minimumDate,
                requireReadableContents: false
            ) {
                signalCandidates.append(signalMatch)
            }

            if includeReadableCandidates,
               let readableMatch = newestScreenshot(
                in: authorizedDirectoryURL,
                minimumDate: minimumDate,
                requireReadableContents: true
               ) {
                readableCandidates.append(readableMatch)
            }
        }

        if includeTemporaryItemsScanning {
            let temporaryScan = newestTemporaryScreenshotMatches(
                minimumDate: minimumDate,
                includeReadableCandidates: includeReadableCandidates
            )
            recentTemporaryContainerDate = temporaryScan.recentContainerDate

            if let signalMatch = temporaryScan.signalMatch {
                signalCandidates.append(signalMatch)
            }

            if let readableMatch = temporaryScan.readableMatch {
                readableCandidates.append(readableMatch)
            }
        }

        return RecentScreenshotScanResult(
            signalCandidate: bestMatch(signalCandidates).map(makeCandidate(from:)),
            readableCandidate: bestMatch(readableCandidates).map(makeCandidate(from:)),
            recentTemporaryContainerDate: recentTemporaryContainerDate
        )
    }

    private func makeCandidate(from match: ScreenshotMatch) -> RecentScreenshotCandidate {
        RecentScreenshotCandidate(
            attachment: ScreenshotAttachment(
                path: match.url.path,
                modifiedAt: match.date,
                fileSize: match.fileSize
            ),
            sourceKey: canonicalSourceKey(for: match.url)
        )
    }

    private func canonicalSourceKey(for url: URL) -> String {
        let filename = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filename.isEmpty {
            return filename.lowercased()
        }

        return url.standardizedFileURL.path.lowercased()
    }

    private func newestScreenshot(
        in directoryURL: URL,
        minimumDate: Date,
        requireReadableContents: Bool
    ) -> ScreenshotMatch? {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
                .isReadableKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        return contents
            .compactMap {
                screenshotMatch(
                    for: $0,
                    minimumDate: minimumDate,
                    requireReadableContents: requireReadableContents
                )
            }
            .max(by: isLowerPriorityMatch)
    }

    private func newestTemporaryScreenshotMatches(
        minimumDate: Date,
        includeReadableCandidates: Bool
    ) -> TemporaryScreenshotScanResult {
        let temporaryItemsURL = temporaryItemsDirectoryProvider().standardizedFileURL

        guard let rootContents = try? fileManager.contentsOfDirectory(
            at: temporaryItemsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return TemporaryScreenshotScanResult(
                signalMatch: nil,
                readableMatch: nil,
                recentContainerDate: nil
            )
        }

        var signalCandidates: [ScreenshotMatch] = []
        var readableCandidates: [ScreenshotMatch] = []
        var recentContainerDate: Date?

        for itemURL in rootContents {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues?.isDirectory == true,
               itemURL.lastPathComponent.hasPrefix("NSIRD_screencaptureui")
            {
                if let containerDate = resourceDate(for: itemURL), containerDate >= minimumDate {
                    recentContainerDate = max(recentContainerDate ?? .distantPast, containerDate)
                }

                if let nestedContents = try? fileManager.contentsOfDirectory(
                    at: itemURL,
                    includingPropertiesForKeys: [
                        .creationDateKey,
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .isRegularFileKey,
                        .isReadableKey,
                    ],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    signalCandidates.append(
                        contentsOf: nestedContents.compactMap {
                            screenshotMatch(
                                for: $0,
                                minimumDate: minimumDate,
                                requireReadableContents: false
                            )
                        }
                    )
                    if includeReadableCandidates {
                        readableCandidates.append(
                            contentsOf: nestedContents.compactMap {
                                screenshotMatch(
                                    for: $0,
                                    minimumDate: minimumDate,
                                    requireReadableContents: true
                                )
                            }
                        )
                    }
                }

                continue
            }

            if let signalMatch = screenshotMatch(
                for: itemURL,
                minimumDate: minimumDate,
                requireReadableContents: false
            ) {
                signalCandidates.append(signalMatch)
            }

            if includeReadableCandidates,
               let readableMatch = screenshotMatch(
                for: itemURL,
                minimumDate: minimumDate,
                requireReadableContents: true
               ) {
                readableCandidates.append(readableMatch)
            }
        }

        return TemporaryScreenshotScanResult(
            signalMatch: bestMatch(signalCandidates),
            readableMatch: bestMatch(readableCandidates),
            recentContainerDate: recentContainerDate
        )
    }

    private func bestMatch(_ candidates: [ScreenshotMatch]) -> ScreenshotMatch? {
        candidates.max(by: isLowerPriorityMatch)
    }

    private func isLowerPriorityMatch(_ left: ScreenshotMatch, _ right: ScreenshotMatch) -> Bool {
        if left.matchScore == right.matchScore {
            return left.date < right.date
        }

        return left.matchScore < right.matchScore
    }

    private func screenshotMatch(
        for url: URL,
        minimumDate: Date,
        requireReadableContents: Bool
    ) -> ScreenshotMatch? {
        guard isEligibleImage(url, requireReadableContents: requireReadableContents) else {
            return nil
        }

        guard let candidateDate = resourceDate(for: url), candidateDate >= minimumDate else {
            return nil
        }

        let matchScore = screenshotMatchScore(for: url)
        guard matchScore > 0 else {
            return nil
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ScreenshotMatch(url: url, date: candidateDate, fileSize: fileSize, matchScore: matchScore)
    }

    private func isEligibleImage(_ url: URL, requireReadableContents: Bool) -> Bool {
        let resourceValues = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey, .isReadableKey]
        )
        guard resourceValues?.isRegularFile == true else {
            return false
        }

        if requireReadableContents {
            guard resourceValues?.isReadable != false else {
                return false
            }

            guard (resourceValues?.fileSize ?? 0) > 0 else {
                return false
            }
        }

        let extensionType = UTType(filenameExtension: url.pathExtension)
        return extensionType?.conforms(to: .image) == true
    }

    private func screenshotMatchScore(for url: URL) -> Int {
        let filename = url.deletingPathExtension().lastPathComponent.lowercased()
        let screenshotHints = [
            "screenshot",
            "screen shot",
            "screen_shot",
            "bildschirmfoto",
            "captura de pantalla",
            "스크린샷",
        ]

        if screenshotHints.contains(where: filename.contains) {
            return 2
        }

        return 1
    }

    private func resourceDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }
}

private struct ScreenshotMatch {
    let url: URL
    let date: Date
    let fileSize: Int
    let matchScore: Int
}

private struct TemporaryScreenshotScanResult {
    let signalMatch: ScreenshotMatch?
    let readableMatch: ScreenshotMatch?
    let recentContainerDate: Date?
}
