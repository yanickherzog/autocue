import ACCore
@testable import ACExport
import ACTestSupport
import XCTest

/// Tests for the name-wrapping and XLSX-usability fixes
/// (`docs/DECISIONS.md`, 2026-09-29) — split into its own file per
/// `CONTRIBUTING.md` §8's `SwiftLint` `type_body_length` limit, the same
/// pattern `CueSheetLayoutComputerTests+Redesign.swift` already establishes.
extension XLSXCueSheetWriterTests {
    /// Real, reported bug: a multi-name cell rendered as four fragmented
    /// lines instead of two whole names — the XLSX side of the same
    /// name-wrapping bug the PDF had. `rowValues` now `"\n"`-joins multiple
    /// right-holders (shared with the PDF); this confirms that value
    /// actually reaches the written cell unmodified.
    func test_write_multipleRightHolders_cellValueIsNewlineJoined_notCommaJoined() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let composerA = Person(firstName: "Johann", lastName: "Johannsson")
        let composerB = Person(firstName: "Hildur", lastName: "Guðnadóttir")
        let cue = Cue(
            title: "Opening Theme",
            duration: MediaDuration(seconds: 60),
            rightHolders: [
                simpleRightHolder(party: .person(composerA.id), role: .composer),
                simpleRightHolder(party: .person(composerB.id), role: .composer),
            ],
            source: .manual
        )
        let base = ProjectFixture.makeMinimal()
        let project = Project(
            id: base.id, name: base.name, createdAt: base.createdAt, updatedAt: base.updatedAt,
            setup: base.setup, cues: [cue], people: [composerA, composerB]
        )
        try XLSXCueSheetWriter.write(project, to: url)
        let strings = try sharedStrings(from: url)

        XCTAssertTrue(strings.contains("Johann Johannsson\nHildur Guðnadóttir"))
        XCTAssertFalse(strings.contains { $0.contains(", ") && $0.contains("Johannsson") })
    }

    /// Real evidence: the previous `widthWeight × 14` scale was unrelated to
    /// actual content and produced columns narrower than a single realistic
    /// name/ISRC value. Confirms the real, `CueSheetLayoutComputer`-derived
    /// widths are now applied instead — checked structurally (a real
    /// `<col>` width, not an exact pixel match, since the conversion is a
    /// documented approximation) against the old, now-wrong value.
    func test_write_columnWidths_areRealNotTheOldArbitraryScale() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXCueSheetWriter.write(ProjectFixture.make(), to: url)
        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)

        // Column A (Komponist*in, widthWeight 1.0): the old scale gave
        // 1.0 × 14 = 14 (stored ~14.71 after libxlsxwriter's own padding).
        // The real, content-derived width must be meaningfully wider.
        let colAWidths = captureGroups(#"<col min="1" max="1" width="([\d.]+)""#, in: sheetXML, groupCount: 1)
        guard let widthString = colAWidths.first?.first, let width = Double(widthString) else {
            XCTFail("Could not find column A's width — sheet XML: \(sheetXML)")
            return
        }
        XCTAssertGreaterThan(width, 15, "Column A's width must be real/content-derived, not the old ~14.7 scale value")
    }

    /// Real evidence: a bold, longer `[h]:mm:ss` TOTAL MUSIK value sharing
    /// Dur.'s own narrow column overflowed to literal "#######" in
    /// Excel/Numbers. Fixed by merging the value across Dur. through the
    /// sheet's last column — confirmed structurally via the real
    /// `<mergeCell>` entry.
    func test_write_totalMusikValue_isMergedAcrossMultipleColumns_soItNeverOverflows() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cues = [simpleComposerCue(title: "Cue One", seconds: 60)]
        try XLSXCueSheetWriter.write(singleComposerProject(cues: cues), to: url)
        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)

        XCTAssertTrue(
            matchCount(#"<mergeCell ref="G\d+:J\d+"/>"#, in: sheetXML) == 1,
            "TOTAL MUSIK's value must be merged from Dur. (G) through the last column (J) — sheet XML: \(sheetXML)"
        )
    }

    /// Real evidence: the sheet showed Excel's default gridlines
    /// everywhere, reading as raw spreadsheet output rather than a designed
    /// document.
    func test_write_defaultGridlines_areHidden() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXCueSheetWriter.write(ProjectFixture.makeMinimal(), to: url)
        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)

        XCTAssertTrue(
            sheetXML.contains(#"showGridLines="0""#),
            "Default gridlines must be explicitly hidden — sheet XML: \(sheetXML)"
        )
    }

    /// Real evidence: the sheet had zero border styling anywhere and no
    /// header-row fill beyond bold text, reading as unstyled. Confirmed
    /// structurally via `styles.xml`: at least one real (non-empty) border
    /// definition and one solid fill.
    func test_write_realBordersAndHeaderRowFill_exist() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXCueSheetWriter.write(ProjectFixture.makeMinimal(), to: url)
        let stylesXML = try readZipEntry("xl/styles.xml", from: url)

        XCTAssertTrue(
            stylesXML.contains(#"<bottom style="thin">"#) || stylesXML.contains(#"<top style="thin">"#),
            "Must define at least one real thin border — styles XML: \(stylesXML)"
        )
        XCTAssertTrue(
            stylesXML.contains(#"patternType="solid""#),
            "Header row must have a real solid fill, not bold text alone — styles XML: \(stylesXML)"
        )
    }

    /// Real evidence: the title was a single unmerged, unstyled-width cell.
    /// Confirmed structurally via a real `<mergeCell>` spanning the full
    /// table width.
    func test_write_titleRow_isMergedAcrossTheFullTableWidth() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXCueSheetWriter.write(ProjectFixture.makeMinimal(), to: url)
        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)
        let lastColumnLetter = "J" // 10 columns, A...J
        XCTAssertTrue(
            matchCount(#"<mergeCell ref="A\d+:\#(lastColumnLetter)\d+"/>"#, in: sheetXML) >= 1,
            "The title must be merged across the full table width — sheet XML: \(sheetXML)"
        )
    }

    /// Real evidence: every row used the spreadsheet's default height
    /// regardless of how many lines its own wrapped content actually
    /// needed, relying entirely on each viewer app's own (inconsistent)
    /// auto-fit. Confirmed structurally: a cue row whose Komponist*in cell
    /// holds two names (two real lines) must have an explicit, real
    /// (`customHeight="1"`) row height, not the sheet's bare default.
    func test_write_multiLineRow_getsAnExplicitCustomRowHeight() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let composerA = Person(firstName: "Johann", lastName: "Johannsson")
        let composerB = Person(firstName: "Hildur", lastName: "Guðnadóttir")
        let cue = Cue(
            title: "Opening Theme",
            duration: MediaDuration(seconds: 60),
            rightHolders: [
                simpleRightHolder(party: .person(composerA.id), role: .composer),
                simpleRightHolder(party: .person(composerB.id), role: .composer),
            ],
            source: .manual
        )
        let base = ProjectFixture.makeMinimal()
        let project = Project(
            id: base.id, name: base.name, createdAt: base.createdAt, updatedAt: base.updatedAt,
            setup: base.setup, cues: [cue], people: [composerA, composerB]
        )
        try XLSXCueSheetWriter.write(project, to: url)
        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)

        XCTAssertTrue(
            matchCount(#"<row r="\d+" spans="1:10" ht="[\d.]+" customHeight="1">"#, in: sheetXML) >= 1,
            "At least one row (the two-name cue row) must have an explicit custom height — sheet XML: \(sheetXML)"
        )
    }
}
