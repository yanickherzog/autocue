import Foundation

/// Imports a WAV file into one `Project` (`ROADMAP.md` D8/T8.5) — relays
/// `AudioAnalysisRepository.importAudio(from:)`'s progress stream, and on
/// completion persists the resulting `AudioAsset` to `Project.audioAsset`
/// via `ProjectRepository.update(id:transform:)` (the same atomic
/// fetch-transform-write pattern `UpdateSetupUseCase` established) before
/// yielding its own `.completed`.
///
/// Does not itself trigger waveform-peak generation — SPEC.md §4.15 says
/// that "runs immediately after import," but chaining the two is
/// `AudioImportViewModel`'s job (`ROADMAP.md` D8/T8.6): it needs to show one
/// coherent progress experience spanning both steps anyway, which is
/// exactly what a ViewModel orchestrates, not what a Use Case hides inside
/// itself.
public struct ImportAudioUseCase: Sendable {
    private let audioAnalysisRepository: AudioAnalysisRepository
    private let projectRepository: ProjectRepository

    public init(audioAnalysisRepository: AudioAnalysisRepository, projectRepository: ProjectRepository) {
        self.audioAnalysisRepository = audioAnalysisRepository
        self.projectRepository = projectRepository
    }

    public func importAudio(
        projectID: Project.ID,
        from url: URL
    ) -> AsyncThrowingStream<OperationProgress<AudioAsset>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in audioAnalysisRepository.importAudio(from: url) {
                        switch event {
                        case let .progress(update):
                            continuation.yield(.progress(update))
                        case let .completed(asset):
                            try await persist(asset, projectID: projectID)
                            continuation.yield(.completed(asset))
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

    private func persist(_ asset: AudioAsset, projectID: Project.ID) async throws {
        let updated = try await projectRepository.update(id: projectID) { project in
            Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: asset,
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
    }
}
