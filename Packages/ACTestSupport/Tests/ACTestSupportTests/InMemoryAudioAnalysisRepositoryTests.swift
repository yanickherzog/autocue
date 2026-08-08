import ACCore
@testable import ACTestSupport
import XCTest

final class InMemoryAudioAnalysisRepositoryTests: XCTestCase {
    func test_importAudio_streamCompletesWithTheConfiguredAsset() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let repository = InMemoryAudioAnalysisRepository(importedAsset: asset)

        var results: [AudioAsset] = []
        for try await event in repository.importAudio(from: URL(fileURLWithPath: "/tmp/fixture.wav")) {
            if case let .completed(completedAsset) = event {
                results.append(completedAsset)
            }
        }

        XCTAssertEqual(results, [asset])
    }

    func test_generateWaveformPeaks_streamCompletesWithTheConfiguredPeaks() async throws {
        let asset = InMemoryAudioAnalysisRepository.placeholderAudioAsset()
        let peaks = WaveformPeaks(audioAssetID: asset.id, resolution: 4, buckets: [
            WaveformPeakBucket(min: -1, max: 1),
            WaveformPeakBucket(min: -1, max: 1),
            WaveformPeakBucket(min: -1, max: 1),
            WaveformPeakBucket(min: -1, max: 1),
        ])
        let repository = InMemoryAudioAnalysisRepository(importedAsset: asset, generatedWaveformPeaks: peaks)

        var results: [WaveformPeaks] = []
        for try await event in repository.generateWaveformPeaks(for: asset) {
            if case let .completed(completedPeaks) = event {
                results.append(completedPeaks)
            }
        }

        XCTAssertEqual(results, [peaks])
    }

    func test_generateWaveformDetail_returnsTheConfiguredBuckets() async throws {
        let buckets = [WaveformPeakBucket(min: -0.2, max: 0.2)]
        let repository = InMemoryAudioAnalysisRepository(waveformDetailBuckets: buckets)

        let result = try await repository.generateWaveformDetail(
            for: InMemoryAudioAnalysisRepository.placeholderAudioAsset(),
            startSeconds: 0,
            endSeconds: 1,
            resolution: 1
        )

        XCTAssertEqual(result, buckets)
    }

    func test_detectCues_streamCompletesWithTheConfiguredCues() async throws {
        let cue = Cue(
            title: "Alpine Theme",
            duration: MediaDuration(seconds: 30),
            rightHolders: [],
            source: .detectedFromAudio
        )
        let repository = InMemoryAudioAnalysisRepository(detectedCues: [cue])

        var results: [[Cue]] = []
        for try await event in repository.detectCues(
            in: InMemoryAudioAnalysisRepository.placeholderAudioAsset(),
            settings: AnalysisSettings()
        ) {
            if case let .completed(completedCues) = event {
                results.append(completedCues)
            }
        }

        XCTAssertEqual(results, [[cue]])
    }
}
