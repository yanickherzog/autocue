import ACCore
@testable import ACExport
import ACTestSupport
import XCTest

/// Tests for the layout follow-up pass (2026-09-29): the new "Arrangeur*in:"
/// summary block (matching the existing "Interpret*in:" block, for the
/// `.arranger` role) and the pagination fix that lets a non-last page use the
/// page's full height instead of reserving space for a footer/summary block
/// it never actually draws. Split into its own file per `CONTRIBUTING.md` §8's
/// `SwiftLint` `file_length` limit — `CueSheetLayoutComputerTests+Redesign.swift`
/// was already at that limit.
extension CueSheetLayoutComputerTests {
    // MARK: - Arrangeur*in summary block

    func test_arrangeurBlock_listsEveryArrangerAcrossTheWholeProject_dedupedByIdentity() {
        let composerID = UUID()
        let arrangerID = UUID()
        let arranger = Person(id: arrangerID, firstName: "Fritz", lastName: "Brun", ipiNumber: "98765432101")
        let composerHolder = simpleRightHolder(party: .person(composerID), role: .composer)
        let arrangerHolder = simpleRightHolder(party: .person(arrangerID), role: .arranger)
        let cueOne = Cue(
            title: "Cue One",
            duration: MediaDuration(seconds: 60),
            rightHolders: [composerHolder, arrangerHolder],
            source: .manual
        )
        let cueTwo = Cue(
            title: "Cue Two",
            duration: MediaDuration(seconds: 60),
            rightHolders: [composerHolder, arrangerHolder],
            source: .manual
        )
        let project = multiCueProject(cues: [cueOne, cueTwo], people: [arranger])

        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        let texts = allText(in: pages)
        XCTAssertTrue(texts.contains("Arrangeur*in:"))
        XCTAssertTrue(texts.contains { $0.contains("Fritz Brun, IPI-Nr. 98765 43 21 01") })

        let aggregated = CueSheetLayoutComputer.arrangeurIPILines(
            cues: project.cues,
            people: project.people,
            labels: project.labels
        )
        XCTAssertEqual(aggregated, ["Fritz Brun, IPI-Nr. 98765 43 21 01"])
    }

