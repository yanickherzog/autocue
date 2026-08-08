@testable import ACCore
import XCTest

final class OperationProgressTests: XCTestCase {
    func test_progressCase_carriesTheGivenUpdate() {
        let update = ProgressUpdate(fractionCompleted: 0.4, message: "Scanning chunk 4")
        let event = OperationProgress<String>.progress(update)

        guard case let .progress(carried) = event else {
            return XCTFail("expected .progress")
        }
        XCTAssertEqual(carried, update)
    }

    func test_completedCase_carriesTheGivenSuccessValue() {
        let event = OperationProgress<String>.completed("done")

        guard case let .completed(value) = event else {
            return XCTFail("expected .completed")
        }
        XCTAssertEqual(value, "done")
    }
}
