import Foundation
import XCTest
@testable import FSILogic

/// FSI-107: the sweep of leftovers of interrupted shares.
final class SweepTests: XCTestCase {
    var container: URL!
    var outside: URL!
    let fm = FileManager.default
    let day: TimeInterval = 24 * 60 * 60

    override func setUpWithError() throws {
        let base = fm.temporaryDirectory.appendingPathComponent("fsi-sweep-\(UUID().uuidString)", isDirectory: true)
        container = base.appendingPathComponent("container", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: container.deletingLastPathComponent())
    }

    func shareDirectory(_ name: String = UUID().uuidString, age: TimeInterval, now: Date) throws -> URL {
        let directory = container.appendingPathComponent("\(ContainerGuard.kShareRootName)/\(name)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory.appendingPathComponent("a.txt"))
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: directory.path)
        return directory
    }

    func thumbnail(_ name: String = "\(UUID().uuidString).jpg", age: TimeInterval, now: Date) throws -> URL {
        let file = container.appendingPathComponent("\(ContainerGuard.kThumbnailRootName)/\(name)")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        return file
    }

    func sweep(now: Date, referenced: Set<String> = []) -> Int {
        ContainerGuard.sweepStaleFiles(containerURL: container, referencedKeys: referenced, now: now,
                                       maxAge: ContainerGuard.kStaleFileMaxAgeSeconds)
    }

    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    func testAgeBoundary() throws {
        let now = Date()
        let justOver = try shareDirectory(age: day + 60, now: now)
        let justUnder = try shareDirectory(age: day - 60, now: now)
        let oldThumbnail = try thumbnail(age: day + 60, now: now)
        let freshThumbnail = try thumbnail(age: day - 60, now: now)
        XCTAssertEqual(sweep(now: now), 2)
        XCTAssertFalse(exists(justOver))
        XCTAssertTrue(exists(justUnder))
        XCTAssertFalse(exists(oldThumbnail))
        XCTAssertTrue(exists(freshThumbnail))
    }

    func testReferencedItemsAreKeptWhateverTheirAge() throws {
        let now = Date()
        let referencedShare = try shareDirectory(age: 10 * day, now: now)
        let referencedThumbnail = try thumbnail(age: 10 * day, now: now)
        let unreferenced = try shareDirectory(age: 10 * day, now: now)
        let referenced = ContainerGuard.referencedKeys(fromIdentifiers: [
            referencedShare.appendingPathComponent("a.txt").absoluteString,
            referencedThumbnail.absoluteString,
        ])
        XCTAssertEqual(sweep(now: now, referenced: referenced), 1)
        XCTAssertTrue(exists(referencedShare))
        XCTAssertTrue(exists(referencedThumbnail))
        XCTAssertFalse(exists(unreferenced))
    }

    func testSymlinksAreNeverFollowedOrRemoved() throws {
        let now = Date()
        let target = outside.appendingPathComponent("target", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let precious = target.appendingPathComponent("keep.txt")
        try Data("x".utf8).write(to: precious)
        let linkedShare = container.appendingPathComponent("\(ContainerGuard.kShareRootName)/\(UUID().uuidString)")
        try fm.createDirectory(at: linkedShare.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linkedShare, withDestinationURL: target)
        let thumbnailRoot = container.appendingPathComponent(ContainerGuard.kThumbnailRootName, isDirectory: true)
        try fm.createDirectory(at: thumbnailRoot, withIntermediateDirectories: true)
        let targetFile = outside.appendingPathComponent("t.bin")
        try Data("x".utf8).write(to: targetFile)
        let linkedThumbnail = thumbnailRoot.appendingPathComponent("\(UUID().uuidString).jpg")
        try fm.createSymbolicLink(at: linkedThumbnail, withDestinationURL: targetFile)

        // Everything counts as old for this call, including the links.
        XCTAssertEqual(sweep(now: now.addingTimeInterval(3 * day)), 0)
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: linkedShare.path))
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: linkedThumbnail.path))
        XCTAssertTrue(exists(precious))
        XCTAssertTrue(exists(targetFile))
    }

    func testSymlinkedRootIsNotEntered() throws {
        let now = Date()
        let victim = outside.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: victim, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-10 * day)], ofItemAtPath: victim.path)
        try fm.createSymbolicLink(at: container.appendingPathComponent(ContainerGuard.kShareRootName), withDestinationURL: outside)
        XCTAssertEqual(sweep(now: now), 0)
        XCTAssertTrue(exists(victim))
    }

    func testOtherNamesAndPlacesAreUntouched() throws {
        let now = Date()
        let notAUuid = try shareDirectory("not-a-uuid", age: 10 * day, now: now)
        let looseThumbnail = try thumbnail("t.jpg", age: 10 * day, now: now)
        let wrongExtension = try thumbnail("\(UUID().uuidString).png", age: 10 * day, now: now)
        let elsewhere = container.appendingPathComponent("other/\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-10 * day)], ofItemAtPath: elsewhere.path)
        let rootFile = container.appendingPathComponent("IMG_0001.jpg")
        try Data("x".utf8).write(to: rootFile)
        XCTAssertEqual(sweep(now: now), 0)
        for url in [notAUuid, looseThumbnail, wrongExtension, elsewhere, rootFile] { XCTAssertTrue(exists(url), url.path) }
    }

    func testReferencedKeysIgnoreTheContainerPrefix() throws {
        let now = Date()
        let uuid = UUID().uuidString
        let share = try shareDirectory(uuid, age: 10 * day, now: now)
        let thumbnailName = "\(UUID().uuidString).jpg"
        let thumb = try thumbnail(thumbnailName, age: 10 * day, now: now)
        let other = try shareDirectory(age: 10 * day, now: now)
        // The payload names the files under a different prefix (as `/private/var`
        // versus `/var` would), and in lowercase.
        let referenced = ContainerGuard.referencedKeys(fromIdentifiers: [
            "file:///private/var/other/prefix/\(ContainerGuard.kShareRootName)/\(uuid.lowercased())/a.txt",
            "/another/root/\(ContainerGuard.kThumbnailRootName)/\(thumbnailName)",
        ])
        XCTAssertEqual(sweep(now: now, referenced: referenced), 1)
        XCTAssertTrue(exists(share))
        XCTAssertTrue(exists(thumb))
        XCTAssertFalse(exists(other))
    }

    func testReferencedKeysIgnoreShapesThatAreNotPluginItems() {
        XCTAssertEqual(ContainerGuard.referencedKeys(fromIdentifiers: [
            "file:///a/b%20c/x.txt", "/plain/path",
            "/c/\(ContainerGuard.kShareRootName)/not-a-uuid/a.txt",
            "/c/\(ContainerGuard.kThumbnailRootName)/t.jpg",
        ]), [])
    }
}
