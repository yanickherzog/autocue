import Foundation

/// The shared "check/refresh/persist `AudioAsset.securityScopedBookmark`"
/// step every Use Case resolving a *previously-persisted* bookmark needs
/// before proceeding (SPEC.md §4.10) — extracted here once
/// `DetectCuesUseCase` became the third near-identical copy of this exact
/// block (`GenerateWaveformPeaksUseCase`, `GenerateWaveformDetailUseCase`
/// each had their own), per `CONTRIBUTING.md` §3's rule of three. A plain,
/// stateless, package-internal helper — not a Use Case itself, since it has
/// no independent reason to exist as public API; every real caller already
/// owns both dependencies it needs.
enum BookmarkRefresher {
    /// Returns `asset` unchanged when its bookmark is still current (the
    /// common case); otherwise persists a freshly-regenerated bookmark onto
    /// `Project.audioAsset` and returns an `AudioAsset` reflecting it, so the
    /// caller never has to re-resolve a second time. `ImportAudioUseCase`
    /// never calls this — it always mints a brand-new bookmark from a live,
    /// user-just-selected `URL`, never a previously-persisted one.
    static func refreshingIfNeeded(
        _ asset: AudioAsset,
        projectID: Project.ID,
        audioAnalysisRepository: AudioAnalysisRepository,
        projectRepository: ProjectRepository
    ) async throws -> AudioAsset {
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
