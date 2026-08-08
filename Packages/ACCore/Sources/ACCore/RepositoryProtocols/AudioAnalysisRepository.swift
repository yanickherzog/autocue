import Foundation

/// The Data-layer boundary for everything audio-related — WAV import,
/// waveform peak generation (overview and on-demand detail), and cue
/// detection. Implemented by `ACAudioKit`'s `AudioAnalysisRepositoryImpl`
/// (`ROADMAP.md` D8's `importAudio`/waveform methods; D9's `detectCues`).
/// Per `CLAUDE.md` rule 3, new audio analysis techniques are added here,
/// behind this same protocol — the rest of the app never needs to change
/// when detection heuristics improve.
///
/// `Sendable` per `CLAUDE.md`, "Use Cases Are Stateless" — see
/// `ProjectRepository`'s doc comment for the same reasoning.
///
/// Every long-running method reports progress via the shared
/// `AsyncThrowingStream<OperationProgress<T>, Error>` contract
/// (`CLAUDE.md`, "Long-Running Operations"), except `generateWaveformDetail`
/// — a bounded time-range read is fast enough that a progress UI would be
/// pointless ceremony (SPEC.md §4.15's Long-Running Operations table).
public protocol AudioAnalysisRepository: Sendable {
    /// Imports a WAV file from a user-selected `URL`, producing a populated
    /// `AudioAsset` (SPEC.md §4.10) — including a `securityScopedBookmark`
    /// captured from `url` for later App Sandbox-compliant access.
    func importAudio(from url: URL) -> AsyncThrowingStream<OperationProgress<AudioAsset>, Error>

    /// Produces the persisted, fixed-resolution waveform overview
    /// (SPEC.md §4.15) — run immediately after import, never lazily.
    func generateWaveformPeaks(for asset: AudioAsset) -> AsyncThrowingStream<OperationProgress<WaveformPeaks>, Error>

    /// Computes peaks for a bounded, zoomed-in time range at a
    /// caller-supplied resolution — never persisted or cached (SPEC.md
    /// §4.15's "on-demand detail" tier).
    func generateWaveformDetail(
        for asset: AudioAsset,
        startSeconds: Double,
        endSeconds: Double,
        resolution: Int
    ) async throws -> [WaveformPeakBucket]

    /// Detects candidate `Cue`s from `asset`'s embedded markers and silence-gap
    /// analysis, per `settings` (SPEC.md §4.11).
    func detectCues(in asset: AudioAsset, settings: AnalysisSettings)
        -> AsyncThrowingStream<OperationProgress<[Cue]>, Error>
}
