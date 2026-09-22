import ACCore
import Foundation

/// Stage 1 of `SilenceDetector` (SPEC.md §4.11): turns a full-file array of
/// windowed-RMS measurements into candidate non-silent regions, purely —
/// no file I/O, no SuperFlux. Implements, in one pass: manual/automatic
/// threshold calibration (with periodic re-estimation), sustained-silence
/// boundary detection, dB-domain threshold-crossing interpolation, and the
/// two-threshold reverb-tail end-truncation mechanism.
///
/// A pure function over already-computed measurements, not a second
/// streaming stage — `RMSWindowStream`'s own doc comment explains why this
/// is safe memory-wise even for a very long file.
enum SilenceDetectionStage1 {
    static func detectRegions(
        measurements: [RMSWindowMeasurement],
        totalDurationSeconds: Double,
        settings: AnalysisSettings
    ) -> [SilenceDetectedRegion] {
        guard !measurements.isEmpty else { return [] }

        let calibration = ThresholdCalibration(measurements: measurements, settings: settings)
        if settings.noiseFloorCalibrationMode == .automatic {
            var scanner = AutomaticModeScanner(measurements: measurements, calibration: calibration, settings: settings)
            return scanner.run(totalDurationSeconds: totalDurationSeconds)
        }
        var scanner = Stage1Scanner(measurements: measurements, calibration: calibration, settings: settings)
        return scanner.run(totalDurationSeconds: totalDurationSeconds)
    }
}

/// Precomputes one effective main threshold per measurement (SPEC.md §4.11,
/// "Threshold: manual vs. automatic" / "Local Peak-Relative Calibration").
/// In `.manual` mode every measurement trivially resolves to the same fixed
/// `silenceThresholdDb`.
///
/// **`.automatic` mode: Local Peak-Relative Calibration (LPRC), replacing
/// the original fixed-cadence leading-window-minimum scheme entirely
/// (`docs/DECISIONS.md`, 2026-09-22).** Four prior mechanisms tried to
/// compute a single *substitute level* to stand in for a floor-pinned
/// leading-window reading — a percentile, an N-interval consensus, a fixed
/// fallback, a whole-file median — and all four failed for the same
/// underlying reason: a real file can contain both genuine bit-exact
/// digital silence between cues *and* genuine quiet-but-real dips within a
/// cue, and no single absolute number can correctly separate both at once
/// when their real dB ranges overlap. LPRC never computes a *floor*
/// (a minimum, which is exactly what pins to `RMSWindowStream.epsilonClampDb`
/// the instant a leading window lands on true silence, and — because the
/// old implausible-jump guard then rejects every subsequent real reading as
/// too-shallow-relative-to-the-pinned-anchor — can never legitimately
/// recalibrate upward again for the rest of the file). It computes a
/// *ceiling* instead: `localPeakDb(t)`, the maximum RMS reached within
/// `localPeakRadiusSeconds` of `t` in *either* time direction (this type
/// already operates on the full in-memory measurement array, not a
/// streaming stage, so a symmetric/lookahead window is free). A local
/// maximum only reads near the epsilon floor when the entire surrounding
/// neighborhood genuinely is silent — which is exactly the case where that
/// is the correct answer — so it cannot floor-pin the way a minimum does.
/// The effective threshold is `localPeakDb(t) − activityMarginDb`: a
/// *relative* margin applied against each local passage's own measured
/// ceiling, never an absolute substitute value competing with real content.
struct ThresholdCalibration {
    private let settings: AnalysisSettings
    private let thresholds: [Double] // one per measurement; empty in .manual mode

    init(measurements: [RMSWindowMeasurement], settings: AnalysisSettings) {
        self.settings = settings

        guard settings.noiseFloorCalibrationMode == .automatic, !measurements.isEmpty else {
            thresholds = []
            return
        }

        let peaks = Self.symmetricLocalPeakDb(measurements, radiusSeconds: settings.localPeakRadiusSeconds)
        let floor = RMSWindowStream.epsilonClampDb + 0.001
        thresholds = peaks.map { max($0 - settings.activityMarginDb, floor) }
    }

    func mainThreshold(at index: Int) -> Double {
        guard !thresholds.isEmpty else { return settings.silenceThresholdDb }
        return thresholds[index]
    }

    /// `.manual` mode only — used by `Stage1Scanner`, unchanged.
    func stricterThreshold(at index: Int) -> Double {
        mainThreshold(at: index) - settings.tailToleranceDb
    }

    /// `.automatic` mode only — used by `AutomaticModeScanner`. A separate,
    /// re-derived margin from `.manual`'s `tailToleranceDb`: under LPRC,
    /// `mainThreshold` is already a deep, peak-relative value (not a
    /// shallow, near-ambient one the way `.manual`'s fixed threshold or the
    /// old floor-pinned scheme could be), so "stricter" needs to mean
    /// something structurally different here — see `AnalysisSettings.
    /// automaticModeTailToleranceDb`'s doc comment and `docs/DECISIONS.md`,
    /// 2026-09-22, for the full real-data derivation.
    func automaticStricterThreshold(at index: Int) -> Double {
        max(mainThreshold(at: index) - settings.automaticModeTailToleranceDb, RMSWindowStream.epsilonClampDb + 0.001)
    }

