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
        var scanner = Stage1Scanner(measurements: measurements, calibration: calibration, settings: settings)
        return scanner.run(totalDurationSeconds: totalDurationSeconds)
    }
}

/// Precomputes one effective main threshold per `noiseFloorReestimationIntervalSeconds`
/// interval (SPEC.md §4.11, "Threshold: manual vs. automatic" / "Time-varying
/// noise floor"). In `.manual` mode every interval trivially resolves to the
/// same fixed `silenceThresholdDb`.
private struct ThresholdCalibration {
    private let settings: AnalysisSettings
    private let intervalThresholds: [Double] // indexed by interval number

    init(measurements: [RMSWindowMeasurement], settings: AnalysisSettings) {
        self.settings = settings

        guard settings.noiseFloorCalibrationMode == .automatic, let lastTime = measurements.last?.windowCenterSeconds
        else {
            intervalThresholds = []
            return
        }

        let intervalLength = max(settings.noiseFloorReestimationIntervalSeconds, 0.001)
        let intervalCount = Int(lastTime / intervalLength) + 1
        // "Confirmed at T8.3 implementation time" (SPEC.md §4.11): a 2.0s
        // leading sample window per interval, minimum RMS-dB as the noise
        // floor statistic, inconclusive (→ fallback) below 5 measurements.
        let leadingWindowSeconds = 2.0
        let minimumMeasurementsForConfidence = 5
        // "Found and fixed 2026-09-10" (SPEC.md §4.11, docs/DECISIONS.md):
        // a candidate threshold more than this many dB shallower than the
        // *previous* interval's own calibrated threshold is treated as
        // implausible — the leading window almost certainly landed inside
        // real content, not silence — and the previous interval's threshold
        // is carried forward instead of trusting the bad measurement. 20dB
        // comfortably allows a genuine ambient-floor shift between
        // intervals (a real location/scene change) while firmly rejecting
        // the kind of jump a leading window landing in active music
        // produces (confirmed empirically at ~74dB on a real fixture).
        let implausibleJumpMarginDb = 20.0

        var thresholds: [Double] = []
        thresholds.reserveCapacity(intervalCount)
        for interval in 0 ..< intervalCount {
            let intervalStart = Double(interval) * intervalLength
            let leadingEnd = intervalStart + leadingWindowSeconds
            let leadingMeasurements = measurements.filter {
                $0.windowCenterSeconds >= intervalStart && $0.windowCenterSeconds < leadingEnd
            }
            guard leadingMeasurements.count >= minimumMeasurementsForConfidence else {
                thresholds.append(settings.silenceThresholdDb)
                continue
            }
            let measuredNoiseFloorDb = leadingMeasurements.map(\.rmsDb).min() ?? settings.silenceThresholdDb
            let candidateThreshold = measuredNoiseFloorDb + settings.calibrationMarginDb
            if interval > 0, candidateThreshold > thresholds[interval - 1] + implausibleJumpMarginDb {
                thresholds.append(thresholds[interval - 1])
            } else {
                thresholds.append(candidateThreshold)
            }
        }
        intervalThresholds = thresholds
    }

    func mainThreshold(atTime time: Double) -> Double {
        guard settings.noiseFloorCalibrationMode == .automatic, !intervalThresholds.isEmpty else {
            return settings.silenceThresholdDb
        }
        let intervalLength = max(settings.noiseFloorReestimationIntervalSeconds, 0.001)
        let index = min(max(Int(time / intervalLength), 0), intervalThresholds.count - 1)
        return intervalThresholds[index]
    }

    /// SPEC.md §4.11, clarified at T8.3 implementation time: always relative
    /// to whichever main threshold is actually in effect at `time`, not the
    /// raw `silenceThresholdDb` field when calibration has moved it.
    func stricterThreshold(atTime time: Double) -> Double {
        mainThreshold(atTime: time) - settings.tailToleranceDb
    }
}

/// The forward-scanning state machine over the measurement timeline.
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
        let mainThreshold = calibration.mainThreshold(atTime: time)
        let stricterThreshold = calibration.stricterThreshold(atTime: time)
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
                threshold: calibration.stricterThreshold(atTime: measurements[stricterStart].windowCenterSeconds)
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
                threshold: calibration.mainThreshold(atTime: measurements[mainGapStartIndex].windowCenterSeconds)
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

    /// SPEC.md §4.11, "RMS time resolution and threshold-crossing
    /// interpolation": `t_cross = t₁ + (thresholdDb − db₁) / (db₂ − db₁) × hop`,
    /// applied uniformly to every crossing this contract defines. Returns
    /// `atIndex`'s own time directly when there's no prior measurement to
    /// interpolate against (a transition at the very first measurement).
    private func interpolateCrossing(beforeIndex: Int, atIndex: Int, threshold: Double) -> Double {
        guard beforeIndex >= 0 else { return measurements[atIndex].windowCenterSeconds }
        let before = measurements[beforeIndex]
        let at = measurements[atIndex]
        guard at.rmsDb != before.rmsDb else { return at.windowCenterSeconds }
        let fraction = (threshold - before.rmsDb) / (at.rmsDb - before.rmsDb)
        return before.windowCenterSeconds + fraction * (at.windowCenterSeconds - before.windowCenterSeconds)
    }
}
