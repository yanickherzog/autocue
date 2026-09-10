@testable import ACAudioKit
import ACCore
import XCTest

/// Regression coverage for the 2026-09-10 `tailCapSeconds` fix (SPEC.md
/// §4.11, "Reverb tails"; `docs/DECISIONS.md`). Through 2026-09-09,
/// `tailCapSeconds` defaulted to `2.0` — exactly equal to
/// `minimumSilenceDurationSeconds`'s own `2.0` default — which made the
/// stricter-threshold tail-cap branch mathematically unreachable: it can
/// only start counting once the signal has already dropped below the
/// *shallower* main threshold, so `stricterGapDuration ≤ mainGapDuration`
/// always, and the main-gap condition (`≥ minimumSilenceDurationSeconds`)
/// therefore always resolves at or before the stricter one (`>
/// tailCapSeconds`) ever could. This went undetected since D8 because no
/// existing test constructed a decay shallow-then-deep enough, and brief
/// enough overall, to distinguish the two paths — every existing fixture's
/// silence was either sustained well past 2.0s (main always wins
/// trivially) or never separated the main/stricter crossings by a
/// meaningful delay.
///
/// This suite proves, against the real production `tailCapSeconds`/
/// `minimumSilenceDurationSeconds` defaults under `.manual` calibration —
/// pinned explicitly since `noiseFloorCalibrationMode` itself later defaulted
/// to `.automatic` (2026-09-10, same date), which would calibrate its own
/// threshold from this fixture's leading silence rather than using the fixed
/// `-40`dBFS this fixture's dB levels were chosen relative to, defeating the
/// point of this suite — that the stricter branch is now genuinely reachable
/// and produces the correct (later, deeper-threshold) truncation point. In
/// the second test, that this is not just an abstract reachability question:
/// without the fix, the exact fixture below would silently produce *one*
/// region instead of two, because the main gap alone never accumulates a
/// full 2.0s before the level recovers.
final class SilenceDetectorTailCapTests: XCTestCase {
    private let sampleRate = 48000.0

    /// Shape: loud → briefly below main only (−43dBFS, above the −46dBFS
    /// stricter reference) → deep (−60dBFS, below stricter) → loud again.
    /// The deep dip lasts 0.8s, comfortably clearing `tailCapSeconds`
    /// (0.5s default) while the *entire* below-main span (0.3s + 0.8s =
    /// 1.1s) never comes close to `minimumSilenceDurationSeconds` (2.0s
    /// default) — so under the pre-fix defaults this whole dip would never
    /// register as a gap at all (see `test_preFixConfiguration_wouldHaveMergedBothCuesIntoOne`,
    /// below); under the fix, the stricter branch resolves it correctly.
    private func makeShallowThenDeepDipBuffer() -> [Float] {
        SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.tone(
                seconds: 1.0,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -80)
            ),
            SyntheticAudioBuilder.tone(
                seconds: 3.5,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -5)
            ),
            SyntheticAudioBuilder.tone(
                seconds: 0.3,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -43)
            ),
            SyntheticAudioBuilder.tone(
                seconds: 0.8,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -60)
            ),
            SyntheticAudioBuilder.tone(
                seconds: 3.5,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -5)
            ),
            SyntheticAudioBuilder.tone(
                seconds: 2.2,
                sampleRate: sampleRate,
                amplitude: SyntheticAudioBuilder.amplitude(forRMSDb: -80)
            ),
        ])
    }

    /// The regression itself: against real production defaults, the
    /// stricter branch now fires, truncating the first cue at the
    /// interpolated −46dBFS crossing (~4.8s — the −43dBFS→−60dBFS segment
    /// boundary) rather than either never resolving (pre-fix) or waiting
    /// for a main-threshold crossing that never sustains 2.0s.
    func test_shallowThenDeepDip_stricterBranchFires_atProductionDefaults() {
        let regions = SilenceDetector.detectRegions(
            monoSamples: makeShallowThenDeepDipBuffer(),
            sampleRate: sampleRate,
            // .manual pinned explicitly (see class doc) — every other field
            // here is the real, untouched production default.
            settings: AnalysisSettings(noiseFloorCalibrationMode: .manual)
        )

        XCTAssertEqual(
            regions.count,
            2,
            "the shallow-then-deep dip must be recognized as a real gap, splitting the two cues"
        )
        guard regions.count == 2 else { return }

        XCTAssertEqual(regions[0].startSeconds, 1.0, accuracy: 0.05)
        // Truncated at the stricter (−46dBFS) crossing, not the main
        // (−40dBFS) crossing at 4.5s, and not left unresolved.
        XCTAssertEqual(regions[0].endSeconds, 4.8, accuracy: 0.1)
        XCTAssertEqual(regions[1].startSeconds, 5.6, accuracy: 0.05)
    }

    /// Same fixture, with `tailCapSeconds` explicitly restored to its
    /// pre-fix value (`2.0`) — proving what the old default actually did:
    /// the dip never resolves as a gap at all (never sustains 2.0s
    /// continuously below main), so the two loud passages silently merge
    /// into one region. This is the test that would have caught the
    /// original bug had it existed since D8, and is kept here (rather than
    /// deleted once the fix landed) as a permanent demonstration of exactly
    /// what regresses if `tailCapSeconds` is ever raised back to
    /// `minimumSilenceDurationSeconds` or above.
    func test_preFixConfiguration_wouldHaveMergedBothCuesIntoOne() {
        let preFixSettings = AnalysisSettings(noiseFloorCalibrationMode: .manual, tailCapSeconds: 2.0)

        let regions = SilenceDetector.detectRegions(
            monoSamples: makeShallowThenDeepDipBuffer(),
            sampleRate: sampleRate,
            settings: preFixSettings
        )

        XCTAssertEqual(
            regions.count, 1,
            "documents the pre-fix defect: with tailCapSeconds == minimumSilenceDurationSeconds, " +
                "the stricter branch can never fire, so a dip that never sustains a full main-threshold " +
                "gap silently merges both cues into one region"
        )
    }
}
