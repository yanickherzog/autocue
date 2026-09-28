import ACCore
import Foundation

/// Title-block computation for `CueSheetLayoutComputer` (SPEC.md §4.16) —
/// the eyebrow line + large production-title heading added at the top of
/// every page in the layout-redesign pass (`docs/DECISIONS.md`), built from
/// the project owner's real InDesign mockup. Split into its own file per
/// `CONTRIBUTING.md` §8's `SwiftLint` `type_body_length` limit; see
/// `+Header.swift`'s doc comment for the full rationale.
extension CueSheetLayoutComputer {
    /// The same `title`/`subtitle` join already used for the "Name der
    /// Sendung" header field (`+Header.swift`), just uppercased — the
    /// mockup's large heading and that field read as the same production
    /// name, just styled differently, not two independently-sourced values.
    static func titleHeadingText(for setup: Setup) -> String {
        [setup.title, setup.subtitle].compactMap { $0 }.joined(separator: " — ").uppercased()
    }

    /// `width`, not `usableWidth` — the title block aligns to
    /// `contentTextMargin`, not the raw page `margin` the table's rule
    /// lines use, so it's measured/drawn at the narrower width that leaves
    /// (`docs/DECISIONS.md`, 2026-09-28 visual pass).
    static func titleBlockHeight(title: String, usableWidth: Double) -> Double {
        let width = usableWidth - cellHorizontalPadding
        let eyebrowHeight = lineHeight(fontSize: eyebrowFontSize, weight: .regular)
        let titleHeight = measuredHeight(text: title, width: width, fontSize: titleFontSize, weight: .bold)
        return eyebrowHeight + titleBlockInternalGap + titleHeight
    }

    static func titleBlockElements(title: String, usableWidth: Double) -> [CueSheetLayoutElement] {
        let width = usableWidth - cellHorizontalPadding
        let eyebrowHeight = lineHeight(fontSize: eyebrowFontSize, weight: .regular)
        let eyebrowElement = CueSheetLayoutElement(
            frame: LayoutRect(x: contentTextMargin, y: margin, width: width, height: eyebrowHeight),
            content: .text(
                eyebrowText,
                font: LayoutFontSpec(weight: .regular, size: eyebrowFontSize, tracking: eyebrowTracking)
            )
        )

        let titleTop = margin + eyebrowHeight + titleBlockInternalGap
        let titleHeight = measuredHeight(text: title, width: width, fontSize: titleFontSize, weight: .bold)
        let titleElement = CueSheetLayoutElement(
            frame: LayoutRect(x: contentTextMargin, y: titleTop, width: width, height: titleHeight),
            content: .text(title, font: LayoutFontSpec(weight: .bold, size: titleFontSize))
        )

        return [eyebrowElement, titleElement]
    }
}
