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
    /// `tracking` defaults to `0`, matching `LayoutFontSpec`'s own default —
    /// only the title block's eyebrow line (layout-redesign pass) passes a
    /// non-zero value, so wrapping measurement never silently disagrees with
    /// what's actually drawn with letter-spacing applied.
    static func measuredHeight(
        text: String,
        width: Double,
        fontSize: Double,
        weight: LayoutFontWeight,
        tracking: Double = 0
    ) -> Double {
        guard !text.isEmpty else { return lineHeight(fontSize: fontSize, weight: weight) }
        let attributedString = attributedStringForMeasurement(
            text: text,
            fontSize: fontSize,
            weight: weight,
            tracking: tracking
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

    /// The natural (unwrapped) width of a single line of `text` — used to
    /// right-align the relocated "TOTAL MUSIK" line under the Dur./Label
    /// columns (layout-redesign pass) by computing its frame's `x` directly,
    /// rather than adding a text-alignment case to `LayoutElementContent`
    /// that every existing `.text` call site/pattern match would need to
    /// account for.
    static func measuredWidth(
        text: String,
        fontSize: Double,
        weight: LayoutFontWeight,
        tracking: Double = 0
    ) -> Double {
        guard !text.isEmpty else { return 0 }
        let attributedString = attributedStringForMeasurement(
            text: text,
            fontSize: fontSize,
            weight: weight,
            tracking: tracking
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let constraints = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            constraints,
            nil
        )
        return Double(suggestedSize.width)
    }

    private static func attributedStringForMeasurement(
        text: String,
        fontSize: Double,
        weight: LayoutFontWeight,
        tracking: Double
    ) -> NSAttributedString {
        let font = CTFontCreateWithName(PDFFontMapping.fontName(for: weight) as CFString, fontSize, nil)
        var attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font]
        if tracking != 0 {
            attributes[kCTKernAttributeName as NSAttributedString.Key] = tracking
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