    /// Symmetric sliding-window maximum via a ring-buffer-backed monotonic
    /// deque, O(n) amortized. `buffer[front..<back]` is always the valid
    /// range — popping the back only ever decrements `back`, popping the
    /// front only ever increments `front`; the two never interfere with
    /// each other's bookkeeping (unlike an array + a separately-tracked
    /// logical head-pointer scheme, where removing from the back can
    /// silently invalidate the front pointer's own bookkeeping — a real bug
    /// found and fixed while validating this mechanism, `docs/DECISIONS.md`
    /// 2026-09-22).
    private static func symmetricLocalPeakDb(
        _ measurements: [RMSWindowMeasurement],
        radiusSeconds: Double
    ) -> [Double] {
        let count = measurements.count
        guard count > 0 else { return [] }
        var result = [Double](repeating: RMSWindowStream.epsilonClampDb, count: count)
        var buffer = [Int](repeating: 0, count: count)
        var front = 0
        var back = 0
        var hi = 0
        for measurementIndex in 0 ..< count {
            let loBound = measurements[measurementIndex].windowCenterSeconds - radiusSeconds
            let hiBound = measurements[measurementIndex].windowCenterSeconds + radiusSeconds
            while hi < count, measurements[hi].windowCenterSeconds <= hiBound {
                while back > front, measurements[buffer[back - 1]].rmsDb <= measurements[hi].rmsDb {
                    back -= 1
                }
                buffer[back] = hi
                back += 1
                hi += 1
            }
            while front < back, measurements[buffer[front]].windowCenterSeconds < loBound {
                front += 1
            }
            result[measurementIndex] = front < back ? measurements[buffer[front]].rmsDb : measurements[measurementIndex]
                .rmsDb
        }
        return result
    }
}

/// The forward-scanning state machine over the measurement timeline,
/// `.manual` mode only (SPEC.md §4.11's "Reverb tails," unchanged since
/// 2026-09-10). `.automatic` mode uses `AutomaticModeScanner` instead — see
/// that type's doc comment for why a real-time race between two independent
/// conditions doesn't carry over correctly to LPRC's threshold shape.
/// `Stage1State` names exactly the three states SPEC.md §4.11's boundary
/// logic distinguishes: not yet in a region, confirmed in one, or currently
/// evaluating a below-threshold dip that hasn't yet resolved into either an
/// abandonment (level recovered) or a confirmed end (main gap sustained, or
/// the stricter tail-cap fired first).
private struct Stage1Scanner {
    private enum State {
        case betweenRegions
        case inRegion(start: Double)
        case candidateGap(regionStart: Double, mainGapStartIndex: Int, stricterGapStartIndex: Int?)
    }

    private let measurements: [RMSWindowMeasurement]
    private let calibration: ThresholdCalibration
    private let settings: AnalysisSettings
    private var results: [SilenceDetectedRegion] = []
    private var state: State = .betweenRegions

    init(measurements: [RMSWindowMeasurement], calibration: ThresholdCalibration, settings: AnalysisSettings) {
        self.measurements = measurements
        self.calibration = calibration
        self.settings = settings
    }

    mutating func run(totalDurationSeconds: Double) -> [SilenceDetectedRegion] {
        for index in measurements.indices {
            step(at: index)
        }
        finalizeAtEndOfFile(totalDurationSeconds: totalDurationSeconds)
        return applyMinimumCueDurationFilter(results)
    }

    /// Bundles one measurement's classification results — keeps the three
    /// `handle...` methods below within SwiftLint's parameter-count
    /// threshold, since all three need the same four values alongside
    /// whatever's in the current `State` case.
    private struct Classification {
        let index: Int
        let time: Double
        let isSilentMain: Bool
        let isSilentStricter: Bool
    }

    private mutating func step(at index: Int) {
        let time = measurements[index].windowCenterSeconds
        let mainThreshold = calibration.mainThreshold(at: index)
        let stricterThreshold = calibration.stricterThreshold(at: index)
        let classification = Classification(
            index: index,
            time: time,
            isSilentMain: measurements[index].rmsDb < mainThreshold,
            isSilentStricter: measurements[index].rmsDb < stricterThreshold
        )

        switch state {
        case .betweenRegions:
            handleBetweenRegions(classification, mainThreshold: mainThreshold)
        case let .inRegion(start):
            handleInRegion(start: start, classification)
        case let .candidateGap(regionStart, mainGapStartIndex, stricterGapStartIndex):
            handleCandidateGap(
                regionStart: regionStart,
                mainGapStartIndex: mainGapStartIndex,
                stricterGapStartIndex: stricterGapStartIndex,
                classification
            )
        }
    }

