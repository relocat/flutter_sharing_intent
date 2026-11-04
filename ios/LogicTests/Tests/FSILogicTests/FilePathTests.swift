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

    /// Round trip through the platform's own URL encoding: names with characters
    /// that need escaping, a decomposed accent and non-ASCII text map back to
    /// the exact path. Runs on the macOS runner as well as on Linux.
    func testRoundTripThroughFileURLs() {
        let names = ["a b.txt", "a;b.txt", "a#b.txt", "a?b.txt", "a%b.txt", "a%20b.txt",
                     "e\u{301}.txt", "\u{e9}.txt", "\u{4e2d}\u{6587}.txt", "\u{1F600}.png"]
        for name in names {
            let path = "/tmp/fsi-roundtrip/" + name
            let identifier = URL(fileURLWithPath: path).absoluteString
            XCTAssertEqual(ContainerGuard.filePath(fromFileIdentifier: identifier), path, name)
        }
    }
}

