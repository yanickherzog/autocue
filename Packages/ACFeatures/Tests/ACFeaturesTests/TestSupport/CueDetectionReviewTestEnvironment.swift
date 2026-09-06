import ACCore
import ACDesignSystem
@testable import ACFeatures
@testable import ACTestSupport
import Foundation
import XCTest

/// Shared test fixtures for `CueDetectionReviewViewModel` — split out once a
/// second test file (`CueDetectionReviewPlaybackAndDisplayDataTests`) needed
/// the exact same environment, per the "rule of three"-adjacent principle of
/// not duplicating identical setup across files once a genuine second
/// consumer exists.
func makeCueDetectionReviewCue(
    startSeconds: Double,
    duration: Double,
    source: CueSource = .detectedFromAudio
) -> Cue {
    Cue(
        title: "",
        duration: MediaDuration(seconds: duration),
        rightHolders: [],
        source: source,
        startTimecode: Timecode(offsetSeconds: startSeconds)
    )
}

func makeCueDetectionReviewProject(cues: [Cue], audioAsset: AudioAsset, waveformPeaks: WaveformPeaks?) -> Project {
    Project(
        name: "Reel One",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        audioAsset: audioAsset,
        waveformPeaks: waveformPeaks,
        setup: Setup(
            title: "A Swiss Story",
            productionRuntime: .zero,
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarationDate: Date(timeIntervalSince1970: 0)
        ),
        cues: cues
    )
}

struct CueDetectionReviewTestEnvironment {
    let viewModel: CueDetectionReviewViewModel
    let projectRepository: InMemoryProjectRepository
    let playbackController: InMemoryAudioPlaybackController
    let project: Project
}

@MainActor
func makeCueDetectionReviewEnvironment(cues: [Cue]) -> CueDetectionReviewTestEnvironment {
    let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
    let peaks = WaveformPeaks(
        audioAssetID: asset.id,
        resolution: 4,
        buckets: (0 ..< 4).map { _ in WaveformPeakBucket(min: -0.5, max: 0.5) }
    )
    let project = makeCueDetectionReviewProject(cues: cues, audioAsset: asset, waveformPeaks: peaks)
    let projectRepository = InMemoryProjectRepository(projects: [project])
    let audioAnalysisRepository = InMemoryAudioAnalysisRepository(importedAsset: asset)
    let playbackController = InMemoryAudioPlaybackController()
    let viewModel = CueDetectionReviewViewModel(
        projectID: project.id,
        observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
        generateWaveformDetailUseCase: GenerateWaveformDetailUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        ),
        updateCueUseCase: UpdateCueUseCase(projectRepository: projectRepository),
        audioPlaybackController: playbackController
    )
    return CueDetectionReviewTestEnvironment(
        viewModel: viewModel,
        projectRepository: projectRepository,
        playbackController: playbackController,
        project: project
    )
}

func waitUntilCueDetectionReviewConditionMet(
    timeout: TimeInterval = 2.0,
    condition: @escaping () async throws -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while try await !condition() {
        if Date() > deadline {
            XCTFail("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}
