import ACCore
import Foundation

/// An in-memory `AudioPlaybackController` fake (`ROADMAP.md` D9/T9.4) — no
/// real `AVAudioPlayer`, just recorded calls and a manually-driven
/// `stateUpdates` stream, per `CONTRIBUTING.md` §5. An `actor`, matching the
/// real implementation's own concurrency shape (it holds mutable state
/// across calls, unlike the stateless Repository fakes).
public actor InMemoryAudioPlaybackController: AudioPlaybackController {
    public private(set) var prepareCallCount = 0
    public private(set) var lastPreparedBookmark: Data?
    public private(set) var lastPreparedMode: AudioAsset.BookmarkAccessMode?
    public private(set) var playCalls: [(from: Double, until: Double?)] = []
    public private(set) var pauseCallCount = 0
    public private(set) var stopCallCount = 0

    private let prepareError: Error?
    private let continuation: AsyncStream<PlaybackState>.Continuation
    public nonisolated let stateUpdates: AsyncStream<PlaybackState>

    public init(prepareError: Error? = nil) {
        self.prepareError = prepareError
        var continuation: AsyncStream<PlaybackState>.Continuation!
        stateUpdates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func prepare(securityScopedBookmark: Data, mode: AudioAsset.BookmarkAccessMode) async throws {
        prepareCallCount += 1
        lastPreparedBookmark = securityScopedBookmark
        lastPreparedMode = mode
        if let prepareError {
            throw prepareError
        }
    }

    public func play(from startSeconds: Double, until endSeconds: Double?) async throws {
        playCalls.append((startSeconds, endSeconds))
        continuation.yield(.playing(positionSeconds: startSeconds))
    }

    public func pause() async {
        pauseCallCount += 1
        continuation.yield(.paused(positionSeconds: 0))
    }

    public func stop() async {
        stopCallCount += 1
        continuation.yield(.stopped)
    }

    /// Manually drives `stateUpdates` for tests asserting on a
    /// `CueDetectionReviewViewModel`'s reaction to a specific state,
    /// independent of a real call to `play`/`pause`/`stop`.
    public func emit(_ state: PlaybackState) {
        continuation.yield(state)
    }
}
