import XCTest
@testable import FSILogic

/// Facts about the share-extension controller that need UIKit to run, pinned
/// from its shipped source by extract.py (see the negative controls there).
final class SourcePinTests: XCTestCase {
    func testEveryStagedDataWriteUsesCompleteFileProtection() { XCTAssertTrue(SourcePins.everyDataWriteIsProtected) }
    func testCopiedFilesAreProtectedAfterTheCopy() { XCTAssertTrue(SourcePins.copiedFilesAreProtected) }
    func testCancelCleansStagedFilesBeforeTheBaseClass() { XCTAssertTrue(SourcePins.cancelCleansBeforeSuper) }
    func testErrorPathCleansStagedFiles() { XCTAssertTrue(SourcePins.errorPathCleans) }
    func testPerShareDirectoriesAreTracked() { XCTAssertTrue(SourcePins.directoriesAreTracked) }
    func testThumbnailsAreTracked() { XCTAssertTrue(SourcePins.thumbnailsAreTracked) }
    func testToStringIsPrivateAndDebugOnly() { XCTAssertTrue(SourcePins.toStringIsPrivateAndDebugOnly) }
    func testRedirectFailsClosedOnAnUnencodableBundleId() { XCTAssertTrue(SourcePins.redirectFailsClosed) }
    func testLoggingIsCompiledOutOfReleaseBuilds() { XCTAssertTrue(SourcePins.loggingIsCompiledOutOfReleaseBuilds) }
}
