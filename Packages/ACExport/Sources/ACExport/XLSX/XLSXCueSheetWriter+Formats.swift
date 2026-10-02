import ACCore
import libxlsxwriter

/// `Formats` plus the row-height measurement constants for
/// `XLSXCueSheetWriter` — split into its own file per `CONTRIBUTING.md` §8's
/// `SwiftLint` `file_length` limit, the same pattern `CueSheetLayoutComputer`
/// already establishes for its own `+Header`/`+Table`/etc. files. Members
/// here are `internal` (no `private`), since Swift's `private` is
/// file-scoped — the main file's functions need them.
extension XLSXCueSheetWriter {
    /// Real Core Text measurement (`CueSheetLayoutComputer.measuredHeight`)
    /// needs a font size to measure against for the header block's own
    /// fields — reuses the PDF's own `headerFontSize` constant rather than
    /// inventing a second number.
    static var headerFieldFontSize: Double {
        CueSheetLayoutComputer.headerFontSize
    }

    static var headerRowVerticalPadding: Double {
        4
    }

    static var titleRowHeight: Double {
        24
    }

    static var tableHeaderRowHeight: Double {
        CueSheetLayoutComputer.lineHeight(fontSize: CueSheetLayoutComputer.columnHeaderFontSize, weight: .bold) + 8
    }

    /// Every `lxw_format` this writer needs, created once per `write(_:to:)`
    /// call and reused across every cell — `libxlsxwriter` formats are
    /// workbook-owned and freed by `workbook_close`, never individually.
    struct Formats {
        let bold: UnsafeMutablePointer<lxw_format>?
        let title: UnsafeMutablePointer<lxw_format>?
        let eyebrow: UnsafeMutablePointer<lxw_format>?
        let wrapped: UnsafeMutablePointer<lxw_format>?
        let duration: UnsafeMutablePointer<lxw_format>?
        let totalDuration: UnsafeMutablePointer<lxw_format>?
        let tableHeader: UnsafeMutablePointer<lxw_format>?
        let tableCell: UnsafeMutablePointer<lxw_format>?
        let totalLabel: UnsafeMutablePointer<lxw_format>?

        init(workbook: UnsafeMutablePointer<lxw_workbook>?) {
            bold = workbook_add_format(workbook)
            format_set_bold(bold)

            title = workbook_add_format(workbook)
            format_set_bold(title)
            format_set_font_size(title, 16)

            eyebrow = workbook_add_format(workbook)
            format_set_font_size(eyebrow, 8)

            wrapped = workbook_add_format(workbook)
            format_set_text_wrap(wrapped)
            format_set_align(wrapped, UInt8(LXW_ALIGN_VERTICAL_TOP.rawValue))

            // "[m]:ss", not "mm:ss" — the bracketed form shows cumulative
            // minutes past 60 instead of wrapping back to 0, matching a
            // single cue's own duration exactly (never truncated) the same
            // way `CueSheetLayoutComputer.formattedLength`'s `MM:SS` never
            // truncates on the PDF.
            duration = workbook_add_format(workbook)
            format_set_num_format(duration, "[m]:ss")
            format_set_bottom(duration, UInt8(LXW_BORDER_THIN.rawValue))

            // "[h]:mm:ss" for the aggregate total specifically — matches
            // `MediaDuration`'s own `HH:MM:SS` formatting convention
            // (SPEC.md §4.8) for a production-level runtime, bracketed so a
            // total past 24 hours (unlikely, but not impossible) still
            // displays correctly rather than wrapping. Merged across
            // Dur.'s own column through the sheet's last column
            // (`writeTable`) so a bold, longer value never overflows into
            // "#######" — real evidence this was needed, `docs/DECISIONS.md`.
            totalDuration = workbook_add_format(workbook)
            format_set_bold(totalDuration)
            format_set_num_format(totalDuration, "[h]:mm:ss")
            format_set_align(totalDuration, UInt8(LXW_ALIGN_RIGHT.rawValue))
            format_set_top(totalDuration, UInt8(LXW_BORDER_THIN.rawValue))

            totalLabel = workbook_add_format(workbook)
            format_set_bold(totalLabel)
            format_set_top(totalLabel, UInt8(LXW_BORDER_THIN.rawValue))

            // Bold + a light gray fill + a bottom border — real visual
            // distinction beyond bold alone, confirmed necessary
            // (`docs/DECISIONS.md`, 2026-09-29): bold text on an otherwise
            // completely unstyled sheet didn't read as a clear header row.
            tableHeader = workbook_add_format(workbook)
            format_set_bold(tableHeader)
            format_set_pattern(tableHeader, UInt8(LXW_PATTERN_SOLID.rawValue))
            format_set_bg_color(tableHeader, 0xD9D9D9)
            format_set_bottom(tableHeader, UInt8(LXW_BORDER_THIN.rawValue))
            format_set_align(tableHeader, UInt8(LXW_ALIGN_VERTICAL_TOP.rawValue))

            // Every table body cell wraps and gets a thin bottom border —
            // the spreadsheet equivalent of the PDF's own row-separator
            // rule lines, and the same "wrap, never truncate, uniformly
            // across every column" rule `CueSheetLayoutComputer`'s own doc
            // comment already establishes for the PDF, now applied here too.
            tableCell = workbook_add_format(workbook)
            format_set_text_wrap(tableCell)
            format_set_bottom(tableCell, UInt8(LXW_BORDER_THIN.rawValue))
            format_set_align(tableCell, UInt8(LXW_ALIGN_VERTICAL_TOP.rawValue))
        }
    }
}
