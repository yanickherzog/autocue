import ACCore
import AVFoundation
import Foundation

/// The real `AudioAnalysisRepository` implementation (`ROADMAP.md` D8/T8.5)
/// — WAV import (metadata + embedded markers + a security-scoped bookmark),
/// waveform peak generation (overview and on-demand detail), backed by
/// `WAVStreamingReader`/`RIFFChunkParser`/`WaveformPeakExtractor`.
///
/// **`detectCues` (`ROADMAP.md` D9/T9.1) runs the real `SilenceDetector`
/// pipeline but stays raw-signal-only** — it never touches
/// `AudioAsset.embeddedMarkers`. Merging that raw output against embedded
/// markers into the final, reconciled `[Cue]` list is `DetectCuesUseCase`'s
/// job (SPEC.md §4.11's "Combining with embedded markers") — this method
/// intentionally mirrors `SilenceDetector`'s own restraint one layer down.
///
/// Stateless (no stored properties) — a `struct`, matching every other
/// Repository/Use Case implementation's "Use Cases Are Stateless" shape
/// (`CLAUDE.md`), even though this is a Data-layer type, not a Use Case
/// itself: nothing here needs per-instance state, since every call resolves
/// its own file access fresh.
public struct AudioAnalysisRepositoryImpl: AudioAnalysisRepository {
    public init() {}

