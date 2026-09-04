@testable import ACAudioKit
import ACCore
import XCTest

final class AudioAnalysisRepositoryImplTests: XCTestCase {
    private var fixtureURLs: [URL] = []
    private let repository = AudioAnalysisRepositoryImpl()

    override func tearDown() {
        for url in fixtureURLs {
            try? FileManager.default.removeItem(at: url)
        }
        fixtureURLs = []
        super.tearDown()
    }

    private func makeFixture(
        sampleRate: Double = 48000,
        frameCount: Int = 48000,
        cuePoints: [WAVFixtureBuilder.CuePointFixture] = []
    ) throws -> URL {
        let url = WAVFixtureBuilder.makeTemporaryURL()
        try WAVFixtureBuilder.writeWAVFile(
            sampleRate: sampleRate,
            channelSamples: [[Float](repeating: 0.1, count: frameCount)],
            cuePoints: cuePoints,
            to: url
        )
        fixtureURLs.append(url)
        return url
    }

    private func collectResult<T>(
        _ stream: AsyncThrowingStream<OperationProgress<T>, Error>
    ) async throws -> T {
        var progressCount = 0
        for try await event in stream {
            switch event {
            case .progress: progressCount += 1
            case let .completed(value): return value
            }
        }
        XCTFail("Stream finished without a .completed event (saw \(progressCount) .progress events)")
        throw XCTSkip("no completed event")
    }

    func test_importAudio_returnsPopulatedAudioAsset_includingEmbeddedMarkers() async throws {
        let url = try makeFixture(cuePoints: [.init(id: 1, sampleOffset: 100, label: "Marker One")])

        let asset = try await collectResult(repository.importAudio(from: url))

        XCTAssertEqual(asset.originalFileName, url.lastPathComponent)
        XCTAssertEqual(asset.sampleRate, 48000)
        XCTAssertEqual(asset.channelCount, 1)
        XCTAssertEqual(asset.bitDepth, 16)
        XCTAssertEqual(asset.embeddedMarkers.count, 1)
        XCTAssertEqual(asset.embeddedMarkers.first?.label, "Marker One")
        XCTAssertFalse(asset.securityScopedBookmark.isEmpty)
        // Fixture URLs here are plain local file URLs, never granted through
        // Powerbox/.fileImporter — the real, narrower failure mode this
        // field exists for (SPEC.md §4.10, "Security-scoped bookmark
        // creation can fail entirely") is specific to that grant path and
        // can't be reproduced by a fixture-based unit test; see that
        // section and `docs/DECISIONS.md` for why. This asserts the normal,
        // expected outcome on a working machine/grant.
        XCTAssertEqual(asset.bookmarkAccessMode, .securityScoped)
    }

    func test_importAudio_emitsProgressBeforeCompleting() async throws {
        let url = try makeFixture()
        var sawProgress = false
        var sawCompleted = false

        for try await event in repository.importAudio(from: url) {
            switch event {
            case .progress: sawProgress = true
            case .completed: sawCompleted = true
            }
        }

        XCTAssertTrue(sawProgress)
        XCTAssertTrue(sawCompleted)
    }

    func test_generateWaveformPeaks_producesExactly4096Buckets_andRoundTripsViaTheBookmark() async throws {
        let url = try makeFixture(frameCount: 200_000)
        let asset = try await collectResult(repository.importAudio(from: url))

        let peaks = try await collectResult(repository.generateWaveformPeaks(for: asset))

        XCTAssertEqual(peaks.resolution, 4096)
        XCTAssertEqual(peaks.buckets.count, 4096)
        XCTAssertEqual(peaks.audioAssetID, asset.id)
    }

    func test_generateWaveformDetail_reducesOnlyTheRequestedSubRange() async throws {
        let url = try makeFixture(frameCount: 48000)
        let asset = try await collectResult(repository.importAudio(from: url))

        let buckets = try await repository.generateWaveformDetail(
            for: asset,
            startSeconds: 0,
            endSeconds: 0.5,
            resolution: 10
        )

        XCTAssertEqual(buckets.count, 10)
    }

    func test_refreshBookmarkIfStale_forAnUnmovedFile_returnsNil() throws {
        let url = try makeFixture()
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        XCTAssertNil(try repository.refreshBookmarkIfStale(bookmark, mode: .securityScoped))
    }

