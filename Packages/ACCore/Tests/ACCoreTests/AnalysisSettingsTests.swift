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
    /// altering detection behavior app-wide. Includes the six fields added
    /// across the 2026-08-13/08-14 SuperFlux/hop research passes, which this
    /// type didn't actually carry until D8 caught the gap.
    func test_defaultsMatchSpec() {
        let settings = AnalysisSettings()

        XCTAssertEqual(settings.noiseFloorCalibrationMode, .automatic)
        XCTAssertEqual(settings.silenceThresholdDb, -40.0)
        XCTAssertEqual(settings.calibrationMarginDb, 6.0)
        XCTAssertEqual(settings.noiseFloorReestimationIntervalSeconds, 300.0)
        XCTAssertEqual(settings.analysisWindowMilliseconds, 50.0)
        XCTAssertEqual(settings.analysisWindowHopMilliseconds, 10.0)
        XCTAssertEqual(settings.minimumSilenceDurationSeconds, 2.0)
        XCTAssertEqual(settings.minimumCueDurationSeconds, 3.0)
        XCTAssertEqual(settings.tailToleranceDb, 6.0)
        XCTAssertEqual(settings.tailCapSeconds, 0.5)
        XCTAssertEqual(settings.embeddedMarkerMergeToleranceSeconds, 1.0)
        XCTAssertEqual(settings.superFluxRefinementSearchWindowSeconds, 0.5)
        XCTAssertEqual(settings.superFluxHopSeconds, 0.01)
        XCTAssertEqual(settings.superFluxMaxFilterBandwidthBins, 3)
        XCTAssertEqual(settings.superFluxAdaptiveThresholdWindowSeconds, 0.1)
        XCTAssertEqual(settings.superFluxAdaptiveThresholdMultiplier, 1.5)
        XCTAssertEqual(settings.superFluxAdaptiveThresholdOffset, 0.05)
    }

    func test_everyField_isOverridableExplicitly() {
        let settings = AnalysisSettings(
            noiseFloorCalibrationMode: .automatic,
            silenceThresholdDb: -35,
            calibrationMarginDb: 8,
            noiseFloorReestimationIntervalSeconds: 120,
            analysisWindowMilliseconds: 25,
            analysisWindowHopMilliseconds: 5,
            minimumSilenceDurationSeconds: 1.5,
            minimumCueDurationSeconds: 2.5,
            tailToleranceDb: 4,
            tailCapSeconds: 1,
            embeddedMarkerMergeToleranceSeconds: 0.5,
            superFluxRefinementSearchWindowSeconds: 0.25,
            superFluxHopSeconds: 0.005,
            superFluxMaxFilterBandwidthBins: 5,
            superFluxAdaptiveThresholdWindowSeconds: 0.2,
            superFluxAdaptiveThresholdMultiplier: 2.0,
            superFluxAdaptiveThresholdOffset: 0.1
        )

        XCTAssertEqual(settings.noiseFloorCalibrationMode, .automatic)
        XCTAssertEqual(settings.silenceThresholdDb, -35)
        XCTAssertEqual(settings.calibrationMarginDb, 8)
        XCTAssertEqual(settings.noiseFloorReestimationIntervalSeconds, 120)
        XCTAssertEqual(settings.analysisWindowMilliseconds, 25)
        XCTAssertEqual(settings.analysisWindowHopMilliseconds, 5)
        XCTAssertEqual(settings.minimumSilenceDurationSeconds, 1.5)
        XCTAssertEqual(settings.minimumCueDurationSeconds, 2.5)
        XCTAssertEqual(settings.tailToleranceDb, 4)
        XCTAssertEqual(settings.tailCapSeconds, 1)
        XCTAssertEqual(settings.embeddedMarkerMergeToleranceSeconds, 0.5)
        XCTAssertEqual(settings.superFluxRefinementSearchWindowSeconds, 0.25)
        XCTAssertEqual(settings.superFluxHopSeconds, 0.005)
        XCTAssertEqual(settings.superFluxMaxFilterBandwidthBins, 5)
        XCTAssertEqual(settings.superFluxAdaptiveThresholdWindowSeconds, 0.2)
        XCTAssertEqual(settings.superFluxAdaptiveThresholdMultiplier, 2.0)
        XCTAssertEqual(settings.superFluxAdaptiveThresholdOffset, 0.1)
    }

    /// SPEC.md §4.11: "Must be odd (centered on the bin being filtered)."
    /// Not enforced by the type itself (no validation in domain structs per
    /// this project's convention — see `SPEC.md` §4.6's rounding/tolerance
    /// policy note for the same "constrain at the boundary, not the type"
    /// pattern) — this test documents the constraint so it doesn't get
    /// silently violated by a future default change.
    func test_superFluxMaxFilterBandwidthBins_defaultIsOdd() {
        XCTAssertEqual(AnalysisSettings().superFluxMaxFilterBandwidthBins % 2, 1)
    }
}

final class NoiseFloorCalibrationModeTests: XCTestCase {
    func test_bothCasesAreDistinct() {
        XCTAssertNotEqual(NoiseFloorCalibrationMode.manual, .automatic)
    }
}
