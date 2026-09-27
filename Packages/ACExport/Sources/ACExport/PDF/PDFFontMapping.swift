import ACCore
import Foundation

/// Maps `LayoutFontWeight` (SPEC.md §4.16 — abstract, `ACCore` stays
/// Foundation-only) to this app's chosen system typeface for the cue sheet
/// PDF — shared by `CueSheetLayoutComputer` (measurement) and
/// `PDFCueSheetRenderer` (drawing) so both use the exact same font for the
/// exact same weight; measuring against the wrong font/weight would let
/// wrapping/pagination silently disagree with what's actually drawn.
///
/// System Helvetica Neue, not this app's own Space Grotesk — a deliberate,
/// easily-revisited first-pass choice, not hidden: `ACExport` cannot depend
/// on `ACDesignSystem` (`CLAUDE.md`'s Package Dependency Graph), which is
/// where Space Grotesk is vendored/registered; duplicating those font files
/// into `ACExport` was judged not worth doing before any real visual
/// feedback exists. Revisit once the project owner's hands-on comparison
/// against their real example says which is actually wanted for a printed
/// document.
enum PDFFontMapping {
    static func fontName(for weight: LayoutFontWeight) -> String {
        switch weight {
        case .regular: "HelveticaNeue"
        case .medium: "HelveticaNeue-Medium"
        case .bold: "HelveticaNeue-Bold"
        }
    }
}
