import ACCore
import Foundation

/// Computes `[CueSheetPageLayout]` for the producer-facing cue sheet PDF
/// (SPEC.md §4.16, `ROADMAP.md` D11/T11.2) — landscape, its own column-based
/// design built from a real cue sheet example, distinct from the literal
/// SUISA WA Film form (D12).
///
/// **Wrap, never truncate, uniformly across every column and the header
/// block — a real, deliberate design rule, not a default.** This is a real
/// reference document a producer/collaborator reads to verify accuracy;
/// silently cutting off a right-holder's name or a work's title would be
/// genuine information loss, not a cosmetic UI-list tradeoff where ellipsis
/// would be normal. Real Core Text measurement drives this (see
/// `+Measurement.swift`): each cell's wrapped height is measured at its
/// column's fixed width, a row's height is the tallest result among its
/// columns, and rows accumulate until a page's usable height is exhausted
/// before a new page starts — "however many rows fit at a legible font
/// size," made concrete rather than a fixed row count (unlike the WA Film
/// form's own confirmed 5/4-per-page rule, which has no real-world
/// counterpart for this document).
///
/// **Font: system Helvetica Neue, not this app's own Space Grotesk —
/// a deliberate, easily-revisited first-pass choice, flagged not hidden.**
/// `ACExport` cannot depend on `ACDesignSystem` (`CLAUDE.md`'s Package
/// Dependency Graph), which is where Space Grotesk is vendored/registered;
/// duplicating those font files into `ACExport` was judged not worth doing
/// before any real visual feedback exists. Revisit once the project owner's
/// hands-on comparison against their real example says which is actually
/// wanted for a printed document.
///
/// **Split across `+Header`/`+Table`/`+Formatting`/`+Measurement` files** —
/// the single-file version exceeded `CONTRIBUTING.md` §8's `SwiftLint`
/// type-body-length threshold, the same reason `SetupView`/
/// `CueDetectionReviewViewModel` are already split the same way. Shared
/// constants below are `internal` (not `private`), since Swift's `private`
/// is file-scoped — every extension file needs them.
enum CueSheetLayoutComputer {
    // MARK: - Page geometry (points — Core Graphics' native PDF unit, no conversion needed)

    /// A4 landscape, ISO 216: 841.89 × 595.28pt.
    static let pageWidth: Double = 841.89
    static let pageHeight: Double = 595.28
    static let margin: Double = 36

    static let headerFontSize: Double = 9
    static let columnHeaderFontSize: Double = 9
    static let cellFontSize: Double = 8.5
    static let footerFontSize: Double = 10
    /// Bumped from an original 4/3pt (2026-09-27, layout-polish pass, per
    /// project-owner feedback that the first render felt cramped) — more
    /// breathing room around every header/table cell's text.
    static let cellHorizontalPadding: Double = 6
    static let cellVerticalPadding: Double = 5
    static let ruleThickness: Double = 0.75
    /// Vertical gap between the header block and the column-header row —
    /// a named constant (2026-09-27 polish pass) rather than an ad hoc
    /// `margin * 0.5`, both for clarity and because it's now deliberately
    /// larger than that derived value (18pt) to give the two sections real
    /// visual separation instead of the header block reading like it runs
    /// straight into the table.
    static let headerToTableGap: Double = 22

    struct Column {
        let title: String
        let widthWeight: Double
    }

    /// Relative widths, not absolute points — normalized against the page's
    /// actual usable width at compute time, so a future margin/page-size
    /// change doesn't require re-deriving every column's width by hand.
    static let columns: [Column] = [
        Column(title: "Komponist*innen", widthWeight: 1.0),
        Column(title: "Arrangement", widthWeight: 0.9),
        Column(title: "Interpret*innen", widthWeight: 1.0),
        Column(title: "Songtitel", widthWeight: 1.1),
        Column(title: "TC In", widthWeight: 0.65),
        Column(title: "TC Out", widthWeight: 0.65),
        Column(title: "Dur.", widthWeight: 0.45),
        Column(title: "Label", widthWeight: 0.9),
        Column(title: "Label-Nr.", widthWeight: 0.6),
        Column(title: "ISRC-Nr.", widthWeight: 0.75),
    ]

    // MARK: - Entry point

