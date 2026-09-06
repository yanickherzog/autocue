@testable import ACAudioKit
import ACCore
import XCTest

final class AudioPlaybackControllerImplTests: XCTestCase {
    private var fixtureURLs: [URL] = []

    override func tearDown() {
        for url in fixtureURLs {
            try? FileManager.default.removeItem(at: url)
        }
        fixtureURLs = []
        super.tearDown()
    }

    /// A real, short but real-length WAV fixture — `AVAudioPlayer` needs an
    /// actually-decodable file, not a zero-length one.
    private func makeFixture(seconds: Double = 2.0, sampleRate: Double = 48000) throws -> URL {
        let url = WAVFixtureBuilder.makeTemporaryURL()
        let frameCount = Int(seconds * sampleRate)
        try WAVFixtureBuilder.writeWAVFile(
            sampleRate: sampleRate,
            channelSamples: [[Float](repeating: 0.1, count: frameCount)],
            cuePoints: [],
            to: url
        )
        fixtureURLs.append(url)
        return url
    }

    func test_prepareAndPlay_emitsPlayingState() async throws {
        let url = try makeFixture()
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let controller = AudioPlaybackControllerImpl()

        try await controller.prepare(securityScopedBookmark: bookmark, mode: .plainFallback)
        try await controller.play(from: 0, until: nil)

        var sawPlaying = false
        for await state in controller.stateUpdates {
            if case .playing = state {
                sawPlaying = true
                break
            }
        }
        await controller.stop()
        XCTAssertTrue(sawPlaying)
    }

    func test_boundedPlayback_stopsAtTheUntilBound() async throws {
        let url = try makeFixture(seconds: 3.0)
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let controller = AudioPlaybackControllerImpl()

        try await controller.prepare(securityScopedBookmark: bookmark, mode: .plainFallback)
        try await controller.play(from: 0, until: 0.2)

        var sawStopped = false
        let deadline = Date().addingTimeInterval(3.0)
        for await state in controller.stateUpdates {
            if case .stopped = state {
                sawStopped = true
                break
            }
            if Date() > deadline {
                break
            }
        }
        XCTAssertTrue(sawStopped)
    }

    func test_playWithoutPrepare_throwsNotPrepared() async throws {
        let controller = AudioPlaybackControllerImpl()
        do {
            try await controller.play(from: 0, until: nil)
            XCTFail("Expected notPrepared")
        } catch AudioPlaybackControllerImplError.notPrepared {}
    }

    func test_playingAgainWhileAlreadyPlaying_seeksAndContinues_doesNotThrow() async throws {
        let url = try makeFixture(seconds: 3.0)
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let controller = AudioPlaybackControllerImpl()

        try await controller.prepare(securityScopedBookmark: bookmark, mode: .plainFallback)
        try await controller.play(from: 0, until: nil)
        try await controller.play(from: 1.0, until: nil) // retarget, not stop-then-replay

        await controller.stop()
    }

    /// Guards the seek-pop fix: every `play(from:until:)` mutes then ramps
    /// back via `AVAudioPlayer.setVolume(_:fadeDuration:)` rather than
    /// jumping straight to full volume across the discontinuous seek. Only
    /// the deterministic end state is asserted — that the ramp actually
    /// reaches full volume shortly after, not left stuck quiet — asserting
    /// on the mid-ramp value would be a real-clock-timing-fragile check
    /// this project's tests otherwise avoid.
    func test_play_seekFadeReachesFullVolumeShortlyAfter() async throws {
        let url = try makeFixture(seconds: 2.0)
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let controller = AudioPlaybackControllerImpl()

        try await controller.prepare(securityScopedBookmark: bookmark, mode: .plainFallback)
        try await controller.play(from: 0, until: nil)

        try await Task.sleep(nanoseconds: 100_000_000) // well past the ~10ms fade
        let volume = await controller.volumeForTesting
        XCTAssertEqual(volume, 1.0)

        await controller.stop()
    }
}
