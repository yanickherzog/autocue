import Foundation

/// Real-time transport control for previewing an imported `AudioAsset`
/// (SPEC.md §4.20) — click-to-play and play-a-cue's-exact-span (`ROADMAP.md`
/// D9/T9.4). Deliberately not suffixed `Repository`, even though it follows
/// the same architectural shape as one (a protocol in `ACCore`, implemented
/// by a Data-layer package, injected via `DependencyContainer`) —
/// "Repository" already has a precise, established meaning in this codebase
/// (data CRUD/observation), and playback is a real-time transport-control
/// surface, not that. Still lives in `RepositoryProtocols/` — that folder
/// groups by *architectural role* (a Domain-defined protocol a Data package
/// implements), which this fits exactly.
///
/// **Not the `OperationProgress<T>`/`AsyncThrowingStream` contract.** That
/// shape fits a bounded, terminating, result-producing operation; playback
/// is indefinite, freely pausable/resumable, and produces no final result
/// value. `stateUpdates: AsyncStream<PlaybackState>` is the correct, simpler
/// shape instead.
///
/// **One `play(from:until:)` method, not two.** `until: nil` covers
/// click-to-play (play from an arbitrary point, no end bound); a real
/// `until` covers play-a-cue's-exact-span (auto-stop at the end) —
/// `CLAUDE.md` rule 7.
public protocol AudioPlaybackController: Sendable {
    /// Resolves and opens the file a single time — subsequent `play`/
    /// `pause`/`stop` calls operate on an already-open player. `mode`
    /// selects `.withSecurityScope` vs. plain resolution options, exactly
    /// like every other consumer of `securityScopedBookmark`
    /// (`AudioAnalysisRepository.generateWaveformPeaks`/
    /// `.generateWaveformDetail`/`.refreshBookmarkIfStale`) — a
    /// `.plainFallback`-mode bookmark was never created as security-scoped
    /// and must never be resolved as if it were (SPEC.md §4.10).
    func prepare(securityScopedBookmark: Data, mode: AudioAsset.BookmarkAccessMode) async throws

    /// Plays from `startSeconds`. `until: nil` runs to the end of the file
    /// (or until stopped); a real value auto-stops there (a bounded
    /// poll-and-stop pattern — no exotic API needed). Calling this while
    /// already playing seeks and continues — it does not require an
    /// explicit `stop()` first, avoiding overlapping audio on rapid
    /// re-clicking.
    func play(from startSeconds: Double, until endSeconds: Double?) async throws
    func pause() async
    func stop() async

    /// Carries both "is it playing at all" and "where" — the same small,
    /// precise value-type-over-loose-tuple preference `ProgressUpdate`
    /// already establishes.
    var stateUpdates: AsyncStream<PlaybackState> { get }
}

public enum PlaybackState: Sendable, Equatable {
    case stopped
    case playing(positionSeconds: Double)
    case paused(positionSeconds: Double)
}