    func test_arrangeurBlock_omittedEntirely_whenTheProjectHasNoArrangers() {
        // `ProjectFixture.makeMinimal()` has no cues at all, so no arrangers.
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.makeMinimal())
        let texts = allText(in: pages)
        XCTAssertFalse(texts.contains("Arrangeur*in:"))
    }

    /// Exercises the Arrangeur*in block rendering with no Interpret*in
    /// block above it, not only the "both present" case.
    func test_arrangeurBlock_rendersOnItsOwn_whenTheProjectHasNoPerformers() {
        let arranger = Person(firstName: "Fritz", lastName: "Brun")
        let project = singleCueProject(
            rightHolders: [
                simpleRightHolder(party: .person(UUID()), role: .composer),
                simpleRightHolder(party: .person(arranger.id), role: .arranger),
            ],
            people: [arranger]
        )

        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        let texts = allText(in: pages)
        XCTAssertFalse(texts.contains("Interpret*in:"))
        XCTAssertTrue(texts.contains("Arrangeur*in:"))
        XCTAssertTrue(texts.contains { $0.contains("Fritz Brun") })
    }

    /// When both blocks are present, Interpret*in must be drawn first,
    /// Arrangeur*in directly below it — per the requested layout ("below
    /// the Interpret*in block, add a matching Arrangeur*in block").
    func test_bothSummaryBlocks_whenPresent_interpretComesBeforeArrangeur() {
        let performer = Person(firstName: "Nina", lastName: "Simone")
        let arranger = Person(firstName: "Fritz", lastName: "Brun")
        let project = singleCueProject(
            rightHolders: [
                simpleRightHolder(party: .person(UUID()), role: .composer),
                simpleRightHolder(party: .person(performer.id), role: .performer),
                simpleRightHolder(party: .person(arranger.id), role: .arranger),
            ],
            people: [performer, arranger]
        )

        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        let texts = allText(in: pages)
        let interpretIndex = texts.firstIndex(of: "Interpret*in:")
        let arrangeurIndex = texts.firstIndex(of: "Arrangeur*in:")
        XCTAssertNotNil(interpretIndex)
        XCTAssertNotNil(arrangeurIndex)
        if let interpretIndex, let arrangeurIndex {
            XCTAssertLessThan(interpretIndex, arrangeurIndex)
        }

        // And geometrically below it, not just later in the element list.
        let interpretLabelY = frameY(of: "Interpret*in:", in: pages)
        let arrangeurLabelY = frameY(of: "Arrangeur*in:", in: pages)
        XCTAssertNotNil(interpretLabelY)
        XCTAssertNotNil(arrangeurLabelY)
        if let interpretLabelY, let arrangeurLabelY {
            XCTAssertLessThan(interpretLabelY, arrangeurLabelY)
        }
    }

    // MARK: - Pagination fills each page to capacity

    /// Real, self-caught bug (2026-09-29, layout follow-up pass, second
    /// round): a first attempt at the fix below forward-filled *every* page
    /// (including the eventual last one) against the full-page budget, then
    /// trimmed whatever landed on the last page down to the tighter
    /// last-page budget, spilling the trimmed rows onto a new final page.
    /// That trim wrongly shrank the *second-to-last* page — once a further
    /// page absorbs the overflow, that page is no longer last and could
    /// have kept its full, non-last-budget row count, but the trim had
    /// already cut it down. Deterministic, direct test against `paginate`
    /// itself (not routed through `computeLayout`'s real measurement) so the
    /// exact row counts are known up front: 25 uniform-height rows, a
    /// full-page budget that fits 9, a last-page budget that fits 5. The
    /// naive forward pass leaves a remainder of 7 on its final page — more
    /// than the last-page budget's 5 — which is exactly what triggers the
    /// old buggy trim-and-spill path.
    func test_paginate_whenTheForwardPassLeavesTooBigARemainderForTheLastPage_earlierPagesStayAtFullCapacity() {
        let rowHeights = Array(repeating: 10.0, count: 25)
        let pages = CueSheetLayoutComputer.paginate(
            rowHeights: rowHeights,
            columnHeaderHeight: 5,
            availableHeight: 95, // fits 9 rows/page: 5 + 9*10
            lastPageAvailableHeight: 55 // fits 5 rows: 5 + 5*10
        )

        XCTAssertEqual(pages, [
            Array(0 ..< 9),
            Array(9 ..< 18),
            Array(18 ..< 20),
            Array(20 ..< 25),
        ], "Pages before the last must stay at full capacity (9, 9) — only the true last page's own " +
            "trailing-remainder budget (5) should shrink anything, and only the page immediately " +
            "before it (2 leftover rows) should be small, not a page that used to be mistaken for last")
    }

    /// Real, self-caught bug (2026-09-29, layout follow-up pass): every page
    /// used to reserve `bottomReservedHeight` (the footer + summary blocks'
    /// space) at its bottom, even though only the genuine last page actually
    /// draws those — silently under-filling every non-last page by that same
    /// amount. Confirmed here via pure geometry (no reliance on any private
    /// pagination helper): a non-last page's actual table content must
    /// extend past where the old, over-conservative last-page-only budget
    /// would have cut it off, while still staying within the page itself.
    func test_nonLastPage_usesTheFullPageHeight_notTheTighterLastPageOnlyBudget() {
        let cues = (0 ..< 60).map { simpleFillerCue(index: $0) }
        let project = manyCuesProject(cues: cues)

        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        XCTAssertGreaterThan(pages.count, 1, "Test setup must actually force multiple pages")

        let firstPage = pages[0]
        let pageContentBottomLimit = CueSheetLayoutComputer.pageHeight - CueSheetLayoutComputer.margin
        let contentTop = columnHeaderTop(of: firstPage)
        let lastRuleYOnFirstPage = lastRuleY(of: firstPage)

        guard let contentTop, let lastRuleYOnFirstPage else {
            XCTFail("Could not locate the expected geometry on the first page")
            return
        }

        // No performers/arrangers in this fixture, so the last page's own
        // reserved bottom space is exactly the footer's.
        let footerHeight = CueSheetLayoutComputer.lineHeight(
            fontSize: CueSheetLayoutComputer.footerFontSize,
            weight: .bold
        ) + CueSheetLayoutComputer.cellVerticalPadding * 2
        let bottomReservedHeight = CueSheetLayoutComputer.tableToFooterGap + footerHeight
        let oldBuggyLimit = pageContentBottomLimit - bottomReservedHeight
        XCTAssertGreaterThan(
            lastRuleYOnFirstPage, oldBuggyLimit,
            "A non-last page must fill past the tighter, last-page-only budget"
        )
        XCTAssertGreaterThan(contentTop, 0, "Sanity check that geometry was actually found")
        XCTAssertLessThanOrEqual(
            lastRuleYOnFirstPage, pageContentBottomLimit,
            "A page's own content must never overflow past its own bottom margin"
        )
    }

    func test_pagination_neverDropsRows_evenWhenTheLastPageNeedsExtraSpaceForBothSummaryBlocks() {
        let performer = Person(firstName: "Nina", lastName: "Simone")
        let arranger = Person(firstName: "Fritz", lastName: "Brun")
        let cues = (0 ..< 60).map { index -> Cue in
            var cue = simpleFillerCue(index: index)
            if index == 0 {
                cue = Cue(
                    title: cue.title,
                    duration: cue.duration,
                    rightHolders: cue.rightHolders + [
                        simpleRightHolder(party: .person(performer.id), role: .performer),
                        simpleRightHolder(party: .person(arranger.id), role: .arranger),
                    ],
                    source: .manual
                )
            }
            return cue
        }
        let project = manyCuesProject(cues: cues, people: [performer, arranger])

        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        let texts = allText(in: pages)
        for index in 0 ..< 60 {
            XCTAssertTrue(texts.contains { $0 == "Cue \(index)" }, "Cue \(index) missing from output")
        }
        XCTAssertTrue(texts.contains("Interpret*in:"))
        XCTAssertTrue(texts.contains("Arrangeur*in:"))

        // Every page's own content — including the last, wider-budget one —
        // must still land within the page itself.
        let pageContentBottomLimit = CueSheetLayoutComputer.pageHeight - CueSheetLayoutComputer.margin
        for page in pages {
            let maxY = page.elements.map { $0.frame.y + $0.frame.height }.max() ?? 0
            XCTAssertLessThanOrEqual(maxY, pageContentBottomLimit + 0.01, "Page \(page.pageIndex) overflowed")
        }
    }

    // MARK: - Shared fixture helpers

    private func simpleRightHolder(party: Party, role: CueRightHolderRole) -> CueRightHolder {
        CueRightHolder(party: party, role: role, performanceBroadcastShare: 0, mechanicalRightsShare: 0)
    }

    private func simpleFillerCue(index: Int) -> Cue {
        Cue(
            title: "Cue \(index)",
            duration: MediaDuration(seconds: 30),
            rightHolders: [simpleRightHolder(party: .person(UUID()), role: .composer)],
            source: .manual
        )
    }

    private func singleCueProject(rightHolders: [CueRightHolder], people: [Person]) -> Project {
        let base = ProjectFixture.makeMinimal()
        let cue = Cue(
            title: "Cue One",
            duration: MediaDuration(seconds: 60),
            rightHolders: rightHolders,
            source: .manual
        )
        return multiCueProject(cues: [cue], people: people, base: base)
    }

    private func manyCuesProject(cues: [Cue], people: [Person] = []) -> Project {
        multiCueProject(cues: cues, people: people)
    }

    private func multiCueProject(cues: [Cue], people: [Person], base: Project? = nil) -> Project {
        let base = base ?? ProjectFixture.makeMinimal()
        return Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: base.setup,
            cues: cues,
            people: people
        )
    }

    private func frameY(of text: String, in pages: [CueSheetPageLayout]) -> Double? {
        pages.flatMap(\.elements).first { element in
            if case let .text(string, _) = element.content {
                string == text
            } else {
                false
            }
        }?.frame.y
    }

    private func columnHeaderTop(of page: CueSheetPageLayout) -> Double? {
        let songtitelY = page.elements.first { element in
            if case .text("Songtitel", _) = element.content {
                true
            } else {
                false
            }
        }?.frame.y
        return songtitelY.map { $0 - CueSheetLayoutComputer.cellVerticalPadding }
    }

    private func lastRuleY(of page: CueSheetPageLayout) -> Double? {
        page.elements
            .compactMap { element -> Double? in
                if case .rule = element.content {
                    element.frame.y
                } else {
                    nil
                }
            }
            .max()
    }
}
