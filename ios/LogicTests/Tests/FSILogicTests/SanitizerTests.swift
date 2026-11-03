import Foundation
import XCTest
@testable import FSILogic

/// F-3 (Character-boundary truncation) and F-4 (control characters) for
/// `FSIShareViewController.sanitizedComponent`.
final class SanitizerTests: XCTestCase {
    let s = Sanitizer()
    let limit = 255

    /// Common invariants: at most `limit` UTF-8 bytes, round-trips as valid
    /// UTF-8, contains no U+FFFD, and is a whole-Character prefix of `expectedSource`.
    func assertWellFormed(_ out: String, prefixOf expectedSource: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(out.utf8.count, limit, "byte cap", file: file, line: line)
        XCTAssertEqual(String(decoding: Array(out.utf8), as: UTF8.self), out, "valid UTF-8", file: file, line: line)
        XCTAssertFalse(out.unicodeScalars.contains("\u{FFFD}"), "no U+FFFD", file: file, line: line)
        XCTAssertTrue(Array(expectedSource).starts(with: Array(out)),
                      "result must be a prefix made of whole Characters", file: file, line: line)
    }

    // MARK: F-3 truncation

    func testShortNameUnchanged() {
        XCTAssertEqual(s.sanitize("report.pdf"), "report.pdf")
    }

    func testLongAsciiIsCutToExactly255Bytes() {
        let out = s.sanitize(String(repeating: "a", count: 300))
        XCTAssertEqual(out, String(repeating: "a", count: 255))
    }

    func testExactly255BytesIsKept() {
        let name = String(repeating: "a", count: 255)
        XCTAssertEqual(s.sanitize(name), name)
    }

    func testTwoByteCharacterAtTheBoundary() {
        // 1 + 2*200 bytes; the 128th é would end at byte 257.
        let input = "a" + String(repeating: "é", count: 200)
        let out = s.sanitize(input)
        XCTAssertEqual(out, "a" + String(repeating: "é", count: 127))
        XCTAssertEqual(out.utf8.count, 255)
        assertWellFormed(out, prefixOf: input)
    }

    func testFourByteEmojiAtTheBoundary() {
        let input = String(repeating: "a", count: 253) + "😀" + "tail"
        let out = s.sanitize(input)
        XCTAssertEqual(out, String(repeating: "a", count: 253))
        assertWellFormed(out, prefixOf: input)
    }

    func testZwjSequenceIsNotSplit() {
        let family = "👩‍👩‍👧" // 18 bytes, one Character
        XCTAssertEqual(family.count, 1)
        let input = String(repeating: "a", count: 250) + family
        let out = s.sanitize(input)
        XCTAssertEqual(out, String(repeating: "a", count: 250))
        assertWellFormed(out, prefixOf: input)
    }

    func testCombiningMarkIsNotSeparatedFromItsBase() {
        let eAcute = "e\u{301}" // 3 bytes, one Character
        let input = String(repeating: "a", count: 254) + eAcute
        let out = s.sanitize(input)
        XCTAssertEqual(out, String(repeating: "a", count: 254))
        assertWellFormed(out, prefixOf: input)
    }

    func testFlagAtTheBoundary() {
        let flag = "🇺🇦" // 8 bytes, one Character
        let input = String(repeating: "a", count: 250) + flag
        let out = s.sanitize(input)
        XCTAssertEqual(out, String(repeating: "a", count: 250))
        assertWellFormed(out, prefixOf: input)
    }

    func testSingleCharacterLongerThanTheCapBecomesUnnamed() {
        let huge = "e" + String(repeating: "\u{301}", count: 200) // one Character, 401 bytes
        XCTAssertEqual(huge.count, 1)
        XCTAssertEqual(s.sanitize(huge), "unnamed")
    }

    func testPseudoRandomInputsKeepTheInvariants() {
        let pool: [String] = ["a", "Z", "é", "ß", "€", "😀", "👩‍👩‍👧", "e\u{301}", "🇺🇦", "中", " ", "-", "ё", "\u{A0}"]
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: state >> 33)
        }
        for _ in 0..<500 {
            var input = "x"
            let n = 50 + next() % 250
            for _ in 0..<n { input += pool[next() % pool.count] }
            let out = s.sanitize(input)
            if out == "unnamed" { continue }
            assertWellFormed(out, prefixOf: input)
            // Maximality: the next whole Character would not have fitted.
            if out.count < input.count {
                let nextChar = Array(input)[out.count]
                XCTAssertGreaterThan(out.utf8.count + nextChar.utf8.count, limit)
            }
        }
    }

    // MARK: F-4 control characters

    func testNulIsStripped() {
        XCTAssertEqual(s.sanitize("a\u{0}b.txt"), "ab.txt")
        XCTAssertFalse(s.sanitize("\u{0}evil\u{0}").unicodeScalars.contains("\u{0}"))
    }

    func testC0ControlsAreStripped() {
        XCTAssertEqual(s.sanitize("a\u{1}\u{9}\u{A}\u{D}\u{1B}\u{1F}b"), "ab")
    }

    func testDelAndC1ControlsAreStripped() {
        XCTAssertEqual(s.sanitize("a\u{7F}\u{80}\u{85}\u{9B}\u{9F}b"), "ab")
    }

    func testNonControlNeighboursAreKept() {
        XCTAssertEqual(s.sanitize("a\u{20}\u{7E}\u{A0}b"), "a ~\u{A0}b")
    }

    func testNormalNamesAreUnchanged() {
        for name in ["photo.jpg", "Résumé 2026 (final).pdf", "😀 party.mov", "中文文件.txt", "e\u{301}cole.doc"] {
            XCTAssertEqual(s.sanitize(name), name)
        }
    }

    func testControlOnlyAndBlankBecomeUnnamed() {
        XCTAssertEqual(s.sanitize("\u{0}\u{1}\u{7F}"), "unnamed")
        XCTAssertEqual(s.sanitize("   "), "unnamed")
        XCTAssertEqual(s.sanitize(""), "unnamed")
    }

    // MARK: separators and dot names (FSI-93 regression)

    func testSlashesAreStripped() {
        XCTAssertEqual(s.sanitize("../../etc/passwd"), "....etcpasswd")
    }

    func testDotNamesBecomeUnnamedEvenAfterStripping() {
        XCTAssertEqual(s.sanitize("."), "unnamed")
        XCTAssertEqual(s.sanitize(".."), "unnamed")
        XCTAssertEqual(s.sanitize("/.."), "unnamed")
        XCTAssertEqual(s.sanitize("\u{0}.."), "unnamed")
        XCTAssertEqual(s.sanitize(".\u{1}."), "unnamed")
    }
}
