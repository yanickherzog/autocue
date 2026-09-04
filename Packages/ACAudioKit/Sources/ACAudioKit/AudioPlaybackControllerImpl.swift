import ACCore
import AVFoundation
import Foundation

/// The real `AudioPlaybackController` implementation (`ROADMAP.md` D9/T9.4,
/// SPEC.md §4.20) — `AVAudioPlayer`-backed, not `AVAudioEngine`: this need
/// (play one already-imported file from an offset, pause/stop, report
/// position) has no real-time mixing/effects graph to justify the heavier
/// API.
///
/// **An `actor`, not a stateless `struct`** — unlike every other
/// `ACAudioKit`/`ACCore` Repository/Use Case, this type genuinely holds
/// mutable state across calls (a live `AVAudioPlayer`, an open
/// security-scoped access grant, a polling `Task`), the same "internal
/// actor is a Data-layer detail" allowance `CLAUDE.md` already makes for
/// Repository implementations, extended here to this non-`Repository`-
/// suffixed protocol of the same architectural shape.
///
/// **Bounded playback (`until` non-nil) uses the poll-and-stop pattern
/// SPEC.md §4.20 specifies** — a periodic check against
/// `AVAudioPlayer.currentTime`, stopping once the bound is reached. The same
/// poll loop doubles as `stateUpdates`' emission cadence (~30Hz), which is
/// also what the playhead needs for smooth tracking — one mechanism, two
/// jobs, not two independently built.
public actor AudioPlaybackControllerImpl: AudioPlaybackController {
    private var player: AVAudioPlayer?
    private var accessScopedURL: URL?
    private var boundedEndSeconds: Double?
    private var pollTask: Task<Void, Never>?

    private let continuation: AsyncStream<PlaybackState>.Continuation
    public nonisolated let stateUpdates: AsyncStream<PlaybackState>

    private static let pollIntervalNanoseconds: UInt64 = 33_000_000 // ~30Hz

    public init() {
        var continuation: AsyncStream<PlaybackState>.Continuation!
        stateUpdates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    deinit {
        pollTask?.cancel()
        accessScopedURL?.stopAccessingSecurityScopedResource()
    }

    public func prepare(securityScopedBookmark: Data, mode: AudioAsset.BookmarkAccessMode) async throws {
        tearDownCurrentPlayer()

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: securityScopedBookmark,
            options: mode.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let accessGranted = url.startAccessingSecurityScopedResource()
        if accessGranted {
            accessScopedURL = url
        }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            player = newPlayer
        } catch {
            tearDownCurrentPlayer()
            throw error
        }
    }

    /// Seeks and continues if already playing — never stop-then-replay,
    /// which would produce overlapping audio on rapid re-clicking
    /// (SPEC.md §4.20).
    public func play(from startSeconds: Double, until endSeconds: Double?) async throws {
        guard let player else { throw AudioPlaybackControllerImplError.notPrepared }
        player.currentTime = startSeconds
        boundedEndSeconds = endSeconds
        if !player.isPlaying {
            player.play()
        }
        startPolling()
    }

    public func pause() async {
        player?.pause()
        pollTask?.cancel()
        continuation.yield(.paused(positionSeconds: player?.currentTime ?? 0))
    }

    public func stop() async {
        player?.stop()
        pollTask?.cancel()
        boundedEndSeconds = nil
        continuation.yield(.stopped)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, await pollOnceAndCheckIfFinished() == false else { return }
                try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
            }
        }
    }

    /// Emits the current `PlaybackState` and returns whether playback has
    /// finished (either the bounded span was reached, or the player stopped
    /// on its own) — in which case polling stops.
    private func pollOnceAndCheckIfFinished() -> Bool {
        guard let player else { return true }
        guard player.isPlaying else {
            continuation.yield(.stopped)
            return true
        }
        if let boundedEndSeconds, player.currentTime >= boundedEndSeconds {
            player.stop()
            continuation.yield(.stopped)
            return true
        }
        continuation.yield(.playing(positionSeconds: player.currentTime))
        return false
    }

    private func tearDownCurrentPlayer() {
        pollTask?.cancel()
        player?.stop()
        player = nil
        accessScopedURL?.stopAccessingSecurityScopedResource()
        accessScopedURL = nil
        boundedEndSeconds = nil
    }
}

public enum AudioPlaybackControllerImplError: Error, Equatable {
    case notPrepared
}
