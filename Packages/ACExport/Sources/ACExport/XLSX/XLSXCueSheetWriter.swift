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
/// No in-app preview — nothing in `SPEC.md`/`CLAUDE.md`/`ROADMAP.md` calls
/// for one, unlike the PDF's `CueSheetPageLayout`/`CueSheetPreviewView`
/// pixel-identical-preview mechanism (`CLAUDE.md`, "Export Architecture").
public enum XLSXCueSheetWriter {
    public enum Failure: Error, Equatable {
        case libxlsxwriterError(code: UInt32)
    }

    /// Column widths are a reasonable proportional mapping from the PDF's
    /// own `widthWeight`s, not a unit-for-unit port — Excel's "characters of
    /// the default font" column-width unit has no direct equivalent to the
    /// PDF's point-based widths across two genuinely different mediums. Cosmetic
    /// only; a user can freely resize columns in their own copy.
    private static let columnWidthScale: Double = 14
    private static let minimumColumnWidth: Double = 6

    public static func write(_ project: Project, to url: URL) throws {
        let workbook = workbook_new(url.path)
        let worksheet = workbook_add_worksheet(workbook, "Cue Sheet")

        let formats = Formats(workbook: workbook)
        var row: UInt32 = 0

        row = writeTitleBlock(worksheet: worksheet, setup: project.setup, formats: formats, startingAt: row)
        row += 1
        row = writeHeaderBlock(worksheet: worksheet, project: project, formats: formats, startingAt: row)
        row += 1
        row = writeTable(worksheet: worksheet, project: project, formats: formats, startingAt: row)
        row = writeSummaryBlocks(worksheet: worksheet, project: project, formats: formats, startingAt: row)

        applyColumnWidths(worksheet: worksheet)

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
        worksheet_write_string(worksheet, row, 0, CueSheetLayoutComputer.eyebrowText, nil)
        let titleText = CueSheetLayoutComputer.titleHeadingText(for: setup)
        worksheet_write_string(worksheet, row + 1, 0, titleText, formats.title)
        return row + 2
    }

    /// Left column: Name der Sendung/Regie/Produktion/Komponist*in. Right
    /// column: Genre/Jahr/Verwertung/Sendedatum — the exact order
    /// `CueSheetLayoutComputer.headerBlockLines` already establishes for the
    /// PDF, reused verbatim rather than re-derived.
    private static func writeHeaderBlock(
        worksheet: UnsafeMutablePointer<lxw_worksheet>?,
        project: Project,
        formats: Formats,
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
            currentRow += 1
        }
        return currentRow
    }

    /// The table header row plus one row per `Cue`, in
    /// `CueSheetLayoutComputer.columns`' exact order — every cell a plain
    /// text match to `rowValues(for:setup:people:labels:)` except Dur.
    /// (real numeric duration, see this type's own doc comment), plus a
    /// live `=SUM()` TOTAL MUSIK row once at least one cue exists.
    private static func writeTable(
        worksheet: UnsafeMutablePointer<lxw_worksheet>?,
        project: Project,
        formats: Formats,
        startingAt row: UInt32
    ) -> UInt32 {
        let columns = CueSheetLayoutComputer.columns
        guard let durColumnIndex = columns.firstIndex(where: { $0.title == "Dur." }) else {
            preconditionFailure("CueSheetLayoutComputer.columns must contain a \"Dur.\" column")
        }

        for (index, column) in columns.enumerated() {
            worksheet_write_string(worksheet, row, UInt16(index), column.title, formats.bold)
        }

        let firstCueRow = row + 1
        var currentRow = firstCueRow
        for cue in project.cues {
            let values = CueSheetLayoutComputer.rowValues(
                for: cue, setup: project.setup, people: project.people, labels: project.labels
            )
            for (index, value) in values.enumerated() {
                if index == durColumnIndex {
                    worksheet_write_number(
                        worksheet,
                        currentRow,
                        UInt16(index),
                        cue.duration.seconds / 86400,
                        formats.duration
                    )
                } else {
                    worksheet_write_string(worksheet, currentRow, UInt16(index), value, nil)
                }
            }
            currentRow += 1
        }

        guard !project.cues.isEmpty else { return currentRow }

        let lastCueRow = currentRow - 1
        let totalRow = currentRow
        worksheet_write_string(worksheet, totalRow, 0, "TOTAL MUSIK:", formats.bold)
        let formula = "=SUM(\(cellReference(row: firstCueRow, column: UInt16(durColumnIndex)))"
            + ":\(cellReference(row: lastCueRow, column: UInt16(durColumnIndex))))"
        worksheet_write_formula(worksheet, totalRow, UInt16(durColumnIndex), formula, formats.totalDuration)
        return totalRow + 1
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

    private static func applyColumnWidths(worksheet: UnsafeMutablePointer<lxw_worksheet>?) {
        for (index, column) in CueSheetLayoutComputer.columns.enumerated() {
            let width = max(column.widthWeight * columnWidthScale, minimumColumnWidth)
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

    /// Every `lxw_format` this writer needs, created once per `write(_:to:)`
    /// call and reused across every cell — `libxlsxwriter` formats are
    /// workbook-owned and freed by `workbook_close`, never individually.
    private struct Formats {
        let bold: UnsafeMutablePointer<lxw_format>?
        let title: UnsafeMutablePointer<lxw_format>?
        let wrapped: UnsafeMutablePointer<lxw_format>?
        let duration: UnsafeMutablePointer<lxw_format>?
        let totalDuration: UnsafeMutablePointer<lxw_format>?

        init(workbook: UnsafeMutablePointer<lxw_workbook>?) {
            bold = workbook_add_format(workbook)
            format_set_bold(bold)

            title = workbook_add_format(workbook)
            format_set_bold(title)
            format_set_font_size(title, 16)

            wrapped = workbook_add_format(workbook)
            format_set_text_wrap(wrapped)

            // "[m]:ss", not "mm:ss" — the bracketed form shows cumulative
            // minutes past 60 instead of wrapping back to 0, matching a
            // single cue's own duration exactly (never truncated) the same
            // way `CueSheetLayoutComputer.formattedLength`'s `MM:SS` never
            // truncates on the PDF.
            duration = workbook_add_format(workbook)
            format_set_num_format(duration, "[m]:ss")

            // "[h]:mm:ss" for the aggregate total specifically — matches
            // `MediaDuration`'s own `HH:MM:SS` formatting convention
            // (SPEC.md §4.8) for a production-level runtime, bracketed so a
            // total past 24 hours (unlikely, but not impossible) still
            // displays correctly rather than wrapping.
            totalDuration = workbook_add_format(workbook)
            format_set_bold(totalDuration)
            format_set_num_format(totalDuration, "[h]:mm:ss")
        }
    }
}
