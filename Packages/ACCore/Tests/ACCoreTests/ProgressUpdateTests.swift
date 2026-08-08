@testable import ACCore
import XCTest

final class ProgressUpdateTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = ProgressUpdate(fractionCompleted: 0.5, message: "Analyzing…")
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_messageDefaultsToNil() {
        let update = ProgressUpdate(fractionCompleted: 0.25)
        XCTAssertNil(update.message)
    }

    func test_differingFractionOrMessage_areNotEqual() {
        let base = ProgressUpdate(fractionCompleted: 0.5, message: "Analyzing…")
        let differentFraction = ProgressUpdate(fractionCompleted: 0.75, message: "Analyzing…")
        let differentMessage = ProgressUpdate(fractionCompleted: 0.5, message: "Importing…")

        XCTAssertNotEqual(base, differentFraction)
        XCTAssertNotEqual(base, differentMessage)
    }
}
