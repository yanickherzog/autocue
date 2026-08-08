import ACCore
import Foundation

/// An in-memory `AudioAnalysisRepository` fake (`ROADMAP.md` D3/T3.4) —
/// returns canned results supplied at construction rather than doing any real
/// audio I/O, per `CONTRIBUTING.md` §5. Real `ACAudioKit` behavior is tested
/// against real fixture WAV files (`ROADMAP.md` D8/D9); this fake exists so
/// `ACCore`/`ACFeatures` callers of `AudioAnalysisRepository` can be tested
/// without either.
public struct InMemoryAudioAnalysisRepository: AudioAnalysisRepository, Sendable {
    public let importedAsset: AudioAsset
    public let generatedWaveformPeaks: WaveformPeaks
    public let waveformDetailBuckets: [WaveformPeakBucket]
    public let detectedCues: [Cue]

    public init(
        importedAsset: AudioAsset = InMemoryAudioAnalysisRepository.placeholderAudioAsset(),
        generatedWaveformPeaks: WaveformPeaks? = nil,
        waveformDetailBuckets: [WaveformPeakBucket] = [],
        detectedCues: [Cue] = []
    ) {
        self.importedAsset = importedAsset
        self.generatedWaveformPeaks = generatedWaveformPeaks
            ?? WaveformPeaks(audioAssetID: importedAsset.id, resolution: 0, buckets: [])
        self.waveformDetailBuckets = waveformDetailBuckets
        self.detectedCues = detectedCues
    }

    public func importAudio(from _: URL) -> AsyncThrowingStream<OperationProgress<AudioAsset>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.progress(ProgressUpdate(fractionCompleted: 1.0)))
            continuation.yield(.completed(importedAsset))
            continuation.finish()
        }
    }

    public func generateWaveformPeaks(
        for _: AudioAsset
    ) -> AsyncThrowingStream<OperationProgress<WaveformPeaks>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.progress(ProgressUpdate(fractionCompleted: 1.0)))
            continuation.yield(.completed(generatedWaveformPeaks))
            continuation.finish()
        }
    }

    public func generateWaveformDetail(
        for _: AudioAsset,
        startSeconds _: Double,
        endSeconds _: Double,
        resolution _: Int
    ) async throws -> [WaveformPeakBucket] {
        waveformDetailBuckets
    }

    public func detectCues(
        in _: AudioAsset,
        settings _: AnalysisSettings
    ) -> AsyncThrowingStream<OperationProgress<[Cue]>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.progress(ProgressUpdate(fractionCompleted: 1.0)))
            continuation.yield(.completed(detectedCues))
            continuation.finish()
        }
    }

    public static func placeholderAudioAsset() -> AudioAsset {
        AudioAsset(
            originalFileName: "fixture.wav",
            securityScopedBookmark: Data(),
            duration: MediaDuration(seconds: 60),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
