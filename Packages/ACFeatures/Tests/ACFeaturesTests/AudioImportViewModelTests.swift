import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

@MainActor
final class AudioImportViewModelTests: XCTestCase {
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

    private func makeViewModel(
        project: Project,
        importedAsset: AudioAsset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
    ) -> (AudioImportViewModel, InMemoryProjectRepository) {
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(importedAsset: importedAsset)
        let viewModel = AudioImportViewModel(
            projectID: project.id,
            importAudioUseCase: ImportAudioUseCase(
                audioAnalysisRepository: audioAnalysisRepository,
                projectRepository: projectRepository
            ),
            generateWaveformPeaksUseCase: GenerateWaveformPeaksUseCase(
                audioAnalysisRepository: audioAnalysisRepository,
                projectRepository: projectRepository
            )
        )
        return (viewModel, projectRepository)
    }

    func test_importFile_startsAtImportingFile() {
        let project = Self.makeProject()
        let (viewModel, _) = makeViewModel(project: project)

        viewModel.importFile(from: URL(fileURLWithPath: "/tmp/fixture.wav"))

        if case .importingFile = viewModel.phase {
            // expected
        } else {
            XCTFail("Expected .importingFile immediately, got \(viewModel.phase)")
        }
    }

    func test_importFile_endsAtCompleted_andPersistsBothAssetAndWaveformPeaks() async throws {
        let project = Self.makeProject()
        let (viewModel, projectRepository) = makeViewModel(project: project)

        viewModel.importFile(from: URL(fileURLWithPath: "/tmp/fixture.wav"))

        try await waitUntil(timeout: 2.0) { viewModel.phase == .completed(bookmarkAccessWarning: nil) }

        let persisted = try await projectRepository.fetch(id: project.id)
        XCTAssertNotNil(persisted?.audioAsset)
        XCTAssertNotNil(persisted?.waveformPeaks)
    }

    /// SPEC.md §4.10, "Security-scoped bookmark creation can fail entirely":
    /// proves the ViewModel surfaces a non-nil warning — not a hard failure,
    /// not silently treated as the normal case — when the imported asset
    /// came back with `bookmarkAccessMode == .plainFallback`.
    func test_importFile_withAPlainFallbackBookmark_completesWithAWarning() async throws {
        let project = Self.makeProject()
        let fallbackAsset = AudioAsset(
            originalFileName: "fixture.wav",
            securityScopedBookmark: Data(),
            bookmarkAccessMode: .plainFallback,
            duration: .zero,
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            importedAt: Date(timeIntervalSince1970: 0)
        )
        let (viewModel, _) = makeViewModel(project: project, importedAsset: fallbackAsset)

        viewModel.importFile(from: URL(fileURLWithPath: "/tmp/fixture.wav"))

        try await waitUntil(timeout: 2.0) {
            if case let .completed(warning) = viewModel.phase {
                return warning != nil
            }
            return false
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
