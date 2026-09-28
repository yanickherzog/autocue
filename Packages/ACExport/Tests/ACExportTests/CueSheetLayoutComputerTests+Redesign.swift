import ACCore
@testable import ACExport
import ACTestSupport
import XCTest

/// Tests for the layout-redesign pass (`docs/DECISIONS.md`, 2026-09-28),
/// built from the project owner's real InDesign mockup — split into its own
/// file per `CONTRIBUTING.md` §8's `SwiftLint` `type_body_length` limit, the
/// same pattern already established for e.g. `UpdateCueUseCaseTests+Delete.swift`.
extension CueSheetLayoutComputerTests {
    func test_titleBlock_showsEyebrowAndUppercasedTitleAboveTheHeaderBlock() {
        let project = ProjectFixture.make()
        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        let texts = allText(in: pages)

        XCTAssertTrue(texts.contains(CueSheetLayoutComputer.eyebrowText))
        let expectedTitle = [project.setup.title, project.setup.subtitle]
            .compactMap { $0 }
            .joined(separator: " — ")
            .uppercased()
        XCTAssertTrue(texts.contains(expectedTitle))

        let eyebrowIndex = try? XCTUnwrap(texts.firstIndex(of: CueSheetLayoutComputer.eyebrowText))
        let titleIndex = try? XCTUnwrap(texts.firstIndex(of: expectedTitle))
        let nameFieldIndex = texts.firstIndex { $0.contains("Name der Sendung:") }
        XCTAssertNotNil(eyebrowIndex)
        XCTAssertNotNil(titleIndex)
        XCTAssertNotNil(nameFieldIndex)
        if let eyebrowIndex, let titleIndex, let nameFieldIndex {
            XCTAssertLessThan(eyebrowIndex, titleIndex, "The eyebrow line must be drawn above the title")
            XCTAssertLessThan(titleIndex, nameFieldIndex, "The title must be drawn above the header block")
        }
    }

    /// Left column: Name der Sendung / Regie / Produktion / Komponist*in.
    /// Right column: Genre / Jahr / Verwertung / Sendedatum. Asserted via
    /// element order, since `headerBlockElements` appends row-by-row,
    /// left-field-then-right-field within each row.
    func test_headerBlock_leftAndRightColumnOrder_matchesTheRedesign() {
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        let texts = allText(in: pages)
        let expectedLabelOrder = [
            "Name der Sendung:", "Genre:", "Regie:", "Jahr:",
            "Produktion:", "Verwertung:", "Komponist*in:", "Sendedatum:",
        ]
        let actualLabelOrder = texts.filter { text in expectedLabelOrder.contains(text) }
        XCTAssertEqual(actualLabelOrder, expectedLabelOrder)
    }

    func test_tableColumnHeader_isArrangeurIn_notArrangement() {
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        let texts = allText(in: pages)
        XCTAssertTrue(texts.contains("Arrangeur*in"))
        XCTAssertFalse(texts.contains("Arrangement"))
    }

    func test_interpretBlock_listsEveryPerformerAcrossTheWholeProject_dedupedByIdentity() {
        let composerID = UUID()
        let performerID = UUID()
        let performer = Person(id: performerID, firstName: "Mario", lastName: "Hänni", ipiNumber: "98765432101")
        let base = ProjectFixture.makeMinimal()
        let composerHolder = CueRightHolder(
            party: .person(composerID),
            role: .composer,
            performanceBroadcastShare: 100,
            mechanicalRightsShare: 100
        )
        let performerHolder = CueRightHolder(
            party: .person(performerID),
            role: .performer,
            performanceBroadcastShare: 0,
            mechanicalRightsShare: 0
        )
        let cueOne = Cue(
            title: "Cue One",
            duration: MediaDuration(seconds: 60),
            rightHolders: [composerHolder, performerHolder],
            source: .manual
        )
        let cueTwo = Cue(
            title: "Cue Two",
            duration: MediaDuration(seconds: 60),
            rightHolders: [composerHolder, performerHolder],
            source: .manual
        )
        let project = Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: base.setup,
            cues: [cueOne, cueTwo],
            people: [performer]
        )

        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        let texts = allText(in: pages)
        XCTAssertTrue(texts.contains("Interpret*innen:"))
        XCTAssertTrue(texts.contains { $0.contains("Mario Hänni, IPI-Nr. 765 43 21 01") })

