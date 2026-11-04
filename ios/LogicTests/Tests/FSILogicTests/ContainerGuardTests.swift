import Foundation
import XCTest
@testable import FSILogic

/// F-2: cleanup path guard (`SwiftFlutterSharingIntentPlugin.isStrictlyInsideContainer`).
final class ContainerGuardTests: XCTestCase {
    let containerPath = "/var/mobile/Containers/Shared/AppGroup/1234-ABCD"
    var container: URL { URL(fileURLWithPath: containerPath, isDirectory: true) }

    func inside(_ p: String, _ c: URL? = nil) -> Bool {
        ContainerGuard.isStrictlyInsideContainer(path: p, containerURL: c ?? container)
    }

    func testNestedLegitimateFileIsAccepted() {
        XCTAssertTrue(inside(containerPath + "/IMG_0001.jpg"))
        XCTAssertTrue(inside(containerPath + "/sub/dir/file.pdf"))
    }

    func testDotDotEscapeIsRejected() {
        XCTAssertFalse(inside(containerPath + "/../x"))
        XCTAssertFalse(inside(containerPath + "/../../../../outside/x"))
        XCTAssertFalse(inside(containerPath + "/sub/../../x"))
    }

    func testDotDotThatStaysInsideIsStillRejectedFailClosed() {
        XCTAssertFalse(inside(containerPath + "/sub/../file"))
    }

    func testSiblingSharingThePrefixIsRejected() {
        XCTAssertFalse(inside(containerPath + "-sibling/x"))
        XCTAssertFalse(inside(containerPath + "X"))
        XCTAssertFalse(inside(containerPath + "X/file"))
    }

    func testDotSegmentsAreStandardised() {
        XCTAssertTrue(inside(containerPath + "/./file"))
        XCTAssertTrue(inside(containerPath + "/sub/./file"))
        XCTAssertFalse(inside(containerPath + "/."), "\"<container>/.\" is the container itself")
    }

    func testTrailingSlashes() {
        XCTAssertTrue(inside(containerPath + "/file/"))
        XCTAssertFalse(inside(containerPath + "/"))
        let slashContainer = URL(fileURLWithPath: containerPath + "/")
        XCTAssertTrue(inside(containerPath + "/file", slashContainer))
        XCTAssertFalse(inside(containerPath + "-sibling/file", slashContainer))
    }

    func testRepeatedSlashes() {
        XCTAssertTrue(inside(containerPath + "//file"))
    }

    func testContainerItselfIsRejected() {
        XCTAssertFalse(inside(containerPath))
    }

    func testEmptyAndRelativePathsAreRejected() {
        XCTAssertFalse(inside(""))
        XCTAssertFalse(inside("file.jpg"))
        XCTAssertFalse(inside("./file.jpg"))
        XCTAssertFalse(inside("../x"))
        XCTAssertFalse(inside("var/mobile/Containers/Shared/AppGroup/1234-ABCD/file"))
    }

    func testRootAndUnrelatedPathsAreRejected() {
        XCTAssertFalse(inside("/"))
        XCTAssertFalse(inside("/outside/x"))
        XCTAssertFalse(inside("/var/mobile/Containers/Shared/AppGroup"))
    }

    // MARK: - Real file system (covers /private/var on macOS runners)

    func makeTree() throws -> (root: URL, container: URL, outside: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fsi-guard-\(UUID().uuidString)", isDirectory: true)
        let c = root.appendingPathComponent("group", isDirectory: true)
        let o = root.appendingPathComponent("group-sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: c.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: c.appendingPathComponent("sub/file.bin"))
        try Data("secret".utf8).write(to: o.appendingPathComponent("secret.txt"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, c, o)
    }

    func testRealNestedFileIsAccepted() throws {
        let t = try makeTree()
        XCTAssertTrue(inside(t.container.appendingPathComponent("sub/file.bin").path, t.container))
    }

    func testRealSiblingAndEscapeAreRejected() throws {
        let t = try makeTree()
        XCTAssertFalse(inside(t.outside.appendingPathComponent("secret.txt").path, t.container))
        XCTAssertFalse(inside(t.container.path + "/../group-sibling/x.txt", t.container))
        XCTAssertFalse(inside(t.container.path, t.container))
    }

    /// A symlink as the last component is accepted, and deleting it removes the
    /// link only: the target outside the container survives.
    func testSymlinkLastComponentDeletesOnlyTheLink() throws {
        let t = try makeTree()
        let link = t.container.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: t.outside)
        XCTAssertTrue(inside(link.path, t.container))
        try FileManager.default.removeItem(atPath: link.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: t.outside.appendingPathComponent("secret.txt").path))
    }

    /// `<container>/link/../x`: lexically inside, but the kernel resolves `..`
    /// after the symlink, so it names a file outside. Must be rejected.
    func testDotDotAfterSymlinkIsRejected() throws {
        let t = try makeTree()
        let inner = t.outside.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let link = t.container.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: inner)
        let tricky = link.path + "/../secret.txt"
        XCTAssertTrue(FileManager.default.fileExists(atPath: tricky), "precondition: the kernel resolves it outside")
        XCTAssertFalse(inside(tricky, t.container))
    }
}
