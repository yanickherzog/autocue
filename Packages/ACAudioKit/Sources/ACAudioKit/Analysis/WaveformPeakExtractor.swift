import Accelerate
import ACCore
import AVFoundation
import Foundation

/// Reduces a `WAVStreamingReader`'s bounded chunks to a fixed-size array of
/// min/max peak buckets (SPEC.md §4.15) — one implementation serving both
/// the whole-file, fixed-4096-bucket persisted overview
/// (`GenerateWaveformPeaksUseCase`) and bounded-range, caller-supplied-
/// resolution on-demand detail (`GenerateWaveformDetailUseCase`), since both
/// call shapes need the identical min/max-per-bucket reduction — never two
/// near-duplicate implementations (`CLAUDE.md` rule 7).
///
/// Multi-channel source audio is mixed down to mono before reduction
/// (SPEC.md §4.15, "v1 simplification: mono mixdown, not per-channel").
/// Every reduction step is `Accelerate`/vDSP (`vDSP_minv`/`vDSP_maxv` for the
/// reduction itself, `vDSP_vadd`/`vDSP_vsmul` for the mixdown) — no
/// hand-rolled sample loops (`CLAUDE.md`, Performance Considerations).
enum WaveformPeakExtractor {
    /// - Parameters:
    ///   - reader: positioned via `seek(toFrame:)` internally — callers
    ///     don't need to pre-seek.
    ///   - startFrame/endFrame: the sample range to reduce; `endFrame` `nil`
    ///     means "to the end of the file" (the whole-file overview case).
    ///   - resolution: bucket count — fixed at 4096 for the persisted
    ///     overview, caller-supplied for on-demand detail.
    ///   - onProgress: called with `0.0...1.0` after each chunk — plain
    ///     synchronous callback; `AudioAnalysisRepositoryImpl` wraps this
    ///     into the shared `AsyncThrowingStream<OperationProgress<T>, Error>`
    ///     contract at the Repository boundary, not here.
    static func extract(
        reader: WAVStreamingReader,
        resolution: Int,
        startFrame: AVAudioFramePosition = 0,
        endFrame: AVAudioFramePosition? = nil,
        chunkFrameCount: AVAudioFrameCount = WAVStreamingReader.defaultChunkFrameCount,
        onProgress: ((Double) -> Void)? = nil
    ) throws -> [WaveformPeakBucket] {
        let rangeEnd = endFrame ?? reader.totalFrameCount
        let totalFrameCount = Int(rangeEnd - startFrame)
        guard totalFrameCount > 0, resolution > 0 else { return [] }

        reader.seek(toFrame: startFrame)
        var accumulator = WaveformPeakAccumulator(totalFrameCount: totalFrameCount, resolution: resolution)
        var framesProcessed = 0
        let channelCount = reader.channelCount
        var mixdownBuffer = [Float](repeating: 0, count: Int(chunkFrameCount))

        while framesProcessed < totalFrameCount {
            let remaining = totalFrameCount - framesProcessed
            let thisChunkMax = AVAudioFrameCount(min(Int(chunkFrameCount), remaining))
            guard let buffer = try reader.readNextChunk(maxFrameCount: thisChunkMax) else { break }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0, let channelData = buffer.floatChannelData else { break }

            if channelCount <= 1 {
                let monoPointer = UnsafeBufferPointer(start: channelData[0], count: frameLength)
                accumulator.ingest(monoSamples: monoPointer)
            } else {
                mixdownBuffer.withUnsafeMutableBufferPointer { mixPointer in
                    MonoMixdown.mixdown(
                        channelData: channelData,
                        channelCount: channelCount,
                        frameLength: frameLength,
                        into: mixPointer
                    )
                    let monoPointer = UnsafeBufferPointer(start: mixPointer.baseAddress, count: frameLength)
                    accumulator.ingest(monoSamples: monoPointer)
                }
            }

            framesProcessed += frameLength
            onProgress?(Double(framesProcessed) / Double(totalFrameCount))
        }

        return accumulator.finalize()
    }
}

/// Incremental min/max-per-bucket reducer — ingests chunks in any size
/// (independent of bucket width) and correctly attributes each chunk's
/// samples to whichever bucket(s) its global sample range overlaps, since a
/// chunk may span many buckets (short file) or a bucket may span many
/// chunks (long file, small `resolution`) depending on the caller.
private struct WaveformPeakAccumulator {
    private let totalFrameCount: Int
    private let resolution: Int
    private var bucketMins: [Float]
    private var bucketMaxes: [Float]
    private var hasData: [Bool]
    private var globalCursor = 0

    init(totalFrameCount: Int, resolution: Int) {
        self.totalFrameCount = max(totalFrameCount, 0)
        self.resolution = max(resolution, 0)
        bucketMins = [Float](repeating: 0, count: self.resolution)
        bucketMaxes = [Float](repeating: 0, count: self.resolution)
        hasData = [Bool](repeating: false, count: self.resolution)
    }

    mutating func ingest(monoSamples: UnsafeBufferPointer<Float>) {
        defer { globalCursor += monoSamples.count }
        guard resolution > 0, totalFrameCount > 0, let base = monoSamples.baseAddress,
              !monoSamples.isEmpty else { return }

        let chunkGlobalStart = globalCursor
        let chunkLength = monoSamples.count
        let bucketWidth = Double(totalFrameCount) / Double(resolution)
        let firstBucket = min(Int(Double(chunkGlobalStart) / bucketWidth), resolution - 1)
        let lastGlobalIndex = chunkGlobalStart + chunkLength - 1
        let lastBucket = min(Int(Double(lastGlobalIndex) / bucketWidth), resolution - 1)
        guard firstBucket <= lastBucket else { return }

        for bucketIndex in firstBucket ... lastBucket {
            let bucketGlobalStart = Int(Double(bucketIndex) * bucketWidth)
            let bucketGlobalEnd = bucketIndex == resolution - 1
                ? totalFrameCount
                : Int(Double(bucketIndex + 1) * bucketWidth)
            let overlapStart = max(bucketGlobalStart, chunkGlobalStart)
            let overlapEnd = min(bucketGlobalEnd, chunkGlobalStart + chunkLength)
            guard overlapStart < overlapEnd else { continue }

            let localStart = overlapStart - chunkGlobalStart
            let localCount = overlapEnd - overlapStart
            var localMin: Float = 0
            var localMax: Float = 0
            vDSP_minv(base + localStart, 1, &localMin, vDSP_Length(localCount))
            vDSP_maxv(base + localStart, 1, &localMax, vDSP_Length(localCount))

            if hasData[bucketIndex] {
                bucketMins[bucketIndex] = min(bucketMins[bucketIndex], localMin)
                bucketMaxes[bucketIndex] = max(bucketMaxes[bucketIndex], localMax)
            } else {
                bucketMins[bucketIndex] = localMin
                bucketMaxes[bucketIndex] = localMax
                hasData[bucketIndex] = true
            }
        }
    }

    func finalize() -> [WaveformPeakBucket] {
        guard resolution > 0 else { return [] }
        return (0 ..< resolution).map { index in
            WaveformPeakBucket(min: bucketMins[index], max: bucketMaxes[index])
        }
    }
}
