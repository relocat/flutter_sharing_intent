import Foundation
import XCTest
@testable import FSILogic

/// Share-extension helpers: strict bundle-id encoding and staged-item cleanup.
final class ExtensionLogicTests: XCTestCase {
    func testOrdinaryBundleIdentifierIsUnchanged() {
        XCTAssertEqual(ExtensionLogic.schemeSafeHost("org.example.app-1"), "org.example.app-1")
    }

    func testSeparatorsAreEncoded() {
        let encoded = ExtensionLogic.schemeSafeHost("a:b/c?d#e@f g")
        XCTAssertEqual(encoded, "a%3Ab%2Fc%3Fd%23e%40f%20g")
        for separator in [":", "/", "?", "#", "@", " "] {
            XCTAssertFalse(encoded?.contains(separator) ?? true, separator)
        }
    }

    func testNonAsciiIsPercentEncoded() {
        XCTAssertEqual(ExtensionLogic.schemeSafeHost("caf\u{e9}"), "caf%C3%A9")
    }

    func testEmptyIdentifierStaysEmpty() {
        XCTAssertEqual(ExtensionLogic.schemeSafeHost(""), "")
    }

    func testStagedItemsAreRemovedAndMissingOnesIgnored() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("fsi-staged-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let shareDirectory = base.appendingPathComponent("flutter_sharing_intent/\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: shareDirectory.appendingPathComponent("a.txt"))
        let thumbnail = base.appendingPathComponent("flutter_sharing_intent_thumbnails/\(UUID().uuidString).jpg")
        try fm.createDirectory(at: thumbnail.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: thumbnail)
        let missing = base.appendingPathComponent("never-created")

        ExtensionLogic.removeStagedItems([shareDirectory, thumbnail, missing])

        XCTAssertFalse(fm.fileExists(atPath: shareDirectory.path))
        XCTAssertFalse(fm.fileExists(atPath: thumbnail.path))
    }

    func testStagedSymlinkIsRemovedAsALinkAndItsTargetSurvives() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("fsi-staged-link-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let precious = outside.appendingPathComponent("keep.txt")
        try Data("x".utf8).write(to: precious)
        let staged = base.appendingPathComponent("staged", isDirectory: true)
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: staged.appendingPathComponent("link"), withDestinationURL: outside)

        ExtensionLogic.removeStagedItems([staged])

        XCTAssertFalse(fm.fileExists(atPath: staged.path))
        XCTAssertTrue(fm.fileExists(atPath: precious.path), "a link inside a staged directory must not be followed")
    }

    func testUsableRootAcceptsMissingAndRealDirectoriesOnly() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("fsi-root-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let realDirectory = base.appendingPathComponent("real", isDirectory: true)
        try fm.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        let plainFile = base.appendingPathComponent("file")
        try Data("x".utf8).write(to: plainFile)
        let link = base.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: realDirectory)

        XCTAssertTrue(ExtensionLogic.isUsableRoot(base.appendingPathComponent("missing")))
        XCTAssertTrue(ExtensionLogic.isUsableRoot(realDirectory))
        XCTAssertFalse(ExtensionLogic.isUsableRoot(plainFile))
        XCTAssertFalse(ExtensionLogic.isUsableRoot(link), "a symlinked plugin directory must be refused")
    }

    func testOnlyRegularNonLinkFilesAreCopyable() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("fsi-copy-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let directory = base.appendingPathComponent("dir", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertTrue(ExtensionLogic.isCopyableRegularFile(file))
        XCTAssertFalse(ExtensionLogic.isCopyableRegularFile(directory))
        XCTAssertFalse(ExtensionLogic.isCopyableRegularFile(link))
        XCTAssertFalse(ExtensionLogic.isCopyableRegularFile(base.appendingPathComponent("missing")))
    }

    func testUsableRootRefusesAnyErrorOtherThanNoSuchFile() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("fsi-denied-\(UUID().uuidString)", isDirectory: true)
        let locked = base.appendingPathComponent("locked", isDirectory: true)
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try fm.createDirectory(at: locked.appendingPathComponent("child"), withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? fm.removeItem(at: base)
        }
        try XCTSkipIf(fm.isReadableFile(atPath: locked.appendingPathComponent("child").path), "running as a user that ignores permissions")

        XCTAssertFalse(ExtensionLogic.isUsableRoot(locked.appendingPathComponent("child")),
                       "a permission error is not proof that the directory is missing")
    }

    func testRegularFileOnDiskIsTrueOnlyForARegularFile() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("fsi-ondisk-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let directory = base.appendingPathComponent("dir", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertTrue(ExtensionLogic.isRegularFileOnDisk(file))
        XCTAssertFalse(ExtensionLogic.isRegularFileOnDisk(directory))
        XCTAssertFalse(ExtensionLogic.isRegularFileOnDisk(link))
        XCTAssertFalse(ExtensionLogic.isRegularFileOnDisk(base.appendingPathComponent("missing")))
    }
}