    static func computeLayout(for project: Project) -> [CueSheetPageLayout] {
        let usableWidth = pageWidth - margin * 2
        let totalWeight = columns.reduce(0) { $0 + $1.widthWeight }
        let columnWidths = columns.map { usableWidth * ($0.widthWeight / totalWeight) }

        let headerLines = headerBlockLines(for: project)
        let headerHeight = headerBlockHeight(lines: headerLines, columnWidth: usableWidth / 2) + headerToTableGap

        let columnHeaderHeight = lineHeight(fontSize: columnHeaderFontSize, weight: .bold) + cellVerticalPadding * 2
        let footerHeight = lineHeight(fontSize: footerFontSize, weight: .bold) + cellVerticalPadding * 2

        let rows = project.cues.map {
            rowValues(for: $0, setup: project.setup, people: project.people, labels: project.labels)
        }
        let rowHeights = measuredRowHeights(rows: rows, columnWidths: columnWidths)

        let contentTop = margin + headerHeight
        let contentBottom = pageHeight - margin
        let availableHeight = contentBottom - contentTop - footerHeight

        let pagesOfRows = paginate(
            rowHeights: rowHeights,
            columnHeaderHeight: columnHeaderHeight,
            availableHeight: availableHeight
        )

        let ctx = PageContext(
            project: project,
            rows: rows,
            rowHeights: rowHeights,
            headerLines: headerLines,
            columnWidths: columnWidths,
            columnHeaderHeight: columnHeaderHeight,
            contentTop: contentTop,
            contentBottom: contentBottom,
            footerHeight: footerHeight,
            usableWidth: usableWidth,
            pageCount: max(pagesOfRows.count, 1)
        )

        return pagesOfRows.enumerated().map { index, indices in
            pageLayout(ctx: ctx, index: index, indices: indices, isLast: index == pagesOfRows.count - 1)
        }
    }

    /// Bundles everything a single page's layout needs beyond its own
    /// `index`/`indices` — keeps `pageLayout` under `CONTRIBUTING.md` §8's
    /// `SwiftLint` `function_parameter_count` limit rather than passing each
    /// of these ten values individually.
    private struct PageContext {
        let project: Project
        let rows: [[String]]
        let rowHeights: [Double]
        let headerLines: [HeaderLine]
        let columnWidths: [Double]
        let columnHeaderHeight: Double
        let contentTop: Double
        let contentBottom: Double
        let footerHeight: Double
        let usableWidth: Double
        let pageCount: Int
    }

    /// Each row's allocated height, content height **plus** vertical padding
    /// — matching `columnHeaderHeight`/`footerHeight`'s own `+ cellVerticalPadding * 2`
    /// in `computeLayout`. Omitting this was a real, self-caught bug: `rowElements`
    /// (`+Table.swift`) always subtracts `cellVerticalPadding * 2` back out when
    /// building each cell's drawn text box, so a row height that was pure content
    /// height (no padding) got that box under-allocated by exactly that amount —
    /// invisible for a tall multi-line row, but enough to make a short single-line
    /// row's box shorter than one line, silently dropping the entire row from the
    /// rendered PDF.
    private static func measuredRowHeights(rows: [[String]], columnWidths: [Double]) -> [Double] {
        rows.map { row in
            let contentHeight = zip(row, columnWidths)
                .map { text, width in
                    measuredHeight(
                        text: text,
                        width: width - cellHorizontalPadding * 2,
                        fontSize: cellFontSize,
                        weight: .regular
                    )
                }
                .max() ?? lineHeight(fontSize: cellFontSize, weight: .regular)
            return contentHeight + cellVerticalPadding * 2
        }
    }

    private static func pageLayout(ctx: PageContext, index: Int, indices: [Int], isLast: Bool) -> CueSheetPageLayout {
        var elements: [CueSheetLayoutElement] = []
        elements.append(contentsOf: headerBlockElements(lines: ctx.headerLines, usableWidth: ctx.usableWidth))

        var rowOriginY = ctx.contentTop
        elements.append(contentsOf: columnHeaderElements(
            widths: ctx.columnWidths,
            top: rowOriginY,
            height: ctx.columnHeaderHeight
        ))
        rowOriginY += ctx.columnHeaderHeight

        for rowIndex in indices {
            let height = ctx.rowHeights[rowIndex]
            elements.append(contentsOf: rowElements(
                cells: ctx.rows[rowIndex],
                widths: ctx.columnWidths,
                top: rowOriginY,
                height: height
            ))
            rowOriginY += height
        }

        if isLast {
            elements.append(footerElement(
                project: ctx.project,
                originY: ctx.contentBottom - ctx.footerHeight,
                width: ctx.usableWidth
            ))
        }

        return CueSheetPageLayout(pageIndex: index, pageCount: ctx.pageCount, elements: elements)
    }

    /// Groups row indices into pages, each page holding as many rows as fit
    /// within `availableHeight` — "however many rows fit at a legible font
    /// size," per this type's own doc comment.
    private static func paginate(rowHeights: [Double], columnHeaderHeight: Double, availableHeight: Double) -> [[Int]] {
        var pages: [[Int]] = [[]]
        var currentHeight = columnHeaderHeight
        for (index, rowHeight) in rowHeights.enumerated() {
            let currentPageIsNonEmpty = !pages[pages.count - 1].isEmpty
            if currentHeight + rowHeight > availableHeight, currentPageIsNonEmpty {
                pages.append([])
                currentHeight = columnHeaderHeight
            }
            pages[pages.count - 1].append(index)
            currentHeight += rowHeight
        }
        if pages.count > 1, pages.last?.isEmpty == true {
            pages.removeLast()
        }
        return pages
    }
}
