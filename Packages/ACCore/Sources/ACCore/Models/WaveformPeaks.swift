import Foundation

/// A fixed-size, downsampled min/max peak array summarizing an `AudioAsset`
/// for waveform display — never raw or full-resolution sample data (SPEC.md
/// §4.15). Generated once, automatically, immediately after import
/// (`GenerateWaveformPeaksUseCase`), and persisted to `Project.waveformPeaks`
/// — not lazily computed on first view.
///
/// `resolution` is fixed regardless of source file length, which is what
/// bounds this type's memory footprint (4096 buckets × 2 `Float` = 32KB) and
/// lets it exist as a plain `ACCore` value type despite the project-wide
/// "never load a full WAV into memory" constraint — the same reasoning
/// `AudioAsset`'s metadata-only invariant relies on.
public struct WaveformPeaks: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let audioAssetID: AudioAsset.ID
    public let resolution: Int
    public let buckets: [WaveformPeakBucket]

    public init(
        id: UUID = UUID(),
        audioAssetID: AudioAsset.ID,
        resolution: Int,
        buckets: [WaveformPeakBucket]
    ) {
        self.id = id
        self.audioAssetID = audioAssetID
        self.resolution = resolution
        self.buckets = buckets
    }
}
