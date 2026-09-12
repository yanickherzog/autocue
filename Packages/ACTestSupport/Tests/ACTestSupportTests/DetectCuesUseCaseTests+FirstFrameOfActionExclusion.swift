import ACCore
@testable import ACTestSupport
import XCTest

/// `FirstFrameOfActionExclusion` (SPEC.md §4.11, `docs/DECISIONS.md`, this
/// date) — split into its own file/extension purely to keep
/// `DetectCuesUseCaseTests` under this project's type-body-length lint
/// limit, the same reason `UpdateCueUseCaseTests+Delete.swift` already is.
/// Reuses that class's `makeAsset`/`makeDetectedCue`/`run` helpers, made
/// non-`private` there specifically so this file can share them.
extension DetectCuesUseCaseTests {
    /// `09:59:52:00` — the same session-start convention
    /// `Audio_Analysis_Test/manifest.json`'s real fixtures use, and
    /// `CreateProjectUseCase`'s own real default. FFOA (`10:00:00:00`) is
    /// therefore `8.0`s audio-file-relative under this timecodeStart —
    /// deliberately chosen so these tests exercise the same real numbers
    /// the SEA_STEM investigation did, not arbitrary ones.
    private static var sessionStartTimecodeStart: Timecode {
        Timecode(offsetSeconds: 35992.0)
    }

    func test_ffoa_regionEntirelyBeforeFFOA_excludedEntirely() async throws {
        let asset = Self.makeAsset()
        // [2, 7) -- entirely before FFOA (8.0s under the session-start base above).
        let detected = [Self.makeDetectedCue(startSeconds: 2, duration: 5)]

        let result = try await run(
            detectedCues: detected,
            asset: asset,
            timecodeStart: Self.sessionStartTimecodeStart
        )

        XCTAssertTrue(result.isEmpty, "A region entirely before FFOA must never be constructed as a Cue at all.")
    }

    func test_ffoa_regionStraddlingFFOA_truncatedToStartExactlyAtFFOA_notDropped() async throws {
        let asset = Self.makeAsset()
        // [6, 16) -- straddles FFOA (8.0s): real content on both sides.
        let detected = [Self.makeDetectedCue(startSeconds: 6, duration: 10)]

        let result = try await run(
            detectedCues: detected,
            asset: asset,
            timecodeStart: Self.sessionStartTimecodeStart
        )

        XCTAssertEqual(result.count, 1, "A straddling region must be truncated, never dropped outright.")
        let cue = try XCTUnwrap(result.first)
        XCTAssertEqual(try XCTUnwrap(cue.startTimecode?.offsetSeconds), 8.0, accuracy: 0.0001)
        XCTAssertEqual(cue.duration.seconds, 8.0, accuracy: 0.0001) // 16 -> original end, unchanged
        XCTAssertEqual(cue.source, .detectedFromAudio)
    }

    func test_ffoa_regionEntirelyAfterFFOA_untouched() async throws {
        let asset = Self.makeAsset()
        let detected = [Self.makeDetectedCue(startSeconds: 10, duration: 20)]

        let result = try await run(
            detectedCues: detected,
            asset: asset,
            timecodeStart: Self.sessionStartTimecodeStart
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.startTimecode?.offsetSeconds, 10)
        XCTAssertEqual(result.first?.duration.seconds, 20)
    }

    func test_ffoa_noTimecodeStart_isANoOp_evenForARegionThatWouldOtherwiseBeExcluded() async throws {
        let asset = Self.makeAsset()
        // Same [2, 7) region as the exclusion test above -- with no
        // timecodeStart, there's no absolute reference to exclude it against.
        let detected = [Self.makeDetectedCue(startSeconds: 2, duration: 5)]

        let result = try await run(detectedCues: detected, asset: asset, timecodeStart: nil)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.startTimecode?.offsetSeconds, 2)
    }

    func test_ffoa_appliesToEmbeddedMarkerDerivedCues_regardlessOfSource() async throws {
        // An unconfirmed marker at 2s, no detected regions at all, a very
        // short 5s file -- produces a freestanding .embeddedMarker cue
        // spanning [2, 5), entirely before FFOA (8.0s). "Applies uniformly
        // regardless of source" means this must be excluded exactly like a
        // .detectedFromAudio region is, not treated as exempt because an
        // embedded marker is "always authoritative" for real-candidate
        // selection -- that rule was never about admitting non-music
        // material (docs/DECISIONS.md, this date).
        let marker = EmbeddedMarker(position: Timecode(offsetSeconds: 2))
        let asset = Self.makeAsset(durationSeconds: 5, embeddedMarkers: [marker])

        let result = try await run(
            detectedCues: [],
            asset: asset,
            timecodeStart: Self.sessionStartTimecodeStart
        )

        XCTAssertTrue(result.isEmpty, "An embedded-marker-derived cue entirely before FFOA must also be excluded.")
    }

    /// Real numbers, not synthetic ones -- the exact detected span
    /// `SilenceDetector` produced for `SEA_STEM_MX_ST_260311.wav`'s cue1
    /// against real `.automatic`-calibration defaults (docs/DECISIONS.md,
    /// this date): one continuous region `[7.996, 78.324)`, straddling FFOA
    /// by 4ms, overwhelmingly real music matching the project owner's own
    /// labeled cue1 (`11.36`-`78.44`). This is the real case that forced the
    /// truncate-not-drop correction to the original exclude-only proposal.
    func test_ffoa_realSeaStemCue1Numbers_truncatedNotDropped() async throws {
        let asset = Self.makeAsset()
        let detected = [Self.makeDetectedCue(startSeconds: 7.996, duration: 78.324 - 7.996)]

        let result = try await run(
            detectedCues: detected,
            asset: asset,
            timecodeStart: Self.sessionStartTimecodeStart
        )

        XCTAssertEqual(result.count, 1, "The real SEA_STEM cue1 region must survive, truncated, not be dropped.")
        let cue = try XCTUnwrap(result.first)
        XCTAssertEqual(try XCTUnwrap(cue.startTimecode?.offsetSeconds), 8.0, accuracy: 0.0001)
        XCTAssertEqual(cue.duration.seconds, 78.324 - 8.0, accuracy: 0.0001)
    }
}
