import XCTest
@testable import ACExport

/// Verifies the libxlsxwriter architectural dependency decision (SPEC.md §7),
/// not any real export feature — see `XLSXFeasibilitySpike`.
final class XLSXFeasibilitySpikeTests: XCTestCase {

    func test_writesAFileThatExistsAndIsNonEmpty() throws {
        let url = makeTemporaryXLSXURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXFeasibilitySpike.writeSingleCellWorkbook(to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func test_writtenFileIsAValidZipContainer_xlsxIsAZipFormat() throws {
        let url = makeTemporaryXLSXURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXFeasibilitySpike.writeSingleCellWorkbook(to: url)

        // .xlsx is a ZIP container — a local file header signature ("PK\x03\x04")
        // at the start of the file is the minimal, dependency-free way to confirm
        // libxlsxwriter actually produced a real archive, not a truncated/corrupt
        // stub, without pulling in a zip-reading library just for this check.
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(data.count, 4)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "missing ZIP local file header signature")
    }

    func test_sheetXMLContainsTheExpectedCellValues() throws {
        let url = makeTemporaryXLSXURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try XLSXFeasibilitySpike.writeSingleCellWorkbook(to: url)

        let sheetXML = try readZipEntry("xl/worksheets/sheet1.xml", from: url)
        // A1 is a shared-string reference (t="s"); confirms the string cell was written.
        XCTAssertTrue(sheetXML.contains(#"<c r="A1" t="s">"#))
        // B1 is a numeric cell with our value.
        XCTAssertTrue(sheetXML.contains(#"<c r="B1"><v>100</v></c>"#))

        let sharedStringsXML = try readZipEntry("xl/sharedStrings.xml", from: url)
        XCTAssertTrue(sharedStringsXML.contains("AutoCue XLSX feasibility check"))
    }

    func test_throwsRatherThanCrashing_onAnUnwritableDestination() {
        // A path inside a nonexistent directory — libxlsxwriter should report a
        // failure through its normal error code, not force us to crash/exit.
        let invalidURL = URL(fileURLWithPath: "/nonexistent-directory-for-autocue-spike/x.xlsx")
        XCTAssertThrowsError(try XLSXFeasibilitySpike.writeSingleCellWorkbook(to: invalidURL))
    }

    // MARK: - Helpers

    private func makeTemporaryXLSXURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("autocue-xlsx-spike-\(UUID().uuidString)")
            .appendingPathExtension("xlsx")
    }

    /// Extracts one entry from a ZIP (.xlsx) file using the `unzip` CLI, so this
    /// test doesn't need to bring in a zip-reading library just to verify output
    /// — acceptable for a one-off feasibility spike test, not a pattern to reuse
    /// in real product code.
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
