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
}
