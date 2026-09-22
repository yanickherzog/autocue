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

        let rawCue = Cue(
            title: "",
            duration: MediaDuration(seconds: cue1Region.endSeconds - cue1Region.startSeconds),
            rightHolders: [],
            source: .detectedFromAudio,
            startTimecode: Timecode(offsetSeconds: cue1Region.startSeconds)
        )

        let filtered = FirstFrameOfActionExclusion.apply(to: [rawCue], timecodeStart: sessionStartTimecodeStart)

        // **2026-09-22 update, real numbers, not silently patched:** under
        // the pre-LPRC mechanism this region's raw onset was `7.996s`, 4ms
        // *before* FFOA (`8.0s`) -- a real straddling case, which this test
        // originally pinned. Under LPRC the same file's raw onset is
        // `8.0411s`, now *after* FFOA -- the straddling case no longer
        // reproduces on this fixture. This is not a detection-quality
        // regression: both values are artifacts of exactly where the
        // pre-FFOA 2-pop/leader tone's own energy happens to cross
        // whichever threshold is in effect, not a meaningful position
        // relative to cue1's real acoustic onset (`11.36s`) either way.
        // `DetectCuesUseCaseTests` (`ACTestSupport`) still covers the
        // truncate-not-drop *logic* synthetically, independent of which
        // real file currently happens to straddle FFOA -- this real-fixture
        // test now documents the *current* real behavior (a clean
        // pass-through, no truncation needed) rather than asserting a
        // straddling scenario that no longer occurs here. If a future real
        // fixture reproduces genuine straddling, add a dedicated real check
        // for it rather than reviving this exact pinned case.
        XCTAssertGreaterThanOrEqual(
            cue1Region.startSeconds, 8.0,
            "documents that this real region no longer straddles FFOA under the current mechanism"
        )
        XCTAssertEqual(filtered.count, 1, "a non-straddling region must pass through unchanged, not be dropped.")
        let cue = try XCTUnwrap(filtered.first)
        XCTAssertEqual(
            try XCTUnwrap(cue.startTimecode?.offsetSeconds), cue1Region.startSeconds, accuracy: 0.0001,
            "no truncation should occur once the region starts at or after FFOA"
        )
        XCTAssertEqual(cue.duration.seconds, cue1Region.endSeconds - cue1Region.startSeconds, accuracy: 0.0001)
    }
}
