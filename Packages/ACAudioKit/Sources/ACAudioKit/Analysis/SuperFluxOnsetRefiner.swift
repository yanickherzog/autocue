import Accelerate
import ACCore
import Foundation

/// SuperFlux onset refinement (SPEC.md §4.11, "SuperFlux-based onset
/// refinement") — Böck & Widmer, "Maximum Filter Vibrato Suppression for
/// Onset Detection," DAFx 2013. Operates on a small, already-bounded
/// in-memory window (the stage-1 candidate ± `superFluxRefinementSearchWindowSeconds`,
/// sliced out by `SilenceDetector` before calling this) — never a whole
/// file, never even the whole search window pre-fetched by any means other
/// than the one bounded read `SilenceDetector` already performed.
///
/// The five-step signal chain, in order: Hann-windowed STFT → log-frequency
/// filterbank + log compression → maximum filter across neighboring bins
/// (vibrato/tremolo suppression) → half-wave-rectified frame-to-frame
/// novelty → adaptive local peak-picking. FFT itself is `Accelerate`/vDSP
/// (`vDSP_fft_zrip`); the filterbank/max-filter/novelty-sum steps are plain
/// loops over a small bounded frame/band count (tens of frames × a couple
/// hundred bands within one bounded search window) — not the
/// large-sample-count territory `CLAUDE.md`'s "no hand-rolled sample loops"
/// rule is aimed at, which the vDSP FFT step itself satisfies.
enum SuperFluxOnsetRefiner {
    /// Fixed FFT frame length, confirmed at implementation time (SPEC.md
    /// §4.11's "documented reference, confirmed at build time" convention,
    /// same treatment as the ~24-bands/octave filterbank resolution) — 1024
    /// samples (~21ms at 48kHz, ~23ms at 44.1kHz), a standard onset-detection
    /// STFT frame size and a power of two, as `vDSP_fft_zrip` requires.
    private static let fftFrameLength = 1024
    private static let minFilterbankFrequencyHz = 30.0

    /// Returns the refined onset offset, in seconds from the start of
    /// `samples`, or `nil` if no candidate frame clears the adaptive
    /// threshold anywhere in the window — the documented fallback (SPEC.md
    /// §4.11): the caller keeps its stage-1 boundary unchanged in that case.
    ///
    /// - Parameter eligiblePeakRangeSeconds: SPEC.md §4.11: "the novelty
    ///   function is actually computed over the search region padded by
    ///   `superFluxAdaptiveThresholdWindowSeconds / 2` on each side" so
    ///   frames near the *real* search window's own edges still get a
    ///   well-formed, non-truncated local median rather than an asymmetric
    ///   one computed from fewer samples. `samples` is expected to already
    ///   include that padding; this parameter marks which sub-range of it is
    ///   the real (unpadded) search window frames may actually be picked
    ///   from — the padding-only frames still contribute novelty/median
    ///   context but are never themselves eligible peaks. `nil` (the
    ///   default) makes the whole of `samples` eligible, for direct,
    ///   padding-independent unit tests of the refinement mechanism itself.
    static func refine(
        samples: [Float],
        sampleRate: Double,
        settings: AnalysisSettings,
        eligiblePeakRangeSeconds: ClosedRange<Double>? = nil
    ) -> Double? {
        guard samples.count >= fftFrameLength else { return nil }

        let filterbank = LogFrequencyFilterbank.build(
            sampleRate: sampleRate,
            fftFrameLength: fftFrameLength,
            minFrequency: minFilterbankFrequencyHz
        )
        guard !filterbank.isEmpty else { return nil }

        let log2n = vDSP_Length(log2(Double(fftFrameLength)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        let fft = FFTContext(fftSetup: fftSetup, log2n: log2n)

        let hopFrameCount = max(1, Int(settings.superFluxHopSeconds * sampleRate))
        let (frameTimes, novelty) = computeNoveltyFrames(
            samples: samples,
            sampleRate: sampleRate,
            filterbank: filterbank,
            fft: fft,
            settings: settings
        )
        guard novelty.count >= 3 else { return nil } // need prev/current/next for peak-picking

        guard let peakFrame = pickPeak(
            novelty: novelty,
            settings: settings,
            hopSeconds: Double(hopFrameCount) / sampleRate,
            frameTimes: frameTimes,
            eligiblePeakRangeSeconds: eligiblePeakRangeSeconds
        ) else {
            return nil
        }

        return frameTimes[peakFrame]
    }

    /// Steps 1–4 of the signal chain (STFT → filterbank/log-compression →
    /// max filter → half-wave-rectified novelty), split out of `refine`
    /// purely to keep that function within a reasonable length — not a
    /// separately-reusable piece on its own.
    private static func computeNoveltyFrames(
        samples: [Float],
        sampleRate: Double,
        filterbank: [LogFrequencyFilterbank.Filter],
        fft: FFTContext,
        settings: AnalysisSettings
    ) -> (frameTimes: [Double], novelty: [Double]) {
        let hopFrameCount = max(1, Int(settings.superFluxHopSeconds * sampleRate))
        var hannWindow = [Float](repeating: 0, count: fftFrameLength)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftFrameLength), Int32(vDSP_HANN_DENORM))

        var frameTimes: [Double] = []
        var bandValuesPerFrame: [[Float]] = []
        var frameStart = 0
        while frameStart + fftFrameLength <= samples.count {
            let magnitudes = magnitudeSpectrum(
                samples: samples,
                frameStart: frameStart,
                hannWindow: hannWindow,
                fft: fft
            )
            let bandValues = filterbank.map { filter -> Float in
                var sum: Float = 0
                for (index, weight) in filter.bins where index < magnitudes.count {
                    sum += magnitudes[index] * weight
                }
                return sum
            }
            bandValuesPerFrame.append(bandValues.map { Float(log(1.0 + Double($0))) }) // γ = 1
            frameTimes.append(Double(frameStart + fftFrameLength / 2) / sampleRate)
            frameStart += hopFrameCount
        }

        guard bandValuesPerFrame.count >= 3 else { return (frameTimes, []) }

        let maxFiltered = bandValuesPerFrame.map { maxFilter($0, bandwidth: settings.superFluxMaxFilterBandwidthBins) }
        var novelty = [Double](repeating: 0, count: bandValuesPerFrame.count)
        for frame in 1 ..< bandValuesPerFrame.count {
            var sum = 0.0
            let current = bandValuesPerFrame[frame]
            let previousMax = maxFiltered[frame - 1]
            for bin in 0 ..< current.count {
                let diff = Double(current[bin] - previousMax[bin])
                if diff > 0 {
                    sum += diff
                }
            }
            novelty[frame] = sum
        }
        return (frameTimes, novelty)
    }

