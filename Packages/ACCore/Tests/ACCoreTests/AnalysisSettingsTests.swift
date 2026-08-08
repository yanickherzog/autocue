@testable import ACCore
import XCTest

final class AnalysisSettingsTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = AnalysisSettings()
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_isHashable_forUseAsASetElement() {
        XCTAssertEqual(Set([AnalysisSettings(), AnalysisSettings()]).count, 1)
    }

    /// SPEC.md §4.11's documented defaults — every field, so a future
    /// accidental default change is caught here rather than silently
    /// altering detection behavior app-wide.
    func test_defaultsMatchSpec() {
        let settings = AnalysisSettings()

        XCTAssertEqual(settings.noiseFloorCalibrationMode, .manual)
        XCTAssertEqual(settings.silenceThresholdDb, -40.0)
        XCTAssertEqual(settings.calibrationMarginDb, 6.0)
        XCTAssertEqual(settings.noiseFloorReestimationIntervalSeconds, 300.0)
        XCTAssertEqual(settings.analysisWindowMilliseconds, 50.0)
        XCTAssertEqual(settings.minimumSilenceDurationSeconds, 2.0)
        XCTAssertEqual(settings.minimumCueDurationSeconds, 3.0)
        XCTAssertEqual(settings.tailToleranceDb, 6.0)
        XCTAssertEqual(settings.tailCapSeconds, 2.0)
        XCTAssertEqual(settings.embeddedMarkerMergeToleranceSeconds, 1.0)
    }

    func test_everyField_isOverridableExplicitly() {
        let settings = AnalysisSettings(
            noiseFloorCalibrationMode: .automatic,
            silenceThresholdDb: -35,
            calibrationMarginDb: 8,
            noiseFloorReestimationIntervalSeconds: 120,
            analysisWindowMilliseconds: 25,
            minimumSilenceDurationSeconds: 1.5,
            minimumCueDurationSeconds: 2.5,
            tailToleranceDb: 4,
            tailCapSeconds: 1,
            embeddedMarkerMergeToleranceSeconds: 0.5
        )

        XCTAssertEqual(settings.noiseFloorCalibrationMode, .automatic)
        XCTAssertEqual(settings.silenceThresholdDb, -35)
        XCTAssertEqual(settings.calibrationMarginDb, 8)
        XCTAssertEqual(settings.noiseFloorReestimationIntervalSeconds, 120)
        XCTAssertEqual(settings.analysisWindowMilliseconds, 25)
        XCTAssertEqual(settings.minimumSilenceDurationSeconds, 1.5)
        XCTAssertEqual(settings.minimumCueDurationSeconds, 2.5)
        XCTAssertEqual(settings.tailToleranceDb, 4)
        XCTAssertEqual(settings.tailCapSeconds, 1)
        XCTAssertEqual(settings.embeddedMarkerMergeToleranceSeconds, 0.5)
    }
}

final class NoiseFloorCalibrationModeTests: XCTestCase {
    func test_bothCasesAreDistinct() {
        XCTAssertNotEqual(NoiseFloorCalibrationMode.manual, .automatic)
    }
}
