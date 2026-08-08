@testable import ACCore
import XCTest

final class TimecodeNonDropFrameTests: XCTestCase {
    func test_zeroOffset_isAllZeroesForEveryNonDropRate() {
        for rate: TimecodeFrameRate in [.fps24, .fps25, .fps29_97NonDrop, .fps30] {
            let tc = Timecode(offsetSeconds: 0)
            XCTAssertEqual(tc.formatted(at: rate), "00:00:00:00")
        }
    }

    func test_oneSecondAt25fps_landsOnFrameZero() {
        let tc = Timecode(offsetSeconds: 1.0)
        XCTAssertEqual(tc.components(at: .fps25), TimecodeComponents(hours: 0, minutes: 0, seconds: 1, frames: 0))
    }

    func test_midSecondAt24fps_decomposesIntoTheRightFrame() {
        // 1.5s at 24fps = frame 12 of second 1
        let tc = Timecode(offsetSeconds: 1.5)
        XCTAssertEqual(tc.components(at: .fps24), TimecodeComponents(hours: 0, minutes: 0, seconds: 1, frames: 12))
    }

    func test_hourAndMinuteRolloverAt30fps() {
        let tc = Timecode(offsetSeconds: 3661.0) // 1h 1m 1s
        XCTAssertEqual(tc.components(at: .fps30), TimecodeComponents(hours: 1, minutes: 1, seconds: 1, frames: 0))
    }

    func test_nonDropFormattedString_usesColonBeforeFF() {
        let tc = Timecode(offsetSeconds: 5)
        XCTAssertTrue(tc.formatted(at: .fps29_97NonDrop).contains(":05"))
        XCTAssertFalse(tc.formatted(at: .fps29_97NonDrop).contains(";"))
    }

    func test_29_97NonDrop_driftsFromWallClockAtTheOneHourMark_unlikeDropFrame() {
        let realFrameCount = Int((3600.0 * 29.97).rounded()) // 107892
        let tc = Timecode(offsetSeconds: Double(realFrameCount) / 29.97)
        let parts = tc.components(at: .fps29_97NonDrop)
        // Non-drop just divides straight through by nominal 30fps, so it does NOT read 01:00:00:00.
        XCTAssertNotEqual(parts, TimecodeComponents(hours: 1, minutes: 0, seconds: 0, frames: 0))
    }
}

final class TimecodeDropFrameTests: XCTestCase {
    func test_startOfMinute1Boundary_skipsDisplayFrames00And01_jumpingStraightTo02() {
        // The 1800th real frame (0-indexed 1800) is the first real frame of minute 1.
        let tc = Timecode(offsetSeconds: 1800.0 / 29.97)
        let expected = TimecodeComponents(hours: 0, minutes: 1, seconds: 0, frames: 2)
        XCTAssertEqual(tc.components(at: .fps29_97Drop), expected)
    }

    func test_lastRealFrameBeforeMinute1Boundary_isStill00_00_59_28() {
        let tc = Timecode(offsetSeconds: 1798.0 / 29.97)
        let expected = TimecodeComponents(hours: 0, minutes: 0, seconds: 59, frames: 28)
        XCTAssertEqual(tc.components(at: .fps29_97Drop), expected)
    }

    func test_exactlyOneHourOfRealTime_reads01_00_00_00_theWholePointOfDropFrame() {
        let realFrameCount = 107_892 // = 17982 * 6, exactly 6 ten-minute blocks
        let tc = Timecode(offsetSeconds: Double(realFrameCount) / 29.97)
        let expected = TimecodeComponents(hours: 1, minutes: 0, seconds: 0, frames: 0)
        XCTAssertEqual(tc.components(at: .fps29_97Drop), expected)
    }

    func test_everyTenthMinuteException_minute10IsExempt_framesAreNotSkippedThere() {
        let boundary = TimecodeComponents(hours: 0, minutes: 10, seconds: 0, frames: 0)
        let tc = Timecode(components: boundary, frameRate: .fps29_97Drop)
        XCTAssertNotNil(tc)
        XCTAssertEqual(tc?.components(at: .fps29_97Drop), boundary)
    }

    func test_minute11_nonExempt_doesSkipFrames00And01_sameAsMinute1() {
        let invalid00 = TimecodeComponents(hours: 0, minutes: 11, seconds: 0, frames: 0)
        let invalid01 = TimecodeComponents(hours: 0, minutes: 11, seconds: 0, frames: 1)
        XCTAssertNil(Timecode(components: invalid00, frameRate: .fps29_97Drop))
        XCTAssertNil(Timecode(components: invalid01, frameRate: .fps29_97Drop))

        let valid02 = TimecodeComponents(hours: 0, minutes: 11, seconds: 0, frames: 2)
        XCTAssertNotNil(Timecode(components: valid02, frameRate: .fps29_97Drop))
    }

