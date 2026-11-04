import Foundation
import XCTest
@testable import FSILogic

/// FSI-106: stored file URLs become paths through `URL`, so percent-escapes are decoded.
final class FilePathTests: XCTestCase {
    func testPercentEscapesAndNonAsciiAreDecoded() {
        XCTAssertEqual(ContainerGuard.filePath(fromFileIdentifier: "file:///tmp/a%20b/%C3%A9%20x.txt"), "/tmp/a b/\u{e9} x.txt")
    }

    func testPlainPathsAreReturnedUnchanged() {
        XCTAssertEqual(ContainerGuard.filePath(fromFileIdentifier: "/var/mobile/Media/DCIM/a b.jpg"), "/var/mobile/Media/DCIM/a b.jpg")
    }

    func testAPlainNameWithoutEscapesStillWorks() {
        XCTAssertEqual(ContainerGuard.filePath(fromFileIdentifier: "file:///tmp/photo.jpg"), "/tmp/photo.jpg")
    }
}
