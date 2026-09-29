import ACCore
import Foundation

/// The "Interpret*in:"/"Arrangeur*in:" summary blocks computed for
/// `CueSheetLayoutComputer` (SPEC.md §4.16) — new in the layout-redesign pass
/// (`docs/DECISIONS.md`, built from the project owner's real InDesign
/// mockup): every Performer/Arranger right-holder across the whole cue
/// sheet, by name + IPI number, stacked below the table and the relocated
/// "TOTAL MUSIK" line, on the last page only. Split into its own file per
/// `CONTRIBUTING.md` §8's `SwiftLint` `type_body_length` limit; see
/// `+Header.swift`'s doc comment for the full rationale.
///
/// **Both block labels are singular ("Interpret*in:"/"Arrangeur*in:"), not
/// plural, even though each always lists every matching right-holder
/// project-wide — a deliberate, final project-owner decision (2026-09-29,
/// two rounds): Komponist*in/Interpret*in first, Arrangeur*in extended to the
/// same treatment immediately after for consistency across all three
/// summary-block/header-field titles.** `Arrangeur*in` (the table column) was
/// already singular since the second round's mockup rename.
///
/// **Both blocks share one generic implementation** (`summaryBlockHeight`/
/// `summaryBlockElements`, below) — the Arrangeur*in block added
/// alongside Interpret*in is identical in shape (label + deduplicated
/// "Name, IPI-Nr. …" list), so per `CLAUDE.md` rule 7 this is exactly the
/// point a second real caller justifies pulling the shared logic out rather
/// than duplicating the Interpret*in file wholesale.
extension CueSheetLayoutComputer {
    /// `0` when there are no matching right-holders anywhere on the project —
    /// the block is omitted entirely in that case (`summaryBlockElements`,
    /// below) rather than rendering a label with nothing under it. Aligns to
    /// `contentTextMargin`, so its width (like the title block's) is
    /// `usableWidth - cellHorizontalPadding`, not the full `usableWidth`.
    static func summaryBlockHeight(lines: [String], usableWidth: Double) -> Double {
        guard !lines.isEmpty else { return 0 }
        let width = usableWidth - cellHorizontalPadding
        let labelHeight = lineHeight(fontSize: headerFontSize, weight: .bold)
        let valueHeight = measuredHeight(
            text: lines.joined(separator: "\n"),
            width: width,
            fontSize: cellFontSize,
            weight: .regular
        )
        return labelHeight + interpretLabelToListGap + valueHeight
    }

    /// **`x: contentTextMargin`, not `x: margin`** — a real, self-caught
    /// misalignment found via the project owner's own visual inspection
    /// (2026-09-28, `docs/DECISIONS.md`): this block previously sat flush
    /// with the table's rule lines (`margin`) instead of the page's shared
    /// text margin every other piece of body text (the title block, every
    /// header field's own text) actually uses.
    static func summaryBlockElements(
        label: String,
        lines: [String],
        top: Double,
        usableWidth: Double
    ) -> [CueSheetLayoutElement] {
        guard !lines.isEmpty else { return [] }
        let width = usableWidth - cellHorizontalPadding

        let labelHeight = lineHeight(fontSize: headerFontSize, weight: .bold)
        let labelElement = CueSheetLayoutElement(
            frame: LayoutRect(x: contentTextMargin, y: top, width: width, height: labelHeight),
            content: .text(label, font: LayoutFontSpec(weight: .bold, size: headerFontSize))
        )

        let value = lines.joined(separator: "\n")
        let valueTop = top + labelHeight + interpretLabelToListGap
        let valueHeight = measuredHeight(text: value, width: width, fontSize: cellFontSize, weight: .regular)
        let valueElement = CueSheetLayoutElement(
            frame: LayoutRect(x: contentTextMargin, y: valueTop, width: width, height: valueHeight),
            content: .text(value, font: LayoutFontSpec(weight: .regular, size: cellFontSize))
        )

        return [labelElement, valueElement]
    }

    static func interpretBlockHeight(lines: [String], usableWidth: Double) -> Double {
        summaryBlockHeight(lines: lines, usableWidth: usableWidth)
    }

    static func interpretBlockElements(lines: [String], top: Double, usableWidth: Double) -> [CueSheetLayoutElement] {
        summaryBlockElements(label: "Interpret*in:", lines: lines, top: top, usableWidth: usableWidth)
    }

    static func arrangeurBlockHeight(lines: [String], usableWidth: Double) -> Double {
        summaryBlockHeight(lines: lines, usableWidth: usableWidth)
    }

    static func arrangeurBlockElements(lines: [String], top: Double, usableWidth: Double) -> [CueSheetLayoutElement] {
        summaryBlockElements(label: "Arrangeur*in:", lines: lines, top: top, usableWidth: usableWidth)
    }
}
