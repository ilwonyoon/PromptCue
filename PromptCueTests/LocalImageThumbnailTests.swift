import Foundation
import XCTest
@testable import Prompt_Cue

final class LocalImageThumbnailTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL, FileManager.default.fileExists(atPath: tempDirectoryURL.path) {
            try FileManager.default.removeItem(at: tempDirectoryURL)
        }

        tempDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testManagedAttachmentOnlyRejectsExistingExternalFile() throws {
        let imageURL = tempDirectoryURL.appendingPathComponent("external.png")
        try Data("png".utf8).write(to: imageURL)

        let readableURL = LocalImageThumbnail.readableURL(
            for: imageURL,
            accessPolicy: .managedAttachmentOnly,
            managedURLProvider: { _ in nil }
        )

        XCTAssertNil(readableURL)
    }

    func testManagedAttachmentOnlyAllowsManagedFileResolverResult() throws {
        let imageURL = tempDirectoryURL.appendingPathComponent("managed.png")
        try Data("png".utf8).write(to: imageURL)

        let readableURL = LocalImageThumbnail.readableURL(
            for: imageURL,
            accessPolicy: .managedAttachmentOnly,
            managedURLProvider: { _ in imageURL }
        )

        XCTAssertEqual(readableURL, imageURL.standardizedFileURL)
    }

    func testDirectExistingFileAllowsTrustedPreviewFile() throws {
        let imageURL = tempDirectoryURL.appendingPathComponent("preview.png")
        try Data("png".utf8).write(to: imageURL)

        let readableURL = LocalImageThumbnail.readableURL(
            for: imageURL,
            accessPolicy: .directExistingFile
        )

        XCTAssertEqual(readableURL, imageURL.standardizedFileURL)
    }
}