        // The table's own Interpret*innen *column* legitimately repeats the
        // performer's name once per cue — only the aggregated summary block
        // (asserted directly here, not via the rendered page text above,
        // which also contains those per-row occurrences) must dedup.
        let aggregated = CueSheetLayoutComputer.performerIPILines(
            cues: project.cues,
            people: project.people,
            labels: project.labels
        )
        XCTAssertEqual(aggregated, ["Mario Hänni, IPI-Nr. 765 43 21 01"])
    }

    func test_interpretBlock_omittedEntirely_whenTheProjectHasNoPerformers() {
        // `ProjectFixture.makeMinimal()` has no cues at all, so no performers.
        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.makeMinimal())
        let texts = allText(in: pages)
        XCTAssertFalse(texts.contains("Interpret*innen:"))
    }

    /// Right edge anchored to the **Dur. column's own right edge**
    /// (index 6 of `columns`), not the wider Dur.+Label span — corrected
    /// 2026-09-28 per the project owner's second visual pass
    /// (`docs/DECISIONS.md`): "clearly positioned under Dur. specifically."
    /// Also confirms the frame's width always equals the text's real
    /// natural width (never clamped/shrunk to fit a narrower region, which
    /// would have made `CTFrameDraw` silently wrap the line).
    func test_footerElement_isRightAligned_toTheDurColumnsRightEdge_atItsNaturalWidth() {
        let columnWidths: [Double] = [100, 90, 100, 110, 65, 65, 45, 90, 60, 75]
        let project = ProjectFixture.make()
        let element = CueSheetLayoutComputer.footerElement(
            project: project,
            columnWidths: columnWidths,
            originY: 200,
            height: 20
        )
        let durColumnEnd = CueSheetLayoutComputer.margin + columnWidths[0 ..< 7].reduce(0, +)
        guard case let .text(text, font) = element.content else {
            XCTFail("Expected a .text element")
            return
        }
        let expectedText = "TOTAL MUSIK: \(project.setup.totalMusicRuntime.formatted)"
        let naturalWidth = CueSheetLayoutComputer.measuredWidth(
            text: expectedText,
            fontSize: CueSheetLayoutComputer.footerFontSize,
            weight: .bold
        )
        XCTAssertEqual(text, expectedText)
        XCTAssertEqual(font.weight, .bold)
        XCTAssertEqual(element.frame.x + element.frame.width, durColumnEnd, accuracy: 0.01)
        XCTAssertEqual(element.frame.width, naturalWidth, accuracy: 0.01)
        XCTAssertLessThan(
            element.frame.width,
            columnWidths.reduce(0, +),
            "Must not span the full table width the way it used to before the redesign"
        )
    }

    func test_formattedIPI_elevenDigitStoredNumber_dropsThePaddingAndGroupsTheRemainingNineDigits() {
        XCTAssertEqual(CueSheetLayoutComputer.formattedIPI("00123456789"), "123 45 67 89")
        XCTAssertEqual(CueSheetLayoutComputer.formattedIPI("11111111111"), "111 11 11 11")
    }

    func test_formattedIPI_nineDigitNumber_groupsDirectly() {
        XCTAssertEqual(CueSheetLayoutComputer.formattedIPI("123456789"), "123 45 67 89")
    }

    func test_formattedIPI_shorterNumber_groupsWhateverIsThere() {
        XCTAssertEqual(CueSheetLayoutComputer.formattedIPI("00123"), "001 23")
    }
}
