import ACCore
@testable import ACExport
import ACTestSupport
import XCTest

final class WAFormLayoutComputerTests: XCTestCase {
    private func cue(
        title: String = "Cue",
        rightHolders: [CueRightHolder] = [
            CueRightHolder(
                party: .person(UUID()),
                role: .composer,
                performanceBroadcastShare: 100,
                mechanicalRightsShare: 100
            ),
        ]
    ) -> Cue {
        Cue(title: title, duration: MediaDuration(seconds: 30), rightHolders: rightHolders, source: .manual)
    }

    private func project(cues: [Cue]) -> Project {
        var base = ProjectFixture.makeMinimal()
        base = Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: base.setup,
            cues: cues
        )
        return base
    }

    func test_computeLayout_noCues_stillProducesTheTwoFixedMainFormPages() {
        let pages = WAFormLayoutComputer.computeLayout(for: project(cues: []), continuationPagesAvailable: 5)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.map(\.pageCount), [2, 2])
    }

    func test_computeLayout_fiveCues_fitsEntirelyOnTheMainFormAlone_noContinuationPages() {
        let cues = (0 ..< 5).map { cue(title: "Cue \($0)") }
        let pages = WAFormLayoutComputer.computeLayout(for: project(cues: cues), continuationPagesAvailable: 5)
        XCTAssertEqual(pages.count, 2)
    }

    func test_computeLayout_sixCues_addsExactlyOneContinuationPage() {
        let cues = (0 ..< 6).map { cue(title: "Cue \($0)") }
        let pages = WAFormLayoutComputer.computeLayout(for: project(cues: cues), continuationPagesAvailable: 5)
        XCTAssertEqual(pages.count, 3)
    }

    func test_computeLayout_nineCues_stillOnlyOneContinuationPage_fourWorksPerContinuationPage() {
        let cues = (0 ..< 9).map { cue(title: "Cue \($0)") }
        let pages = WAFormLayoutComputer.computeLayout(for: project(cues: cues), continuationPagesAvailable: 5)
        XCTAssertEqual(pages.count, 3)
    }

    func test_computeLayout_tenCues_needsASecondContinuationPage() {
        let cues = (0 ..< 10).map { cue(title: "Cue \($0)") }
        let pages = WAFormLayoutComputer.computeLayout(for: project(cues: cues), continuationPagesAvailable: 5)
        XCTAssertEqual(pages.count, 4)
    }

    /// The real, confirmed capacity ceiling (`ROADMAP.md` D12) — cues beyond
    /// what the template's own real page count can hold are silently not
    /// drawn, never crash. Surfacing this as a validation warning is
    /// `ROADMAP.md` T12.3's job, not this pure function's.
    func test_computeLayout_moreCuesThanTemplateCanHold_capsAtWhatsAvailable_doesNotCrash() {
        let cues = (0 ..< 30).map { cue(title: "Cue \($0)") }
        let pages = WAFormLayoutComputer.computeLayout(for: project(cues: cues), continuationPagesAvailable: 1)
        // 2 main-form pages + exactly 1 continuation page, never more.
        XCTAssertEqual(pages.count, 3)
    }

    func test_computeLayout_zeroContinuationPagesAvailable_staysAtTheTwoMainFormPages() {
        let cues = (0 ..< 20).map { cue(title: "Cue \($0)") }
        let pages = WAFormLayoutComputer.computeLayout(for: project(cues: cues), continuationPagesAvailable: 0)
        XCTAssertEqual(pages.count, 2)
    }

    /// SPEC.md §4.16's per-document rule: `.performer` rows are excluded
    /// entirely from this document (unlike the cue sheet, which resolves
    /// them into an Interpret*in column) — confirmed here by checking the
    /// performer's own name never appears anywhere in the computed layout.
    func test_computeLayout_performerRightHolders_areExcludedEntirely() {
        let performer = Person(firstName: "Perry", lastName: "Former")
        let composer = Person(firstName: "Carla", lastName: "Composer")
        let testCue = Cue(
            title: "Cue With Performer",
            duration: MediaDuration(seconds: 30),
            rightHolders: [
                CueRightHolder(
                    party: .person(composer.id),
                    role: .composer,
                    performanceBroadcastShare: 100,
                    mechanicalRightsShare: 100
                ),
                CueRightHolder(
                    party: .person(performer.id),
                    role: .performer,
                    performanceBroadcastShare: 0,
                    mechanicalRightsShare: 0
                ),
            ],
            source: .manual
        )
        var base = ProjectFixture.makeMinimal()
        base = Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: base.setup,
            cues: [testCue],
            people: [performer, composer]
        )

        let pages = WAFormLayoutComputer.computeLayout(for: base, continuationPagesAvailable: 0)
        let allText = pages.flatMap(\.elements).compactMap { element -> String? in
            if case let .text(string, _) = element.content {
                return string
            }
            return nil
        }.joined(separator: "\n")

        XCTAssertTrue(allText.contains("Carla Composer"))
        XCTAssertFalse(allText.contains("Perry Former"))
    }

    /// The real, confirmed 3-row capacity limit (`+WorkBlock.swift`'s own
    /// doc comment) — a 4th non-`.performer` right-holder is silently
    /// dropped, never drawn past the real form's own 3 printed dotted lines.
    func test_computeLayout_moreThanThreeNonPerformerRightHolders_onlyFirstThreeAppear() {
        let people = (0 ..< 4).map { Person(firstName: "Person", lastName: "\($0)") }
        let testCue = Cue(
            title: "Crowded Cue",
            duration: MediaDuration(seconds: 30),
            rightHolders: people.map {
                CueRightHolder(
                    party: .person($0.id),
                    role: .composer,
                    performanceBroadcastShare: 25,
                    mechanicalRightsShare: 25
                )
            },
            source: .manual
        )
        var base = ProjectFixture.makeMinimal()
        base = Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: base.setup,
            cues: [testCue],
            people: people
        )

        let pages = WAFormLayoutComputer.computeLayout(for: base, continuationPagesAvailable: 0)
        // Scoped to page 0 (the single work block this 1-cue project draws
        // on the main form's page 1) deliberately, not every page's text:
        // round 3's item B (`docs/DECISIONS.md`, 2026-10-02) added a page 2
        // box that legitimately lists every composer across the whole
        // production — including "Person 3" — for signature purposes, a
        // separate concern from this work block's own real 3-row capacity
        // limit. Scoping here keeps this test about the row cap only.
        let page0Text = pages[0].elements.compactMap { element -> String? in
            if case let .text(string, _) = element.content {
                return string
            }
            return nil
        }.joined(separator: "\n")

        XCTAssertTrue(page0Text.contains("Person 0"))
        XCTAssertTrue(page0Text.contains("Person 1"))
        XCTAssertTrue(page0Text.contains("Person 2"))
        XCTAssertFalse(page0Text.contains("Person 3"))
    }

    func test_computeLayout_checkedProductionType_producesACheckmarkAtItsRealMeasuredBox() throws {
        var base = ProjectFixture.makeMinimal()
        base = Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: Setup(
                title: base.setup.title,
                producer: base.setup.producer,
                directorOrPrincipal: base.setup.directorOrPrincipal,
                productionRuntime: base.setup.productionRuntime,
                totalMusicRuntime: base.setup.totalMusicRuntime,
                productionYear: base.setup.productionYear,
                containsAdditionalUndeclaredWorks: base.setup.containsAdditionalUndeclaredWorks,
                productionTypes: [.series],
                declarant: base.setup.declarant,
                declarationDate: base.setup.declarationDate
            ),
            cues: []
        )

        let pages = WAFormLayoutComputer.computeLayout(for: base, continuationPagesAvailable: 0)
        let seriesBox = try XCTUnwrap(WAFormLayoutComputer.productionTypeCheckboxes[.series])
        let expectedMark = WAFormLayoutComputer.checkboxMark(at: seriesBox)
        XCTAssertTrue(pages[0].elements.contains(expectedMark))

        let commercialBox = try XCTUnwrap(WAFormLayoutComputer.productionTypeCheckboxes[.commercial])
        let uncheckedMark = WAFormLayoutComputer.checkboxMark(at: commercialBox)
        XCTAssertFalse(pages[0].elements.contains(uncheckedMark))
    }

    /// Guards the real grid structure extracted from the actual template —
    /// 14 real checkboxes (confirmed vector-square count on the real PDF),
    /// one per `ProductionType` case, no duplicates, no gaps.
    func test_productionTypeCheckboxes_hasExactlyOneBoxPerRealCase() {
        XCTAssertEqual(WAFormLayoutComputer.productionTypeCheckboxes.count, ProductionType.allCases.count)
    }

    func test_attachmentTypeCheckboxes_hasExactlyOneBoxPerRealCase() {
        XCTAssertEqual(WAFormLayoutComputer.attachmentTypeCheckboxes.count, AttachmentType.allCases.count)
    }

    /// Item B (round 3, `docs/DECISIONS.md` 2026-10-02): the main form's
    /// page 2 "aller anderen Rechtsinhaber" signature box lists every
    /// distinct composer across the whole production, except the
    /// declarant — confirms exclusion, cross-cue dedupe, and that the list
    /// lands on page 2 (index 1), not the per-cue work block.
    func test_computeLayout_otherComposerSignatureBox_listsEveryComposerExceptTheDeclarant_deduplicatedAcrossCues() {
        let declarantComposer = Person(firstName: "Dana", lastName: "Declarant")
        let otherComposer = Person(firstName: "Carla", lastName: "Composer")
        let cueOne = Cue(
            title: "Cue One", duration: MediaDuration(seconds: 30),
            rightHolders: [
                CueRightHolder(
                    party: .person(declarantComposer.id), role: .composer,
                    performanceBroadcastShare: 50, mechanicalRightsShare: 50
                ),
                CueRightHolder(
                    party: .person(otherComposer.id), role: .composer,
                    performanceBroadcastShare: 50, mechanicalRightsShare: 50
                ),
            ],
            source: .manual
        )
        let cueTwo = Cue(
            title: "Cue Two", duration: MediaDuration(seconds: 30),
            rightHolders: [
                CueRightHolder(
                    party: .person(otherComposer.id), role: .composer,
                    performanceBroadcastShare: 100, mechanicalRightsShare: 100
                ),
            ],
            source: .manual
        )

        // Tests `otherComposerSignatureLines` directly, not a full rendered
        // page — no `Project`/`Setup` ceremony needed for that, and the
        // declarant's own name legitimately appears elsewhere on page 2 too
        // (the declarant block itself), so searching rendered page text
        // would conflate that separate, correct rendering with this
        // function's own exclusion rule.
        let lines = WAFormLayoutComputer.otherComposerSignatureLines(
            cues: [cueOne, cueTwo], excludingDeclarant: .person(declarantComposer.id),
            people: [declarantComposer, otherComposer], labels: []
        )

        XCTAssertEqual(lines, ["Carla Composer"], "declarant excluded; appears exactly once despite being on both cues")
    }

    /// Round 5 (`docs/DECISIONS.md`, 2026-10-02): confirms two things the
    /// project owner explicitly required proven together before this item
    /// could be called done — (1) `computeLayout` genuinely cycles through
    /// more than one continuation page when the cue count and
    /// `continuationPagesAvailable` both allow it (15 cues, 5 pages
    /// available → main form's 5 works + 10 remaining works across 3
    /// continuation pages of 4/4/2), and (2) the composer signature box now
    /// renders on **every** continuation page, not only the last — real,
    /// previously-missing content this round added to
    /// `continuationPageElements` to match the real template's own design
    /// (every one of the 5 real continuation pages carries an identical
    /// "aller Rechtsinhaber" signature box, confirmed by the project owner
    /// via direct text extraction).
    func test_computeLayout_fifteenCues_spansThreeContinuationPages_eachCarryingTheSignatureBox() {
        let composer = Person(firstName: "Carla", lastName: "Composer")
        let cues = (0 ..< 15).map { index in
            Cue(
                title: "Cue \(index)", duration: MediaDuration(seconds: 30),
                rightHolders: [
                    CueRightHolder(
                        party: .person(composer.id), role: .composer,
                        performanceBroadcastShare: 100, mechanicalRightsShare: 100
                    ),
                ],
                source: .manual
            )
        }
        var base = ProjectFixture.makeMinimal()
        base = Project(
            id: base.id, name: base.name, createdAt: base.createdAt, updatedAt: base.updatedAt,
            setup: base.setup, cues: cues, people: [composer]
        )

        let pages = WAFormLayoutComputer.computeLayout(for: base, continuationPagesAvailable: 5)

        // 2 main form pages + 3 continuation pages (4 + 4 + 2 works).
        XCTAssertEqual(pages.count, 5)

        for continuationPageIndex in [2, 3, 4] {
            let pageText = pages[continuationPageIndex].elements.compactMap { element -> String? in
                if case let .text(string, _) = element.content {
                    return string
                }
                return nil
            }.joined(separator: "\n")
            XCTAssertTrue(
                pageText.contains("Carla Composer"),
                "continuation page \(continuationPageIndex - 1) is missing its own signature box"
            )
        }
    }
}
