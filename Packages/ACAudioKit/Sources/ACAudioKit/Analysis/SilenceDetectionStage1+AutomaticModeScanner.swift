import ACCore
import Foundation

/// The `.automatic`-mode scanner (SPEC.md §4.11, "Local Peak-Relative
/// Calibration"; `docs/DECISIONS.md`, 2026-09-22) — a batch, two-pass
/// design, not a real-time state machine. `Stage1Scanner`'s original
/// tail-cap mechanism raced two independent conditions in scan order (main:
/// `automaticModeSilenceDurationSeconds` at the shallow main
/// threshold; stricter: `tailCapSeconds` at a deeper one) and used whichever
/// was satisfied first. Under LPRC this doesn't carry over correctly: the
/// main condition's shorter wall-clock requirement routinely completes
/// before the deeper condition is even reached, so the deeper, more
/// accurate crossing point never gets a chance to apply, even on a real,
/// long-confirmed gap (confirmed on a real fixture where several tails
/// lingered for many seconds past the main crossing without the stricter
/// condition ever firing).
///
/// **Pass 1 — classify every below-`mainThreshold` run by its own full,
/// lookahead-computed extent**, not by how quickly a fixed duration is
/// reached from its start: a run shorter than
/// `automaticModeSilenceDurationSeconds` in total is never a real
/// gap, full stop, regardless of how deep it gets — this is what keeps a
/// real, sustained-but-brief within-cue dip (confirmed real case, SEA_STEM:
/// a genuine musical diminuendo-and-recover reaching `-156.56dBFS` and
/// returning to normal level within ~100ms) from ever triggering the
/// tail-cap branch, at *any* `automaticModeTailToleranceDb` value — not by
/// tuning the margin deep enough to miss it, but by structurally excluding
/// it before depth is even considered.
///
/// **Pass 2 — within a run already confirmed real, always prefer the
/// earliest point where the signal has sustained continuously below the
/// deeper `automaticStricterThreshold` for longer than `tailCapSeconds`**,
/// falling back to the run's own main-threshold crossing only if no such
/// point exists anywhere in the run. This is a "most accurate boundary
/// within a confirmed-real gap" rule, not a "which of two independent
/// conditions wins the race" rule — the distinction that fixes the
/// real-fixture regression above.
struct AutomaticModeScanner {
    private let measurements: [RMSWindowMeasurement]
    private let calibration: ThresholdCalibration
    private let settings: AnalysisSettings
    private let isSilentMain: [Bool]
    private let isSilentStricter: [Bool]

    init(measurements: [RMSWindowMeasurement], calibration: ThresholdCalibration, settings: AnalysisSettings) {
        self.measurements = measurements
        self.calibration = calibration
        self.settings = settings
        isSilentMain = measurements.indices.map { measurements[$0].rmsDb < calibration.mainThreshold(at: $0) }
        isSilentStricter = measurements.indices
            .map { measurements[$0].rmsDb < calibration.automaticStricterThreshold(at: $0) }
    }

    mutating func run(totalDurationSeconds: Double) -> [SilenceDetectedRegion] {
        var results: [SilenceDetectedRegion] = []
        var regionStartTime: Double?
        var index = 0
        let count = measurements.count

        while index < count {
            guard let regionStart = regionStartTime else {
                if !isSilentMain[index] {
                    regionStartTime = index == 0 ? 0 : interpolateCrossing(
                        beforeIndex: index - 1,
                        atIndex: index,
                        threshold: calibration.mainThreshold(at: index)
                    )
                }
                index += 1
                continue
            }
            guard isSilentMain[index] else {
                index += 1
                continue
            }

            let runStart = index
            var runEnd = index
            while runEnd < count, isSilentMain[runEnd] {
                runEnd += 1
            }
            let runDuration = measurements[runEnd - 1].windowCenterSeconds - measurements[runStart].windowCenterSeconds

            guard runDuration >= settings.automaticModeSilenceDurationSeconds else {
                // Not a real gap -- absorbed into the ongoing region.
                index = runEnd
                continue
            }

            let mainCrossingTime = interpolateCrossing(
                beforeIndex: runStart - 1,
                atIndex: runStart,
                threshold: calibration.mainThreshold(at: runStart)
            )
            let end = earliestQualifyingStricterCrossing(
                runStart: runStart,
                runEnd: runEnd,
                mainCrossingTime: mainCrossingTime
            ) ?? mainCrossingTime
            results.append(SilenceDetectedRegion(startSeconds: regionStart, endSeconds: end))
            regionStartTime = nil
            index = runEnd
        }

        if let start = regionStartTime {
            results.append(SilenceDetectedRegion(startSeconds: start, endSeconds: totalDurationSeconds))
        }

        let durationFiltered = results.filter { $0.endSeconds - $0.startSeconds >= settings.minimumCueDurationSeconds }
        return applyMinimumAudiblePeakFilter(durationFiltered)
    }

