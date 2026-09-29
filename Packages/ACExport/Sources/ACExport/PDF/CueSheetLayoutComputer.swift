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

    // MARK: - Title block

    // Layout-redesign pass, built from the project owner's real InDesign
    // mockup — see `docs/DECISIONS.md`.
    static let eyebrowText = "SUISA/SWISSPERFORM-ANGABEN ZUR FOLGENDEN SENDUNG:"
    static let eyebrowFontSize: Double = 7.5
    /// Extra points of space between characters (`LayoutFontSpec.tracking`)
    /// — the eyebrow line's deliberately letter-spaced small-caps look, per
    /// the mockup.
    static let eyebrowTracking: Double = 1.5
    static let titleFontSize: Double = 24
    static let titleBlockInternalGap: Double = 6
    static let titleToHeaderGap: Double = 18

    /// Horizontal gap between a header field's bold label (e.g.
    /// `"Regie:"`) and its regular-weight value, drawn as two adjacent
    /// elements on the same line rather than one mixed-weight string —
    /// `LayoutElementContent.text` carries a single `LayoutFontSpec` for its
    /// whole string, so two weights on one line means two elements.
    static let headerLabelValueGap: Double = 4

    /// Vertical gap between the table's own bottom rule and the relocated
    /// "TOTAL MUSIK" line — bumped from `0` (flush against the rule) to a
    /// real, visible separation per the project owner's second visual
    /// pass (2026-09-28, `docs/DECISIONS.md`): "attached, not flush."
    static let tableToFooterGap: Double = 25
    /// Vertical gap between the relocated "TOTAL MUSIK" line and the first
    /// summary block below it (Interpret*in, or Arrangeur*in if the
    /// project has no performers) — also reused as the gap before
    /// Arrangeur*in when it's the *only* summary block present, so a
    /// block's gap to whatever's directly above it is always this value.
    static let totalMusikToInterpretGap: Double = 16
    /// Vertical gap between the Interpret*in block and the Arrangeur*in
    /// block immediately below it, when both are present.
    static let interpretToArrangeurGap: Double = 16
    static let interpretLabelToListGap: Double = 3

    /// Header field row spacing — deliberately its own constant, distinct
    /// from `cellVerticalPadding` (used by the table/column-header/footer),
    /// so tightening the header block's line rhythm (2026-09-28 visual pass,
    /// `docs/DECISIONS.md`) doesn't also compress the table.
    static let headerFieldVerticalPadding: Double = 2

    /// The page's shared left text margin for content that isn't a table
    /// cell — the title block and the Interpret*in block both align
    /// here, matching where a header field's own *text* starts (`margin +
    /// cellHorizontalPadding`, `headerFieldElements` in `+Header.swift`),
    /// not the raw page `margin` the table's rule lines are drawn at.
    /// Named explicitly (2026-09-28 visual pass) after the Interpret*in
    /// block was found sitting flush with the table's rule lines instead —
    /// see `docs/DECISIONS.md`.
    static let contentTextMargin: Double = margin + cellHorizontalPadding

    struct Column {
        let title: String
        let widthWeight: Double
    }

    /// Relative widths, not absolute points — normalized against the page's
    /// actual usable width at compute time, so a future margin/page-size
    /// change doesn't require re-deriving every column's width by hand.
    ///
    /// **Label/Label-Nr./ISRC-Nr. rebalanced 2026-09-29** (layout follow-up
    /// pass) so ISRC-Nr. — a fixed-format code (`CC-XXX-YY-NNNNN`, always 16
    /// characters) whose required width is therefore known and predictable,
    /// unlike free-text columns — renders on one line instead of wrapping.
    /// Label-Nr. gave up the width: real Core Text measurement showed it had
    /// several points of slack for a typical short catalog number, while
    /// Label/Interpret*in/Komponist*in etc. already wrap to multiple
    /// lines for realistic multi-word/multi-name values regardless of their
    /// exact width, so narrowing Label a little costs nothing already-fitting.
    /// The other seven columns' weights are unchanged — this only
    /// redistributes the combined 2.25 these three columns already had.
    ///
    /// **Songtitel/TC In/TC Out/Dur./Label rebalanced again, 2026-09-29**
    /// (same pass, project-owner decision): Songtitel widened enough for the
    /// longest realistic title (`"ProjectTitle_Score_Cue-NN"`, real Core Text
    /// measurement, ~118pt at this font) to render on one line, per an
    /// explicit instruction *not* to shrink the font to help it — funded by
    /// TC In/TC Out/Dur., which are genuinely, structurally fixed-width (a
    /// timecode is always the same character count; so is `MM:SS`), so
    /// narrowing them to their real measured need plus a small buffer carries
    /// none of the content-variance risk a free-text column's width would,
    /// plus a small additional amount from Label (already wraps to multiple
    /// lines for a realistic multi-word name regardless of exact width, the
    /// same reasoning the first rebalance above already used for it). These
    /// five columns' combined weight (3.65) is unchanged; Komponist*in/
    /// Arrangeur*in/Interpret*in/Label-Nr./ISRC-Nr. are untouched by this
    /// second rebalance.
    ///
    /// **Komponist*innen/Interpret*innen renamed to singular Komponist*in/
    /// Interpret*in, 2026-09-29** (project-owner decision, final): applies
    /// even though each column/block can list more than one person — matches
    /// "Arrangeur*in," already singular since the second round's mockup
    /// rename, and the header block's own "Komponist*in" field, which was
    /// singular from the very first redesign pass. The "Interpret*in:"
    /// summary block below the table (`+InterpretBlock.swift`) is renamed in
    /// the same change for consistency.
    static let columns: [Column] = [
        Column(title: "Komponist*in", widthWeight: 1.0),
        Column(title: "Arrangeur*in", widthWeight: 0.9),
        Column(title: "Interpret*in", widthWeight: 1.0),
        Column(title: "Songtitel", widthWeight: 1.37),
        Column(title: "TC In", widthWeight: 0.6),
        Column(title: "TC Out", widthWeight: 0.6),
        Column(title: "Dur.", widthWeight: 0.35),
        Column(title: "Label", widthWeight: 0.73),
        Column(title: "Label-Nr.", widthWeight: 0.55),
        Column(title: "ISRC-Nr.", widthWeight: 0.9),
    ]

    // MARK: - Entry point

    static func computeLayout(for project: Project) -> [CueSheetPageLayout] {
        let usableWidth = pageWidth - margin * 2
        let totalWeight = columns.reduce(0) { $0 + $1.widthWeight }
        let columnWidths = columns.map { usableWidth * ($0.widthWeight / totalWeight) }

        let titleText = titleHeadingText(for: project.setup)
        let titleBlockH = titleBlockHeight(title: titleText, usableWidth: usableWidth)

        let headerLines = headerBlockLines(for: project)
        let headerBlockH = headerBlockHeight(
            left: headerLines.left,
            right: headerLines.right,
            columnWidth: usableWidth / 2
        )
        let headerHeight = titleBlockH + titleToHeaderGap + headerBlockH + headerToTableGap

        let columnHeaderHeight = lineHeight(fontSize: columnHeaderFontSize, weight: .bold) + cellVerticalPadding * 2
        let footerHeight = lineHeight(fontSize: footerFontSize, weight: .bold) + cellVerticalPadding * 2

        let rows = project.cues.map {
            rowValues(for: $0, setup: project.setup, people: project.people, labels: project.labels)
        }
        let rowHeights = measuredRowHeights(rows: rows, columnWidths: columnWidths)

        let summaryBlocks = computeSummaryBlocks(for: project, usableWidth: usableWidth)
        let bottomReservedHeight = tableToFooterGap + footerHeight + summaryBlocks.reservedHeight

        let contentTop = margin + headerHeight
        let contentBottom = pageHeight - margin

        // Non-last pages don't draw the footer/summary blocks at all, so
        // they can use the page's full remaining height — only the actual
        // last page needs `bottomReservedHeight` held back. Reserving it on
        // every page (as this used to) under-filled every page before the
        // last one, leaving real, unnecessary blank space and pushing rows
        // onto more pages than the content actually needs.
        let fullPageAvailableHeight = contentBottom - contentTop
        let lastPageAvailableHeight = fullPageAvailableHeight - bottomReservedHeight

        let pagesOfRows = paginate(
            rowHeights: rowHeights,
            columnHeaderHeight: columnHeaderHeight,
            availableHeight: fullPageAvailableHeight,
            lastPageAvailableHeight: lastPageAvailableHeight
        )

        let ctx = PageContext(
            project: project,
            rows: rows,
            rowHeights: rowHeights,
            titleText: titleText,
            titleBlockHeight: titleBlockH,
            headerLines: headerLines,
            interpretLines: summaryBlocks.interpretLines,
            interpretBlockHeight: summaryBlocks.interpretBlockHeight,
            arrangeurLines: summaryBlocks.arrangeurLines,
            columnWidths: columnWidths,
            columnHeaderHeight: columnHeaderHeight,
            contentTop: contentTop,
            footerHeight: footerHeight,
            usableWidth: usableWidth,
            pageCount: max(pagesOfRows.count, 1)
        )

        return pagesOfRows.enumerated().map { index, indices in
            pageLayout(ctx: ctx, index: index, indices: indices, isLast: index == pagesOfRows.count - 1)
        }
    }
}
