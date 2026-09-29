import ACCore
@testable import ACExport
import ACTestSupport
import XCTest

/// Real, fixture-driven tests for `CueSheetLayoutComputer` (SPEC.md §4.16,
/// `ROADMAP.md` D11/T11.2) — never mocked measurement, per `CONTRIBUTING.md`
/// §5: this exercises the real Core Text framesetter.
final class CueSheetLayoutComputerTests: XCTestCase {
    func test_fixtureProject_producesAtLeastOnePage() {
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        XCTAssertFalse(pages.isEmpty)
    }

    func test_everyPage_reportsTheSameTotalPageCount() {
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        for page in pages {
            XCTAssertEqual(page.pageCount, pages.count)
        }
    }

    func test_pageIndices_areSequentialStartingAtZero() {
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        XCTAssertEqual(pages.map(\.pageIndex), Array(0 ..< pages.count))
    }

    func test_headerBlock_includesSetupTitleAndProducerName() {
        let project = ProjectFixture.make()
        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        let texts = allText(in: pages)
        XCTAssertTrue(texts.contains { $0.contains(project.setup.title) })
        XCTAssertTrue(texts.contains { $0.contains("Grace Hopper") })
    }

    func test_footer_onlyAppearsOnTheLastPage() throws {
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        for page in pages.dropLast() {
            XCTAssertFalse(allText(in: [page]).contains { $0.contains("TOTAL MUSIK") })
        }
        XCTAssertTrue(try allText(in: [XCTUnwrap(pages.last)]).contains { $0.contains("TOTAL MUSIK") })
    }

    func test_cueSheetRow_includesComposerAndPerformerNames_forTheLicensedTrackCue() {
        // "Opening Theme" (ProjectFixture) has a composer (Ada Lovelace), a
        // publisher (Helvetic Music Publishing), and a performer (Nina
        // Simone) — the real licensed-third-party-track scenario that
        // motivated re-enabling `.performer` in the editor and adding
        // `Cue.recordingLabel`/etc. (`docs/DECISIONS.md`, 2026-09-27).
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        let texts = allText(in: pages)
        XCTAssertTrue(texts.contains { $0.contains("Ada Lovelace") })
        XCTAssertTrue(
            texts.contains { $0.contains("Nina Simone") },
            "Performer must appear in Interpret*in, not be excluded"
        )
    }

    func test_cueSheetRow_includesRecordingLabelFields_forTheLicensedTrackCue() {
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        let texts = allText(in: pages)
        XCTAssertTrue(texts.contains { $0.contains("Needle Drop Records") })
        XCTAssertTrue(texts.contains { $0.contains("NDR-4471") })
        XCTAssertTrue(texts.contains { $0.contains("CH-A12-26-00001") })
    }

    func test_noPercentagesRenderAnywhere() {
        // SPEC.md §4.16: the cue sheet is names-only, unlike the WA Film
        // form — confirmed 2026-09-27 against a real cue sheet example.
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        let texts = allText(in: pages)
        XCTAssertFalse(texts.contains { $0.contains("60.00") || $0.contains("40.00") || $0.contains("33.33") })
    }

