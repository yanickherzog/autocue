import ACCore
import CoreText
import Foundation

/// Real Core Text measurement for `CueSheetLayoutComputer` (SPEC.md §4.16)
/// — split out per `CONTRIBUTING.md` §8's `SwiftLint` `type_body_length`
/// limit; see `+Header.swift`'s doc comment for the full rationale.
///
/// **Measures against the exact same font/weight `PDFCueSheetRenderer`
/// draws with (`PDFFontMapping`) — never a hardcoded regular-weight
/// stand-in.** An earlier version of this measurement always used regular
/// weight regardless of what was actually drawn (column headers/footer draw
/// bold, which is wider); left uncorrected, real wrapping/pagination could
/// silently disagree with what's actually rendered — exactly the failure
/// mode the shared `CueSheetPageLayout` architecture exists to prevent.
extension CueSheetLayoutComputer {
    /// `weight` has no default — every call site states explicitly which
    /// weight it's budgeting height for, so a bold column header/footer line
    /// can never silently get measured as if it were regular (the exact bug
    /// this file's own doc comment describes).
    static func lineHeight(fontSize: Double, weight: LayoutFontWeight) -> Double {
        let font = CTFontCreateWithName(PDFFontMapping.fontName(for: weight) as CFString, fontSize, nil)
        return Double(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    /// The height `text` wraps to when constrained to `width` — the real
    /// measurement "wrap, never truncate" pagination is built on (this
    /// type's own doc comment). Never mocked/estimated: uses the same
    /// `CTFramesetter` machinery `PDFCueSheetRenderer` uses to actually draw.
    static func measuredHeight(text: String, width: Double, fontSize: Double, weight: LayoutFontWeight) -> Double {
        guard !text.isEmpty else { return lineHeight(fontSize: fontSize, weight: weight) }
        let font = CTFontCreateWithName(PDFFontMapping.fontName(for: weight) as CFString, fontSize, nil)
        let attributedString = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let constraints = CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            constraints,
            nil
        )
        return Double(suggestedSize.height)
    }
}
