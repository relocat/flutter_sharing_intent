import XCTest
@testable import FSILogic

/// Facts about the share-extension controller that need UIKit to run, pinned
/// from its shipped source by extract.py (see the negative controls there).
final class SourcePinTests: XCTestCase {
    func testEveryStagedDataWriteUsesCompleteFileProtection() { XCTAssertTrue(SourcePins.everyDataWriteIsProtected) }
    func testCopiedFilesAreProtectedAfterTheCopy() { XCTAssertTrue(SourcePins.copiedFilesAreProtected) }
    func testProtectFailsClosed() { XCTAssertTrue(SourcePins.protectFailsClosed) }
    func testCopyRejectsNonRegularSources() { XCTAssertTrue(SourcePins.copyRejectsNonRegularSources) }
    func testDirectoriesAreCreatedProtected() { XCTAssertTrue(SourcePins.directoriesAreCreatedProtected) }
    func testRootsAreCheckedBeforeStaging() { XCTAssertTrue(SourcePins.rootsAreCheckedBeforeStaging) }
    func testCancelAbortsBeforeTheBaseClass() { XCTAssertTrue(SourcePins.cancelAbortsBeforeSuper) }
    func testErrorPathAborts() { XCTAssertTrue(SourcePins.errorPathAborts) }
    func testErrorUiRunsOnMain() { XCTAssertTrue(SourcePins.errorUiRunsOnMain) }
    func testAbortFlagIsSetBeforeCleanup() { XCTAssertTrue(SourcePins.abortFlagIsSetBeforeCleanup) }
    func testNotifyDropsAnAbortedShare() { XCTAssertTrue(SourcePins.notifyDropsAnAbortedShare) }
    func testHandlersRunOnTheStateQueue() { XCTAssertTrue(SourcePins.handlersRunOnTheStateQueue) }
    func testSharedStateIsOnlyAccessedOnTheQueue() { XCTAssertTrue(SourcePins.sharedStateIsOnlyAccessedOnTheQueue) }
    func testPerShareDirectoriesAreTracked() { XCTAssertTrue(SourcePins.directoriesAreTracked) }
    func testThumbnailsAreTracked() { XCTAssertTrue(SourcePins.thumbnailsAreTracked) }
    func testRedirectIsComputedBeforeDefaultsAreWritten() { XCTAssertTrue(SourcePins.redirectIsComputedBeforeDefaultsAreWritten) }
    func testRedirectFailureCleansUp() { XCTAssertTrue(SourcePins.redirectFailureCleansUp) }
    func testRedirectFailsClosedOnAnUnencodableBundleId() { XCTAssertTrue(SourcePins.redirectFailsClosed) }
    func testEmptyResultCleansUp() { XCTAssertTrue(SourcePins.emptyResultCleansUp) }
    func testToStringIsPrivateAndDebugOnly() { XCTAssertTrue(SourcePins.toStringIsPrivateAndDebugOnly) }
    func testLoggingIsCompiledOutOfReleaseBuilds() { XCTAssertTrue(SourcePins.loggingIsCompiledOutOfReleaseBuilds) }
}
