import Foundation
import PromptCueCore
import UniformTypeIdentifiers

@MainActor
final class ScreenshotMonitor {
    func mostRecentScreenshot(maxAge: TimeInterval) -> ScreenshotAttachment? {
        let now = Date()
        let minimumDate = now.addingTimeInterval(-maxAge)

        return (
            screenshotDirectories()
            .compactMap { newestScreenshot(in: $0, minimumDate: minimumDate) }
            .max { left, right in
                if left.matchScore == right.matchScore {
                    return left.date < right.date
                }

                return left.matchScore < right.matchScore
            }
        )
        .map { ScreenshotAttachment(path: $0.url.path) }
    }

    private func screenshotDirectories() -> [SearchLocation] {
        var directories: [SearchLocation] = []
        if let preferredDirectory = ScreenshotDirectoryResolver.preferredDirectoryURL() {
            directories.append(
                SearchLocation(
                    url: preferredDirectory,
                    acceptsUnnamedImages: true
                )
            )
        }

        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            directories.append(SearchLocation(url: desktop, acceptsUnnamedImages: false))
        }

        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            directories.append(SearchLocation(url: downloads, acceptsUnnamedImages: false))
        }

        if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            directories.append(SearchLocation(url: pictures, acceptsUnnamedImages: false))
        }

        var seenPaths = Set<String>()
        return directories.filter { seenPaths.insert($0.url.standardizedFileURL.path).inserted }
    }

    private func newestScreenshot(in location: SearchLocation, minimumDate: Date) -> ScreenshotMatch? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: location.url,
            includingPropertiesForKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .isRegularFileKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        return contents
            .compactMap { screenshotMatch(for: $0, in: location, minimumDate: minimumDate) }
            .max { left, right in
                if left.matchScore == right.matchScore {
                    return left.date < right.date
                }

                return left.matchScore < right.matchScore
            }
    }

    private func screenshotMatch(
        for url: URL,
        in location: SearchLocation,
        minimumDate: Date
    ) -> ScreenshotMatch? {
        guard isEligibleImage(url) else {
            return nil
        }

        guard let candidateDate = resourceDate(for: url), candidateDate >= minimumDate else {
            return nil
        }

        let matchScore = screenshotMatchScore(for: url, acceptsUnnamedImages: location.acceptsUnnamedImages)
        guard matchScore > 0 else {
            return nil
        }

        return ScreenshotMatch(url: url, date: candidateDate, matchScore: matchScore)
    }

    private func isEligibleImage(_ url: URL) -> Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues?.isRegularFile == true else {
            return false
        }

        let extensionType = UTType(filenameExtension: url.pathExtension)
        guard extensionType?.conforms(to: .image) == true else {
            return false
        }

        return true
    }

    private func screenshotMatchScore(for url: URL, acceptsUnnamedImages: Bool) -> Int {
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

        return acceptsUnnamedImages ? 1 : 0
    }

    private func resourceDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }
}

private struct SearchLocation {
    let url: URL
    let acceptsUnnamedImages: Bool
}

private struct ScreenshotMatch {
    let url: URL
    let date: Date
    let matchScore: Int
}
