@testable import ACAudioKit
import XCTest

/// The real-fixture hard-case tier (`ROADMAP.md` D8/T8.3): exercises the
/// gradual-fade-in, quiet-under-ambient-mix, and short-non-silent-gap
/// failure modes synthetic buffers can't, against real hand-verified audio
/// the project owner supplies.
///
/// **Location, gitignore, and manifest convention** (`docs/DECISIONS.md`,
/// 2026-08-12): `Audio_Analysis_Test/` at the repo root, entirely outside
/// version control. Every test here **skips (`XCTSkip`), never fails**,
/// when the folder or its `manifest.json` is absent — this is what keeps CI
/// green, since the folder can never exist on a CI checkout. This tier is
/// only ever exercised for real on a machine where the project owner has
/// actually placed fixtures and confirmed the generated manifest.
final class SilenceDetectorRealFixtureTests: XCTestCase {
    private struct ManifestEntry: Decodable {
        let filename: String
        let scenario: String
        let groundTruthOffsetSeconds: Double
        let groundTruthEndOffsetSeconds: Double?
        let notes: String?
        /// `true` marks this entry as a **false-positive exclusion zone**,
        /// not a real ground-truth cue — `groundTruthOffsetSeconds`/
        /// `groundTruthEndOffsetSeconds` are the zone's bounds, not a cue's
        /// onset/offset. `nil`/absent is treated as `false` (an ordinary
        /// cue entry) — the overwhelming majority of this manifest.
        /// `docs/DECISIONS.md`, this date.
        let expectedZeroCues: Bool?
    }

    /// Walks up from this source file's own location to find the repo
    /// root (identified by `SPEC.md` living alongside it), then resolves
    /// `Audio_Analysis_Test/` relative to that — independent of the current
    /// working directory `swift test`/`xcodebuild test` happens to use.
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

    private func loadManifest() throws -> [ManifestEntry]? {
        guard let repoRoot = repoRootURL() else { return nil }
        let manifestURL = repoRoot
            .appendingPathComponent("Audio_Analysis_Test")
            .appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode([ManifestEntry].self, from: data)
    }

    /// 1 frame at the tightest supported `TimecodeFrameRate` (SPEC.md §4.9,
    /// `.fps30`/`.fps29_97NonDrop`/`.fps29_97Drop`) — the same bound the
    /// synthetic tier asserts against.
    private let oneFrameToleranceSeconds = 1.0 / 30.0

    func test_onsetAccuracy_everyFixtureClip_withinOneFrameToleranceOfGroundTruth() throws {
        guard let manifest = try loadManifest() else {
            throw XCTSkip(
                "Audio_Analysis_Test/manifest.json not present — real-fixture tier skipped, per its documented, " +
                    "permanent CI-coverage gap (docs/DECISIONS.md, 2026-08-12)."
            )
        }
        guard let repoRoot = repoRootURL() else {
            throw XCTSkip("Could not resolve repo root.")
        }

        // False-positive exclusion zones aren't ground-truth cues at all —
        // see test_falsePositiveExclusionZones below for their own,
        // differently-shaped assertion.
        for entry in manifest where entry.expectedZeroCues != true {
            let fixtureURL = repoRoot.appendingPathComponent("Audio_Analysis_Test")
                .appendingPathComponent(entry.filename)
            let reader = try WAVStreamingReader(url: fixtureURL)
            let regions = try SilenceDetector.detectRegions(reader: reader, settings: .init())

            let closestOnset = regions.map(\.startSeconds).min {
                abs($0 - entry.groundTruthOffsetSeconds) < abs($1 - entry.groundTruthOffsetSeconds)
            }
            let onset = try XCTUnwrap(
                closestOnset,
                "No region detected at all for \(entry.filename) (\(entry.scenario))"
            )
            XCTAssertEqual(
                onset,
                entry.groundTruthOffsetSeconds,
                accuracy: oneFrameToleranceSeconds,
                "\(entry.filename) (\(entry.scenario)): onset accuracy"
            )
        }
    }

