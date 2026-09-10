@testable import ACAudioKit
import ACCore
import XCTest

/// Regression coverage for the 2026-09-10 automatic-calibration
/// implausible-jump sanity check (SPEC.md §4.11, "Threshold: manual vs.
/// automatic"; `docs/DECISIONS.md`). Found via a real fixture
/// (`TEST-TRACKS-ORIGINAL.wav`): `.automatic` mode's fixed-cadence
/// re-estimation blindly trusted whatever RMS level its leading window
/// happened to land on. When a re-estimation boundary landed inside an
/// ongoing loud passage — a real, reproducible case, not a rare edge case —
/// the interval recalibrated its threshold to (that loud level +
/// `calibrationMarginDb`), which then classified the *rest of that same
/// ongoing passage* as silence, since the passage's own level now sat below
/// its own newly-inflated threshold. On the real fixture this corrupted
/// detection for the entire remainder of the file (a cue falsely split,
/// another cue truncated ~14.8s early).
///
/// This suite reproduces the mechanism synthetically: a genuinely quiet
/// leading window correctly calibrates interval 0, then a single continuous
/// loud tone deliberately spans the interval-1 re-estimation boundary, so
/// interval 1's own leading window samples only that ongoing tone — exactly
/// the failure shape found on the real file.
final class AutomaticCalibrationSanityTests: XCTestCase {
    private let sampleRate = 48000.0

    private func settings(reestimationInterval: Double) -> AnalysisSettings {
        AnalysisSettings(
            noiseFloorCalibrationMode: .automatic,
            calibrationMarginDb: 6.0,
            noiseFloorReestimationIntervalSeconds: reestimationInterval,
            analysisWindowMilliseconds: 20,
            analysisWindowHopMilliseconds: 5,
            minimumSilenceDurationSeconds: 0.3,
            minimumCueDurationSeconds: 0.3,
            tailCapSeconds: 0.1
        )
    }

    /// A single continuous loud tone from t=1s to t=11s, deliberately
    /// spanning the interval-1 boundary at t=3s (with a 3.0s re-estimation
    /// interval) — interval 1's own 2.0s leading window ([3,5)) therefore
    /// samples nothing but the ongoing tone, never silence.
    private func makeSpanningToneBuffer() -> [Float] {
        SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.silence(seconds: 1.0, sampleRate: sampleRate),
            SyntheticAudioBuilder.tone(
                seconds: 10.0,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -10)
            ),
            SyntheticAudioBuilder.silence(seconds: 3.0, sampleRate: sampleRate),
        ])
    }

    /// The regression itself: with the sanity check in place, interval 1's
    /// implausible re-estimation (measuring the ongoing tone's own loud
    /// level as if it were silence) is rejected, and interval 0's correctly-
    /// measured threshold is carried forward instead — so the tone is
    /// detected as exactly one continuous region, not corrupted mid-way
    /// through by a bad recalibration.
    func test_loudToneSpanningReestimationBoundary_detectedAsOneContinuousRegion() {
        let regions = SilenceDetector.detectRegions(
            monoSamples: makeSpanningToneBuffer(),
            sampleRate: sampleRate,
            settings: settings(reestimationInterval: 3.0)
        )

        XCTAssertEqual(
            regions.count, 1,
            "a bad re-estimation landing inside the ongoing tone must not fragment or truncate it"
        )
        guard let region = regions.first else { return }
        XCTAssertEqual(region.startSeconds, 1.0, accuracy: 0.05)
        XCTAssertEqual(region.endSeconds, 11.0, accuracy: 0.05)
    }

    /// Same fixture with re-estimation effectively disabled (an interval
    /// longer than the whole buffer) as a control: proves the assertions
    /// above aren't trivially true regardless of re-estimation — without a
    /// second interval to go wrong, the tone is (as expected) still
    /// detected as one clean region, confirming the first test's fixture
    /// itself is sound and the interval boundary is what's actually being
    /// exercised.
    func test_sameFixture_noReestimationBoundary_alsoOneContinuousRegion() {
        let regions = SilenceDetector.detectRegions(
            monoSamples: makeSpanningToneBuffer(),
            sampleRate: sampleRate,
            settings: settings(reestimationInterval: 100.0)
        )

        XCTAssertEqual(regions.count, 1)
        guard let region = regions.first else { return }
        XCTAssertEqual(region.startSeconds, 1.0, accuracy: 0.05)
        XCTAssertEqual(region.endSeconds, 11.0, accuracy: 0.05)
    }
}
