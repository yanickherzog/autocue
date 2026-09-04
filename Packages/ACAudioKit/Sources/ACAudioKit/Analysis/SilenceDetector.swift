import ACCore
import AVFoundation
import Foundation

/// The full two-stage boundary detection contract (SPEC.md §4.11):
/// overlapping-hop windowed RMS with dB-domain threshold-crossing
/// interpolation and reverb-tail truncation (stage 1), refined by SuperFlux
/// onset detection for cue *starts* only (stage 2). Never touches
/// `AudioAsset.embeddedMarkers` and never constructs `Cue` — merging against
/// embedded markers is `DetectCuesUseCase`'s job (`ROADMAP.md` D9/T9.1).
///
/// **Two entry points, one algorithm.** `detectRegions(monoSamples:...)`
/// operates directly over an in-memory buffer — the convenient, file-free
/// entry point every synthetic test in `SilenceDetectorTests` uses.
/// `detectRegions(reader:...)` drives the same algorithm from a real file via
/// `WAVStreamingReader`, for `AudioAnalysisRepositoryImpl` and
/// `SilenceDetectorRealFixtureTests`. Both feed the identical
/// `RMSWindowStream` → `SilenceDetectionStage1` → SuperFlux refinement
/// pipeline; the only difference is where the mono samples come from.
enum SilenceDetector {
    /// Runs the full pipeline over an already-in-memory mono sample buffer.
    /// Safe for test-scale buffers (seconds to tens of seconds); not used
    /// for real files, which stream via the `reader:` overload below instead
    /// of ever holding a whole file's samples in one array.
    static func detectRegions(
        monoSamples: [Float],
        sampleRate: Double,
        settings: AnalysisSettings
    ) -> [SilenceDetectedRegion] {
        var stream = RMSWindowStream(
            sampleRate: sampleRate,
            windowFrameCount: frameCount(forMilliseconds: settings.analysisWindowMilliseconds, sampleRate: sampleRate),
            hopFrameCount: frameCount(forMilliseconds: settings.analysisWindowHopMilliseconds, sampleRate: sampleRate)
        )
        let measurements = monoSamples.withUnsafeBufferPointer { stream.ingest(monoSamples: $0) }
        let totalDurationSeconds = Double(monoSamples.count) / sampleRate

        let stage1Regions = SilenceDetectionStage1.detectRegions(
            measurements: measurements,
            totalDurationSeconds: totalDurationSeconds,
            settings: settings
        )

        return stage1Regions.map { region in
            refineOnset(
                of: region,
                monoSamples: monoSamples,
                sampleRate: sampleRate,
                settings: settings
            )
        }
    }

    /// Drives the same pipeline from a real file, streaming raw samples in
    /// bounded chunks (never loading the whole file) and accumulating only
    /// the much smaller derived RMS-measurement array in full — see
    /// `RMSWindowStream`'s doc comment for why that's safe even for a
    /// 3-hour file. Stage 2's SuperFlux refinement re-reads a small, bounded
    /// window directly from the file at each stage-1 candidate's position —
    /// never the whole file either.
    static func detectRegions(
        reader: WAVStreamingReader,
        settings: AnalysisSettings,
        chunkFrameCount: AVAudioFrameCount = WAVStreamingReader.defaultChunkFrameCount,
        onProgress: ((Double) -> Void)? = nil
    ) throws -> [SilenceDetectedRegion] {
        let sampleRate = reader.sampleRate
        var stream = RMSWindowStream(
            sampleRate: sampleRate,
            windowFrameCount: frameCount(forMilliseconds: settings.analysisWindowMilliseconds, sampleRate: sampleRate),
            hopFrameCount: frameCount(forMilliseconds: settings.analysisWindowHopMilliseconds, sampleRate: sampleRate)
        )

        reader.seek(toFrame: 0)
        var measurements: [RMSWindowMeasurement] = []
        var framesProcessed = 0
        let totalFrameCount = Int(reader.totalFrameCount)
        let channelCount = reader.channelCount
        var mixdownBuffer = [Float](repeating: 0, count: Int(chunkFrameCount))

        while let buffer = try reader.readNextChunk(maxFrameCount: chunkFrameCount) {
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0, let channelData = buffer.floatChannelData else { break }

            if channelCount <= 1 {
                let monoPointer = UnsafeBufferPointer(start: channelData[0], count: frameLength)
                measurements.append(contentsOf: stream.ingest(monoSamples: monoPointer))
            } else {
                mixdownBuffer.withUnsafeMutableBufferPointer { mixPointer in
                    MonoMixdown.mixdown(
                        channelData: channelData,
                        channelCount: channelCount,
                        frameLength: frameLength,
                        into: mixPointer
                    )
                    let monoPointer = UnsafeBufferPointer(start: mixPointer.baseAddress, count: frameLength)
                    measurements.append(contentsOf: stream.ingest(monoSamples: monoPointer))
                }
            }

            framesProcessed += frameLength
            if totalFrameCount > 0 {
                onProgress?(Double(framesProcessed) / Double(totalFrameCount))
            }
        }

        let stage1Regions = SilenceDetectionStage1.detectRegions(
            measurements: measurements,
            totalDurationSeconds: reader.durationSeconds,
            settings: settings
        )

        return try stage1Regions.map { region in
            try refineOnset(of: region, reader: reader, settings: settings)
        }
    }

