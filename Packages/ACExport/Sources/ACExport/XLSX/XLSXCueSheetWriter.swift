import ACCore
import Foundation
import libxlsxwriter

/// The real XLSX cue sheet writer (`ROADMAP.md` D11/T11.4), superseding the
/// `XLSXFeasibilitySpike` scaffold (`docs/DECISIONS.md`, 2026-08-08) — that
/// type only ever proved the `libxlsxwriter` dependency itself works, never
/// the real feature.
///
/// **Deliberately not an independently-designed layout — a direct rendering
/// of the identical content `CueSheetLayoutComputer` already computes for
/// the PDF cue sheet, in a spreadsheet instead of a page** (project-owner
/// decision, 2026-09-29, `docs/DECISIONS.md`): the same title block, the
/// same header-block fields in the same left/right order, the exact same
/// ten table columns in the exact same order, the same "Interpret*in:"/
/// "Arrangeur*in:" summary blocks below the table, in the same singular
/// label wording finalized in the T11.2 layout follow-up thread. Every one
/// of those strings comes from calling `CueSheetLayoutComputer`'s existing
/// content-computation functions directly (`headerBlockLines`,
/// `titleHeadingText`, `rowValues`, `performerIPILines`/`arrangeurIPILines`,
/// `totalMusikText`) — not a second, hand-copied transcription of the same
/// values that could silently drift from the PDF's own. `CueSheetPageLayout`
/// itself (pixel-positioned frames, explicit page breaks) is deliberately
/// **not** reused here — a spreadsheet has no continuous coordinate system
/// and no pagination (it just keeps scrolling), so routing XLSX through a
/// page-layout model built for exactly those two things would be the
/// "independently-designed via a different mechanism" trap, not a genuine
/// reuse of it.
///
/// **Two deliberate, medium-driven adaptations — everything else is an exact
/// text match:**
/// - **Dur.** is a real numeric duration value (a fraction-of-a-day double,
///   Excel's native time representation), not the `"MM:SS"` string the PDF
///   renders, so it participates in real spreadsheet arithmetic.
/// - **TOTAL MUSIK** is a live `=SUM()` formula over the sheet's own Dur.
///   column, not `CueSheetLayoutComputer.totalMusikText(for:)`'s
///   precomputed string — deliberately a genuine recalculation of what's
///   actually in the sheet, not a copy of `Setup.totalMusicRuntime`. The two
///   normally agree (`SPEC.md` §4.14's auto-recompute rule keeps
///   `totalMusicRuntime` in sync with `Σ cues[].duration`), but they are
///   not the same value by construction — if a user edits a Dur. cell in
///   their own copy, this formula recalculates; a copy of the stored field
///   would silently go stale instead, defeating the entire point of this
///   adaptation. The row *label* text ("TOTAL MUSIK:") still comes from
///   `totalMusikText(for:)`'s own wording, split from its value.
///
/// **Real column widths and row heights, real borders, hidden default
/// gridlines — a deliberately designed export, not raw spreadsheet output
/// (`docs/DECISIONS.md`, 2026-09-29, XLSX-usability fix).** An earlier
/// version of this writer sized columns via an arbitrary `widthWeight × 14`
/// scale with no relationship to actual content, never hid Excel's own
/// default gridlines, never set an explicit row height anywhere, and defined
/// zero border styling — confirmed, via direct inspection of a real
/// generated file's underlying XML, to cause cramped/wrapped-mid-name
/// columns, a `"#######"`-overflowing TOTAL MUSIK cell, and a sheet that
/// read as unstyled raw spreadsheet output. Fixed by reusing
/// `CueSheetLayoutComputer.columnWidths()` (the PDF's own real, gross,
/// point-based per-column widths) converted through the standard Excel
/// column-width formula, reusing `measuredRowHeights`/`measuredHeight` (the
/// same Core Text measurement the PDF's own pagination is built on) for
/// explicit row heights, hiding all default gridlines
/// (`worksheet_gridlines`), and adding real thin borders under every table
/// row plus a shaded, bordered header row and a merged, prominent title.
/// This is still, deliberately, an approximation, not a pixel-identical
/// match — Excel/Numbers render with their own default font (Calibri), not
/// this writer's Helvetica Neue reference metrics, and a spreadsheet's grid
/// model has no equivalent to a page's continuous coordinate space. See
/// `docs/DECISIONS.md` for the full, itemized fix.
///
/// No in-app preview — nothing in `SPEC.md`/`CLAUDE.md`/`ROADMAP.md` calls
/// for one, unlike the PDF's `CueSheetPageLayout`/`CueSheetPreviewView`
/// pixel-identical-preview mechanism (`CLAUDE.md`, "Export Architecture").
public enum XLSXCueSheetWriter {
    public enum Failure: Error, Equatable {
        case libxlsxwriterError(code: UInt32)
    }