    /// Graded as an independent assertion from onset accuracy (above) —
    /// starts and ends are produced by two different mechanisms (SuperFlux
    /// for starts; the unchanged reverb-tail mechanism for ends) that must
    /// be able to regress independently and be caught independently
    /// (SPEC.md §4.11).
    func test_offsetAccuracy_everyFixtureClipWithADocumentedEnd_withinOneFrameToleranceOfGroundTruth() throws {
        guard let manifest = try loadManifest() else {
            throw XCTSkip("Audio_Analysis_Test/manifest.json not present — real-fixture tier skipped.")
        }
        guard let repoRoot = repoRootURL() else {
            throw XCTSkip("Could not resolve repo root.")
        }

        let entriesWithEndOffset = manifest.filter {
            $0.groundTruthEndOffsetSeconds != nil && $0.expectedZeroCues != true
        }
        guard !entriesWithEndOffset.isEmpty else {
            throw XCTSkip("No manifest entries document a ground-truth end offset.")
        }

        for entry in entriesWithEndOffset {
            guard let groundTruthEnd = entry.groundTruthEndOffsetSeconds else { continue }
            let fixtureURL = repoRoot.appendingPathComponent("Audio_Analysis_Test")
                .appendingPathComponent(entry.filename)
            let reader = try WAVStreamingReader(url: fixtureURL)
            let regions = try SilenceDetector.detectRegions(reader: reader, settings: .init())

            let closestEnd = regions.map(\.endSeconds).min {
                abs($0 - groundTruthEnd) < abs($1 - groundTruthEnd)
            }
            let end = try XCTUnwrap(closestEnd, "No region detected at all for \(entry.filename) (\(entry.scenario))")
            XCTAssertEqual(
                end,
                groundTruthEnd,
                accuracy: oneFrameToleranceSeconds,
                "\(entry.filename) (\(entry.scenario)): offset accuracy"
            )
        }
    }

    /// A different shape of assertion from the two above — these manifest
    /// entries (`expectedZeroCues == true`) aren't ground-truth cues at all,
    /// they're confirmed-silent spans where `SilenceDetector` genuinely
    /// detects a region that shouldn't exist (a real, calibration-depth
    /// false positive, not a logic defect — `docs/DECISIONS.md`, this
    /// date). "Closest region" matching doesn't apply here; the only
    /// meaningful check is that **no** detected region overlaps the zone at
    /// all.
    func test_falsePositiveExclusionZones_noDetectedRegionOverlapsAConfirmedSilentSpan() throws {
        guard let manifest = try loadManifest() else {
            throw XCTSkip("Audio_Analysis_Test/manifest.json not present — real-fixture tier skipped.")
        }
        guard let repoRoot = repoRootURL() else {
            throw XCTSkip("Could not resolve repo root.")
        }

        let zones = manifest.filter { $0.expectedZeroCues == true }
        guard !zones.isEmpty else {
            throw XCTSkip("No manifest entries mark a false-positive exclusion zone.")
        }

        for zone in zones {
            guard let zoneEnd = zone.groundTruthEndOffsetSeconds else {
                XCTFail("\(zone.filename) (\(zone.scenario)): expectedZeroCues entries must have an end offset.")
                continue
            }
            let zoneStart = zone.groundTruthOffsetSeconds
            let fixtureURL = repoRoot.appendingPathComponent("Audio_Analysis_Test")
                .appendingPathComponent(zone.filename)
            let reader = try WAVStreamingReader(url: fixtureURL)
            let regions = try SilenceDetector.detectRegions(reader: reader, settings: .init())

            let overlapping = regions.filter { $0.startSeconds < zoneEnd && $0.endSeconds > zoneStart }
            XCTAssertTrue(
                overlapping.isEmpty,
                "\(zone.filename) (\(zone.scenario)): expected zero detected regions in [\(zoneStart), " +
                    "\(zoneEnd)) but found \(overlapping.count): \(overlapping)"
            )
        }
    }
}
