import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `CueSheetSectionViewModel`'s resume-state computation (`ROADMAP.md`
/// D9/T9.5, SPEC.md §4.21) — each of the five states, not just the two
/// endpoints (fully-empty, fully-populated).
@MainActor
final class CueSheetSectionViewModelTests: XCTestCase {
    private static func makeSetup() -> Setup {
        Setup(
            title: "A Swiss Story",
            productionRuntime: .zero,
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarationDate: Date(timeIntervalSince1970: 0)
        )
    }

    private static func makeProject(
        audioAsset: AudioAsset? = nil,
        waveformPeaks: WaveformPeaks? = nil,
        cues: [Cue] = []
    ) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            audioAsset: audioAsset,
            waveformPeaks: waveformPeaks,
            setup: makeSetup(),
            cues: cues
        )
    }

    private func makeViewModel(project: Project) -> CueSheetSectionViewModel {
        let projectRepository = InMemoryProjectRepository(projects: [project])
        return CueSheetSectionViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository)
        )
    }

    func test_beforeFirstLoad_stateIsLoading() {
        let project = Self.makeProject()
        let viewModel = makeViewModel(project: project)
        XCTAssertEqual(viewModel.resumeState, .loading)
    }

    func test_noAudioAsset_needsImport() async throws {
        let project = Self.makeProject()
        let viewModel = makeViewModel(project: project)
        let task = Task { await viewModel.load() }
        try await waitUntil { viewModel.resumeState == .needsImport }
        task.cancel()
    }

    func test_assetButNoWaveformPeaks_needsWaveformGeneration() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let project = Self.makeProject(audioAsset: asset)
        let viewModel = makeViewModel(project: project)
        let task = Task { await viewModel.load() }
        try await waitUntil { viewModel.resumeState == .needsWaveformGeneration(asset) }
        task.cancel()
    }

    func test_assetAndWaveformPeaksButNoCues_needsCueDetection() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let peaks = WaveformPeaks(audioAssetID: asset.id, resolution: 4, buckets: [])
        let project = Self.makeProject(audioAsset: asset, waveformPeaks: peaks)
        let viewModel = makeViewModel(project: project)
        let task = Task { await viewModel.load() }
        try await waitUntil { viewModel.resumeState == .needsCueDetection(asset, peaks) }
        task.cancel()
    }

    func test_assetPeaksAndCues_readyForReview() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let peaks = WaveformPeaks(audioAssetID: asset.id, resolution: 4, buckets: [])
        let cue = Cue(title: "A Cue", duration: MediaDuration(seconds: 10), rightHolders: [], source: .manual)
        let project = Self.makeProject(audioAsset: asset, waveformPeaks: peaks, cues: [cue])
        let viewModel = makeViewModel(project: project)
        let task = Task { await viewModel.load() }
        try await waitUntil { viewModel.resumeState == .readyForReview(asset, peaks) }
        task.cancel()
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
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