    public func importAudio(from url: URL) -> AsyncThrowingStream<OperationProgress<AudioAsset>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // `accessGranted` is deliberately *not* gated on directly
                    // (`guard ... else { throw }`) — `false` is also the
                    // harmless, documented return for a URL that was never
                    // security-scoped to begin with (e.g. test fixtures,
                    // which read perfectly fine without it). It's only a
                    // real signal once combined with the actual read below
                    // *also* failing — see the `catch` clause.
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }

                    continuation.yield(.progress(ProgressUpdate(fractionCompleted: 0.0, message: "Reading file")))

                    let reader: WAVStreamingReader
                    do {
                        reader = try WAVStreamingReader(url: url)
                    } catch {
                        throw Self.diagnosableError(
                            from: error,
                            accessGranted: accessGranted,
                            stage: "WAVStreamingReader.init"
                        )
                    }

                    let parsed: RIFFChunkParser.ParseResult
                    do {
                        parsed = try RIFFChunkParser.parse(url: url)
                    } catch {
                        throw Self.diagnosableError(
                            from: error,
                            accessGranted: accessGranted,
                            stage: "RIFFChunkParser.parse"
                        )
                    }

                    let (bookmark, bookmarkAccessMode) = try Self.makeBookmark(for: url, accessGranted: accessGranted)

                    let asset = AudioAsset(
                        originalFileName: url.lastPathComponent,
                        securityScopedBookmark: bookmark,
                        bookmarkAccessMode: bookmarkAccessMode,
                        duration: MediaDuration(seconds: reader.durationSeconds),
                        sampleRate: reader.sampleRate,
                        channelCount: reader.channelCount,
                        bitDepth: reader.bitDepth,
                        embeddedMarkers: parsed.embeddedMarkers,
                        broadcastWaveMetadata: parsed.broadcastWaveMetadata,
                        importedAt: Date()
                    )

                    continuation.yield(.progress(ProgressUpdate(fractionCompleted: 1.0, message: nil)))
                    continuation.yield(.completed(asset))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateWaveformPeaks(
        for asset: AudioAsset
    ) -> AsyncThrowingStream<OperationProgress<WaveformPeaks>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = try Self.resolveURL(
                        bookmark: asset.securityScopedBookmark,
                        mode: asset.bookmarkAccessMode
                    )
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }

                    do {
                        let reader = try WAVStreamingReader(url: url)
                        let buckets = try WaveformPeakExtractor.extract(
                            reader: reader,
                            resolution: Self.persistedOverviewResolution
                        ) { progress in
                            continuation.yield(.progress(ProgressUpdate(fractionCompleted: progress, message: nil)))
                        }
                        let peaks = WaveformPeaks(
                            audioAssetID: asset.id,
                            resolution: Self.persistedOverviewResolution,
                            buckets: buckets
                        )
                        continuation.yield(.completed(peaks))
                        continuation.finish()
                    } catch {
                        throw Self.diagnosableError(
                            from: error,
                            accessGranted: accessGranted,
                            stage: "generateWaveformPeaks"
                        )
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateWaveformDetail(
        for asset: AudioAsset,
        startSeconds: Double,
        endSeconds: Double,
        resolution: Int
    ) async throws -> [WaveformPeakBucket] {
        let url = try Self.resolveURL(bookmark: asset.securityScopedBookmark, mode: asset.bookmarkAccessMode)
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let reader = try WAVStreamingReader(url: url)
            return try WaveformPeakExtractor.extract(
                reader: reader,
                resolution: resolution,
                startFrame: AVAudioFramePosition(startSeconds * reader.sampleRate),
                endFrame: AVAudioFramePosition(endSeconds * reader.sampleRate)
            )
        } catch {
            throw Self.diagnosableError(from: error, accessGranted: accessGranted, stage: "generateWaveformDetail")
        }
    }

    /// Raw signal detection only, per `AudioAnalysisRepository`'s protocol
    /// contract — merging against `asset.embeddedMarkers` is
    /// `DetectCuesUseCase`'s job (`ROADMAP.md` D9/T9.1). Mirrors
    /// `generateWaveformDetail`'s plain (non-staleness-checking) bookmark
    /// resolution — refreshing a stale bookmark is the calling Use Case's
    /// responsibility, not this method's.
    public func detectCues(
        in asset: AudioAsset,
        settings: AnalysisSettings
    ) -> AsyncThrowingStream<OperationProgress<[Cue]>, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = try Self.resolveURL(
                        bookmark: asset.securityScopedBookmark,
                        mode: asset.bookmarkAccessMode
                    )
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }

                    do {
                        let reader = try WAVStreamingReader(url: url)
                        let regions = try SilenceDetector
                            .detectRegions(reader: reader, settings: settings) { progress in
                                continuation.yield(.progress(ProgressUpdate(fractionCompleted: progress, message: nil)))
                            }
                        let cues = regions.map { region in
                            Cue(
                                title: "",
                                duration: MediaDuration(seconds: region.endSeconds - region.startSeconds),
                                rightHolders: [],
                                source: .detectedFromAudio,
                                startTimecode: Timecode(offsetSeconds: region.startSeconds)
                            )
                        }
                        continuation.yield(.completed(cues))
                        continuation.finish()
                    } catch {
                        throw Self.diagnosableError(from: error, accessGranted: accessGranted, stage: "detectCues")
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// `URL(resolvingBookmarkData:...)` reports staleness as a side effect of
    /// resolution — a stale bookmark still resolves to a working `URL` (the
    /// OS follows the underlying file via other stored identifying
    /// information, e.g. after a rename), it's just no longer an accurate
    /// record of the file's *current* location/state, and the OS
    /// recommends regenerating it. Regeneration itself needs a real,
    /// briefly-accessible `URL` to call `bookmarkData(options:...)` against,
    /// so this resolves once, checks `isStale`, and — only when true —
    /// captures a fresh bookmark from that same resolved `URL` before
    /// releasing access. `mode` selects `.withSecurityScope` vs. plain
    /// options throughout, matching whichever kind of bookmark was actually
    /// stored — never upgraded from `.plainFallback` back to
    /// `.securityScoped` here (SPEC.md §4.10 — that would require re-running
    /// the same creation attempt `importAudio` already made, which only a
    /// fresh, live, user-just-selected `URL` can attempt meaningfully).
    public func refreshBookmarkIfStale(_ bookmark: Data, mode: AudioAsset.BookmarkAccessMode) throws -> Data? {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: mode.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard isStale else { return nil }

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            return try url.bookmarkData(
                options: mode.creationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw Self.diagnosableError(from: error, accessGranted: accessGranted, stage: "refreshBookmarkIfStale")
        }
    }

    // MARK: - Bookmark creation and resolution

    /// A security-scoped bookmark is always attempted first — it's the only
    /// kind that reliably survives an app relaunch under App Sandbox. If
    /// creation itself fails, falls back to a plain bookmark so the current
    /// session's import isn't blocked on something outside this app's
    /// control — see SPEC.md §4.10, "Security-scoped bookmark creation can
    /// fail entirely," and `docs/DECISIONS.md` for why this fallback exists
    /// (a real, documented macOS failure mode, confirmed across many rounds
    /// of ruling out every code-level cause first: URL identity, call
    /// ordering, entitlements, App Translocation, TCC-protected-folder
    /// nesting, sandbox enforcement, and `.fileImporter` configuration were
    /// all individually verified clean before concluding this).
    private static func makeBookmark(
        for url: URL,
        accessGranted: Bool
    ) throws -> (Data, AudioAsset.BookmarkAccessMode) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return (bookmark, .securityScoped)
        } catch let securityScopedError {
            do {
                let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                return (bookmark, .plainFallback)
            } catch let plainError {
                let securityScopedNSError = securityScopedError as NSError
                throw Self.diagnosableError(
                    from: plainError,
                    accessGranted: accessGranted,
                    stage: "bookmarkData (security-scoped attempt also failed: "
                        + "domain=\(securityScopedNSError.domain) code=\(securityScopedNSError.code))"
                )
            }
        }
    }

    /// Re-resolves a previously-captured bookmark back to a usable `URL` —
    /// `mode` must match whatever `bookmarkAccessMode` the bookmark was
    /// actually created under (`makeBookmark`, above, or `importAudio`'s
    /// resulting `AudioAsset`), or resolution can silently fail to restore
    /// sandboxed access.
    private static func resolveURL(bookmark: Data, mode: AudioAsset.BookmarkAccessMode) throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: bookmark,
            options: mode.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// **Temporary diagnostic wrapping** — every failure at any of these
    /// call sites currently surfaces as `.stageFailed`, reporting exactly
    /// which stage threw, whether `startAccessingSecurityScopedResource()`
    /// reported success, and the underlying `NSError`'s real domain/code
    /// (plus any nested `NSUnderlyingErrorKey`, where AVFoundation/CoreAudio
    /// failures often carry their real root cause) — because the generic
    /// Cocoa errors this wraps (e.g. `NSCocoaErrorDomain` code 256, "The
    /// file couldn't be opened") give no actionable detail on their own.
    /// Once the real root cause is confirmed, this collapses back down to
    /// one clean, permanent, user-legible message — this verbose form is
    /// intentionally not the final shape.
    private static func diagnosableError(from error: Error, accessGranted: Bool, stage: String) -> Error {
        AudioAnalysisRepositoryImplError.stageFailed(stage: stage, accessGranted: accessGranted, underlying: error)
    }

    private static let persistedOverviewResolution = 4096
}

