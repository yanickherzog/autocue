import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `GenerateWaveformPeaksUseCase` against the real
/// `InMemoryProjectRepository`/`InMemoryAudioAnalysisRepository` fakes
/// (`ROADMAP.md` D8/T8.5) — same orchestration shape as `ImportAudioUseCase`.
final class GenerateWaveformPeaksUseCaseTests: XCTestCase {
    private static func makeProject(audioAsset: AudioAsset? = nil) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            audioAsset: audioAsset,
            setup: Setup(
                title: "A Swiss Story",
                productionRuntime: .zero,
                totalMusicRuntime: .zero,
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarationDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    func test_generate_persistsCompletedPeaksToProject() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let project = Self.makeProject(audioAsset: asset)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let peaks = WaveformPeaks(
            audioAssetID: asset.id,
            resolution: 4,
            buckets: (0 ..< 4).map { _ in WaveformPeakBucket(min: -0.5, max: 0.5) }
        )
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(
            importedAsset: asset,
            generatedWaveformPeaks: peaks
        )
        let useCase = GenerateWaveformPeaksUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        var completedPeaks: WaveformPeaks?
        for try await event in useCase.generate(projectID: project.id, asset: asset) {
            if case let .completed(value) = event {
                completedPeaks = value
            }
        }

        XCTAssertEqual(completedPeaks, peaks)
        let persisted = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(persisted?.waveformPeaks, peaks)
    }

    /// The real bug this test exists to catch: a stale bookmark resolving
    /// "successfully" is not the same as the app actually keeping the
    /// stored bookmark current. This proves the *persisted* bookmark
    /// actually changes, not merely that resolution didn't throw.
    func test_generate_whenBookmarkIsStale_refreshesAndPersistsIt() async throws {
        let originalBookmark = Data([0x01, 0x02])
        let refreshedBookmark = Data([0x03, 0x04])
        let asset = AudioAsset(
            originalFileName: "fixture.wav",
            securityScopedBookmark: originalBookmark,
            duration: MediaDuration(seconds: 60),
            sampleRate: 48000,
            channelCount: 1,
            bitDepth: 16,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let project = Self.makeProject(audioAsset: asset)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(
            importedAsset: asset,
            staleBookmarkRefreshedTo: refreshedBookmark
        )
        let useCase = GenerateWaveformPeaksUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        for try await _ in useCase.generate(projectID: project.id, asset: asset) {}

        let persisted = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(persisted?.audioAsset?.securityScopedBookmark, refreshedBookmark)
    }

    /// Negative case, kept alongside the positive one above so a future
    /// regression that *always* writes (whether stale or not) is caught
    /// too, not just the "does it ever refresh" direction.
    func test_generate_whenBookmarkIsNotStale_doesNotTouchThePersistedBookmark() async throws {
        let originalBookmark = Data([0x01, 0x02])
        let asset = AudioAsset(
            originalFileName: "fixture.wav",
            securityScopedBookmark: originalBookmark,
            duration: MediaDuration(seconds: 60),
            sampleRate: 48000,
            channelCount: 1,
            bitDepth: 16,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let project = Self.makeProject(audioAsset: asset)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(
            importedAsset: asset,
            staleBookmarkRefreshedTo: nil
        )
        let useCase = GenerateWaveformPeaksUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        for try await _ in useCase.generate(projectID: project.id, asset: asset) {}

        let persisted = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(persisted?.audioAsset?.securityScopedBookmark, originalBookmark)
    }

    func test_generate_unknownProjectID_throwsProjectNotFoundError() async {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let projectRepository = InMemoryProjectRepository()
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(importedAsset: asset)
        let useCase = GenerateWaveformPeaksUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )
        let unknownID = UUID()

        do {
            for try await _ in useCase.generate(projectID: unknownID, asset: asset) {}
            XCTFail("Expected ProjectNotFoundError")
        } catch let error as ProjectNotFoundError {
            XCTAssertEqual(error.projectID, unknownID)
        } catch {
            XCTFail("Expected ProjectNotFoundError, got \(error)")
        }
    }
}