    /// Converts a real, gross point width (`CueSheetLayoutComputer
    /// .columnWidths()`) into Excel's own "number of characters of the
    /// default font" column-width unit — the standard, documented formula
    /// (pixels = points × 96/72 at Excel's assumed 96 DPI; character width =
    /// (pixels − 5) ÷ 7, where 7 is Calibri 11's own maximum digit width,
    /// Excel's default column font) — not the arbitrary `widthWeight × 14`
    /// scale this writer used before (`docs/DECISIONS.md`, 2026-09-29). Still
    /// an approximation across two different font systems (Helvetica Neue
    /// vs. Calibri), but a real, grounded one rather than an unrelated
    /// number picked to look plausible.
    private static func excelColumnWidth(forPoints points: Double) -> Double {
        let pixels = points * 96.0 / 72.0
        return max((pixels - 5) / 7, minimumColumnWidth)
    }

    private static let minimumColumnWidth: Double = 4

    public static func write(_ project: Project, to url: URL) throws {
        let workbook = workbook_new(url.path)
        let worksheet = workbook_add_worksheet(workbook, "Cue Sheet")

        // Hide Excel's own default screen/print gridlines everywhere — the
        // real borders this writer now draws around the actual table are
        // what should read as structure, not an ambient grid over the whole
        // sheet (`docs/DECISIONS.md`, 2026-09-29).
        worksheet_gridlines(worksheet, UInt8(LXW_HIDE_ALL_GRIDLINES.rawValue))

        let columnWidths = CueSheetLayoutComputer.columnWidths()
        let formats = Formats(workbook: workbook)
        var row: UInt32 = 0

        row = writeTitleBlock(worksheet: worksheet, setup: project.setup, formats: formats, startingAt: row)
        row += 1
        row = writeHeaderBlock(
            worksheet: worksheet, project: project, formats: formats, columnWidths: columnWidths, startingAt: row
        )
        row += 1
        row = writeTable(
            worksheet: worksheet, project: project, formats: formats, columnWidths: columnWidths, startingAt: row
        )
        row = writeSummaryBlocks(worksheet: worksheet, project: project, formats: formats, startingAt: row)

        applyColumnWidths(worksheet: worksheet, columnWidths: columnWidths)

        let result = workbook_close(workbook)
        guard result == LXW_NO_ERROR else {
            throw Failure.libxlsxwriterError(code: result.rawValue)
        }
    }

    // MARK: - Sections

    private static func writeTitleBlock(
        worksheet: UnsafeMutablePointer<lxw_worksheet>?,
        setup: Setup,
        formats: Formats,
        startingAt row: UInt32
    ) -> UInt32 {
        let lastColumn = UInt16(CueSheetLayoutComputer.columns.count - 1)
        worksheet_merge_range(worksheet, row, 0, row, lastColumn, CueSheetLayoutComputer.eyebrowText, formats.eyebrow)

        let titleText = CueSheetLayoutComputer.titleHeadingText(for: setup)
        worksheet_merge_range(worksheet, row + 1, 0, row + 1, lastColumn, "", formats.title)
        worksheet_write_string(worksheet, row + 1, 0, titleText, formats.title)
        worksheet_set_row(worksheet, row + 1, titleRowHeight, nil)

        return row + 2
    }

