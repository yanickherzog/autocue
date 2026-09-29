import ACCore
import Foundation

/// Per-page layout assembly and row pagination for `CueSheetLayoutComputer`
/// (SPEC.md §4.16) — split into its own file per `CONTRIBUTING.md` §8's
/// `SwiftLint` `file_length` limit; see `+Header.swift`'s doc comment for the
/// full rationale. Members here are `internal` (no `private`), since Swift's
/// `private` is file-scoped and `computeLayout` (`CueSheetLayoutComputer.swift`)
/// constructs `PageContext`/calls `paginate` directly.
extension CueSheetLayoutComputer {
    /// Bundles everything a single page's layout needs beyond its own
    /// `index`/`indices` — keeps `pageLayout` under `CONTRIBUTING.md` §8's
    /// `SwiftLint` `function_parameter_count` limit rather than passing each
    /// of these ten values individually.
    struct PageContext {
        let project: Project
        let rows: [[String]]
        let rowHeights: [Double]
        let titleText: String
        let titleBlockHeight: Double
        let headerLines: (left: [HeaderLine], right: [HeaderLine])
        let interpretLines: [String]
        let interpretBlockHeight: Double
        let arrangeurLines: [String]
        let columnWidths: [Double]
        let columnHeaderHeight: Double
        let contentTop: Double
        let footerHeight: Double
        let usableWidth: Double
        let pageCount: Int
    }

    /// The two summary blocks' computed lines/heights, plus the total extra
    /// vertical space they (and the gaps around them) require on the last
    /// page — pulled out of `computeLayout` to keep that function under
    /// `CONTRIBUTING.md` §8's `SwiftLint` `function_body_length` limit.
    struct SummaryBlocks {
        let interpretLines: [String]
        let interpretBlockHeight: Double
        let arrangeurLines: [String]
        let reservedHeight: Double
    }

