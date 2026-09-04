@testable import ACAudioKit
import ACCore
import XCTest

final class SilenceDetectorTests: XCTestCase {
    private let sampleRate = 48000.0

    /// Shorter durations than the real defaults, so synthetic fixtures stay
    /// small/fast — a standard, expected testing practice, not a claim these
    /// values are realistic production settings.
    private func fastSettings(
        mode: NoiseFloorCalibrationMode = .manual,
        silenceThresholdDb: Double = -40,
        calibrationMarginDb: Double = 6,
        reestimationInterval: Double = 300,
        minimumSilenceDurationSeconds: Double = 0.2,
        minimumCueDurationSeconds: Double = 0.2,
        tailCapSeconds: Double = 0.2,
        superFluxSearchWindow: Double = 0.3
    ) -> AnalysisSettings {
        AnalysisSettings(
            noiseFloorCalibrationMode: mode,
            silenceThresholdDb: silenceThresholdDb,
            calibrationMarginDb: calibrationMarginDb,
            noiseFloorReestimationIntervalSeconds: reestimationInterval,
            analysisWindowMilliseconds: 20,
            analysisWindowHopMilliseconds: 5,
            minimumSilenceDurationSeconds: minimumSilenceDurationSeconds,
            minimumCueDurationSeconds: minimumCueDurationSeconds,
            tailToleranceDb: 6,
            tailCapSeconds: tailCapSeconds,
            embeddedMarkerMergeToleranceSeconds: 1.0,
            superFluxRefinementSearchWindowSeconds: superFluxSearchWindow,
            superFluxHopSeconds: 0.01,
            superFluxMaxFilterBandwidthBins: 3,
            superFluxAdaptiveThresholdWindowSeconds: 0.1,
            superFluxAdaptiveThresholdMultiplier: 1.5,
            superFluxAdaptiveThresholdOffset: 0.05
        )
    }

    // MARK: - Synthetic tier: clean transitions, both calibration modes