    /// Left column: Name der Sendung/Regie/Produktion/Komponist*in. Right
    /// column: Genre/Jahr/Verwertung/Sendedatum — the exact order
    /// `CueSheetLayoutComputer.headerBlockLines` already establishes for the
    /// PDF, reused verbatim rather than re-derived. Each row's height is set
    /// explicitly from real Core Text measurement of its own value against
    /// the real column B/E width, so a multi-line Komponist*in field
    /// actually displays every line rather than relying on the viewer app's
    /// own auto-fit (`docs/DECISIONS.md`, 2026-09-29).
    private static func writeHeaderBlock(
        worksheet: UnsafeMutablePointer<lxw_worksheet>?,
        project: Project,
        formats: Formats,
        columnWidths: [Double],
        startingAt row: UInt32
    ) -> UInt32 {
        let headerLines = CueSheetLayoutComputer.headerBlockLines(for: project)
        var currentRow = row
        for (leftLine, rightLine) in zip(headerLines.left, headerLines.right) {
            worksheet_write_string(worksheet, currentRow, 0, "\(leftLine.label):", formats.bold)
            let leftFormat = leftLine.value.contains("\n") ? formats.wrapped : nil
            worksheet_write_string(worksheet, currentRow, 1, leftLine.value, leftFormat)

            worksheet_write_string(worksheet, currentRow, 3, "\(rightLine.label):", formats.bold)
            let rightFormat = rightLine.value.contains("\n") ? formats.wrapped : nil
            worksheet_write_string(worksheet, currentRow, 4, rightLine.value, rightFormat)

            let leftHeight = CueSheetLayoutComputer.measuredHeight(
                text: leftLine.value, width: columnWidths[1], fontSize: headerFieldFontSize, weight: .regular
            )
            let rightHeight = CueSheetLayoutComputer.measuredHeight(
                text: rightLine.value, width: columnWidths[4], fontSize: headerFieldFontSize, weight: .regular
            )
            let rowHeight = max(leftHeight, rightHeight) + headerRowVerticalPadding
            worksheet_set_row(worksheet, currentRow, rowHeight, nil)

            currentRow += 1
        }
        return currentRow
    }

    /// The table header row plus one row per `Cue`, in
    /// `CueSheetLayoutComputer.columns`' exact order — every cell a plain
    /// text match to `rowValues(for:setup:people:labels:)` except Dur.
    /// (real numeric duration, see this type's own doc comment), plus a
    /// live `=SUM()` TOTAL MUSIK row once at least one cue exists. Every row
    /// gets a real, measured height and a bottom border, matching the PDF's
    /// own row-separator rule lines (`docs/DECISIONS.md`, 2026-09-29).
    private static func writeTable(
        worksheet: UnsafeMutablePointer<lxw_worksheet>?,
        project: Project,
        formats: Formats,
        columnWidths: [Double],
        startingAt row: UInt32
    ) -> UInt32 {
        let columns = CueSheetLayoutComputer.columns
        guard let durColumnIndex = columns.firstIndex(where: { $0.title == "Dur." }) else {
            preconditionFailure("CueSheetLayoutComputer.columns must contain a \"Dur.\" column")
        }

        for (index, column) in columns.enumerated() {
            worksheet_write_string(worksheet, row, UInt16(index), column.title, formats.tableHeader)
        }
        worksheet_set_row(worksheet, row, tableHeaderRowHeight, nil)

        let firstCueRow = row + 1
        let currentRow = writeCueRows(
            worksheet: worksheet, project: project, formats: formats, columnWidths: columnWidths,
            startingAt: firstCueRow
        )

        guard !project.cues.isEmpty else { return currentRow }

        let lastCueRow = currentRow - 1
        let totalRow = currentRow
        worksheet_write_string(worksheet, totalRow, 0, "TOTAL MUSIK:", formats.totalLabel)

        // Merged across Dur. through the last column — the PDF's own
        // `footerElement` extends this text *leftward* from Dur.'s own
        // right edge into blank space for the same reason (a bold, longer
        // `[h]:mm:ss` value doesn't fit Dur.'s own narrow, `MM:SS`-sized
        // column); a merged range is the spreadsheet equivalent
        // (`docs/DECISIONS.md`, 2026-09-29 — real evidence: the unmerged
        // version showed literal "#######" in Excel/Numbers, the standard
        // too-narrow-column overflow indicator).
        let lastColumn = UInt16(columns.count - 1)
        worksheet_merge_range(
            worksheet,
            totalRow,
            UInt16(durColumnIndex),
            totalRow,
            lastColumn,
            "",
            formats.totalDuration
        )
        let formula = "=SUM(\(cellReference(row: firstCueRow, column: UInt16(durColumnIndex)))"
            + ":\(cellReference(row: lastCueRow, column: UInt16(durColumnIndex))))"
        worksheet_write_formula(worksheet, totalRow, UInt16(durColumnIndex), formula, formats.totalDuration)
        return totalRow + 1
    }

