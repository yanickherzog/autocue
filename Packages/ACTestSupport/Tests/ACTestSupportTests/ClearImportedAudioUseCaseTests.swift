import ACCore
@testable import ACTestSupport
import XCTest

final class ClearImportedAudioUseCaseTests: XCTestCase {
    private static func makeAsset() -> AudioAsset {
        AudioAsset(
            originalFileName: "fixture.wav",
            securityScopedBookmark: Data(),
            duration: MediaDuration(seconds: 60),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func makeCue(startSeconds: Double, duration: Double) -> Cue {
        Cue(
            title: "",
            duration: MediaDuration(seconds: duration),
            rightHolders: [],
            source: .detectedFromAudio,
            startTimecode: Timecode(offsetSeconds: startSeconds)
        )
    }

    private static func makeProject(audioAsset: AudioAsset?, waveformPeaks: WaveformPeaks?, cues: [Cue]) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            audioAsset: audioAsset,
            waveformPeaks: waveformPeaks,
            setup: Setup(
                title: "A Swiss Story",
                productionRuntime: .zero,
                totalMusicRuntime: MediaDuration(seconds: 40),
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarationDate: Date(timeIntervalSince1970: 0)
            ),
            cues: cues
        )
    }

    func test_clear_removesAudioAssetWaveformPeaksAndCues_andRecalculatesTotalMusicRuntimeToZero() async throws {
        let asset = Self.makeAsset()
        let peaks = WaveformPeaks(
            audioAssetID: asset.id,
            resolution: 4,
            buckets: (0 ..< 4).map { _ in WaveformPeakBucket(min: -0.5, max: 0.5) }
        )
        let cue = Self.makeCue(startSeconds: 10, duration: 30)
        let project = Self.makeProject(audioAsset: asset, waveformPeaks: peaks, cues: [cue])
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let useCase = ClearImportedAudioUseCase(projectRepository: projectRepository)

        try await useCase.clear(projectID: project.id)

        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertNil(updated?.audioAsset)
        XCTAssertNil(updated?.waveformPeaks)
        XCTAssertEqual(updated?.cues, [])
        XCTAssertEqual(updated?.setup.totalMusicRuntime, .zero)
    }

    func test_clear_preservesEverythingElse() async throws {
        let asset = Self.makeAsset()
        let project = Self.makeProject(audioAsset: asset, waveformPeaks: nil, cues: [])
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let useCase = ClearImportedAudioUseCase(projectRepository: projectRepository)

        try await useCase.clear(projectID: project.id)

        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.name, project.name)
        XCTAssertEqual(updated?.setup.title, project.setup.title)
    }

    func test_clear_projectDoesNotExist_throwsProjectNotFound() async throws {
        let projectRepository = InMemoryProjectRepository(projects: [])
        let useCase = ClearImportedAudioUseCase(projectRepository: projectRepository)
        let missingID = UUID()

        do {
            try await useCase.clear(projectID: missingID)
            XCTFail("expected ProjectNotFoundError")
        } catch let error as ProjectNotFoundError {
            XCTAssertEqual(error.projectID, missingID)
        }
    }
}
