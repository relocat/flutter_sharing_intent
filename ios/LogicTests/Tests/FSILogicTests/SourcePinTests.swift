import XCTest
@testable import FSILogic

/// Facts about the share-extension controller that need UIKit to run, pinned
/// from its shipped source by extract.py (see the negative controls there).
final class SourcePinTests: XCTestCase {
    func testEveryDataWriteIsProtected() { XCTAssertTrue(SourcePins.everyDataWriteIsProtected) }
    func testCopiedFilesAreProtected() { XCTAssertTrue(SourcePins.copiedFilesAreProtected) }
    func testProtectFailsClosed() { XCTAssertTrue(SourcePins.protectFailsClosed) }
    func testCopyRejectsNonRegularSources() { XCTAssertTrue(SourcePins.copyRejectsNonRegularSources) }
    func testCopyVerifiesTheCreatedFile() { XCTAssertTrue(SourcePins.copyVerifiesTheCreatedFile) }
    func testDirectoriesAreCreatedProtected() { XCTAssertTrue(SourcePins.directoriesAreCreatedProtected) }
    func testRootsAreCheckedBeforeStaging() { XCTAssertTrue(SourcePins.rootsAreCheckedBeforeStaging) }
    func testStagingRunsOnTheStateQueue() { XCTAssertTrue(SourcePins.stagingRunsOnTheStateQueue) }
    func testCancelClaimsCompletionBeforeSuper() { XCTAssertTrue(SourcePins.cancelClaimsCompletionBeforeSuper) }
    func testCancelClaimsBeforeItCleansUp() { XCTAssertTrue(SourcePins.cancelClaimsBeforeItCleansUp) }
    func testPostIgnoresUnsettledLoads() { XCTAssertTrue(SourcePins.postIgnoresUnsettledLoads) }
    func testCancelAbortsBeforeSuper() { XCTAssertTrue(SourcePins.cancelAbortsBeforeSuper) }
    func testErrorPathAborts() { XCTAssertTrue(SourcePins.errorPathAborts) }
    func testErrorUiRunsOnMain() { XCTAssertTrue(SourcePins.errorUiRunsOnMain) }
    func testAbortFlagIsSetBeforeCleanup() { XCTAssertTrue(SourcePins.abortFlagIsSetBeforeCleanup) }
    func testCancelDoesNotWaitOnTheStateQueue() { XCTAssertTrue(SourcePins.cancelDoesNotWaitOnTheStateQueue) }
    func testAbortClearsSharedMedia() { XCTAssertTrue(SourcePins.abortClearsSharedMedia) }
    func testAbortFlagsAreLockProtected() { XCTAssertTrue(SourcePins.abortFlagsAreLockProtected) }
    func testNotifyDropsAnAbortedShare() { XCTAssertTrue(SourcePins.notifyDropsAnAbortedShare) }
    func testHandlersRunOnTheStateQueue() { XCTAssertTrue(SourcePins.handlersRunOnTheStateQueue) }
    func testHandlersSkipFinishedAndAbortedShares() { XCTAssertTrue(SourcePins.handlersSkipFinishedAndAbortedShares) }
    func testAbortedHandlersRemoveWhatTheyStaged() { XCTAssertTrue(SourcePins.abortedHandlersRemoveWhatTheyStaged) }
    func testSharedStateIsOnlyAccessedOnTheQueue() { XCTAssertTrue(SourcePins.sharedStateIsOnlyAccessedOnTheQueue) }
    func testDeliveryIsOneAtomicDecision() { XCTAssertTrue(SourcePins.deliveryIsOneAtomicDecision) }
    func testDeliveryFindsFinishedFirst() { XCTAssertTrue(SourcePins.deliveryFindsFinishedFirst) }
    func testDeliveryDropsAnAbortedShare() { XCTAssertTrue(SourcePins.deliveryDropsAnAbortedShare) }
    func testDeliveryMarksFinishedBeforeTheAbortCheck() { XCTAssertTrue(SourcePins.deliveryMarksFinishedBeforeTheAbortCheck) }
    func testPostWaitsForSettledLoads() { XCTAssertTrue(SourcePins.postWaitsForSettledLoads) }
    func testRequestIsCompletedOnce() { XCTAssertTrue(SourcePins.requestIsCompletedOnce) }
    func testDirectoriesAreTracked() { XCTAssertTrue(SourcePins.directoriesAreTracked) }
    func testThumbnailsAreTracked() { XCTAssertTrue(SourcePins.thumbnailsAreTracked) }
    func testRedirectIsComputedBeforeDefaultsAreWritten() { XCTAssertTrue(SourcePins.redirectIsComputedBeforeDefaultsAreWritten) }
    func testRedirectFailureCleansUp() { XCTAssertTrue(SourcePins.redirectFailureCleansUp) }
    func testDefaultsFailuresCleanUp() { XCTAssertTrue(SourcePins.defaultsFailuresCleanUp) }
    func testRedirectFailsClosed() { XCTAssertTrue(SourcePins.redirectFailsClosed) }
    func testEmptyResultCleansUp() { XCTAssertTrue(SourcePins.emptyResultCleansUp) }
    func testToStringIsPrivateAndDebugOnly() { XCTAssertTrue(SourcePins.toStringIsPrivateAndDebugOnly) }
    func testLoggingIsCompiledOutOfReleaseBuilds() { XCTAssertTrue(SourcePins.loggingIsCompiledOutOfReleaseBuilds) }
}