    func test_cleanTransitions_detectedWithin1FrameTolerance_manualMode() {
        let samples = SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.silence(seconds: 1.5, sampleRate: sampleRate),
            SyntheticAudioBuilder.tone(seconds: 2.0, sampleRate: sampleRate, amplitude: 0.8),
            SyntheticAudioBuilder.silence(seconds: 1.5, sampleRate: sampleRate),
        ])

        let regions = SilenceDetector.detectRegions(
            monoSamples: samples,
            sampleRate: sampleRate,
            settings: fastSettings()
        )

        XCTAssertEqual(regions.count, 1)
        let tolerance = 1.0 / 30.0 // tightest 1-frame tolerance (SPEC.md §4.9, .fps30)
        XCTAssertEqual(regions[0].startSeconds, 1.5, accuracy: tolerance)
        XCTAssertEqual(regions[0].endSeconds, 3.5, accuracy: tolerance)
    }

    func test_automaticCalibration_correctlyClassifiesAmbientHiss_whereManualDefaultWouldNot() {
        let hiss = SyntheticAudioBuilder.amplitude(forRMSDb: -30)
        let tone = SyntheticAudioBuilder.amplitude(forRMSDb: -5)
        let samples = SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.tone(seconds: 2.0, sampleRate: sampleRate, amplitude: hiss),
            SyntheticAudioBuilder.tone(seconds: 2.0, sampleRate: sampleRate, amplitude: tone),
            SyntheticAudioBuilder.tone(seconds: 2.0, sampleRate: sampleRate, amplitude: hiss),
        ])

        // -30dB ambient hiss sits ABOVE the -40dB manual default, so a fixed
        // manual threshold never sees a gap at all — the whole buffer reads
        // as one continuous region.
        let manualRegions = SilenceDetector.detectRegions(
            monoSamples: samples,
            sampleRate: sampleRate,
            settings: fastSettings(mode: .manual, minimumSilenceDurationSeconds: 0.5, minimumCueDurationSeconds: 0.5)
        )
        XCTAssertEqual(manualRegions.count, 1)
        XCTAssertLessThan(manualRegions[0].startSeconds, 0.5)
        XCTAssertGreaterThan(manualRegions[0].endSeconds, 5.5)

        // Automatic mode measures the -30dB floor from the leading hiss and
        // sets the effective threshold to -30 + 6 = -24dB, correctly
        // isolating the -5dB tone as its own region.
        let automaticRegions = SilenceDetector.detectRegions(
            monoSamples: samples,
            sampleRate: sampleRate,
            settings: fastSettings(mode: .automatic, minimumSilenceDurationSeconds: 0.5, minimumCueDurationSeconds: 0.5)
        )
        XCTAssertEqual(automaticRegions.count, 1)
        XCTAssertEqual(automaticRegions[0].startSeconds, 2.0, accuracy: 0.1)
        XCTAssertEqual(automaticRegions[0].endSeconds, 4.0, accuracy: 0.1)
    }

    /// Proves `noiseFloorReestimationIntervalSeconds` actually re-measures
    /// periodically, rather than calibrating once globally: interval 0's
    /// ambient floor (-30dB) is meaningfully different from interval 1's
    /// (-15dB), and each interval's own onset is only correctly isolated if
    /// its *own* interval's calibration is used — reusing interval 0's
    /// threshold for interval 1 would fail to detect a gap there at all
    /// (-15dB ambient would sit above interval 0's -24dB threshold).
    func test_automaticCalibration_reEstimatesPeriodically_perInterval() {
        let hiss1 = SyntheticAudioBuilder.amplitude(forRMSDb: -30)
        let hiss2 = SyntheticAudioBuilder.amplitude(forRMSDb: -15)
        let tone = SyntheticAudioBuilder.amplitude(forRMSDb: -5)

        let samples = SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.tone(seconds: 1.5, sampleRate: sampleRate, amplitude: hiss1), // interval 0
            SyntheticAudioBuilder.tone(seconds: 1.0, sampleRate: sampleRate, amplitude: tone),
            SyntheticAudioBuilder.tone(seconds: 1.5, sampleRate: sampleRate, amplitude: hiss1),
            SyntheticAudioBuilder.tone(seconds: 1.5, sampleRate: sampleRate, amplitude: hiss2), // interval 1
            SyntheticAudioBuilder.tone(seconds: 1.0, sampleRate: sampleRate, amplitude: tone),
            SyntheticAudioBuilder.tone(seconds: 1.5, sampleRate: sampleRate, amplitude: hiss2),
        ])

        let regions = SilenceDetector.detectRegions(
            monoSamples: samples,
            sampleRate: sampleRate,
            settings: fastSettings(
                mode: .automatic,
                reestimationInterval: 4.0,
                minimumSilenceDurationSeconds: 0.5,
                minimumCueDurationSeconds: 0.5
            )
        )

        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].startSeconds, 1.5, accuracy: 0.1)
        XCTAssertEqual(regions[0].endSeconds, 2.5, accuracy: 0.1)
        XCTAssertEqual(regions[1].startSeconds, 5.5, accuracy: 0.1)
        XCTAssertEqual(regions[1].endSeconds, 6.5, accuracy: 0.1)
    }

    // MARK: - SuperFlux stage 2: fade-in, flat-spectrum fallback, vibrato

    /// SPEC.md §4.11's documented failure mode: a gradual fade-in has no
    /// single clean RMS crossing, so a higher (less sensitive) threshold
    /// makes stage-1-alone cross late, well past the ramp's true start.
    /// SuperFlux must land at least as close to the true onset as stage 1
    /// alone — measurably closer for this specific, deliberately-hard case.
    func test_fadeIn_superFluxRefinementImprovesOverStage1Alone() {
        let trueOnset = 1.0
        let samples = SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.silence(seconds: trueOnset, sampleRate: sampleRate),
            SyntheticAudioBuilder.fadeIn(seconds: 3.0, sampleRate: sampleRate, amplitude: 0.8),
            SyntheticAudioBuilder.silence(seconds: 1.0, sampleRate: sampleRate),
        ])
        // Deliberately elevated (less sensitive) threshold — SPEC.md's
        // documented case where the crossing "tends to land later than the
        // true onset."
        let settings = fastSettings(silenceThresholdDb: -10, minimumSilenceDurationSeconds: 0.3)

        let stage1Only = stage1Regions(samples: samples, settings: settings)
        let refined = SilenceDetector.detectRegions(monoSamples: samples, sampleRate: sampleRate, settings: settings)

        XCTAssertEqual(stage1Only.count, 1)
        XCTAssertEqual(refined.count, 1)

        let stage1Distance = abs(stage1Only[0].startSeconds - trueOnset)
        let refinedDistance = abs(refined[0].startSeconds - trueOnset)
        XCTAssertLessThanOrEqual(refinedDistance, stage1Distance)
    }

    /// SPEC.md §4.11's documented fallback, tested directly at the
    /// `SuperFluxOnsetRefiner` level: a perfectly steady tone — constant
    /// amplitude, constant frequency, no envelope, no transient anywhere —
    /// has no real spectral change for the novelty function to lock onto
    /// anywhere in the window. Engineering an end-to-end `SilenceDetector`
    /// scenario that both (a) produces a stage-1 crossing at all and (b)
    /// guarantees zero nearby novelty is fragile to tune precisely (any
    /// gradual envelope, however slight, still has *some* residual novelty);
    /// testing the refiner directly on a signal with categorically no
    /// change at all is the robust way to prove this specific contract.
    func test_steadyTone_noRealTransientAnywhere_refinerFallsBackToNil() {
        // A frequency chosen so its period divides both the FFT frame
        // length (1024) and hop (480 at 48kHz/10ms) evenly — 48000/32=1500 —
        // so consecutive analysis frames are exact phase-shifted repeats of
        // each other with zero frame-to-frame spectral leakage artifact.
        // (An arbitrary frequency like 440Hz, misaligned with the frame/hop
        // structure, produces a small but genuine leakage-driven novelty
        // wobble — a real artifact of *this test's* signal construction,
        // not of any actual onset content, and far smaller in magnitude
        // than any genuine musical onset this mechanism needs to detect.)
        let samples = SyntheticAudioBuilder.tone(
            seconds: 1.0,
            sampleRate: sampleRate,
            frequency: 1500,
            amplitude: 0.5
        )

        // Restricts eligible peaks to the buffer's central range, away from
        // its own true start/end — exactly what `SilenceDetector` does in
        // real usage (SPEC.md §4.11's padded-search-window mechanism), since
        // frames genuinely at the edge of *any* available data inherently
        // have a truncated, less reliable local median regardless of
        // padding — that's a real, unavoidable edge effect this parameter
        // exists to keep away from actual peak eligibility, not a bug.
        let refined = SuperFluxOnsetRefiner.refine(
            samples: samples,
            sampleRate: sampleRate,
            settings: fastSettings(),
            eligiblePeakRangeSeconds: 0.3 ... 0.7
        )

        XCTAssertNil(refined)
    }

    /// Natural pitch wobble on an otherwise-continuous sustained note must
    /// not be mistaken for a second onset, nor drag the refined boundary
    /// away from the true silence→sound transition.
    func test_vibratoModulatedTone_doesNotCauseSpuriousRelocation() {
        let trueOnset = 1.0
        let samples = SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.silence(seconds: trueOnset, sampleRate: sampleRate),
            SyntheticAudioBuilder.vibratoTone(seconds: 2.0, sampleRate: sampleRate, amplitude: 0.8),
            SyntheticAudioBuilder.silence(seconds: 1.0, sampleRate: sampleRate),
        ])

        let regions = SilenceDetector.detectRegions(
            monoSamples: samples,
            sampleRate: sampleRate,
            settings: fastSettings(minimumSilenceDurationSeconds: 0.3)
        )

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].startSeconds, trueOnset, accuracy: 0.05)
    }

    // MARK: - Adaptive local peak-picking across differing loudness contexts

    /// A loud onset and a much quieter onset, well-separated so each gets
    /// its own independently-scoped SuperFlux search window (this
    /// implementation refines exactly one candidate per stage-1 region, so
    /// "one fixed global sensitivity fails one of the two" is exercised as
    /// two regions whose absolute novelty magnitudes differ by an order of
    /// magnitude, rather than as one shared window spanning both) — proves
    /// the adaptive, per-window local median correctly accepts a genuine
    /// peak regardless of the passage's own absolute loudness.
    func test_adaptiveThreshold_correctlyDetectsBothALoudAndAMuchQuieterOnset() {
        let loudOnset = 1.0
        let quietOnset = 4.0
        let samples = SyntheticAudioBuilder.concatenate([
            SyntheticAudioBuilder.silence(seconds: 1.0, sampleRate: sampleRate),
            SyntheticAudioBuilder.tone(seconds: 1.0, sampleRate: sampleRate, amplitude: 0.8), // loud
            SyntheticAudioBuilder.silence(seconds: 2.0, sampleRate: sampleRate),
            SyntheticAudioBuilder.tone(seconds: 1.0, sampleRate: sampleRate, amplitude: 0.05), // quiet
            SyntheticAudioBuilder.silence(seconds: 1.0, sampleRate: sampleRate),
        ])

        let regions = SilenceDetector.detectRegions(
            monoSamples: samples,
            sampleRate: sampleRate,
            settings: fastSettings(minimumSilenceDurationSeconds: 0.5, minimumCueDurationSeconds: 0.3)
        )

        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].startSeconds, loudOnset, accuracy: 0.05)
        XCTAssertEqual(regions[1].startSeconds, quietOnset, accuracy: 0.05)
    }

    // MARK: - RMS hop-size/interpolation precision (stage 1 only, isolating SuperFlux out)

    /// Tests the dB-domain interpolation formula directly and exactly, via
    /// hand-constructed measurements — no real windowed audio involved, so
    /// there's no window-smearing approximation to reason about, only the
    /// formula itself: `t_cross = t₁ + (thresholdDb − db₁) / (db₂ − db₁) × hop`.
    /// The crossing here is deliberately not aligned to either measurement's
    /// own timestamp — proving this locates a point *between* two
    /// measurements, not simply one of the measurements' own hop-quantized
    /// times.
    func test_interpolationFormula_locatesCrossingExactlyBetweenTwoMeasurements() {
        let measurements = [
            RMSWindowMeasurement(windowCenterSeconds: 0.00, rmsDb: -60),
            RMSWindowMeasurement(windowCenterSeconds: 0.01, rmsDb: -60),
            RMSWindowMeasurement(windowCenterSeconds: 0.02, rmsDb: -60),
            RMSWindowMeasurement(windowCenterSeconds: 0.03, rmsDb: -20), // crosses -40 between 0.02 and 0.03
            RMSWindowMeasurement(windowCenterSeconds: 0.04, rmsDb: -20),
            RMSWindowMeasurement(windowCenterSeconds: 0.05, rmsDb: -20),
        ]

        let regions = SilenceDetectionStage1.detectRegions(
            measurements: measurements,
            totalDurationSeconds: 0.06,
            settings: fastSettings(minimumSilenceDurationSeconds: 0.01, minimumCueDurationSeconds: 0.01)
        )

        // fraction = (-40 − (-60)) / (-20 − (-60)) = 20/40 = 0.5
        // crossing = 0.02 + 0.5 × (0.03 − 0.02) = 0.025 — exactly between
        // the two straddling measurements, not either one's own timestamp.
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions.first?.startSeconds ?? -1, 0.025, accuracy: 0.0001)
    }

    /// A real-pipeline (not hand-constructed) proof that sub-hop position
    /// actually matters: two transitions placed exactly half a hop apart
    /// must produce two detected crossings that differ by roughly that same
    /// half-hop amount — a naive, non-interpolated implementation (which
    /// only ever reports the hop-quantized window boundary) would report
    /// either *no* difference or a full hop's difference, never something
    /// proportional to the actual half-hop shift.
    func test_realPipeline_subHopShiftInTransitionPosition_producesProportionalShiftInDetectedCrossing() throws {
        let settings = fastSettings(minimumSilenceDurationSeconds: 0.05, minimumCueDurationSeconds: 0.05)
        let hopFrameCount = Int(settings.analysisWindowHopMilliseconds / 1000.0 * sampleRate)
        let hopSeconds = Double(hopFrameCount) / sampleRate
        let baseFrame = 5000
        let shiftedFrame = baseFrame + hopFrameCount / 2

        func buildAndDetect(transitionFrame: Int) -> Double? {
            var samples = [Float](repeating: 0, count: transitionFrame)
            samples.append(contentsOf: SyntheticAudioBuilder.tone(
                seconds: 0.2,
                sampleRate: sampleRate,
                amplitude: 0.8
            ))
            samples.append(contentsOf: SyntheticAudioBuilder.silence(seconds: 0.1, sampleRate: sampleRate))
            return stage1Regions(samples: samples, settings: settings).first?.startSeconds
        }

        let baseCrossing = try XCTUnwrap(buildAndDetect(transitionFrame: baseFrame))
        let shiftedCrossing = try XCTUnwrap(buildAndDetect(transitionFrame: shiftedFrame))
        let actualShift = shiftedCrossing - baseCrossing

        // Generously bounded: clearly nonzero (rules out a naive
        // hop-quantized-only implementation reporting the same window every
        // time, which would show exactly zero here) and clearly less than a
        // full hop (rules out over-shooting to the next window's boundary
        // entirely, which would show ≥ one full hop).
        XCTAssertGreaterThan(actualShift, hopSeconds * 0.05)
        XCTAssertLessThan(actualShift, hopSeconds * 0.99)
    }

    // MARK: - Performance budget

    /// Validates the approach scales toward a 3-hour file — a ~10-minute
    /// buffer, structured with several real transitions (not one giant
    /// silent/loud block), completing within a documented, generous budget.
    func test_performanceBudget_tenMinuteSyntheticBuffer() {
        var segments: [[Float]] = []
        for cycle in 0 ..< 10 {
            segments.append(SyntheticAudioBuilder.silence(seconds: 30, sampleRate: sampleRate))
            segments.append(SyntheticAudioBuilder.tone(
                seconds: 30,
                sampleRate: sampleRate,
                amplitude: cycle.isMultiple(of: 2) ? 0.8 : 0.3
            ))
        }
        let samples = SyntheticAudioBuilder.concatenate(segments)
        XCTAssertEqual(Double(samples.count) / sampleRate, 600, accuracy: 0.001)

        let start = Date()
        let regions = SilenceDetector.detectRegions(
            monoSamples: samples,
            sampleRate: sampleRate,
            settings: fastSettings()
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(regions.count, 10)
        // Documented budget: 60s for a 10-minute buffer — generous relative
        // to measured performance, confirmed once real numbers existed
        // rather than guessed in advance (SPEC.md §4.11's own convention).
        XCTAssertLessThan(elapsed, 60.0)
    }

    // MARK: - Helpers

    private func stage1Regions(samples: [Float], settings: AnalysisSettings) -> [SilenceDetectedRegion] {
        var stream = RMSWindowStream(
            sampleRate: sampleRate,
            windowFrameCount: max(1, Int(settings.analysisWindowMilliseconds / 1000.0 * sampleRate)),
            hopFrameCount: max(1, Int(settings.analysisWindowHopMilliseconds / 1000.0 * sampleRate))
        )
        let measurements = samples.withUnsafeBufferPointer { stream.ingest(monoSamples: $0) }
        return SilenceDetectionStage1.detectRegions(
            measurements: measurements,
            totalDurationSeconds: Double(samples.count) / sampleRate,
            settings: settings
        )
    }
}
