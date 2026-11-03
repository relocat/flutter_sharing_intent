import Foundation
import XCTest
@testable import FSILogic

/// FSI-103: cleanup removes only regular files (`SwiftFlutterSharingIntentPlugin.isRegularFile`).
final class RegularFileTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fsi-regular-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func isRegular(_ url: URL) -> Bool { ContainerGuard.isRegularFile(atPath: url.path) }

    func testRegularFileIsAccepted() throws {
        let file = directory.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertTrue(isRegular(file))
    }

    func testDirectoryIsRefused() throws {
        let sub = directory.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: sub.appendingPathComponent("inner.txt"))
        XCTAssertFalse(isRegular(sub))
        XCTAssertFalse(isRegular(directory))
    }

    func testSymlinkIsRefusedWhetherItPointsAtAFileOrADirectory() throws {
        let target = directory.appendingPathComponent("target.txt")
        try Data("x".utf8).write(to: target)
        let fileLink = directory.appendingPathComponent("file-link")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: target)
        let dirLink = directory.appendingPathComponent("dir-link")
        try FileManager.default.createSymbolicLink(at: dirLink, withDestinationURL: directory)
        XCTAssertFalse(isRegular(fileLink))
        XCTAssertFalse(isRegular(dirLink))
    }

    func testMissingAndEmptyPathsAreRefused() {
        XCTAssertFalse(isRegular(directory.appendingPathComponent("missing")))
        XCTAssertFalse(ContainerGuard.isRegularFile(atPath: ""))
    }
}