    /// Earliest point within `[runStart, runEnd)`, and within
    /// `automaticModeTailSearchBoundSeconds` of `mainCrossingTime`, where
    /// `isSilentStricter` sustains continuously for longer than
    /// `tailCapSeconds` — `nil` if no such point exists that early.
    ///
    /// **The bound is load-bearing, not a tuning nicety** (`docs/
    /// DECISIONS.md`, 2026-09-22): real trajectory data on multiple real
    /// fixtures (TWBS cue5/cue8, ECHTE cue7/cue29) shows main-threshold's
    /// own crossing already lands within ~0-2s of the true perceptual end
    /// in every real case checked — the large overshoots this bound fixes
    /// came entirely from searching for a deep confirmation that, for a
    /// slowly-decaying tail sitting on an extended quiet-but-not-silent
    /// plateau (real durations observed: ~5-16s), doesn't arrive until true
    /// digital silence. Without this bound, "earliest qualifying" is still
    /// unbounded in how far past the main crossing it's willing to wait.
    private func earliestQualifyingStricterCrossing(runStart: Int, runEnd: Int, mainCrossingTime: Double) -> Double? {
        let searchLimit = mainCrossingTime + settings.automaticModeTailSearchBoundSeconds
        var cursor = runStart
        while cursor < runEnd, measurements[cursor].windowCenterSeconds <= searchLimit {
            guard isSilentStricter[cursor] else {
                cursor += 1
                continue
            }
            let stricterStart = cursor
            var cursorEnd = cursor
            while cursorEnd < runEnd, isSilentStricter[cursorEnd] {
                cursorEnd += 1
            }
            let stricterDuration = measurements[cursorEnd - 1].windowCenterSeconds - measurements[stricterStart]
                .windowCenterSeconds
            if stricterDuration > settings.tailCapSeconds {
                let crossing = interpolateCrossing(
                    beforeIndex: stricterStart - 1,
                    atIndex: stricterStart,
                    threshold: calibration.automaticStricterThreshold(at: stricterStart)
                )
                return crossing <= searchLimit ? crossing : nil
            }
            cursor = cursorEnd
        }
        return nil
    }

    /// Minimum Audible Confirmation (docs/DECISIONS.md, 2026-09-22) — a
    /// coarse, region-level plausibility gate, not a per-sample silence
    /// boundary: a detected region is discarded unless it reaches
    /// `minimumAudiblePeakDb` somewhere within its own span. Closes a
    /// narrow gap LPRC's depth-relative threshold alone leaves open: an
    /// isolated transient that never gets anywhere near an audible level
    /// (confirmed inaudible by direct listening on the real fixture that
    /// surfaced it, peaking at `-96.7dBFS`) can still register as a
    /// standalone region, because its own excursion contaminates its own
    /// local-peak reference. A real cue virtually always has at least one
    /// moment above `minimumAudiblePeakDb`; a genuine within-cue quiet dip
    /// isn't a standalone region at all -- an internal fluctuation inside
    /// an already-qualifying region -- so this never touches it.
    /// Deliberately a dedicated field, not a reuse of `silenceThresholdDb`
    /// (`AnalysisSettings.minimumAudiblePeakDb`'s doc comment has the full
    /// account, including the real regression reusing it would have caused).
    private func applyMinimumAudiblePeakFilter(_ regions: [SilenceDetectedRegion]) -> [SilenceDetectedRegion] {
        regions.filter { region in
            measurements.contains {
                $0.windowCenterSeconds >= region.startSeconds &&
                    $0.windowCenterSeconds < region.endSeconds &&
                    $0.rmsDb >= settings.minimumAudiblePeakDb
            }
        }
    }

    private func interpolateCrossing(beforeIndex: Int, atIndex: Int, threshold: Double) -> Double {
        crossingTime(in: measurements, beforeIndex: beforeIndex, atIndex: atIndex, threshold: threshold)
    }
}