    /// Bundles the two vDSP FFT handles `magnitudeSpectrum` needs, so that
    /// function stays within SwiftLint's parameter-count threshold.
    private struct FFTContext {
        let fftSetup: FFTSetup
        let log2n: vDSP_Length
    }

    private static func magnitudeSpectrum(
        samples: [Float],
        frameStart: Int,
        hannWindow: [Float],
        fft: FFTContext
    ) -> [Float] {
        let frameLength = fftFrameLength
        var windowed = [Float](repeating: 0, count: frameLength)
        samples.withUnsafeBufferPointer { samplesPointer in
            guard let base = samplesPointer.baseAddress else { return }
            vDSP_vmul(base + frameStart, 1, hannWindow, 1, &windowed, 1, vDSP_Length(frameLength))
        }

        let halfLength = frameLength / 2
        var realp = [Float](repeating: 0, count: halfLength)
        var imagp = [Float](repeating: 0, count: halfLength)
        var magnitudes = [Float](repeating: 0, count: halfLength)

        realp.withUnsafeMutableBufferPointer { realPointer in
            imagp.withUnsafeMutableBufferPointer { imagPointer in
                guard let realBase = realPointer.baseAddress, let imagBase = imagPointer.baseAddress else { return }
                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                windowed.withUnsafeBufferPointer { windowedPointer in
                    guard let windowedBase = windowedPointer.baseAddress else { return }
                    windowedBase.withMemoryRebound(to: DSPComplex.self, capacity: halfLength) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(halfLength))
                    }
                }
                vDSP_fft_zrip(fft.fftSetup, &splitComplex, 1, fft.log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfLength))
            }
        }
        return magnitudes
    }

    /// SPEC.md §4.11, step 3: replaces each bin with the max found within a
    /// `bandwidth`-wide neighborhood centered on it (`bandwidth` odd — one
    /// side each way).
    private static func maxFilter(_ values: [Float], bandwidth: Int) -> [Float] {
        let half = max(bandwidth, 1) / 2
        return values.indices.map { index in
            let lo = max(0, index - half)
            let hi = min(values.count - 1, index + half)
            return values[lo ... hi].max() ?? values[index]
        }
    }

    /// SPEC.md §4.11, "Adaptive local peak-picking": a candidate frame must
    /// be a local maximum *and* clear `median(local window) × multiplier +
    /// offset × peakNoveltyInSearchWindow`. Among frames that pass, the
    /// highest-novelty one wins. `eligiblePeakRangeSeconds` restricts which
    /// frames may actually be *picked* (the real, unpadded search window) —
    /// padding-only frames still contribute to `novelty`'s local medians
    /// (giving eligible edge frames a non-truncated median) but are never
    /// themselves candidates, and `peakNoveltyInSearchWindow` is computed
    /// only over the eligible range too, per SPEC.md's own definition of it
    /// as "the peak novelty... in the current stage-2 search window."
    private static func pickPeak(
        novelty: [Double],
        settings: AnalysisSettings,
        hopSeconds: Double,
        frameTimes: [Double],
        eligiblePeakRangeSeconds: ClosedRange<Double>?
    ) -> Int? {
        guard novelty.count >= 3 else { return nil }
        let medianWindowFrames = max(1, Int(settings.superFluxAdaptiveThresholdWindowSeconds / hopSeconds))

        func isEligible(_ index: Int) -> Bool {
            guard let range = eligiblePeakRangeSeconds else { return true }
            return range.contains(frameTimes[index])
        }

        let eligibleNovelty = novelty.indices.filter(isEligible).map { novelty[$0] }
        let peakNoveltyInSearchWindow = eligibleNovelty.max() ?? 0

        var bestIndex: Int?
        var bestNovelty = -Double.infinity
        for index in 1 ..< (novelty.count - 1) {
            guard isEligible(index) else { continue }
            let value = novelty[index]
            let isLocalMax = value >= novelty[index - 1] && value >= novelty[index + 1] &&
                (value > novelty[index - 1] || value > novelty[index + 1])
            guard isLocalMax else { continue }

            let lo = max(0, index - medianWindowFrames)
            let hi = min(novelty.count - 1, index + medianWindowFrames)
            let localMedian = median(Array(novelty[lo ... hi]))
            let threshold = localMedian * settings.superFluxAdaptiveThresholdMultiplier +
                settings.superFluxAdaptiveThresholdOffset * peakNoveltyInSearchWindow

            guard value > threshold, value > bestNovelty else { continue }
            bestNovelty = value
            bestIndex = index
        }
        return bestIndex
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        guard !sorted.isEmpty else { return 0 }
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

/// A triangular filterbank mapping linear FFT bins onto ~24-bands/octave
/// log-frequency bands (SPEC.md §4.11, step 1) — the same construction
/// technique as a mel-filterbank, log2-spaced instead of mel-spaced.
private enum LogFrequencyFilterbank {
    struct Filter {
        let bins: [(index: Int, weight: Float)]
    }

    static func build(
        sampleRate: Double,
        fftFrameLength: Int,
        bandsPerOctave: Double = 24,
        minFrequency: Double
    ) -> [Filter] {
        let numBins = fftFrameLength / 2
        let nyquist = sampleRate / 2
        guard minFrequency < nyquist, numBins > 0 else { return [] }

        let octaves = log2(nyquist / minFrequency)
        let bandCount = max(Int(octaves * bandsPerOctave), 1)

        var centers: [Double] = []
        for index in 0 ... (bandCount + 1) {
            centers.append(min(minFrequency * pow(2.0, Double(index) / bandsPerOctave), nyquist))
        }

        var filters: [Filter] = []
        filters.reserveCapacity(bandCount)
        for band in 0 ..< bandCount {
            let lowFreq = centers[band]
            let centerFreq = centers[band + 1]
            let highFreq = centers[min(band + 2, centers.count - 1)]

            var bins: [(Int, Float)] = []
            for binIndex in 0 ..< numBins {
                let binFreq = Double(binIndex) * sampleRate / Double(fftFrameLength)
                var weight = 0.0
                if binFreq >= lowFreq, binFreq <= centerFreq, centerFreq > lowFreq {
                    weight = (binFreq - lowFreq) / (centerFreq - lowFreq)
                } else if binFreq > centerFreq, binFreq <= highFreq, highFreq > centerFreq {
                    weight = (highFreq - binFreq) / (highFreq - centerFreq)
                }
                if weight > 0 {
                    bins.append((binIndex, Float(weight)))
                }
            }
            filters.append(Filter(bins: bins))
        }
        return filters
    }
}
