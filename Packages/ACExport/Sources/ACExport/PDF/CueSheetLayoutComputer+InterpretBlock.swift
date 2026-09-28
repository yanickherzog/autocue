import ACCore
import Foundation

/// The "Interpret*innen:" summary block computed for `CueSheetLayoutComputer`
/// (SPEC.md §4.16) — new in the layout-redesign pass (`docs/DECISIONS.md`,
/// built from the project owner's real InDesign mockup): every Performer
/// right-holder across the whole cue sheet, by name + IPI number, stacked
/// below the table and the relocated "TOTAL MUSIK" line, on the last page
/// only. Split into its own file per `CONTRIBUTING.md` §8's `SwiftLint`
/// `type_body_length` limit; see `+Header.swift`'s doc comment for the full
/// rationale.
extension CueSheetLayoutComputer {
    /// `0` when there are no performers anywhere on the project — the block
    /// is omitted entirely in that case (`interpretBlockElements`, below)
    /// rather than rendering a label with nothing under it. Aligns to
    /// `contentTextMargin`, so its width (like the title block's) is
    /// `usableWidth - cellHorizontalPadding`, not the full `usableWidth`.
    static func interpretBlockHeight(lines: [String], usableWidth: Double) -> Double {
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
    static func interpretBlockElements(lines: [String], top: Double, usableWidth: Double) -> [CueSheetLayoutElement] {
        guard !lines.isEmpty else { return [] }
        let width = usableWidth - cellHorizontalPadding

        let labelHeight = lineHeight(fontSize: headerFontSize, weight: .bold)
        let labelElement = CueSheetLayoutElement(
            frame: LayoutRect(x: contentTextMargin, y: top, width: width, height: labelHeight),
            content: .text("Interpret*innen:", font: LayoutFontSpec(weight: .bold, size: headerFontSize))
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
}
