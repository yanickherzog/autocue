import Foundation

/// Generates the persisted, fixed-resolution waveform overview for an
/// imported `AudioAsset` (SPEC.md §4.15) — relays
/// `AudioAnalysisRepository.generateWaveformPeaks(for:)`'s progress stream,
/// and on completion persists the result to `Project.waveformPeaks` via
/// `ProjectRepository.update(id:transform:)` before yielding its own
/// `.completed`. Same shape as `ImportAudioUseCase`, which it's meant to run
/// immediately after — chained by `AudioImportViewModel`, not internally.
public struct GenerateWaveformPeaksUseCase: Sendable {
    private let audioAnalysisRepository: AudioAnalysisRepository
    private let projectRepository: ProjectRepository

    public init(audioAnalysisRepository: AudioAnalysisRepository, projectRepository: ProjectRepository) {
        self.audioAnalysisRepository = audioAnalysisRepository
        self.projectRepository = projectRepository
    }

    public func generate(
        projectID: Project.ID,
        asset: AudioAsset
    ) -> AsyncThrowingStream<OperationProgress<WaveformPeaks>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // `asset` carries an existing, previously-persisted
                    // bookmark (unlike `ImportAudioUseCase`, which always
                    // mints a fresh one) — must be checked/refreshed before
                    // the repository resolves it, or a stale bookmark keeps
                    // silently resolving forever with nothing ever
                    // persisting a fresh one in its place.
                    let asset = try await BookmarkRefresher.refreshingIfNeeded(
                        asset,
                        projectID: projectID,
                        audioAnalysisRepository: audioAnalysisRepository,
                        projectRepository: projectRepository
                    )
                    for try await event in audioAnalysisRepository.generateWaveformPeaks(for: asset) {
                        switch event {
                        case let .progress(update):
                            continuation.yield(.progress(update))
                        case let .completed(peaks):
                            try await persist(peaks, projectID: projectID)
                            continuation.yield(.completed(peaks))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func persist(_ peaks: WaveformPeaks, projectID: Project.ID) async throws {
        let updated = try await projectRepository.update(id: projectID) { project in
            Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: project.audioAsset,
                waveformPeaks: peaks,
                setup: project.setup,
                cues: project.cues,
                people: project.people,
                labels: project.labels
            )
        }
        guard updated != nil else {
            throw ProjectNotFoundError(projectID: projectID)
        }
    }
}
