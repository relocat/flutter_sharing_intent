import Foundation
import XCTest
@testable import FSILogic

/// FSI-105 and the cleanup wiring: `removeOwnedFiles` is the shipped function
/// copied byte-for-byte, so these tests fail if a guard is removed from it.
final class CleanupWiringTests: XCTestCase {
    var container: URL!
    var outside: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        let base = fm.temporaryDirectory.appendingPathComponent("fsi-wiring-\(UUID().uuidString)", isDirectory: true)
        container = base.appendingPathComponent("container", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: container.deletingLastPathComponent())
    }

    @discardableResult
    func write(_ url: URL, _ text: String = "x") throws -> URL {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func shareFile(_ name: String = "a.txt", uuid: String = UUID().uuidString) throws -> URL {
        try write(container.appendingPathComponent("\(ContainerGuard.kShareRootName)/\(uuid)/\(name)"))
    }

    func remove(_ urls: [URL]) -> Int {
        ContainerGuard.removeOwnedFiles(paths: urls.map { $0.path }, containerURL: container)
    }

    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    func testOwnedShareFileIsRemovedAndItsEmptyDirectoryToo() throws {
        let file = try shareFile()
        XCTAssertEqual(remove([file]), 1)
        XCTAssertFalse(exists(file))
        XCTAssertFalse(exists(file.deletingLastPathComponent()), "the empty per-share directory is removed")
        XCTAssertTrue(exists(container.appendingPathComponent(ContainerGuard.kShareRootName)), "the share root stays")
    }

    func testPerShareDirectoryWithAnotherFileIsKept() throws {
        let file = try shareFile()
        let sibling = try write(file.deletingLastPathComponent().appendingPathComponent("other.txt"))
        XCTAssertEqual(remove([file]), 1)
        XCTAssertTrue(exists(sibling))
    }

    func testThumbnailIsRemovedAndItsRootStays() throws {
        let thumbnail = try write(container.appendingPathComponent("\(ContainerGuard.kThumbnailRootName)/\(UUID().uuidString).jpg"))
        XCTAssertEqual(remove([thumbnail]), 1)
        XCTAssertFalse(exists(thumbnail))
        XCTAssertTrue(exists(container.appendingPathComponent(ContainerGuard.kThumbnailRootName)))
    }

    func testFilesAtTheContainerRootAreNotOwned() throws {
        let legacy = try write(container.appendingPathComponent("IMG_0001.jpg"))
        let plist = try write(container.appendingPathComponent("Library/Preferences/group.plist"))
        XCTAssertEqual(remove([legacy, plist]), 0)
        XCTAssertTrue(exists(legacy))
        XCTAssertTrue(exists(plist))
    }

    func testPathsOutsideTheContainerAreRefused() throws {
        let foreign = try write(outside.appendingPathComponent("keep.txt"))
        let escaping = try shareFile()
        let dotDot = escaping.deletingLastPathComponent().path + "/../../../../outside/keep.txt"
        XCTAssertEqual(ContainerGuard.removeOwnedFiles(paths: [foreign.path, dotDot], containerURL: container), 0)
        XCTAssertTrue(exists(foreign))
    }

    func testWrongShapesAreNotOwned() throws {
        let notAUuid = try write(container.appendingPathComponent("\(ContainerGuard.kShareRootName)/not-a-uuid/a.txt"))
        let wrongRoot = try write(container.appendingPathComponent("other/\(UUID().uuidString)/a.txt"))
        let tooDeep = try write(container.appendingPathComponent("\(ContainerGuard.kShareRootName)/\(UUID().uuidString)/sub/a.txt"))
        let directlyInRoot = try write(container.appendingPathComponent("\(ContainerGuard.kShareRootName)/a.txt"))
        let looseThumbnail = try write(container.appendingPathComponent("\(ContainerGuard.kThumbnailRootName)/t.jpg"))
        XCTAssertEqual(remove([notAUuid, wrongRoot, tooDeep, directlyInRoot, looseThumbnail]), 0)
        for url in [notAUuid, wrongRoot, tooDeep, directlyInRoot, looseThumbnail] { XCTAssertTrue(exists(url), url.path) }
    }

    func testDirectoryAtAnOwnedPathIsNeverRemoved() throws {
        let file = try shareFile()
        let directory = file.deletingLastPathComponent().appendingPathComponent("subdir", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(directory.appendingPathComponent("inner.txt"))
        XCTAssertEqual(remove([directory]), 0)
        XCTAssertTrue(exists(directory.appendingPathComponent("inner.txt")))
    }

    func testSymlinkAtAnOwnedPathIsNeverFollowedOrRemoved() throws {
        let target = try write(outside.appendingPathComponent("target.txt"))
        let link = container.appendingPathComponent("\(ContainerGuard.kShareRootName)/\(UUID().uuidString)/link")
        try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(remove([link]), 0)
        XCTAssertTrue(exists(target))
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: link.path), "the link itself is untouched")
    }

    func testMissingFileIsRefusedWithoutError() {
        let missing = container.appendingPathComponent("\(ContainerGuard.kShareRootName)/\(UUID().uuidString)/gone.txt")
        XCTAssertEqual(remove([missing]), 0)
    }

    func testOwnedShapeRecognition() {
        let uuid = UUID().uuidString
        let root = container.path
        XCTAssertTrue(ContainerGuard.isPluginOwnedPath(path: "\(root)/\(ContainerGuard.kShareRootName)/\(uuid)/a.txt", containerURL: container))
        XCTAssertTrue(ContainerGuard.isPluginOwnedPath(path: "\(root)/\(ContainerGuard.kShareRootName)/\(uuid.lowercased())/a.txt", containerURL: container))
        XCTAssertTrue(ContainerGuard.isPluginOwnedPath(path: "\(root)/\(ContainerGuard.kThumbnailRootName)/\(uuid).jpg", containerURL: container))
        XCTAssertFalse(ContainerGuard.isPluginOwnedPath(path: "\(root)/\(ContainerGuard.kThumbnailRootName)/t.jpg", containerURL: container), "a thumbnail leaf must be <UUID>.jpg")
        XCTAssertFalse(ContainerGuard.isPluginOwnedPath(path: "\(root)/\(ContainerGuard.kThumbnailRootName)/\(uuid).png", containerURL: container))
        XCTAssertFalse(ContainerGuard.isPluginOwnedPath(path: "\(root)/\(ContainerGuard.kShareRootName)/\(uuid)", containerURL: container))
        XCTAssertFalse(ContainerGuard.isPluginOwnedPath(path: "\(root)/a.txt", containerURL: container))
        XCTAssertFalse(ContainerGuard.isPluginOwnedPath(path: "\(root)/\(ContainerGuard.kShareRootName)/\(uuid)/../x", containerURL: container))
    }

    // FSI-106: a symlinked plugin directory must not redirect a delete.
    func testSymlinkedShareRootIsRefused() throws {
        let uuid = UUID().uuidString
        let victim = try write(outside.appendingPathComponent("\(uuid)/a.txt"))
        try fm.createSymbolicLink(at: container.appendingPathComponent(ContainerGuard.kShareRootName), withDestinationURL: outside)
        let path = container.appendingPathComponent("\(ContainerGuard.kShareRootName)/\(uuid)/a.txt")
        XCTAssertEqual(remove([path]), 0)
        XCTAssertTrue(exists(victim))
    }

    func testSymlinkedPerShareDirectoryIsRefused() throws {
        let uuid = UUID().uuidString
        let victim = try write(outside.appendingPathComponent("a.txt"))
        let root = container.appendingPathComponent(ContainerGuard.kShareRootName, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent(uuid), withDestinationURL: outside)
        XCTAssertEqual(remove([root.appendingPathComponent("\(uuid)/a.txt")]), 0)
        XCTAssertTrue(exists(victim))
    }

    func testSymlinkedThumbnailRootIsRefused() throws {
        let name = "\(UUID().uuidString).jpg"
        let victim = try write(outside.appendingPathComponent(name))
        try fm.createSymbolicLink(at: container.appendingPathComponent(ContainerGuard.kThumbnailRootName), withDestinationURL: outside)
        XCTAssertEqual(remove([container.appendingPathComponent("\(ContainerGuard.kThumbnailRootName)/\(name)")]), 0)
        XCTAssertTrue(exists(victim))
    }

    func testNonStandardOwnedPathIsDeletedAsItsStandardForm() throws {
        let file = try shareFile()
        let odd = file.deletingLastPathComponent().path + "/./" + file.lastPathComponent
        XCTAssertEqual(ContainerGuard.removeOwnedFiles(paths: [odd], containerURL: container), 1)
        XCTAssertFalse(exists(file))
        XCTAssertFalse(exists(file.deletingLastPathComponent()))
    }
}

