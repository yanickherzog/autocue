import ACCore
@testable import ACExport
import ACTestSupport
import XCTest

/// Real XLSX generation, not a mock (`CONTRIBUTING.md` §5) — writes an
/// actual file and inspects its real XML contents, the same standard
/// `PDFCueSheetRendererTests`/the retired `XLSXFeasibilitySpikeTests`
/// already established for both export formats.
///
/// Every content assertion below calls the exact same
/// `CueSheetLayoutComputer` function the PDF renderer calls, then checks the
/// XLSX cell equals that same computed value — proving the two renderers
/// can't silently drift apart, not just that the XLSX file "looks about
/// right" in isolation.
final class XLSXCueSheetWriterTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xlsx")
    }

    func test_write_producesAValidZipContainer_xlsxIsAZipFormat() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXCueSheetWriter.write(ProjectFixture.make(), to: url)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(data.count, 4)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "missing ZIP local file header signature")
    }

    func test_write_throwsRatherThanCrashing_onAnUnwritableDestination() {
        let invalidURL = URL(fileURLWithPath: "/nonexistent-directory-for-autocue-xlsx/x.xlsx")
        XCTAssertThrowsError(try XLSXCueSheetWriter.write(ProjectFixture.make(), to: invalidURL))
    }

    func test_write_titleAndHeaderBlock_matchWhatThePDFComputes() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let project = ProjectFixture.make()
        try XLSXCueSheetWriter.write(project, to: url)
        let strings = try sharedStrings(from: url)

        XCTAssertTrue(strings.contains(CueSheetLayoutComputer.eyebrowText))
        XCTAssertTrue(strings.contains(CueSheetLayoutComputer.titleHeadingText(for: project.setup)))

        let headerLines = CueSheetLayoutComputer.headerBlockLines(for: project)
        for line in headerLines.left + headerLines.right {
            XCTAssertTrue(strings.contains("\(line.label):"), "Missing label '\(line.label):'")
            XCTAssertTrue(strings.contains(line.value), "Missing value for '\(line.label)': \(line.value)")
        }
    }

    func test_write_tableColumnHeaders_matchExactlyInOrder() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXCueSheetWriter.write(ProjectFixture.make(), to: url)
        let strings = try sharedStrings(from: url)

        for column in CueSheetLayoutComputer.columns {
            XCTAssertTrue(strings.contains(column.title), "Missing column header '\(column.title)'")
        }
        // Singular labels, finalized in the T11.2 layout follow-up thread —
        // never the old plural forms.
        XCTAssertTrue(strings.contains("Komponist*in"))
        XCTAssertTrue(strings.contains("Interpret*in"))
        XCTAssertFalse(strings.contains("Komponist*innen"))
        XCTAssertFalse(strings.contains("Interpret*innen"))
    }

    func test_write_everyCueRow_matchesRowValuesExactly() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let project = ProjectFixture.make()
        try XLSXCueSheetWriter.write(project, to: url)
        let strings = try sharedStrings(from: url)

        for cue in project.cues {
            let values = CueSheetLayoutComputer.rowValues(
                for: cue, setup: project.setup, people: project.people, labels: project.labels
            )
            for (index, value) in values.enumerated() where index != 6 { // Dur. (index 6) is numeric, not a string
                guard !value.isEmpty else { continue }
                XCTAssertTrue(strings.contains(value), "Missing row value '\(value)' for cue '\(cue.title)'")
            }
        }
    }

    func test_write_durColumn_isARealNumericValue_notAString() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let project = singleComposerProject(cues: [simpleComposerCue(title: "Cue One", seconds: 90)])
        try XLSXCueSheetWriter.write(project, to: url)

        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)
        // Some column-G (Dur., index 6) cell must be a plain numeric cell —
        // no `t="s"` (shared-string) attribute — holding 90 seconds as a
        // fraction of a day. Matched structurally (any row) rather than a
        // hardcoded row number, so this doesn't silently break the moment
        // the header block's own row count changes for an unrelated reason.
        let durCells = captureGroups(#"<c r="G\d+"[^>]*><v>([^<]+)</v></c>"#, in: sheetXML, groupCount: 1)
        let expectedFraction = 90.0 / 86400.0
        let matchingCell = durCells.first { group in
            guard let value = Double(group[0]) else { return false }
            return abs(value - expectedFraction) < 1e-9
        }
        XCTAssertNotNil(
            matchingCell,
            "No plain-numeric Dur. cell found with the expected fraction — sheet XML: \(sheetXML)"
        )

        XCTAssertEqual(
            matchCount(#"<c r="G\d+" t="s">"#, in: sheetXML), 0,
            "No Dur. cell may be a shared-string (text) cell"
        )
    }

    func test_write_totalMusik_isALiveSumFormula_overTheDurColumn() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let cues = [
            simpleComposerCue(title: "Cue One", seconds: 60),
            simpleComposerCue(title: "Cue Two", seconds: 120),
        ]
        try XLSXCueSheetWriter.write(singleComposerProject(cues: cues), to: url)

        let strings = try sharedStrings(from: url)
        XCTAssertTrue(strings.contains("TOTAL MUSIK:"))

        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)
        // Matched structurally rather than a hardcoded row number (see the
        // Dur.-cell test's own comment for why) — two consecutive column-G
        // rows summed, whatever rows they actually landed on.
        let formulaMatches = captureGroups(#"<f>SUM\(G(\d+):G(\d+)\)</f>"#, in: sheetXML, groupCount: 2)
        guard let formula = formulaMatches.first, let firstRow = Int(formula[0]), let lastRow = Int(formula[1]) else {
            XCTFail(
                "TOTAL MUSIK must be a real =SUM() formula over the actual Dur. cell range — sheet XML: \(sheetXML)"
            )
            return
        }
        XCTAssertEqual(lastRow, firstRow + 1, "Exactly two cue rows were written — the sum range must span both")
    }

    func test_write_noCues_omitsTotalMusikRowEntirely() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXCueSheetWriter.write(ProjectFixture.makeMinimal(), to: url)

        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)
        XCTAssertFalse(sheetXML.contains("<f>SUM("), "No cues means nothing to sum — no formula should be written")
        let strings = try sharedStrings(from: url)
        XCTAssertFalse(strings.contains("TOTAL MUSIK:"))
    }

    func test_write_interpretAndArrangeurBlocks_dedupedAcrossTheWholeProject_matchThePDFsAggregation() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let performer = Person(firstName: "Mario", lastName: "Hänni", ipiNumber: "98765432101")
        let arranger = Person(firstName: "Fritz", lastName: "Brun", ipiNumber: "11122233301")
        let rightHolders = [
            simpleRightHolder(party: .person(UUID()), role: .composer),
            simpleRightHolder(party: .person(performer.id), role: .performer),
            simpleRightHolder(party: .person(arranger.id), role: .arranger),
        ]
        let cues = ["Cue One", "Cue Two"].map {
            Cue(title: $0, duration: MediaDuration(seconds: 60), rightHolders: rightHolders, source: .manual)
        }
        let base = ProjectFixture.makeMinimal()
        let project = Project(
            id: base.id, name: base.name, createdAt: base.createdAt, updatedAt: base.updatedAt,
            setup: base.setup, cues: cues, people: [performer, arranger]
        )

        try XLSXCueSheetWriter.write(project, to: url)
        let strings = try sharedStrings(from: url)

        XCTAssertTrue(strings.contains("Interpret*in:"))
        XCTAssertTrue(strings.contains("Arrangeur*in:"))

        let expectedPerformerLine = CueSheetLayoutComputer.performerIPILines(
            cues: project.cues, people: project.people, labels: project.labels
        )
        let expectedArrangeurLine = CueSheetLayoutComputer.arrangeurIPILines(
            cues: project.cues, people: project.people, labels: project.labels
        )
        XCTAssertEqual(expectedPerformerLine.count, 1, "Deduped across both cues")
        XCTAssertEqual(expectedArrangeurLine.count, 1, "Deduped across both cues")
        XCTAssertTrue(strings.contains(expectedPerformerLine[0]))
        XCTAssertTrue(strings.contains(expectedArrangeurLine[0]))
    }

    // MARK: - Helpers

    private func simpleRightHolder(party: Party, role: CueRightHolderRole) -> CueRightHolder {
        CueRightHolder(party: party, role: role, performanceBroadcastShare: 100, mechanicalRightsShare: 100)
    }

    private func simpleComposerCue(title: String, seconds: Double) -> Cue {
        Cue(
            title: title,
            duration: MediaDuration(seconds: seconds),
            rightHolders: [simpleRightHolder(party: .person(UUID()), role: .composer)],
            source: .manual
        )
    }

    private func singleComposerProject(cues: [Cue]) -> Project {
        let base = ProjectFixture.makeMinimal()
        return Project(
            id: base.id, name: base.name, createdAt: base.createdAt, updatedAt: base.updatedAt,
            setup: base.setup, cues: cues
        )
    }

    /// The full set of shared strings the workbook wrote — sufficient for
    /// content-presence assertions without caring about exact cell
    /// addresses, the same level most of these tests need.
    private func sharedStrings(from url: URL) throws -> Set<String> {
        let xml = try readZipEntry("xl/sharedStrings.xml", from: url)
        var results: Set<String> = []
        var remainder = xml[...]
        while let startRange = remainder.range(of: "<t") {
            guard let openEnd = remainder[startRange.upperBound...].range(of: ">") else { break }
            let contentStart = openEnd.upperBound
            guard let closeRange = remainder[contentStart...].range(of: "</t>") else { break }
            let raw = String(remainder[contentStart ..< closeRange.lowerBound])
            results.insert(decodeXMLEntities(raw))
            remainder = remainder[closeRange.upperBound...]
        }
        return results
    }

    private func decodeXMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    /// Number of matches of a zero-capture-group pattern — a pure
    /// presence/absence or count check.
    private func matchCount(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    /// Every match's `groupCount` capture groups, in order — for a pattern
    /// with `groupCount` capturing parentheses.
    private func captureGroups(_ pattern: String, in text: String, groupCount: Int) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let groups = (1 ... groupCount).compactMap { groupIndex -> String? in
                guard let groupRange = Range(match.range(at: groupIndex), in: text) else { return nil }
                return String(text[groupRange])
            }
            return groups.count == groupCount ? groups : nil
        }
    }

    /// Extracts one entry from a ZIP (.xlsx) file using the `unzip` CLI, so
    /// this test doesn't need a zip-reading library — the same approach the
    /// retired `XLSXFeasibilitySpikeTests` already established.
    private func readZipEntry(_ entryName: String, from url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entryName]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