    /// The real, previously-missing correctness case: renaming the target
    /// file after a bookmark was created is the standard, reliable way to
    /// make a bookmark resolve *successfully* (macOS follows the file via
    /// identifying information beyond just the path) while still correctly
    /// reporting itself stale — proving `refreshBookmarkIfStale` actually
    /// detects this real condition, not just that it compiles against the
    /// `isStale` flag.
    func test_refreshBookmarkIfStale_afterFileIsRenamed_returnsARefreshedBookmarkPointingAtTheNewLocation() throws {
        let originalURL = try makeFixture()
        let originalBookmark = try originalURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let renamedURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent("renamed-\(UUID().uuidString).wav")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        fixtureURLs.append(renamedURL) // so tearDown cleans up the renamed file too

        let refreshed = try repository.refreshBookmarkIfStale(originalBookmark, mode: .securityScoped)
        let refreshedBookmark = try XCTUnwrap(refreshed, "Expected the moved file's bookmark to resolve as stale")

        var isStaleAfterRefresh = false
        let resolvedURL = try URL(
            resolvingBookmarkData: refreshedBookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStaleAfterRefresh
        )
        XCTAssertFalse(isStaleAfterRefresh)
        XCTAssertEqual(resolvedURL.lastPathComponent, renamedURL.lastPathComponent)
    }

    /// SPEC.md §4.10, "Security-scoped bookmark creation can fail entirely":
    /// this is the mode-aware *resolution* behavior the fallback depends on
    /// — proves `generateWaveformPeaks`/`generateWaveformDetail` correctly
    /// resolve a `.plainFallback` bookmark (no `.withSecurityScope` option),
    /// independent of whether the real security-scoped creation path is
    /// working on the machine running this test. The actual fallback
    /// *trigger* (a real `bookmarkData(options: .withSecurityScope, ...)`
    /// failure) is a live OS/Powerbox condition this suite cannot force —
    /// see the note on `test_importAudio_returnsPopulatedAudioAsset_
    /// includingEmbeddedMarkers`, above.
    func test_generateWaveformPeaksAndDetail_withAPlainFallbackBookmark_resolveWithoutSecurityScope() async throws {
        let url = try makeFixture(frameCount: 48000)
        let plainBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let importedAsset = try await collectResult(repository.importAudio(from: url))
        let fallbackAsset = AudioAsset(
            id: importedAsset.id,
            originalFileName: importedAsset.originalFileName,
            securityScopedBookmark: plainBookmark,
            bookmarkAccessMode: .plainFallback,
            duration: importedAsset.duration,
            sampleRate: importedAsset.sampleRate,
            channelCount: importedAsset.channelCount,
            bitDepth: importedAsset.bitDepth,
            importedAt: importedAsset.importedAt
        )

        let peaks = try await collectResult(repository.generateWaveformPeaks(for: fallbackAsset))
        XCTAssertEqual(peaks.buckets.count, 4096)

        let buckets = try await repository.generateWaveformDetail(
            for: fallbackAsset,
            startSeconds: 0,
            endSeconds: 0.5,
            resolution: 10
        )
        XCTAssertEqual(buckets.count, 10)
    }

    /// Mirrors `test_refreshBookmarkIfStale_afterFileIsRenamed_...` above,
    /// but for a `.plainFallback` bookmark — proves staleness detection and
    /// regeneration both work correctly without `.withSecurityScope`.
    func test_refreshBookmarkIfStale_withPlainFallbackMode_afterRename_returnsARefreshedPlainBookmark() throws {
        let originalURL = try makeFixture()
        let originalBookmark = try originalURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let renamedURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent("renamed-\(UUID().uuidString).wav")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        fixtureURLs.append(renamedURL)

        let refreshed = try repository.refreshBookmarkIfStale(originalBookmark, mode: .plainFallback)
        let refreshedBookmark = try XCTUnwrap(refreshed, "Expected the moved file's bookmark to resolve as stale")

        var isStaleAfterRefresh = false
        let resolvedURL = try URL(
            resolvingBookmarkData: refreshedBookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStaleAfterRefresh
        )
        XCTAssertFalse(isStaleAfterRefresh)
        XCTAssertEqual(resolvedURL.lastPathComponent, renamedURL.lastPathComponent)
    }

    /// D9/T9.1's real job — placeholder here, flagged explicitly rather
    /// than silently discovered (`ROADMAP.md` D8/T8.5).
    func test_detectCues_placeholderCompletesImmediately_withAnEmptyResult() async throws {
        let asset = AudioAsset(
            originalFileName: "placeholder.wav",
            securityScopedBookmark: Data(),
            duration: MediaDuration(seconds: 1),
            sampleRate: 48000,
            channelCount: 1,
            bitDepth: 16,
            importedAt: Date()
        )

        let cues = try await collectResult(repository.detectCues(in: asset, settings: AnalysisSettings()))

        XCTAssertEqual(cues, [])
    }
}
