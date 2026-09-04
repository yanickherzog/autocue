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
        let asset = try await refreshingBookmarkIfNeeded(asset, projectID: projectID)
        return try await audioAnalysisRepository.generateWaveformDetail(
            for: asset,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            resolution: resolution
        )
    }

    /// Same bookmark-lifecycle handling as `GenerateWaveformPeaksUseCase`'s
    /// own method of the same name — not shared/extracted between the two,
    /// consistent with this codebase's existing "duplicate the first two
    /// times" convention (`CONTRIBUTING.md` §3) for this exact
    /// fetch-transform-persist-one-field shape, already duplicated this way
    /// between `ImportAudioUseCase`/`GenerateWaveformPeaksUseCase`'s own
    /// `persist` methods before this pair existed.
    private func refreshingBookmarkIfNeeded(_ asset: AudioAsset, projectID: Project.ID) async throws -> AudioAsset {
        guard let refreshedBookmark = try audioAnalysisRepository.refreshBookmarkIfStale(
            asset.securityScopedBookmark,
            mode: asset.bookmarkAccessMode
        ) else {
            return asset
        }

        let updatedAsset = AudioAsset(
            id: asset.id,
            originalFileName: asset.originalFileName,
            securityScopedBookmark: refreshedBookmark,
            bookmarkAccessMode: asset.bookmarkAccessMode,
            duration: asset.duration,
            sampleRate: asset.sampleRate,
            channelCount: asset.channelCount,
            bitDepth: asset.bitDepth,
            embeddedMarkers: asset.embeddedMarkers,
            broadcastWaveMetadata: asset.broadcastWaveMetadata,
            importedAt: asset.importedAt
        )
        let updated = try await projectRepository.update(id: projectID) { project in
            Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: updatedAsset,
                waveformPeaks: project.waveformPeaks,
                setup: project.setup,
                cues: project.cues,
                people: project.people,
                labels: project.labels
            )
        }
        guard updated != nil else {
            throw ProjectNotFoundError(projectID: projectID)
        }
        return updatedAsset
    }
}
