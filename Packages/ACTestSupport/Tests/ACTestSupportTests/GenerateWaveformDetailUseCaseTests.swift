import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `GenerateWaveformDetailUseCase` against the real
/// `InMemoryAudioAnalysisRepository`/`InMemoryProjectRepository` fakes —
/// the pass-through result behavior (SPEC.md §4.15's "on-demand detail"
/// tier: never cached/persisted itself), plus the bookmark-lifecycle
/// side effect this Use Case is now responsible for (a stale
/// `AudioAsset.securityScopedBookmark` must be refreshed and persisted
/// before the repository resolves it — see `AudioAnalysisRepositoryImpl.
/// refreshBookmarkIfStale`'s own doc comment for why this matters).
final class GenerateWaveformDetailUseCaseTests: XCTestCase {
    private static func makeProject(audioAsset: AudioAsset) -> Project {
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

    func test_generate_returnsTheRepositoriesBuckets() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let project = Self.makeProject(audioAsset: asset)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let expectedBuckets = (0 ..< 3).map { _ in WaveformPeakBucket(min: -0.2, max: 0.2) }
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(
            importedAsset: asset,
            waveformDetailBuckets: expectedBuckets
        )
        let useCase = GenerateWaveformDetailUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        let buckets = try await useCase.generate(
            projectID: project.id,
            for: asset,
            startSeconds: 0,
            endSeconds: 1,
            resolution: 3
        )

        XCTAssertEqual(buckets, expectedBuckets)
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
        let useCase = GenerateWaveformDetailUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        _ = try await useCase.generate(projectID: project.id, for: asset, startSeconds: 0, endSeconds: 1, resolution: 3)

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
        let useCase = GenerateWaveformDetailUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        _ = try await useCase.generate(projectID: project.id, for: asset, startSeconds: 0, endSeconds: 1, resolution: 3)

        let persisted = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(persisted?.audioAsset?.securityScopedBookmark, originalBookmark)
    }
}
