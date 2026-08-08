import Foundation
import libxlsxwriter

/// Feasibility verification for the `libxlsxwriter` architectural dependency
/// (CLAUDE.md rule 4, SPEC.md §7) — **not** the real XLSX export feature.
///
/// `XLSXCueSheetWriter` (M28) will take a `Project`/`Setup`/`[Cue]` and produce
/// the actual SUISA-shaped tabular export; this type does neither. Its only job
/// is proving `libxlsxwriter` genuinely compiles, links, and produces a valid
/// workbook when integrated via SPM the way `ACExport` is meant to consume it —
/// see `ACExportTests/XLSXFeasibilitySpikeTests.swift` for the verification.
public enum XLSXFeasibilitySpike {
    public enum Failure: Error, Equatable {
        case libxlsxwriterError(code: UInt32)
    }

    /// Writes a workbook with exactly one string cell and one number cell to
    /// `url`, then closes it. Mirrors the two cell types a real cue-sheet row
    /// export needs (text fields, percentage/duration numbers) without
    /// attempting to model an actual cue sheet.
    public static func writeSingleCellWorkbook(to url: URL) throws {
        let workbook = workbook_new(url.path)
        let worksheet = workbook_add_worksheet(workbook, "Sheet1")

        worksheet_write_string(worksheet, 0, 0, "AutoCue XLSX feasibility check", nil)
        worksheet_write_number(worksheet, 0, 1, 100.0, nil)

        let result = workbook_close(workbook)
        guard result == LXW_NO_ERROR else {
            throw Failure.libxlsxwriterError(code: result.rawValue)
        }
    }
}
