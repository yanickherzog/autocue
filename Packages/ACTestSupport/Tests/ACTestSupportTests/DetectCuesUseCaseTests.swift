import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `DetectCuesUseCase`'s embedded-marker merge algorithm
/// (`ROADMAP.md` D9/T9.1, SPEC.md §4.11) synthetically, against
/// `InMemoryAudioAnalysisRepository`'s `detectedCues:` canned parameter — no
/// real audio needed, per `CONTRIBUTING.md` §5: the merge rule is pure
/// Domain logic over plain values. Real-fixture accuracy of the underlying
/// `SilenceDetector` boundaries is covered separately in `ACAudioKitTests`.
final class DetectCuesUseCaseTests: XCTestCase {
    private static func makeProject(cues: [Cue] = [], audioAsset: AudioAsset) -> Project {
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
            ),
            cues: cues
        )
    }

    private static func makeAsset(
        durationSeconds: Double = 600,
        embeddedMarkers: [EmbeddedMarker] = []
    ) -> AudioAsset {
        AudioAsset(
            originalFileName: "reel.wav",
            securityScopedBookmark: Data(),
            duration: MediaDuration(seconds: durationSeconds),
            sampleRate: 48000,
            channelCount: 1,
            bitDepth: 16,
            embeddedMarkers: embeddedMarkers,
            importedAt: Date()
        )
    }

    private static func makeDetectedCue(startSeconds: Double, duration: Double) -> Cue {
        Cue(
            title: "",
            duration: MediaDuration(seconds: duration),
            rightHolders: [],
            source: .detectedFromAudio,
            startTimecode: Timecode(offsetSeconds: startSeconds)
        )
    }

    private func run(
        detectedCues: [Cue],
        asset: AudioAsset,
        existingCues: [Cue] = [],
        settings: AnalysisSettings = AnalysisSettings()
    ) async throws -> [Cue] {
        let project = Self.makeProject(cues: existingCues, audioAsset: asset)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(
            importedAsset: asset,
            detectedCues: detectedCues
        )
        let useCase = DetectCuesUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        var result: [Cue] = []
        for try await event in useCase.detectCues(projectID: project.id, asset: asset, settings: settings) {
            if case let .completed(cues) = event {
                result = cues
            }
        }
        return result
    }

    // MARK: - No markers

    func test_noEmbeddedMarkers_detectedRegionsPassThroughUnchanged() async throws {
        let asset = Self.makeAsset()
        let detected = [Self.makeDetectedCue(startSeconds: 10, duration: 30)]

        let result = try await run(detectedCues: detected, asset: asset)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.source, .detectedFromAudio)
        XCTAssertEqual(result.first?.startTimecode, Timecode(offsetSeconds: 10))
    }

    // MARK: - Marker confirms a nearby detected boundary

    func test_markerWithinTolerance_confirmsRegion_reclassifiesAndSnapsStart_keepsEndFixed() async throws {
        // Region detected at [10, 40); marker sits 0.3s later, within the
        // default 1.0s embeddedMarkerMergeToleranceSeconds.
        let marker = EmbeddedMarker(position: Timecode(offsetSeconds: 10.3))
        let asset = Self.makeAsset(embeddedMarkers: [marker])
        let detected = [Self.makeDetectedCue(startSeconds: 10, duration: 30)]

        let result = try await run(detectedCues: detected, asset: asset)

        XCTAssertEqual(result.count, 1)
        let cue = try XCTUnwrap(result.first)
        XCTAssertEqual(cue.source, .embeddedMarker)
        XCTAssertEqual(cue.startTimecode, Timecode(offsetSeconds: 10.3))
        // End stays fixed at the original region's end (40) — only the start snapped.
        XCTAssertEqual(try XCTUnwrap(cue.startTimecode?.offsetSeconds) + cue.duration.seconds, 40, accuracy: 0.0001)
    }

    func test_markerOutsideTolerance_doesNotConfirm_bothProduceSeparateOutcomes() async throws {
        // 2.0s away — outside the default 1.0s tolerance — so this is NOT a
        // confirmation; it's an unconfirmed marker landing in the silence
        // gap before the detected region.
        let marker = EmbeddedMarker(position: Timecode(offsetSeconds: 8))
        let asset = Self.makeAsset(embeddedMarkers: [marker])
        let detected = [Self.makeDetectedCue(startSeconds: 10, duration: 30)]

        let result = try await run(detectedCues: detected, asset: asset)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].source, .embeddedMarker)
        XCTAssertEqual(result[0].startTimecode, Timecode(offsetSeconds: 8))
        XCTAssertEqual(result[1].source, .detectedFromAudio)
        XCTAssertEqual(result[1].startTimecode, Timecode(offsetSeconds: 10))
    }

    // MARK: - Unconfirmed marker inside an existing region — splits it

    func test_unconfirmedMarkerInsideDetectedRegion_splitsIt() async throws {
        // Region [10, 40); marker at 25 is far from the region's own start
        // (outside tolerance) but sits inside its span — the exact
        // attacca/segue case (SPEC.md §4.11's 2026-09-05 resolution).
        let marker = EmbeddedMarker(position: Timecode(offsetSeconds: 25))
        let asset = Self.makeAsset(embeddedMarkers: [marker])
        let detected = [Self.makeDetectedCue(startSeconds: 10, duration: 30)]

        let result = try await run(detectedCues: detected, asset: asset)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].source, .detectedFromAudio)
        XCTAssertEqual(result[0].startTimecode, Timecode(offsetSeconds: 10))
        XCTAssertEqual(result[0].duration.seconds, 15, accuracy: 0.0001) // 10 -> 25
        XCTAssertEqual(result[1].source, .embeddedMarker)
        XCTAssertEqual(result[1].startTimecode, Timecode(offsetSeconds: 25))
        XCTAssertEqual(result[1].duration.seconds, 15, accuracy: 0.0001) // 25 -> 40
        // No gap, no overlap: the two halves exactly reconstruct the original span.
        XCTAssertEqual(
            try XCTUnwrap(result[0].startTimecode?.offsetSeconds) + result[0].duration.seconds,
            try XCTUnwrap(result[1].startTimecode?.offsetSeconds),
            accuracy: 0.0001
        )
    }

    // MARK: - Unconfirmed marker in silence — extends to the next boundary

    func test_unconfirmedMarkerInSilenceBetweenRegions_extendsToNextRegionStart() async throws {
        let marker = EmbeddedMarker(position: Timecode(offsetSeconds: 50))
        let asset = Self.makeAsset(embeddedMarkers: [marker])
        let detected = [
            Self.makeDetectedCue(startSeconds: 10, duration: 30), // [10, 40)
            Self.makeDetectedCue(startSeconds: 70, duration: 30), // [70, 100)
        ]

        let result = try await run(detectedCues: detected, asset: asset)

        XCTAssertEqual(result.count, 3)
        let markerCue = result[1]
        XCTAssertEqual(markerCue.source, .embeddedMarker)
        XCTAssertEqual(markerCue.startTimecode, Timecode(offsetSeconds: 50))
        XCTAssertEqual(markerCue.duration.seconds, 20, accuracy: 0.0001) // 50 -> 70
    }

    func test_unconfirmedMarkerAfterLastRegion_extendsToFileDuration() async throws {
        let marker = EmbeddedMarker(position: Timecode(offsetSeconds: 500))
        let asset = Self.makeAsset(durationSeconds: 600, embeddedMarkers: [marker])
        let detected = [Self.makeDetectedCue(startSeconds: 10, duration: 30)]

        let result = try await run(detectedCues: detected, asset: asset)

        XCTAssertEqual(result.count, 2)
        let markerCue = try XCTUnwrap(result.last)
        XCTAssertEqual(markerCue.source, .embeddedMarker)
        XCTAssertEqual(markerCue.startTimecode, Timecode(offsetSeconds: 500))
        XCTAssertEqual(markerCue.duration.seconds, 100, accuracy: 0.0001) // 500 -> file end (600)
    }

    // MARK: - Re-run preservation

    func test_rerun_preservesManualAndEmbeddedMarkerCues_replacesOnlyDetectedFromAudioOnes() async throws {
        let asset = Self.makeAsset()
        let manualCue = Cue(
            title: "Hand-placed",
            duration: MediaDuration(seconds: 5),
            rightHolders: [],
            source: .manual,
            startTimecode: Timecode(offsetSeconds: 200)
        )
        let staleDetectedCue = Cue(
            title: "",
            duration: MediaDuration(seconds: 5),
            rightHolders: [],
            source: .detectedFromAudio,
            startTimecode: Timecode(offsetSeconds: 5)
        )
        let freshDetected = [Self.makeDetectedCue(startSeconds: 10, duration: 30)]

        let result = try await run(
            detectedCues: freshDetected,
            asset: asset,
            existingCues: [staleDetectedCue, manualCue]
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(manualCue))
        XCTAssertFalse(result.contains(staleDetectedCue))
        XCTAssertTrue(result.contains { $0.source == .detectedFromAudio && $0.startTimecode?.offsetSeconds == 10 })
    }

    func test_totalMusicRuntimeRecomputedAfterDetection() async throws {
        let asset = Self.makeAsset()
        let detected = [
            Self.makeDetectedCue(startSeconds: 10, duration: 30),
            Self.makeDetectedCue(startSeconds: 100, duration: 20),
        ]
        let project = Self.makeProject(audioAsset: asset)
        let projectRepository = InMemoryProjectRepository(projects: [project])
        let audioAnalysisRepository = InMemoryAudioAnalysisRepository(importedAsset: asset, detectedCues: detected)
        let useCase = DetectCuesUseCase(
            audioAnalysisRepository: audioAnalysisRepository,
            projectRepository: projectRepository
        )

        for try await _ in useCase.detectCues(projectID: project.id, asset: asset, settings: AnalysisSettings()) {}

        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.setup.totalMusicRuntime, MediaDuration(seconds: 50))
    }
}
