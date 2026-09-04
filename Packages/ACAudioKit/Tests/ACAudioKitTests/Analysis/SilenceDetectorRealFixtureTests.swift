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

        for entry in manifest {
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

        let entriesWithEndOffset = manifest.filter { $0.groundTruthEndOffsetSeconds != nil }
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
}
