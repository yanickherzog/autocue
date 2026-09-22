@testable import ACAudioKit
import ACCore
import XCTest

/// Regression coverage for the 2026-09-10 `noiseFloorCalibrationMode`
/// default change (SPEC.md §4.11; `docs/DECISIONS.md`) — `.manual` (fixed
/// `-40.0`dBFS) → `.automatic`. Confirmed across four real gain tiers of the
/// same content plus three genuinely distinct real pieces (choral,
/// sustained/vibrato, electronic): a single fixed threshold cannot serve
/// both a normally-mixed file and a significantly quieter one (e.g. music
/// mixed down as a background bed) with the same value. `.automatic`
/// mode's own calibration mechanism was replaced in full on 2026-09-22
/// (Local Peak-Relative Calibration, `docs/DECISIONS.md`) — this suite's
/// synthetic fixture was updated the same day to the new mechanism's real
/// margin, but the property it proves (the default genuinely beats a fixed
/// `.manual` threshold on a quiet mixed-down cue) is unchanged.
///
/// This suite proves the *default* itself, not just the mechanism: a quiet
/// mixed-down cue that the old `.manual -40dBFS` default would have missed
/// entirely is correctly detected at real, untouched `AnalysisSettings()`
/// defaults — and stays a permanent guard against ever silently reverting
/// the default back to `.manual`.
final class DefaultCalibrationModeTests: XCTestCase {
    private let sampleRate = 48000.0

    /// A cue mixed at `-50`dBFS — comfortably below the old fixed
    /// `-40`dBFS manual default (so `.manual` would never see it at all) —
    /// flanked by near-digital-silence, comfortably below LPRC's real
    /// production effective threshold (`-50 − activityMarginDb(78) =
    /// -128dBFS`; `docs/DECISIONS.md`, 2026-09-22). Unlike the pre-LPRC
    /// mechanism's small `calibrationMarginDb` (6dB), LPRC's much larger,
    /// real-fixture-derived margin means a merely-quieter ambient floor
    /// (e.g. `-70dBFS`, the original level here) no longer separates from
    /// a `-50dBFS` cue at all — this buffer's flanking level was corrected
    /// accordingly, same day, when the original level stopped passing
    /// under the new mechanism. Silence segments clear
    /// `automaticModeSilenceDurationSeconds` (2.6s) and the tone
    /// clears `minimumCueDurationSeconds` (3.0s), both with real margin.
    private func makeQuietMixedDownCueBuffer() -> [Float] {
        SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.tone(
                seconds: 3.0,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -170)
            ),
            SyntheticAudioBuilder.tone(
                seconds: 4.0,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -50)
            ),
            SyntheticAudioBuilder.tone(
                seconds: 3.0,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -170)
            ),
        ])
    }

    /// The regression itself: real, untouched `AnalysisSettings()` —
    /// proving the shipped default is genuinely `.automatic`, not just
    /// documented as such, and that it behaves correctly on a case the old
    /// default structurally could not.
    func test_realDefaults_correctlyDetectQuietMixedDownCue() {
        let regions = SilenceDetector.detectRegions(
            monoSamples: makeQuietMixedDownCueBuffer(),
            sampleRate: sampleRate,
            settings: AnalysisSettings() // real shipped defaults, no overrides
        )

        XCTAssertEqual(
            regions.count, 1,
            "a -50dBFS cue must be detected under real production defaults"
        )
        guard let region = regions.first else { return }
        XCTAssertEqual(region.startSeconds, 3.0, accuracy: 0.05)
        XCTAssertEqual(region.endSeconds, 7.0, accuracy: 0.05)
    }

    /// Same fixture, with calibration mode explicitly restored to the old
    /// default (`.manual`, fixed `-40.0`dBFS) — documents exactly what the
    /// old default would have done: the `-50`dBFS cue never crosses `-40`,
    /// so it's silently invisible, never even considered a candidate.
    /// Kept permanently as a guard against ever reverting the default.
    func test_oldManualDefault_wouldHaveMissedThisCueEntirely() {
        let oldDefaultEquivalent = AnalysisSettings(noiseFloorCalibrationMode: .manual)

        let regions = SilenceDetector.detectRegions(
            monoSamples: makeQuietMixedDownCueBuffer(),
            sampleRate: sampleRate,
            settings: oldDefaultEquivalent
        )

        XCTAssertEqual(
            regions.count, 0,
            "documents the old default's real blind spot: a -50dBFS cue never crosses a fixed " +
                "-40dBFS threshold, so the old .manual default would have missed it entirely"
        )
    }
}
