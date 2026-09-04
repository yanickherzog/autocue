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

    /// Checks whether a previously-captured `AudioAsset.securityScopedBookmark`
    /// is stale and, if so, regenerates and returns a fresh one — `nil` when
    /// the bookmark is still current, nothing to do. `mode` (`AudioAsset.
    /// bookmarkAccessMode`) selects `.withSecurityScope` vs. plain resolution/
    /// regeneration options — a `.plainFallback` bookmark is never resolved or
    /// regenerated with `.withSecurityScope`, since it was never created with
    /// it (SPEC.md §4.10, "Security-scoped bookmark creation can fail
    /// entirely").
    ///
    /// **Callers that resolve an existing bookmark (`generateWaveformPeaks`,
    /// `generateWaveformDetail`, `detectCues`) must call this first and, when
    /// it returns non-`nil`, persist the result back onto `Project.audioAsset.
    /// securityScopedBookmark` via `ProjectRepository` before proceeding.**
    /// A stale bookmark still resolves successfully today — that's exactly
    /// what makes this dangerous to skip: nothing fails now, but the app
    /// keeps resolving increasingly outdated bookmark data indefinitely,
    /// which eventually fails unpredictably (the file moved, a volume was
    /// remounted, an OS update changed how the reference resolves) with no
    /// obvious cause at that point. `ImportAudioUseCase` never calls this —
    /// it always mints a brand-new bookmark from a live, user-just-selected
    /// `URL`, never resolves a previously-stored one.
    func refreshBookmarkIfStale(_ bookmark: Data, mode: AudioAsset.BookmarkAccessMode) throws -> Data?

    /// **Raw signal detection only — never touches `asset.embeddedMarkers`.**
    /// Runs `SilenceDetector` against the file and maps each resulting
    /// candidate region into a plain `Cue` (`source: .detectedFromAudio`,
    /// empty `title`/`rightHolders`, matching "+ Add Cue"'s own defaults).
    /// Merging this raw output against `asset.embeddedMarkers` into the
    /// final, reconciled `[Cue]` list is `DetectCuesUseCase`'s job
    /// (`ROADMAP.md` D9/T9.1, SPEC.md §4.11's "Combining with embedded
    /// markers") — this method's implementation intentionally mirrors
    /// `SilenceDetector`'s own restraint one layer down, for the same reason.
    /// Resolves `asset`'s bookmark the same plain way `generateWaveformDetail`
    /// does; staleness/refresh is the calling Use Case's responsibility (see
    /// `refreshBookmarkIfStale`, above), not this method's.
    func detectCues(in asset: AudioAsset, settings: AnalysisSettings)
        -> AsyncThrowingStream<OperationProgress<[Cue]>, Error>
}
