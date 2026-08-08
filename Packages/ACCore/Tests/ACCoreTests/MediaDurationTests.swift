@testable import ACCore
import XCTest

final class MediaDurationTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = MediaDuration(seconds: 125.5)
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingSeconds_makesDurationsUnequal() {
        XCTAssertNotEqual(MediaDuration(seconds: 10), MediaDuration(seconds: 20))
    }

    func test_comparable_ordersBySeconds() {
        XCTAssertLessThan(MediaDuration(seconds: 10), MediaDuration(seconds: 20))
        XCTAssertGreaterThan(MediaDuration(seconds: 20), MediaDuration(seconds: 10))
    }

    func test_zero_hasZeroSeconds() {
        XCTAssertEqual(MediaDuration.zero.seconds, 0)
    }

    func test_addition_sumsSeconds() {
        let sum = MediaDuration(seconds: 90) + MediaDuration(seconds: 30)
        XCTAssertEqual(sum, MediaDuration(seconds: 120))
    }

    func test_additionWithZero_isIdentity() {
        let duration = MediaDuration(seconds: 42)
        XCTAssertEqual(duration + .zero, duration)
    }

    func test_subtraction_differencesSeconds() {
        let difference = MediaDuration(seconds: 90) - MediaDuration(seconds: 30)
        XCTAssertEqual(difference, MediaDuration(seconds: 60))
    }

    func test_summingCueDurations_viaReduce_matchesManualTotal() {
        // Exercises exactly the shape SPEC.md §4.14's Σ cues[].duration needs.
        let durations = [MediaDuration(seconds: 60), MediaDuration(seconds: 125), MediaDuration(seconds: 30)]
        let total = durations.reduce(.zero, +)
        XCTAssertEqual(total, MediaDuration(seconds: 215))
    }

    func test_formatted_zeroSeconds_isAllZeroes() {
        XCTAssertEqual(MediaDuration(seconds: 0).formatted, "00:00:00")
    }

    func test_formatted_underAnHour_omitsNoComponents() {
        XCTAssertEqual(MediaDuration(seconds: 125).formatted, "00:02:05")
    }

    func test_formatted_hourAndMinuteRollover() {
        XCTAssertEqual(MediaDuration(seconds: 3661).formatted, "01:01:01")
    }

    func test_formatted_roundsToNearestSecond() {
        XCTAssertEqual(MediaDuration(seconds: 59.6).formatted, "00:01:00")
    }

    func test_formatted_longFilmClassDuration_threeHours() {
        XCTAssertEqual(MediaDuration(seconds: 3 * 3600).formatted, "03:00:00")
    }
}