    /// Every cue's own row — split out of `writeTable` (`CONTRIBUTING.md`
    /// §8's `SwiftLint` `function_body_length` limit). Each row's height is
    /// real, measured (`CueSheetLayoutComputer.measuredRowHeights` — the
    /// same function the PDF's own pagination uses), not the sheet's bare
    /// default (`docs/DECISIONS.md`, 2026-09-29).
    private static func writeCueRows(
        worksheet: UnsafeMutablePointer<lxw_worksheet>?,
        project: Project,
        formats: Formats,
        columnWidths: [Double],
        startingAt row: UInt32
    ) -> UInt32 {
        // Recomputed here rather than passed in from `writeTable` — keeps
        // this function's own parameter count under `CONTRIBUTING.md` §8's
        // `SwiftLint` limit; a 10-element linear scan is negligible.
        guard let durColumnIndex = CueSheetLayoutComputer.columns.firstIndex(where: { $0.title == "Dur." }) else {
            preconditionFailure("CueSheetLayoutComputer.columns must contain a \"Dur.\" column")
        }
        let rows = project.cues.map {
            CueSheetLayoutComputer.rowValues(
                for: $0, setup: project.setup, people: project.people, labels: project.labels
            )
        }
        let rowHeights = CueSheetLayoutComputer.measuredRowHeights(rows: rows, columnWidths: columnWidths)

        var currentRow = row
        for (cueIndex, cue) in project.cues.enumerated() {
            let values = rows[cueIndex]
            for (index, value) in values.enumerated() {
                if index == durColumnIndex {
                    worksheet_write_number(
                        worksheet, currentRow, UInt16(index), cue.duration.seconds / 86400, formats.duration
                    )
                } else {
                    worksheet_write_string(worksheet, currentRow, UInt16(index), value, formats.tableCell)
                }
            }
            worksheet_set_row(worksheet, currentRow, rowHeights[cueIndex], nil)
            currentRow += 1
        }
        return currentRow
    }

    /// "Interpret*in:"/"Arrangeur*in:" — same aggregation, same singular
    /// wording, same omitted-when-empty rule as the PDF's summary blocks
    /// (`CueSheetLayoutComputer+InterpretBlock.swift`).
    private static func writeSummaryBlocks(
        worksheet: UnsafeMutablePointer<lxw_worksheet>?,
        project: Project,
        formats: Formats,
        startingAt row: UInt32
    ) -> UInt32 {
        var currentRow = row
        let interpretLines = CueSheetLayoutComputer.performerIPILines(
            cues: project.cues, people: project.people, labels: project.labels
        )
        currentRow = writeSummaryBlock(
            worksheet: worksheet, label: "Interpret*in:", lines: interpretLines, formats: formats,
            startingAt: currentRow
        )

        let arrangeurLines = CueSheetLayoutComputer.arrangeurIPILines(
            cues: project.cues, people: project.people, labels: project.labels
        )
        currentRow = writeSummaryBlock(
            worksheet: worksheet, label: "Arrangeur*in:", lines: arrangeurLines, formats: formats,
            startingAt: currentRow
        )
        return currentRow
    }

    private static func writeSummaryBlock(
        worksheet: UnsafeMutablePointer<lxw_worksheet>?,
        label: String,
        lines: [String],
        formats: Formats,
        startingAt row: UInt32
    ) -> UInt32 {
        guard !lines.isEmpty else { return row }
        var currentRow = row + 1
        worksheet_write_string(worksheet, currentRow, 0, label, formats.bold)
        currentRow += 1
        for line in lines {
            worksheet_write_string(worksheet, currentRow, 0, line, nil)
            currentRow += 1
        }
        return currentRow
    }

    /// Real, content-grounded widths (`excelColumnWidth(forPoints:)`), not
    /// the arbitrary `widthWeight × 14` scale this writer used before
    /// (`docs/DECISIONS.md`, 2026-09-29).
    private static func applyColumnWidths(worksheet: UnsafeMutablePointer<lxw_worksheet>?, columnWidths: [Double]) {
        for (index, points) in columnWidths.enumerated() {
            let width = excelColumnWidth(forPoints: points)
            worksheet_set_column(worksheet, UInt16(index), UInt16(index), width, nil)
        }
    }

    /// `row`/`column` are 0-based internally, matching every other
    /// coordinate in this file; spreadsheet references are 1-based, hence
    /// `row + 1` here specifically (only at the point of building the
    /// formula string, not anywhere else in this type).
    private static func cellReference(row: UInt32, column: UInt16) -> String {
        var remaining = Int(column)
        var letters = ""
        repeat {
            let letterIndex = remaining % 26
            guard let scalar = UnicodeScalar(65 + letterIndex) else { break }
            letters = String(Character(scalar)) + letters
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return "\(letters)\(row + 1)"
    }
}