    // MARK: - Stage 2 (SuperFlux) glue

    /// In-memory variant: SuperFlux's bounded search window is just a slice
    /// of the already-in-memory buffer — no file I/O involved at all.
    private static func refineOnset(
        of region: SilenceDetectedRegion,
        monoSamples: [Float],
        sampleRate: Double,
        settings: AnalysisSettings
    ) -> SilenceDetectedRegion {
        let bounds = SuperFluxWindowBounds(
            candidateSeconds: region.startSeconds,
            durationSeconds: Double(monoSamples.count) / sampleRate,
            settings: settings
        )
        let startFrame = Int(bounds.paddedStartSeconds * sampleRate)
        let endFrame = min(Int(bounds.paddedEndSeconds * sampleRate), monoSamples.count)
        guard startFrame < endFrame else { return region }

        let windowSamples = Array(monoSamples[startFrame ..< endFrame])

        guard let refinedOffsetInWindow = SuperFluxOnsetRefiner.refine(
            samples: windowSamples,
            sampleRate: sampleRate,
            settings: settings,
            eligiblePeakRangeSeconds: bounds.eligibleRange
        ) else {
            return region // fallback: no clear peak — stage-1 boundary stands unchanged
        }

        return SilenceDetectedRegion(
            startSeconds: bounds.paddedStartSeconds + refinedOffsetInWindow,
            endSeconds: region.endSeconds
        )
    }

    /// File-driving variant: reads just the bounded search-window range
    /// directly from the file via `reader`, never the whole file.
    private static func refineOnset(
        of region: SilenceDetectedRegion,
        reader: WAVStreamingReader,
        settings: AnalysisSettings
    ) throws -> SilenceDetectedRegion {
        let sampleRate = reader.sampleRate
        let bounds = SuperFluxWindowBounds(
            candidateSeconds: region.startSeconds,
            durationSeconds: reader.durationSeconds,
            settings: settings
        )
        let startFrame = AVAudioFramePosition(bounds.paddedStartSeconds * sampleRate)
        let endFrame = AVAudioFramePosition(bounds.paddedEndSeconds * sampleRate)
        guard startFrame < endFrame else { return region }

        reader.seek(toFrame: startFrame)
        var windowSamples: [Float] = []
        let channelCount = reader.channelCount
        var remaining = Int(endFrame - startFrame)
        var mixdownBuffer = [Float](repeating: 0, count: remaining)

        while remaining > 0, let buffer = try reader.readNextChunk(maxFrameCount: AVAudioFrameCount(remaining)) {
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0, let channelData = buffer.floatChannelData else { break }
            if channelCount <= 1 {
                windowSamples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameLength))
            } else {
                mixdownBuffer.withUnsafeMutableBufferPointer { mixPointer in
                    MonoMixdown.mixdown(
                        channelData: channelData,
                        channelCount: channelCount,
                        frameLength: frameLength,
                        into: mixPointer
                    )
                }
                windowSamples.append(contentsOf: mixdownBuffer.prefix(frameLength))
            }
            remaining -= frameLength
        }

        guard let refinedOffsetInWindow = SuperFluxOnsetRefiner.refine(
            samples: windowSamples,
            sampleRate: sampleRate,
            settings: settings,
            eligiblePeakRangeSeconds: bounds.eligibleRange
        ) else {
            return region
        }

        return SilenceDetectedRegion(
            startSeconds: bounds.paddedStartSeconds + refinedOffsetInWindow,
            endSeconds: region.endSeconds
        )
    }

    private static func frameCount(forMilliseconds milliseconds: Double, sampleRate: Double) -> Int {
        max(1, Int((milliseconds / 1000.0) * sampleRate))
    }
}

/// Computes the padded window bounds around one stage-1 onset candidate —
/// shared by both `refineOnset` overloads. SPEC.md §4.11: the real search
/// window is `candidateSeconds ± superFluxRefinementSearchWindowSeconds`;
/// the *computed* window additionally pads `superFluxAdaptiveThresholdWindowSeconds / 2`
/// on each side so frames right at the real search window's own edges still
/// get a well-formed, non-truncated local median for adaptive peak-picking.
private struct SuperFluxWindowBounds {
    let paddedStartSeconds: Double
    let paddedEndSeconds: Double
    private let realSearchStartSeconds: Double
    private let realSearchEndSeconds: Double

    init(candidateSeconds: Double, durationSeconds: Double, settings: AnalysisSettings) {
        let searchWindow = settings.superFluxRefinementSearchWindowSeconds
        let extraPad = settings.superFluxAdaptiveThresholdWindowSeconds / 2
        realSearchStartSeconds = max(0, candidateSeconds - searchWindow)
        realSearchEndSeconds = min(durationSeconds, candidateSeconds + searchWindow)
        paddedStartSeconds = max(0, candidateSeconds - searchWindow - extraPad)
        paddedEndSeconds = min(durationSeconds, candidateSeconds + searchWindow + extraPad)
    }

    /// The real (unpadded) search window, expressed relative to the start
    /// of the *padded* window actually extracted for analysis — this is
    /// what `SuperFluxOnsetRefiner` needs to know which frames are eligible
    /// peak candidates versus padding-only context.
    var eligibleRange: ClosedRange<Double> {
        (realSearchStartSeconds - paddedStartSeconds) ... (realSearchEndSeconds - paddedStartSeconds)
    }
}