    static func computeSummaryBlocks(for project: Project, usableWidth: Double) -> SummaryBlocks {
        let interpretLines = performerIPILines(cues: project.cues, people: project.people, labels: project.labels)
        let interpretBlockH = interpretBlockHeight(lines: interpretLines, usableWidth: usableWidth)
        let arrangeurLines = arrangeurIPILines(cues: project.cues, people: project.people, labels: project.labels)
        let arrangeurBlockH = arrangeurBlockHeight(lines: arrangeurLines, usableWidth: usableWidth)

        let interpretReserved = interpretLines.isEmpty ? 0 : totalMusikToInterpretGap + interpretBlockH
        let arrangeurGap = interpretLines.isEmpty ? totalMusikToInterpretGap : interpretToArrangeurGap
        let arrangeurReserved = arrangeurLines.isEmpty ? 0 : arrangeurGap + arrangeurBlockH

        return SummaryBlocks(
            interpretLines: interpretLines,
            interpretBlockHeight: interpretBlockH,
            arrangeurLines: arrangeurLines,
            reservedHeight: interpretReserved + arrangeurReserved
        )
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
    static func measuredRowHeights(rows: [[String]], columnWidths: [Double]) -> [Double] {
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

    static func pageLayout(ctx: PageContext, index: Int, indices: [Int], isLast: Bool) -> CueSheetPageLayout {
        var elements: [CueSheetLayoutElement] = []
        elements.append(contentsOf: titleBlockElements(title: ctx.titleText, usableWidth: ctx.usableWidth))
        elements.append(contentsOf: headerBlockElements(
            left: ctx.headerLines.left,
            right: ctx.headerLines.right,
            top: margin + ctx.titleBlockHeight + titleToHeaderGap,
            usableWidth: ctx.usableWidth
        ))

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
            elements.append(contentsOf: lastPageOnlyElements(ctx: ctx, tableBottom: rowOriginY))
        }

        return CueSheetPageLayout(pageIndex: index, pageCount: ctx.pageCount, elements: elements)
    }

    /// The footer + both summary blocks — drawn once, on the genuine last
    /// page only. Pulled out of `pageLayout` to keep that function under
    /// `CONTRIBUTING.md` §8's `SwiftLint` `function_body_length` limit.
    static func lastPageOnlyElements(ctx: PageContext, tableBottom: Double) -> [CueSheetLayoutElement] {
        var elements: [CueSheetLayoutElement] = []
        var originY = tableBottom + tableToFooterGap

        elements.append(footerElement(
            project: ctx.project,
            columnWidths: ctx.columnWidths,
            originY: originY,
            height: ctx.footerHeight
        ))
        originY += ctx.footerHeight

        if !ctx.interpretLines.isEmpty {
            originY += totalMusikToInterpretGap
            elements.append(contentsOf: interpretBlockElements(
                lines: ctx.interpretLines,
                top: originY,
                usableWidth: ctx.usableWidth
            ))
            originY += ctx.interpretBlockHeight
        }

        if !ctx.arrangeurLines.isEmpty {
            originY += ctx.interpretLines.isEmpty ? totalMusikToInterpretGap : interpretToArrangeurGap
            elements.append(contentsOf: arrangeurBlockElements(
                lines: ctx.arrangeurLines,
                top: originY,
                usableWidth: ctx.usableWidth
            ))
        }

        return elements
    }

    /// Groups row indices into pages, each page holding as many rows as fit
    /// within its own budget — "however many rows fit at a legible font
    /// size," per this type's own doc comment.
    ///
    /// Two budgets, not one: only the genuine *last* page draws the
    /// footer/summary blocks, so it alone needs `lastPageAvailableHeight`
    /// (the tighter budget that leaves room for them); every other page can
    /// use the full `availableHeight`. Which rows land on the last page is
    /// therefore determined **first**, as the longest trailing run of rows
    /// that fits under the tighter budget (`lastPageRowCount`, below) — not
    /// as an afterthought correction applied to whatever a single forward
    /// pass happened to leave on its final page. That afterthought approach
    /// was tried and found to have a real, self-caught bug (2026-09-29): if
    /// forward-filling under the *full* budget left more rows on the final
    /// page than fit under the *tighter* one, trimming that page down to fit
    /// wrongly shrank it even though, once a further page absorbs the
    /// overflow, that page is no longer last and could have kept its full,
    /// non-last-budget row count — reintroducing this exact bug's own
    /// symptom (unnecessary blank space) one page earlier than before.
    /// Everything before the last page's rows is forward-filled at the full
    /// budget instead, free of that trap.
    static func paginate(
        rowHeights: [Double],
        columnHeaderHeight: Double,
        availableHeight: Double,
        lastPageAvailableHeight: Double
    ) -> [[Int]] {
        guard !rowHeights.isEmpty else { return [[]] }

        let lastPageRowCount = lastPageRowCount(
            rowHeights: rowHeights,
            columnHeaderHeight: columnHeaderHeight,
            lastPageAvailableHeight: lastPageAvailableHeight
        )
        guard lastPageRowCount < rowHeights.count else {
            return [Array(rowHeights.indices)]
        }

        let precedingRowCount = rowHeights.count - lastPageRowCount
        var pages = forwardFillPages(
            rowHeights: Array(rowHeights[0 ..< precedingRowCount]),
            columnHeaderHeight: columnHeaderHeight,
            availableHeight: availableHeight
        )
        pages.append(Array(precedingRowCount ..< rowHeights.count))
        return pages
    }

    /// The longest run of *trailing* rows whose combined height (plus the
    /// column header repeated on every page) fits within
    /// `lastPageAvailableHeight` — always at least 1, even if that single
    /// row alone doesn't fit (graceful degradation for a pathological
    /// oversized row/summary-block combination, rather than an infinite
    /// regress of ever-smaller last pages).
    private static func lastPageRowCount(
        rowHeights: [Double],
        columnHeaderHeight: Double,
        lastPageAvailableHeight: Double
    ) -> Int {
        var count = 0
        var height: Double = 0
        for rowHeight in rowHeights.reversed() {
            let candidateHeight = height + rowHeight
            if columnHeaderHeight + candidateHeight > lastPageAvailableHeight, count > 0 {
                break
            }
            height = candidateHeight
            count += 1
        }
        return count
    }

    /// Simple greedy forward pack, used for every page except the last —
    /// each holds as many rows as fit within `availableHeight` before
    /// starting a new page.
    private static func forwardFillPages(
        rowHeights: [Double],
        columnHeaderHeight: Double,
        availableHeight: Double
    ) -> [[Int]] {
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
