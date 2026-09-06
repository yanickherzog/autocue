import Foundation

/// Clears a `Project`'s imported audio so `CueSheetSectionViewModel`'s
/// resume-state routing (SPEC.md §4.21) falls back to `.needsImport` and
/// `AudioImportView` shows again — the "wrong file, start over" affordance
/// needed alongside D9's waveform review screen, since nothing else lets a
/// user swap an already-imported file for a different one.
///
/// **Cascades to `waveformPeaks` and `cues`, not just `audioAsset`** — both
/// are meaningless without the specific audio they were derived from.
/// `waveformPeaks` is a direct peak-extraction of that file's own samples
/// (SPEC.md §4.15); every cue reachable from this screen is `source ==
/// .detectedFromAudio` or `.embeddedMarker` (D9 has no manual cue creation —
/// that's D10), so every cue's `startTimecode` is a position on *this*
/// file's specific timeline. Keeping them after clearing the audio they
/// were positioned against would leave dangling, meaningless timecodes
/// pointing at nothing. `Setup.totalMusicRuntime` is recalculated to `.zero`
/// for the same reason `DetectCuesUseCase`/`UpdateCueUseCase` already
/// recalculate it after any cue-list change (SPEC.md §4.14).
public struct ClearImportedAudioUseCase: Sendable {
    private let projectRepository: ProjectRepository

    public init(projectRepository: ProjectRepository) {
        self.projectRepository = projectRepository
    }

    public func clear(projectID: Project.ID) async throws {
        let updated = try await projectRepository.update(id: projectID) { project in
            Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: nil,
                waveformPeaks: nil,
                setup: project.setup
                    .updating(totalMusicRuntime: RecalculateTotalMusicRuntimeUseCase.recalculate(cues: [])),
                cues: [],
                people: project.people,
                labels: project.labels
            )
        }
        guard updated != nil else { throw ProjectNotFoundError(projectID: projectID) }
    }
}