    func test_frameNumbers00And01_atNonExemptMinuteZeroSecond_areRejectedAsInvalidDropFrameTimecode() {
        func timecode(_ hours: Int, _ minutes: Int, _ seconds: Int, _ frames: Int) -> Timecode? {
            let parts = TimecodeComponents(hours: hours, minutes: minutes, seconds: seconds, frames: frames)
            return Timecode(components: parts, frameRate: .fps29_97Drop)
        }

        XCTAssertNil(timecode(0, 1, 0, 0))
        XCTAssertNil(timecode(0, 1, 0, 1))
        // frame 2+ at that same boundary is fine
        XCTAssertNotNil(timecode(0, 1, 0, 2))
        // frames 0/1 at any second OTHER than :00 are always fine — the rule only applies at the minute boundary
        XCTAssertNotNil(timecode(0, 1, 5, 0))
        // frames 0/1 at :00 of an EXEMPT minute are fine
        XCTAssertNotNil(timecode(0, 0, 0, 0))
        XCTAssertNotNil(timecode(0, 20, 0, 1))
    }

    func test_dropFrameFormattedString_usesSemicolonBeforeFF() {
        let tc = Timecode(offsetSeconds: 5.0)
        XCTAssertTrue(tc.formatted(at: .fps29_97Drop).contains(";"))
    }

    func test_roundTripsAcrossAWideRangeOfRealFrameCounts_includingEveryTenMinuteBoundaryInAThreeHourFile() {
        let maxFrames = 3 * 3600 * 30 // 3-hour-class file, nominal 30fps upper bound
        var frame = 0
        while frame < maxFrames {
            let offset = Double(frame) / 29.97
            let tc = Timecode(offsetSeconds: offset)
            let components = tc.components(at: .fps29_97Drop)
            let reconstructed = Timecode(components: components, frameRate: .fps29_97Drop)
            XCTAssertNotNil(reconstructed, "failed to reconstruct a Timecode from valid components at frame \(frame)")
            if let reconstructed {
                let message = "round-trip mismatch at real frame \(frame): \(reconstructed.offsetSeconds) != \(offset)"
                XCTAssertLessThan(abs(reconstructed.offsetSeconds - offset), 0.0001, message)
            }
            frame += 37 // odd stride so we hit varied phases within each minute/10-minute block, not just boundaries
        }
    }

    func test_roundTripAlsoHoldsForNonDropRates() {
        for rate: TimecodeFrameRate in [.fps24, .fps25, .fps29_97NonDrop, .fps30] {
            var frame = 0
            let maxFrames = Int(2.5 * 3600.0 * Double(rate.nominalFramesPerSecond))
            while frame < maxFrames {
                let offset = Double(frame) / rate.realFramesPerSecond
                let tc = Timecode(offsetSeconds: offset)
                let components = tc.components(at: rate)
                let reconstructed = Timecode(components: components, frameRate: rate)
                XCTAssertNotNil(reconstructed)
                if let reconstructed {
                    XCTAssertLessThan(abs(reconstructed.offsetSeconds - offset), 0.0001)
                }
                frame += 4001 // prime-ish stride, coarser since there's no drop-frame edge case to hunt for here
            }
        }
    }
}

final class TimecodeValueSemanticsTests: XCTestCase {
    func test_comparable_ordersByOffset() {
        XCTAssertLessThan(Timecode(offsetSeconds: 1), Timecode(offsetSeconds: 2))
        XCTAssertFalse(Timecode(offsetSeconds: 2) < Timecode(offsetSeconds: 2))
    }

    func test_valueSemantics_copiesAreIndependentAndEqual() {
        let original = Timecode(offsetSeconds: 12345.678)
        let copy = original
        XCTAssertEqual(copy, original)

        let rebuilt = Timecode(offsetSeconds: original.offsetSeconds)
        XCTAssertEqual(rebuilt, original)

        let different = Timecode(offsetSeconds: original.offsetSeconds + 1)
        XCTAssertNotEqual(different, original)
    }

    func test_isDropFrame_isTrueOnlyForFps29_97Drop() {
        for rate: TimecodeFrameRate in TimecodeFrameRate.allCases {
            XCTAssertEqual(rate.isDropFrame, rate == .fps29_97Drop)
        }
    }
}