    private mutating func handleBetweenRegions(_ classification: Classification, mainThreshold: Double) {
        guard !classification.isSilentMain else { return }
        let index = classification.index
        let onsetTime = index == 0
            ? 0
            : interpolateCrossing(beforeIndex: index - 1, atIndex: index, threshold: mainThreshold)
        state = .inRegion(start: onsetTime)
    }

    private mutating func handleInRegion(start: Double, _ classification: Classification) {
        guard classification.isSilentMain else { return }
        state = .candidateGap(
            regionStart: start,
            mainGapStartIndex: classification.index,
            stricterGapStartIndex: classification.isSilentStricter ? classification.index : nil
        )
    }

    private mutating func handleCandidateGap(
        regionStart: Double,
        mainGapStartIndex: Int,
        stricterGapStartIndex: Int?,
        _ classification: Classification
    ) {
        guard classification.isSilentMain else {
            state = .inRegion(start: regionStart) // recovered before either confirmation — abandon the gap
            return
        }
        let index = classification.index
        let time = classification.time

        var updatedStricterStart = stricterGapStartIndex
        if classification.isSilentStricter {
            if updatedStricterStart == nil {
                updatedStricterStart = index
            }
        } else {
            updatedStricterStart = nil
        }

        let stricterGapDuration = updatedStricterStart.map { time - measurements[$0].windowCenterSeconds } ?? 0
        if let stricterStart = updatedStricterStart, stricterGapDuration > settings.tailCapSeconds {
            let crossing = interpolateCrossing(
                beforeIndex: stricterStart - 1,
                atIndex: stricterStart,
                threshold: calibration.stricterThreshold(at: stricterStart)
            )
            results.append(SilenceDetectedRegion(startSeconds: regionStart, endSeconds: crossing))
            state = .betweenRegions
            return
        }

        let mainGapDuration = time - measurements[mainGapStartIndex].windowCenterSeconds
        if mainGapDuration >= settings.minimumSilenceDurationSeconds {
            let crossing = interpolateCrossing(
                beforeIndex: mainGapStartIndex - 1,
                atIndex: mainGapStartIndex,
                threshold: calibration.mainThreshold(at: mainGapStartIndex)
            )
            results.append(SilenceDetectedRegion(startSeconds: regionStart, endSeconds: crossing))
            state = .betweenRegions
            return
        }

        state = .candidateGap(
            regionStart: regionStart,
            mainGapStartIndex: mainGapStartIndex,
            stricterGapStartIndex: updatedStricterStart
        )
    }

    /// The file ends while still "in" a region (confirmed, or an
    /// unconfirmed candidate gap that never got to finalize) — the region
    /// simply ends where the audio does; there's no more silence left to
    /// confirm a gap against.
    private mutating func finalizeAtEndOfFile(totalDurationSeconds: Double) {
        switch state {
        case .betweenRegions:
            return
        case let .inRegion(start):
            results.append(SilenceDetectedRegion(startSeconds: start, endSeconds: totalDurationSeconds))
        case let .candidateGap(regionStart, _, _):
            results.append(SilenceDetectedRegion(startSeconds: regionStart, endSeconds: totalDurationSeconds))
        }
        state = .betweenRegions
    }

    /// SPEC.md §4.11: a candidate non-silent region shorter than
    /// `minimumCueDurationSeconds` is discarded (merged into whichever
    /// neighboring silence run absorbs it), not promoted to a boundary.
    private func applyMinimumCueDurationFilter(_ regions: [SilenceDetectedRegion]) -> [SilenceDetectedRegion] {
        regions.filter { $0.endSeconds - $0.startSeconds >= settings.minimumCueDurationSeconds }
    }

    private func interpolateCrossing(beforeIndex: Int, atIndex: Int, threshold: Double) -> Double {
        crossingTime(in: measurements, beforeIndex: beforeIndex, atIndex: atIndex, threshold: threshold)
    }
}

/// SPEC.md §4.11, "RMS time resolution and threshold-crossing
/// interpolation": `t_cross = t₁ + (thresholdDb − db₁) / (db₂ − db₁) × hop`,
/// applied uniformly to every crossing this contract defines — shared by
/// both `Stage1Scanner` (`.manual`) and `AutomaticModeScanner`
/// (`.automatic`). Returns `atIndex`'s own time directly when there's no
/// prior measurement to interpolate against (a transition at the very
/// first measurement).
func crossingTime(
    in measurements: [RMSWindowMeasurement],
    beforeIndex: Int,
    atIndex: Int,
    threshold: Double
) -> Double {
    guard beforeIndex >= 0 else { return measurements[atIndex].windowCenterSeconds }
    let before = measurements[beforeIndex]
    let at = measurements[atIndex]
    guard at.rmsDb != before.rmsDb else { return at.windowCenterSeconds }
    let fraction = (threshold - before.rmsDb) / (at.rmsDb - before.rmsDb)
    return before.windowCenterSeconds + fraction * (at.windowCenterSeconds - before.windowCenterSeconds)
}
