@testable import ACAudioKit
@testable import ACCore
import XCTest

/// Real-fixture regression for `FirstFrameOfActionExclusion` (SPEC.md
/// §4.11, `docs/DECISIONS.md`, this date) — proves the truncate-not-drop
/// correction against the real audio that motivated it, not only against
/// synthetic numbers (`DetectCuesUseCaseTests` in `ACTestSupport` already
/// covers the synthetic cases, plus these same real SEA_STEM numbers
/// hardcoded as input). Same skip-if-absent convention as
/// `SilenceDetectorRealFixtureTests` (`docs/DECISIONS.md`, 2026-08-12):
/// `Audio_Analysis_Test/` is gitignored, so this only ever runs for real on
/// a machine where the project owner has placed the fixtures.
final class FFOAExclusionRealFixtureTests: XCTestCase {
    private func repoRootURL() -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("SPEC.md").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    /// `09:59:52:00` — the real session-start base
    /// `Audio_Analysis_Test/manifest.json`'s SEA_STEM entries use. FFOA
    /// (`10:00:00:00`) is `8.0`s audio-file-relative under it.
    private let sessionStartTimecodeStart = Timecode(offsetSeconds: 35992.0)

    func test_seaStemCue1_realDetectedRegion_straddlesFFOA_truncatedNotDropped() throws {
        guard let repoRoot = repoRootURL() else {
            throw XCTSkip("Could not resolve repo root.")
        }
        let fixtureURL = repoRoot
            .appendingPathComponent("Audio_Analysis_Test")
            .appendingPathComponent("SEA_STEM_MX_ST_260311.wav")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip(
                "SEA_STEM_MX_ST_260311.wav not present — real-fixture tier skipped, same documented, permanent " +
                    "CI-coverage gap as SilenceDetectorRealFixtureTests (docs/DECISIONS.md, 2026-08-12)."
            )
        }

        let reader = try WAVStreamingReader(url: fixtureURL)
        let regions = try SilenceDetector.detectRegions(reader: reader, settings: .init())

        // The real region matching ground-truth cue1 (11.36-78.44,
        // docs/DECISIONS.md this date) -- closest match by onset, same
        // convention SilenceDetectorRealFixtureTests uses.
        let cue1Region = try XCTUnwrap(
            regions.min { abs($0.startSeconds - 11.36) < abs($1.startSeconds - 11.36) },
            "No region detected near SEA_STEM cue1's ground-truth onset at all."
        )

        // Real, unmodified detection currently starts this region a few
        // milliseconds *before* FFOA (8.0s) -- confirms the straddling case
        // this regression exists to guard is still real, not a numbers
        // drift since the investigation that found it. If this assertion
        // ever fails, the underlying detection has changed and this
        // regression's premise needs re-checking, not silently loosening.
        XCTAssertLessThan(cue1Region.startSeconds, 8.0)

        let rawCue = Cue(
            title: "",
            duration: MediaDuration(seconds: cue1Region.endSeconds - cue1Region.startSeconds),
            rightHolders: [],
            source: .detectedFromAudio,
            startTimecode: Timecode(offsetSeconds: cue1Region.startSeconds)
        )

        let filtered = FirstFrameOfActionExclusion.apply(to: [rawCue], timecodeStart: sessionStartTimecodeStart)

        XCTAssertEqual(filtered.count, 1, "The real straddling region must survive, truncated, not be dropped.")
        let cue = try XCTUnwrap(filtered.first)
        XCTAssertEqual(try XCTUnwrap(cue.startTimecode?.offsetSeconds), 8.0, accuracy: 0.0001)
        XCTAssertEqual(cue.duration.seconds, cue1Region.endSeconds - 8.0, accuracy: 0.0001)
    }
}