/// Maps `AudioAsset.BookmarkAccessMode` to the actual `URL` bookmark options
/// it corresponds to — kept local to this Data-layer package rather than on
/// the `ACCore` enum itself, since `URL.Bookmark{Creation,Resolution}Options`
/// are Foundation API surface this Repository implementation owns, not a
/// concern the Domain type needs to know the shape of.
private extension AudioAsset.BookmarkAccessMode {
    var creationOptions: URL.BookmarkCreationOptions {
        switch self {
        case .securityScoped: .withSecurityScope
        case .plainFallback: []
        }
    }

    var resolutionOptions: URL.BookmarkResolutionOptions {
        switch self {
        case .securityScoped: .withSecurityScope
        case .plainFallback: []
        }
    }
}

/// User-legible errors specific to this Repository implementation's
/// sandboxed file access — distinct from the raw Cocoa/AVFoundation errors
/// they wrap, which are rarely legible to an end user on their own (e.g.
/// `NSCocoaErrorDomain Code=256 "Could not open() the item"` gives no hint
/// that the actual cause was a denied security-scoped resource grant).
public enum AudioAnalysisRepositoryImplError: LocalizedError {
    case stageFailed(stage: String, accessGranted: Bool, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case let .stageFailed(stage, accessGranted, underlying):
            let nsError = underlying as NSError
            let userInfoDump = nsError.userInfo
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
            return "[DIAGNOSTIC] stage=\(stage) securityScopeAccessGranted=\(accessGranted) "
                + "domain=\(nsError.domain) code=\(nsError.code) "
                + "localizedDescription=\(underlying.localizedDescription) "
                + "userInfo={\(userInfoDump)}"
        }
    }
}