    func test_manyCues_forcesMultiplePages() {
        var project = ProjectFixture.make()
        let extraCues = (0 ..< 40).map { index in
            Cue(
                title: "Filler Cue \(index) with a genuinely long title to force wrapping in narrow columns",
                duration: MediaDuration(seconds: 30),
                rightHolders: [
                    CueRightHolder(
                        party: .person(UUID()),
                        role: .composer,
                        performanceBroadcastShare: 100,
                        mechanicalRightsShare: 100
                    ),
                ],
                source: .manual
            )
        }
        project = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            audioAsset: project.audioAsset,
            waveformPeaks: project.waveformPeaks,
            setup: project.setup,
            cues: project.cues + extraCues,
            people: project.people,
            labels: project.labels
        )
        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        XCTAssertGreaterThan(pages.count, 1)
    }

    func test_noRowsAreDropped_acrossPagination() {
        var project = ProjectFixture.make()
        let extraCues = (0 ..< 40).map { index in
            Cue(
                title: "Filler Cue \(index)",
                duration: MediaDuration(seconds: 30),
                rightHolders: [
                    CueRightHolder(
                        party: .person(UUID()),
                        role: .composer,
                        performanceBroadcastShare: 100,
                        mechanicalRightsShare: 100
                    ),
                ],
                source: .manual
            )
        }
        project = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            audioAsset: project.audioAsset,
            waveformPeaks: project.waveformPeaks,
            setup: project.setup,
            cues: project.cues + extraCues,
            people: project.people,
            labels: project.labels
        )
        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        let texts = allText(in: pages)
        for index in 0 ..< 40 {
            XCTAssertTrue(texts.contains { $0 == "Filler Cue \(index)" }, "Cue \(index) missing from output")
        }
    }

    /// Real, self-caught bug (2026-09-27, `docs/DECISIONS.md`): the
    /// "Komponist-IPI" header cell rendered bare IPI numbers with no name
    /// attached, and `ProjectFixture` alone never exercises the multi-composer
    /// case (its two cues share the same single composer, Ada Lovelace) — so
    /// a dedicated multi-composer fixture is built here, not reused from
    /// `ProjectFixture`, per the project owner's own explicit request to
    /// verify against more than the single-composer case.
    ///
    /// Format updated (layout-redesign pass, `docs/DECISIONS.md`) from
    /// `"Name: IPI Nr. <raw>"` to `"Name, IPI-Nr. <grouped>"` — an 11-digit
    /// stored number's leading 2-digit padding is dropped and the remaining
    /// 9 digits grouped 3-2-2-2 (`CueSheetLayoutComputer.formattedIPI`).
    func test_headerBlock_komponistIPI_perComposerNameAndIPI_dedupedAcrossCues_missingIPIShowsNameOnly() {
        let pages = CueSheetLayoutComputer.computeLayout(for: multiComposerFixtureProject())
        let headerText = allText(in: pages).joined(separator: "\n")

        XCTAssertTrue(
            headerText.contains("Alice WithIPI, IPI-Nr. 111 11 11 11"),
            "A composer's name and IPI number must both appear, in \"Name, IPI-Nr. X\" format"
        )
        XCTAssertTrue(
            headerText.contains("Bob NoIPI"),
            "A composer with no IPI number on file must still be listed, by name"
        )
        XCTAssertFalse(
            headerText.contains("Bob NoIPI, IPI-Nr."),
            "A composer with no IPI number must show their bare name, never a blank/placeholder number"
        )
        let occurrences = headerText.components(separatedBy: "Alice WithIPI, IPI-Nr. 111 11 11 11").count - 1
        XCTAssertEqual(
            occurrences, 1,
            "The same composer appearing on multiple cues must be listed once in the header, not once per cue"
        )
    }

    /// Two composers across two cues — Alice (has an IPI number, composer on
    /// both, exercising dedup) and Bob (no IPI number on file) — a dedicated
    /// fixture, not reused from `ProjectFixture`, whose two cues share a
    /// single composer and so never exercises this multi-composer case. See
    /// `PDFCueSheetRendererTests`'s own copy of this fixture (kept separate
    /// rather than shared across test targets, matching this file's existing
    /// `allText`-per-file convention).
    private func multiComposerFixtureProject() -> Project {
        let composerWithIPI = Person(firstName: "Alice", lastName: "WithIPI", ipiNumber: "11111111111")
        let composerWithoutIPI = Person(firstName: "Bob", lastName: "NoIPI")
        let base = ProjectFixture.makeMinimal()
        let cueOne = Cue(
            title: "Cue One",
            duration: MediaDuration(seconds: 60),
            rightHolders: [
                CueRightHolder(
                    party: .person(composerWithIPI.id),
                    role: .composer,
                    performanceBroadcastShare: 100,
                    mechanicalRightsShare: 100
                ),
            ],
            source: .manual
        )
        let cueTwo = Cue(
            title: "Cue Two",
            duration: MediaDuration(seconds: 60),
            rightHolders: [
                CueRightHolder(
                    party: .person(composerWithIPI.id),
                    role: .composer,
                    performanceBroadcastShare: 50,
                    mechanicalRightsShare: 50
                ),
                CueRightHolder(
                    party: .person(composerWithoutIPI.id),
                    role: .composer,
                    performanceBroadcastShare: 50,
                    mechanicalRightsShare: 50
                ),
            ],
            source: .manual
        )
        return Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: base.setup,
            cues: [cueOne, cueTwo],
            people: [composerWithIPI, composerWithoutIPI]
        )
    }

    /// Not `private` — the layout-redesign pass's tests
    /// (`CueSheetLayoutComputerTests+Redesign.swift`) are an `extension` of
    /// this class in a separate file, split per `CONTRIBUTING.md` §8's
    /// `SwiftLint` `type_body_length` limit, and need this too.
    func allText(in pages: [CueSheetPageLayout]) -> [String] {
        pages.flatMap(\.elements).compactMap { element in
            if case let .text(string, _) = element.content {
                string
            } else {
                nil
            }
        }
    }
}
