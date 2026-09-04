import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `ImportAudioUseCase` against the real `InMemoryProjectRepository`
/// and `InMemoryAudioAnalysisRepository` fakes (`ROADMAP.md` D8/T8.5) — pure
/// orchestration (relay progress, persist on completion), no pure half to
/// test separately in `ACCoreTests` (`CONTRIBUTING.md` §5).
final class ImportAudioUseCaseTests: XCTestCase {
    private static func makeProject() -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
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

    private static func makeAsset(id: UUID = UUID()) -> AudioAsset {
        AudioAsset(
            id: id,
            originalFileName: "fixture.wav",
            securityScopedBookmark: Data(),
            duration: MediaDuration(seconds: 60),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func test_importAudio_persistsCompletedAssetToProject() async throws {
        let project = Self.makeProject()
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let asset = Self.makeAsset()
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(importedAsset: asset)
        let useCase = ImportAudioUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        var completedAsset: AudioAsset?
        for try await event in useCase.importAudio(projectID: project.id, from: URL(fileURLWithPath: "/tmp/x.wav")) {
            if case let .completed(value) = event {
                completedAsset = value
            }
        }

        XCTAssertEqual(completedAsset, asset)
        let persisted = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(persisted?.audioAsset, asset)
    }

    func test_importAudio_relaysProgressEvents() async throws {
        let project = Self.makeProject()
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(importedAsset: Self.makeAsset())
        let useCase = ImportAudioUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        var sawProgress = false
        for try await event in useCase.importAudio(projectID: project.id, from: URL(fileURLWithPath: "/tmp/x.wav")) {
            if case .progress = event {
                sawProgress = true
            }
        }

        XCTAssertTrue(sawProgress)
    }

    func test_importAudio_unknownProjectID_throwsProjectNotFoundError() async {
        let projectRepository = InMemoryProjectRepository()
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(importedAsset: Self.makeAsset())
        let useCase = ImportAudioUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )
        let unknownID = UUID()

        do {
            for try await _ in useCase.importAudio(projectID: unknownID, from: URL(fileURLWithPath: "/tmp/x.wav")) {}
            XCTFail("Expected ProjectNotFoundError")
        } catch let error as ProjectNotFoundError {
            XCTAssertEqual(error.projectID, unknownID)
        } catch {
            XCTFail("Expected ProjectNotFoundError, got \(error)")
        }
    }
}
