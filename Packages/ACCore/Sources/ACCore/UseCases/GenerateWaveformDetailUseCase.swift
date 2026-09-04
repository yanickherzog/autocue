import Foundation

/// Computes on-demand waveform peaks for a bounded, zoomed-in time range
/// (SPEC.md §4.15's "on-demand detail" tier) — a thin pass-through to
/// `AudioAnalysisRepository.generateWaveformDetail(for:startSeconds:endSeconds:resolution:)`.
///
/// Deliberately the plain `async throws` shape, no `OperationProgress`
/// stream: the *result* (`[WaveformPeakBucket]`) is never cached or
/// persisted (a bounded time-range read is cheap even against a 3-hour
/// file), and a progress UI for it would be pointless ceremony — the same
/// "not every operation needs the full contract" precedent this method's own
/// protocol doc comment already establishes.
///
/// **Does now need `ProjectRepository` — not for the result above, but for
/// `asset.securityScopedBookmark`'s own lifecycle.** `asset` here (unlike
/// `ImportAudioUseCase`'s freshly-minted one) carries a previously-persisted
/// bookmark that may have gone stale since import; `refreshBookmarkIfStale`
/// must be checked before the repository resolves it, and a refreshed
/// bookmark persisted back onto `Project.audioAsset`, or a stale bookmark
/// keeps silently resolving forever with nothing ever replacing it — the
/// same requirement `GenerateWaveformPeaksUseCase` already implements,
/// applied here for the same reason.
public struct GenerateWaveformDetailUseCase: Sendable {
    private let audioAnalysisRepository: AudioAnalysisRepository
    private let projectRepository: ProjectRepository

    public init(audioAnalysisRepository: AudioAnalysisRepository, projectRepository: ProjectRepository) {
        self.audioAnalysisRepository = audioAnalysisRepository
        self.projectRepository = projectRepository
    }

    public func generate(
        projectID: Project.ID,
        for asset: AudioAsset,
        startSeconds: Double,
        endSeconds: Double,
        resolution: Int
    ) async throws -> [WaveformPeakBucket] {
        let asset = try await BookmarkRefresher.refreshingIfNeeded(
            asset,
            projectID: projectID,
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )
        return try await audioAnalysisRepository.generateWaveformDetail(
            for: asset,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            resolution: resolution
        )
    }
}
